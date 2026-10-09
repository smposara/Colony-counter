import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../core/annotate.dart';
import '../core/plate.dart';
import '../core/zones.dart';
import '../data/plate_store.dart';
import '../data/zone_record.dart';
import '../l10n/l10n.dart';
import 'format.dart';
import 'insets.dart';
import 'photo_flow.dart';
import 'zone_setup_sheet.dart';

/// Shows the measured inhibition zones over the photo and lets the user
/// check and correct them.
///
/// Open with [photo] and [setup] for a new plate (it is measured on arrival)
/// or with [record] to revisit a saved one.
class ZoneReviewScreen extends StatefulWidget {
  const ZoneReviewScreen({
    super.key,
    required this.store,
    this.photo,
    this.setup,
    this.record,
  }) : assert((photo != null && setup != null) || record != null);

  final PlateStore store;
  final Uint8List? photo;
  final ZoneSetup? setup;
  final ZoneRecord? record;

  @override
  State<ZoneReviewScreen> createState() => _ZoneReviewScreenState();
}

/// One step back: the marks and the plate as they were.
typedef _Snapshot = (List<ZoneMark>, Plate, double);

class _ZoneReviewScreenState extends State<ZoneReviewScreen> {
  final _viewer = TransformationController();
  PlateStore get store => widget.store;

  Uint8List? _photo;
  ZoneRecord? _rec;
  String? _error;
  bool _busy = false;
  bool _dirty = false;
  bool _showMarks = true;

  /// Moving and resizing the plate circle before measuring again.
  bool _plateMode = false;
  Plate? _platePending;

  /// The zone whose edge is being dragged.
  int? _dragging;
  final List<_Snapshot> _undo = [];
  double _fitScale = 1;

  late final ZoneAssay _assay = widget.record?.assay ?? widget.setup!.assay;
  late final double _diskMm = widget.record?.diskMm ?? widget.setup!.diskMm;
  late final PlateFormat _format =
      widget.record?.format ?? widget.setup!.format;

  bool get _wells => _assay == ZoneAssay.well;
  double get _screenScale => _fitScale * _viewer.value.getMaxScaleOnAxis();

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    if (record != null) {
      _rec = record;
      store.readPhotoPath(record.imagePath).then((bytes) {
        if (!mounted) return;
        setState(() {
          _photo = bytes;
          if (bytes == null) _error = tr.zoneNotMeasured;
        });
      });
    } else {
      _photo = widget.photo;
      _measure();
    }
  }

  @override
  void dispose() {
    _viewer.dispose();
    super.dispose();
  }

  List<String> get _panelLabels {
    final name = _rec?.panel ?? widget.setup?.panel ?? '';
    return store.zonePanels.where((p) => p.name == name).firstOrNull?.labels ??
        const [];
  }

  /// Measures the whole plate (again), on [plate] when given.
  Future<void> _measure({Plate? plate}) async {
    final photo = _photo;
    if (photo == null) return;
    setState(() => _busy = true);
    try {
      final res = await compute(measureZonesInPhoto, (
        photo,
        ZoneOptions(
          format: _format,
          assay: _assay,
          diskMm: _diskMm,
          plate: plate,
        ),
      ));
      final old = _rec;
      final setup = widget.setup;
      final rec = ZoneRecord.fromResult(
        res,
        id: old?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        imagePath: old?.imagePath ?? '',
        createdAt: old?.createdAt ?? DateTime.now(),
        format: _format,
        diskMm: _diskMm,
        labels: _panelLabels,
        experiment: old?.experiment ?? setup!.experiment,
        organism: old?.organism ?? setup!.organism,
        replicate: old?.replicate ?? setup!.replicate,
        panel: old?.panel ?? setup!.panel,
      );
      if (!mounted) return;
      setState(() {
        if (old != null) _pushUndo();
        _rec = old == null ? rec : rec.copyWith(notes: old.notes);
        _busy = false;
        _dirty = _dirty || old != null || widget.record == null;
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  void _pushUndo() {
    final r = _rec!;
    _undo.add((r.marks, r.plate, r.mmPerPx));
    if (_undo.length > 30) _undo.removeAt(0);
  }

  void _setMarks(List<ZoneMark> marks) => setState(() {
    _rec = _rec!.copyWith(marks: marks);
    _dirty = true;
  });

  void _undoLast() {
    if (_undo.isEmpty) return;
    final (marks, plate, mmPerPx) = _undo.removeLast();
    setState(() {
      _rec = _rec!.copyWith(marks: marks, plate: plate, mmPerPx: mmPerPx);
      _dirty = true;
    });
  }

  // ---------------------------------------------------------------------
  // Gestures

  /// Radius of the circle whose edge can be dragged: the zone, or the disk
  /// when there is no zone to show.
  double _edgeRadius(ZoneMark m) =>
      m.diameterMm.isFinite && !m.noZone ? m.radiusPx : m.diskRadiusPx;

  /// The mark with a zone edge under [p], if any.
  int? _hitEdge(Offset p) {
    final marks = _rec?.marks ?? const [];
    final tol = 16 / _screenScale;
    int? best;
    var bestD = double.infinity;
    for (var i = 0; i < marks.length; i++) {
      final m = marks[i];
      final d = ((p - Offset(m.x, m.y)).distance - _edgeRadius(m)).abs();
      if (d <= tol && d < bestD) {
        best = i;
        bestD = d;
      }
    }
    return best;
  }

  /// The mark at [p]: inside its zone (or near its disk).
  int? _hitMark(Offset p) {
    final marks = _rec?.marks ?? const [];
    int? best;
    var bestD = double.infinity;
    for (var i = 0; i < marks.length; i++) {
      final m = marks[i];
      final d = (p - Offset(m.x, m.y)).distance;
      final reach = math.max(
        math.max(_edgeRadius(m), m.diskRadiusPx * 1.5),
        20 / _screenScale,
      );
      if (d <= reach && d < bestD) {
        best = i;
        bestD = d;
      }
    }
    return best;
  }

  /// Takes a one-finger drag only when it starts on a zone edge (or
  /// anywhere while fixing the plate); otherwise the view pans.
  bool _acceptDrag(Offset p) =>
      _rec != null &&
      !_busy &&
      (_plateMode || (_showMarks && _hitEdge(p) != null));

  void _dragStart(Offset p) {
    if (_plateMode) return;
    _dragging = _hitEdge(p);
    if (_dragging != null) _pushUndo();
  }

  void _dragUpdate(DragUpdateDetails d) {
    if (_plateMode) {
      final pl = _platePending;
      if (pl == null) return;
      setState(
        () => _platePending = pl.copyWith(
          cx: pl.cx + d.delta.dx,
          cy: pl.cy + d.delta.dy,
        ),
      );
      return;
    }
    final i = _dragging;
    final r = _rec;
    if (i == null || r == null) return;
    final m = r.marks[i];
    final radius = math.max(
      (d.localPosition - Offset(m.x, m.y)).distance,
      m.diskRadiusPx,
    );
    _setMarks([
      ...r.marks.take(i),
      m.copyWith(
        radiusPx: radius,
        diameterMm: 2 * radius * r.mmPerPx,
        noZone: false,
        opened: true,
      ),
      ...r.marks.skip(i + 1),
    ]);
  }

  Future<void> _onTap(Offset p) async {
    if (_plateMode || !_showMarks) return;
    final i = _hitMark(p);
    if (i != null) await _openMark(i);
  }

  Future<void> _onLongPress(Offset p) async {
    if (_plateMode || _busy || _rec == null) return;
    if (!_showMarks) setState(() => _showMarks = true);
    final hit = _hitMark(p);
    if (hit != null) return _openMark(hit);
    final pl = _rec!.plate;
    if ((p - Offset(pl.cx, pl.cy)).distance > pl.radius) return;
    await _addDisk(p);
  }

  /// Adds a disk the app missed at [p] and measures its zone.
  Future<void> _addDisk(Offset p) async {
    final r = _rec!;
    final photo = _photo;
    if (photo == null) return;
    final r0 = _diskMm / 2 / r.mmPerPx;
    setState(() => _busy = true);
    ZoneMark mark;
    try {
      final res = await compute(measureZonesInPhoto, (
        photo,
        ZoneOptions(
          format: _format,
          assay: _assay,
          diskMm: _diskMm,
          plate: r.plate,
          disks: [
            for (final m in r.marks) Disk(m.x, m.y, m.diskRadiusPx),
            Disk(p.dx, p.dy, r0, measured: false),
          ],
        ),
      ));
      final z = res.zones.last;
      final mm = z.radiusPx.isFinite ? 2 * z.radiusPx * r.mmPerPx : double.nan;
      mark = ZoneMark(
        x: p.dx,
        y: p.dy,
        diskRadiusPx: r0,
        radiusPx: z.radiusPx,
        diameterMm: mm,
        autoDiameterMm: mm,
        confidence: z.confidence,
        edgeWidthMm: z.edgeWidthMm,
        flags: List.of(z.flags),
        noZone: z.flags.contains('no_zone'),
        manual: true,
      );
    } on Object {
      mark = ZoneMark(
        x: p.dx,
        y: p.dy,
        diskRadiusPx: r0,
        radiusPx: double.nan,
        diameterMm: double.nan,
        autoDiameterMm: double.nan,
        flags: const ['unmeasured'],
        manual: true,
      );
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _pushUndo();
    // Kept in clockwise order, so the numbers follow the plate.
    final marks = assignLabels([...r.marks, mark], r.plate, const []);
    _setMarks(marks);
    await _openMark(marks.indexOf(mark));
  }

  Future<void> _openMark(int i) async {
    final r = _rec!;
    final res = await showModalBottomSheet<_SheetResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ZoneSheet(
        mark: r.marks[i],
        number: i + 1,
        wells: _wells,
        diskMm: _diskMm,
        mmPerPx: r.mmPerPx,
        suggestions: _panelLabels,
      ),
    );
    if (!mounted) return;
    final cur = _rec!.marks;
    if (i >= cur.length) return;
    final after = (res?.mark ?? cur[i]).copyWith(opened: true);
    // Looked at again and left as it was: nothing to save.
    if (res?.delete != true &&
        jsonEncode(after.toJson()) == jsonEncode(cur[i].toJson())) {
      return;
    }
    _pushUndo();
    if (res != null && res.delete) {
      _setMarks([...cur.take(i), ...cur.skip(i + 1)]);
      return;
    }
    // Closing the sheet counts as having looked at the zone.
    _setMarks([...cur.take(i), after, ...cur.skip(i + 1)]);
  }

  // ---------------------------------------------------------------------
  // Plate circle

  void _togglePlateMode() => setState(() {
    _plateMode = !_plateMode;
    _platePending = _plateMode ? _rec?.plate : null;
  });

  Future<void> _applyPlate() async {
    final r = _rec;
    final plate = _platePending;
    if (r == null || plate == null) return;
    if (r.edits > 0 || r.marks.any((m) => m.opened)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr.zoneRemeasureTitle),
          content: Text(tr.zoneRemeasureBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr.homeCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr.zoneMeasureAgain),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() {
      _plateMode = false;
      _platePending = null;
    });
    await _measure(plate: plate);
  }

  // ---------------------------------------------------------------------
  // Saving

  Future<void> _editDetails() async {
    final r = _rec;
    if (r == null) return;
    final s = await showZoneDetailsSheet(context, store, r);
    if (s == null || !mounted) return;
    setState(() {
      _rec = r.copyWith(
        experiment: s.experiment,
        organism: s.organism,
        replicate: s.replicate,
      );
      _dirty = true;
    });
  }

  Future<void> _save() async {
    var r = _rec;
    final photo = _photo;
    if (r == null || photo == null) return;
    setState(() => _busy = true);
    if (r.imagePath.isEmpty) {
      final name = await store.savePhoto(photo, 'zone_${r.id}');
      r = ZoneRecord.fromJson({...r.toJson(), 'image': name});
    }
    await store.upsertZone(r);
    if (!mounted) return;
    _dirty = false;
    Navigator.of(context).pop(r);
  }

  Future<void> _shareAnnotated() async {
    final r = _rec;
    final photo = _photo;
    if (r == null || photo == null) return;
    setState(() => _busy = true);
    try {
      final jpeg = await compute(
        annotatePhoto,
        AnnotationJob(
          photo: photo,
          plate: r.plate,
          colonies: const [],
          zones: zoneAnnotations(r),
          header: zoneAnnotationHeader(r),
          rimFraction: 1,
        ),
      );
      final safe = r.experiment.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      await shareBytes(
        jpeg,
        'zones_${safe.isEmpty ? 'plate' : safe}_R${r.replicate}_'
            '${DateTime.now().millisecondsSinceEpoch}.jpg',
        'image/jpeg',
        subject: tr.zoneShareSubject,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(tr.reviewCouldNotShare('$e'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr.reviewDiscardTitle),
        content: Text(tr.reviewDiscardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr.reviewKeep),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr.reviewDiscard),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  // ---------------------------------------------------------------------
  // Layout

  @override
  Widget build(BuildContext context) {
    final r = _rec;
    final title = r == null || r.experiment.isEmpty
        ? tr.zoneSetupTitle
        : r.experiment;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) {
          _dirty = false;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title, overflow: TextOverflow.ellipsis),
          actions: [
            IconButton(
              tooltip: tr.reviewUndo,
              onPressed: _undo.isEmpty || _busy ? null : _undoLast,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: tr.zoneFixPlate,
              isSelected: _plateMode,
              onPressed: r == null || _busy ? null : _togglePlateMode,
              icon: const Icon(Icons.radio_button_unchecked),
              selectedIcon: const Icon(Icons.adjust),
            ),
            IconButton(
              tooltip: tr.reviewShareAnnotated,
              onPressed: r == null || _busy || _photo == null || _plateMode
                  ? null
                  : _shareAnnotated,
              icon: const Icon(Icons.share_outlined),
            ),
            IconButton(
              tooltip: tr.zoneDetails,
              onPressed: r == null || _busy ? null : _editDetails,
              icon: const Icon(Icons.edit_note),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(child: _buildImage()),
            if (r != null) _buildPanel(r),
          ],
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (_error != null) {
      return Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)),
      );
    }
    final photo = _photo;
    final r = _rec;
    if (photo == null || r == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(tr.zoneMeasuring),
          ],
        ),
      );
    }
    final w = r.imageWidth.toDouble(), h = r.imageHeight.toDouble();
    return LayoutBuilder(
      builder: (context, box) {
        _fitScale = math.min(box.maxWidth / w, box.maxHeight / h);
        return Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black,
                child: InteractiveViewer(
                  transformationController: _viewer,
                  maxScale: 12,
                  panEnabled: !_plateMode,
                  scaleEnabled: !_plateMode,
                  onInteractionUpdate: (_) => setState(() {}),
                  child: Center(
                    child: FittedBox(
                      child: SizedBox(
                        width: w,
                        height: h,
                        child: RawGestureDetector(
                          key: const ValueKey('zonePhoto'),
                          behavior: HitTestBehavior.opaque,
                          gestures: {
                            _EdgeDragRecognizer:
                                GestureRecognizerFactoryWithHandlers<
                                  _EdgeDragRecognizer
                                >(() => _EdgeDragRecognizer(_acceptDrag), (g) {
                                  // Start where the finger went down (on
                                  // the edge), not after the drag slop.
                                  g.dragStartBehavior = DragStartBehavior.down;
                                  g.onStart = (d) =>
                                      _dragStart(d.localPosition);
                                  g.onUpdate = _dragUpdate;
                                  g.onEnd = (_) => _dragging = null;
                                  g.onCancel = () => _dragging = null;
                                }),
                            TapGestureRecognizer:
                                GestureRecognizerFactoryWithHandlers<
                                  TapGestureRecognizer
                                >(TapGestureRecognizer.new, (g) {
                                  g.onTapUp = (d) => _onTap(d.localPosition);
                                }),
                            LongPressGestureRecognizer:
                                GestureRecognizerFactoryWithHandlers<
                                  LongPressGestureRecognizer
                                >(LongPressGestureRecognizer.new, (g) {
                                  g.onLongPressStart = (d) =>
                                      _onLongPress(d.localPosition);
                                }),
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(
                                photo,
                                fit: BoxFit.fill,
                                gaplessPlayback: true,
                              ),
                              CustomPaint(
                                painter: ZoneOverlayPainter(
                                  plate: _plateMode ? _platePending : r.plate,
                                  marks: r.marks,
                                  diskMm: r.diskMm,
                                  scale: _screenScale,
                                  plateMode: _plateMode,
                                  showMarks: _showMarks,
                                  active: _dragging,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filledTonal(
                tooltip: _showMarks ? tr.reviewHideMarks : tr.reviewShowMarks,
                isSelected: !_showMarks,
                onPressed: () => setState(() => _showMarks = !_showMarks),
                icon: const Icon(Icons.visibility_outlined),
                selectedIcon: const Icon(Icons.visibility_off_outlined),
              ),
            ),
            if (_busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x66000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _chip(ZoneRecord r, int i) {
    final cs = Theme.of(context).colorScheme;
    final m = r.marks[i];
    final mm = m.roundedMm(r.diskMm);
    final name = m.label.isEmpty ? '${i + 1}' : m.label;
    return ActionChip(
      key: ValueKey('zoneChip$i'),
      avatar: m.lowConfidence && !m.opened
          ? Icon(Icons.help_outline, size: 18, color: cs.tertiary)
          : null,
      label: Text(mm == null ? '$name · ?' : '$name · $mm'),
      onPressed: _busy ? null : () => _openMark(i),
    );
  }

  Widget _buildPanel(ZoneRecord r) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final toCheck = r.marks.where((m) => m.lowConfidence && !m.opened).length;
    final warnings = [
      if (r.flags.contains('scale_mismatch')) tr.zoneScaleMismatch,
      if (r.flags.contains('scale_unchecked')) tr.zoneScaleUnchecked,
      if (r.marks.isEmpty) _wells ? tr.zoneNoWells : tr.zoneNoDisks,
    ];
    final pending = _platePending;
    return Material(
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: scrollPadding(
            context,
            const EdgeInsets.fromLTRB(16, 8, 16, 12),
          ).copyWith(bottom: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_plateMode && pending != null) ...[
                Text(tr.zoneHintPlate, style: t.bodySmall),
                Slider(
                  label: tr.reviewSize,
                  value: pending.radius.clamp(
                    r.imageWidth * 0.15,
                    r.imageWidth * 0.7,
                  ),
                  min: r.imageWidth * 0.15,
                  max: r.imageWidth * 0.7,
                  onChanged: (v) => setState(
                    () => _platePending = pending.copyWith(radius: v),
                  ),
                ),
                if (pending.isSquare)
                  Row(
                    children: [
                      const Icon(Icons.rotate_right, size: 20),
                      Expanded(
                        child: Slider(
                          value: pending.angle.clamp(-0.8, 0.8),
                          min: -0.8,
                          max: 0.8,
                          onChanged: (v) => setState(
                            () => _platePending = pending.copyWith(angle: v),
                          ),
                        ),
                      ),
                    ],
                  ),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _applyPlate,
                  icon: const Icon(Icons.refresh),
                  label: Text(tr.zoneMeasureAgain),
                ),
              ] else ...[
                Row(
                  children: [
                    Text(tr.zoneNZones(r.marks.length), style: t.titleMedium),
                    const Spacer(),
                    if (r.marks.isNotEmpty)
                      Text(
                        toCheck == 0
                            ? tr.zoneAllChecked
                            : tr.zoneNToCheck(toCheck),
                        style: t.labelLarge?.copyWith(
                          color: toCheck == 0 ? cs.primary : cs.tertiary,
                        ),
                      ),
                  ],
                ),
                for (final w in warnings)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      w,
                      style: t.bodySmall?.copyWith(color: cs.error),
                    ),
                  ),
                if (r.marks.isNotEmpty)
                  SizedBox(
                    height: 48,
                    // A plate holds a dozen disks at most: build every chip.
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        spacing: 6,
                        children: [
                          for (var i = 0; i < r.marks.length; i++) _chip(r, i),
                        ],
                      ),
                    ),
                  ),
                Text(
                  _wells ? tr.zoneHintWell : tr.zoneHint,
                  style: t.bodySmall,
                ),
                const SizedBox(height: 6),
                FilledButton.icon(
                  onPressed: _busy || _photo == null ? null : _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    widget.record == null
                        ? tr.reviewSavePlate
                        : tr.reviewSaveChanges,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The zones as drawn on a shared photo: size in whole mm and label.
List<AnnotatedZone> zoneAnnotations(ZoneRecord r) => [
  for (var i = 0; i < r.marks.length; i++)
    () {
      final m = r.marks[i];
      final mm = m.roundedMm(r.diskMm);
      final name = m.label.isEmpty ? '${i + 1}' : m.label;
      return AnnotatedZone(
        m.x,
        m.y,
        m.diskRadiusPx,
        m.noZone ? double.nan : m.radiusPx,
        [
          mm == null ? '?' : '$mm mm',
          if (m.noZone) '(no zone)',
          name,
        ].join(' '),
        unsure: !m.measured || (m.lowConfidence && !m.opened),
      );
    }(),
];

/// Banner lines for a shared zone photo (the image fonts are ASCII only, so
/// it is in English like the colony photos).
List<String> zoneAnnotationHeader(ZoneRecord r) => [
  [
    r.experiment.isEmpty ? 'Zone plate' : r.experiment,
    if (r.organism.isNotEmpty) r.organism,
    'Rep ${r.replicate}',
  ].join(' - '),
  '${r.assay == ZoneAssay.well ? 'Wells' : 'Disks'} '
      '${_mmNum(r.diskMm)} mm - ${r.marks.length} zones - '
      '${r.checked ? 'all checked' : 'not all checked'}',
  '${shortDate(r.createdAt)} - zone diameters only, no S/I/R interpretation',
];

/// A pan that only joins the gesture arena when [accept] says so for the
/// point it starts at, so other drags still pan the view.
class _EdgeDragRecognizer extends PanGestureRecognizer {
  _EdgeDragRecognizer(this.accept);

  final bool Function(Offset local) accept;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (accept(event.localPosition)) super.addAllowedPointer(event);
  }
}

/// Plain-language text for a zone flag.
String zoneFlagText(String flag) => switch (flag) {
  'no_zone' => tr.zoneFlagNoZone,
  'overlap' => tr.zoneFlagOverlap,
  'hits_rim' => tr.zoneFlagHitsRim,
  'hazy' => tr.zoneFlagHazy,
  'colonies_in_zone' => tr.zoneFlagColonies,
  'low_confidence' => tr.zoneFlagLowConfidence,
  'unmeasured' => tr.zoneFlagUnmeasured,
  _ => flag,
};

/// A size in mm as text: whole mm plain, else to 0.1 mm.
String _mmNum(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

typedef _SheetResult = ({ZoneMark? mark, bool delete});

/// One disk or well: its label, zone size and flags.
class _ZoneSheet extends StatefulWidget {
  const _ZoneSheet({
    required this.mark,
    required this.number,
    required this.wells,
    required this.diskMm,
    required this.mmPerPx,
    required this.suggestions,
  });

  final ZoneMark mark;
  final int number;
  final bool wells;
  final double diskMm;
  final double mmPerPx;
  final List<String> suggestions;

  @override
  State<_ZoneSheet> createState() => _ZoneSheetState();
}

class _ZoneSheetState extends State<_ZoneSheet> {
  late ZoneMark _m = widget.mark;
  late final _label = TextEditingController(text: widget.mark.label);

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  void _step(int by) {
    final now = _m.noZone || !_m.diameterMm.isFinite
        ? widget.diskMm.round()
        : _m.roundedMm(widget.diskMm)!;
    final mm = math.max(widget.diskMm, (now + by).toDouble());
    setState(
      () => _m = _m.copyWith(
        diameterMm: mm,
        radiusPx: mm / 2 / widget.mmPerPx,
        noZone: false,
      ),
    );
  }

  void _done() => Navigator.pop(context, (
    mark: _m.copyWith(label: _label.text.trim()),
    delete: false,
  ));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final mm = _m.roundedMm(widget.diskMm);
    final flags = _m.flags.where((f) => f != 'no_zone' || _m.noZone).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: scrollPadding(
          context,
          const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.wells
                  ? tr.zoneWellN(widget.number)
                  : tr.zoneDiskN(widget.number),
              style: t.titleLarge,
            ),
            const SizedBox(height: 12),
            Autocomplete<String>(
              initialValue: TextEditingValue(text: _label.text),
              optionsBuilder: (v) => widget.suggestions.where(
                (o) =>
                    o.toLowerCase().contains(v.text.toLowerCase()) &&
                    o != v.text,
              ),
              onSelected: (v) => _label.text = v,
              fieldViewBuilder: (context, controller, focus, _) => TextField(
                key: const ValueKey('zoneLabel'),
                controller: controller,
                focusNode: focus,
                onChanged: (v) => _label.text = v,
                decoration: InputDecoration(
                  labelText: tr.zoneLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(tr.zoneDiameter, style: t.titleSmall),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.outlined(
                  tooltip: tr.zoneSmaller,
                  onPressed: () => _step(-1),
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 140,
                  child: Text(
                    mm == null ? tr.zoneNotMeasured : tr.zoneMm('$mm'),
                    key: const ValueKey('zoneMm'),
                    textAlign: TextAlign.center,
                    style: t.headlineMedium,
                  ),
                ),
                IconButton.outlined(
                  tooltip: tr.zoneLarger,
                  onPressed: () => _step(1),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            if (_m.manual)
              Text(tr.zoneAdded, style: t.bodySmall)
            else if (_m.autoDiameterMm.isFinite &&
                (_m.noZone || (_m.diameterMm - _m.autoDiameterMm).abs() > 1e-6))
              Text(
                tr.zoneAutoWas(_mmNum(_m.autoDiameterMm)),
                style: t.bodySmall,
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr.zoneNoZone),
              subtitle: Text(
                widget.wells
                    ? tr.zoneNoZoneHelpWell(_mmNum(widget.diskMm))
                    : tr.zoneNoZoneHelp(_mmNum(widget.diskMm)),
              ),
              value: _m.noZone,
              onChanged: (v) => setState(() => _m = _m.copyWith(noZone: v)),
            ),
            for (final f in flags)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: cs.tertiary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(zoneFlagText(f), style: t.bodyMedium)),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () =>
                      Navigator.pop(context, (mark: null, delete: true)),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(tr.homeDelete),
                ),
                const Spacer(),
                FilledButton(onPressed: _done, child: Text(tr.multiDone)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Plate outline, disks or wells, and zone circles with their size in whole
/// mm. Zones still to be checked are amber; checked or confident ones green;
/// a disk with no measurement is red.
class ZoneOverlayPainter extends CustomPainter {
  ZoneOverlayPainter({
    required this.plate,
    required this.marks,
    required this.diskMm,
    required this.scale,
    this.plateMode = false,
    this.showMarks = true,
    this.active,
  });

  final Plate? plate;
  final List<ZoneMark> marks;
  final double diskMm;

  /// Image pixels to screen pixels, so strokes stay the same on screen.
  final double scale;
  final bool plateMode;
  final bool showMarks;
  final int? active;

  static const _checked = Colors.lightGreenAccent;
  static const _toCheck = Colors.amberAccent;
  static const _missing = Colors.redAccent;

  @override
  void paint(Canvas canvas, Size size) {
    final px = 1 / scale;
    final pl = plate;
    if (pl != null && (showMarks || plateMode)) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (plateMode ? 3 : 1.5) * px
        ..color = plateMode
            ? Colors.amberAccent
            : Colors.cyanAccent.withValues(alpha: 0.7);
      if (pl.isSquare) {
        canvas.drawPath(
          Path()..addPolygon([
            for (final (x, y) in pl.outline()) Offset(x, y),
          ], true),
          paint,
        );
      } else {
        canvas.drawCircle(Offset(pl.cx, pl.cy), pl.radius, paint);
      }
    }
    if (!showMarks || plateMode) return;
    for (var i = 0; i < marks.length; i++) {
      final m = marks[i];
      final c = Offset(m.x, m.y);
      final zone = m.diameterMm.isFinite && !m.noZone;
      final colour = !m.measured
          ? _missing
          : m.lowConfidence && !m.opened
          ? _toCheck
          : _checked;
      canvas.drawCircle(
        c,
        m.diskRadiusPx,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * px
          ..color = (zone ? Colors.white : colour).withValues(alpha: 0.9),
      );
      canvas.drawCircle(c, 2.5 * px, Paint()..color = colour);
      if (zone) {
        canvas.drawCircle(
          c,
          m.radiusPx,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (i == active ? 3.5 : 2) * px
            ..color = colour,
        );
      }
      final mm = m.roundedMm(diskMm);
      final top = zone ? m.radiusPx : m.diskRadiusPx;
      final text = [
        mm == null ? '?' : '$mm mm',
        if (m.label.isNotEmpty) m.label,
      ].join('\n');
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: Colors.black,
            backgroundColor: colour,
            fontSize: 13 * px,
            fontFamily: 'Roboto',
            fontFamilyFallback: const ['ColonySymbols'],
            fontWeight: FontWeight.bold,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(m.x - tp.width / 2, m.y - top - tp.height - 2 * px),
      );
    }
  }

  @override
  bool shouldRepaint(ZoneOverlayPainter old) =>
      old.plate != plate ||
      old.marks != marks ||
      old.scale != scale ||
      old.plateMode != plateMode ||
      old.showMarks != showMarks ||
      old.active != active;
}
