import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/background.dart';
import '../core/classical.dart';
import '../core/colour.dart';
import '../core/pipeline.dart';
import '../core/plate.dart';
import '../core/spots.dart';
import '../data/plate_record.dart';
import '../data/plate_store.dart';
import '../data/sample_info.dart';
import 'format.dart';
import 'photo_flow.dart';
import 'save_sheet.dart';

const double kRimFraction = 0.95;

enum _Mode { zoom, edit, plate, spots, colour }

/// Default drop diameter for a 10 µL drop on agar.
const double kDropDiameterMm = 7;

/// Shows the automatic count over the photo and lets the user correct it.
///
/// Open with [photo] (encoded image bytes) for a new capture (it is counted on arrival) or with
/// [record] to revisit a saved plate.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    super.key,
    required this.store,
    this.photo,
    this.record,
    this.guided = false,
    this.preset,
  }) : assert(photo != null || record != null);

  final PlateStore store;
  final Uint8List? photo;
  final PlateRecord? record;
  final bool guided;

  /// Sample plan and plate slot this new photo belongs to, if any.
  final PlatePreset? preset;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final _viewer = TransformationController();
  Uint8List? _photo;

  bool _busy = false;
  String? _error;
  _Mode _mode = _Mode.edit;

  int _imageW = 0, _imageH = 0;
  Plate? _plate;
  List<Colony> _colonies = [];
  int _autoCount = 0;
  List<String> _flags = [];
  double _kSigma = 4.0;
  final List<(List<Colony>, List<Spot>)> _undo = [];
  bool _dirty = false;

  /// Drops of a drop plate (empty for whole plates).
  List<Spot> _spots = [];
  bool _drop = false;
  ColourMode _colourMode = ColourMode.none;
  int? _dragSpot;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    if (r != null) {
      _loadSavedPhoto(r);
      _imageW = r.imageWidth;
      _imageH = r.imageHeight;
      _plate = r.plate;
      _colonies = List.of(r.colonies);
      _autoCount = r.autoCount;
      _flags = List.of(r.flags);
      _kSigma = r.kSigma;
      _spots = List.of(r.spots);
      _drop = r.isDropPlate;
      _colourMode = r.colourMode;
    } else {
      final info = widget.preset?.info;
      _drop = info?.isDrop ?? false;
      _colourMode = info?.colourMode ?? ColourMode.none;
      _photo = widget.photo!;
      _recount();
    }
  }

  Future<void> _loadSavedPhoto(PlateRecord r) async {
    final bytes = await widget.store.readPhoto(r);
    if (!mounted) return;
    setState(() {
      _photo = bytes;
      if (bytes == null) _error = 'The photo for this plate is missing.';
    });
  }

  int get _count => _colonies.fold(0, (s, c) => s + c.n);
  int get _added => _colonies.where((c) => c.manual).length;
  int get _removed =>
      _autoCount - _colonies.where((c) => !c.manual).fold(0, (s, c) => s + c.n);
  bool get _hasEdits => _undo.isNotEmpty || _added > 0 || _removed != 0;

  Future<void> _recount({Plate? plate}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await countPhotoInBackground(
        _photo!,
        CountOptions(
          plate: plate,
          rimFraction: kRimFraction,
          params: DetectParams(kSigma: _kSigma),
        ),
      );
      if (!mounted) return;
      setState(() {
        _imageW = res.imageWidth;
        _imageH = res.imageHeight;
        _plate = res.plate;
        _colonies = _classified(res.colonies, _colourMode);
        _autoCount = res.count;
        _flags = res.flags;
        _undo.clear();
        _dirty = true;
        if (_drop && _spots.isEmpty) _spots = _suggestSpots();
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not count this photo: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmDiscardEdits() async {
    if (!_hasEdits) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recount plate?'),
        content: const Text(
          'Your manual additions and removals will be discarded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Recount'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  // --- drops and colours ----------------------------------------------------

  static List<Colony> _classified(List<Colony> colonies, ColourMode mode) {
    if (mode == ColourMode.none) {
      return [for (final c in colonies) c.withCls(0)];
    }
    final measured = [
      for (final c in colonies)
        if (c.colour != null) c.colour!,
    ];
    final cls = classifyColours(measured, mode);
    var k = 0;
    return [
      for (final c in colonies) c.colour == null ? c : c.withCls(cls[k++]),
    ];
  }

  double get _dropRadiusPx => kDropDiameterMm / 2 / (_plate?.mmPerPx ?? 0.05);

  /// Dilution and replicate for the [i]-th drop, from the sample plan.
  Spot _labelSpot(Spot s, int i) {
    final preset = widget.preset;
    final info = preset?.info;
    if (info == null || !info.isDrop) {
      return s.copyWith(
        dilutionExp: widget.record?.dilutionExp ?? 0,
        replicate: i + 1,
      );
    }
    if (info.dropLayout == DropLayout.replicates) {
      return s.copyWith(
        dilutionExp: preset!.slot.dilutionExp ?? info.dilutions.first,
        replicate: i % info.replicates + 1,
      );
    }
    return s.copyWith(
      dilutionExp: info.dilutions[i % info.dilutions.length],
      replicate: preset!.slot.replicate ?? 1,
    );
  }

  List<Spot> _suggestSpots() {
    final pl = _plate;
    if (pl == null) return [];
    final found = suggestSpots(
      _colonies,
      pl.mmPerPx,
      dropDiameterMm: kDropDiameterMm,
    );
    return [for (var i = 0; i < found.length; i++) _labelSpot(found[i], i)];
  }

  int? _hitSpot(Offset p) {
    int? best;
    for (var i = 0; i < _spots.length; i++) {
      if (_spots[i].contains(p.dx, p.dy) &&
          (best == null || _spots[i].radius < _spots[best].radius)) {
        best = i;
      }
    }
    return best;
  }

  void _setDrop(bool drop) {
    setState(() {
      _push();
      _drop = drop;
      if (drop && _spots.isEmpty) _spots = _suggestSpots();
      if (!drop) _spots = [];
      _mode = drop ? _Mode.spots : _Mode.edit;
    });
  }

  void _setColourMode(ColourMode mode) {
    setState(() {
      _push();
      _colourMode = mode;
      _colonies = _classified(_colonies, mode);
      _mode = mode == ColourMode.none ? _Mode.edit : _Mode.colour;
    });
  }

  Future<void> _editSpot(int i) async {
    // A Spot to keep, 'delete' to remove it, or null when dismissed.
    final result = await showDialog<Object>(
      context: context,
      builder: (context) => _SpotDialog(
        spot: _spots[i],
        index: i,
        count: countInSpot(_spots[i], _colonies),
        mmPerPx: _plate?.mmPerPx ?? 0.05,
      ),
    );
    if (!mounted || result == null || result == _spots[i]) return;
    setState(() {
      _push();
      final next = [..._spots];
      if (result is Spot) {
        next[i] = result;
      } else {
        next.removeAt(i);
      }
      _spots = next;
    });
  }

  // --- editing -------------------------------------------------------------

  /// Image pixels → screen pixels at the current zoom.
  double get _screenScale => _fitScale * _viewer.value.getMaxScaleOnAxis();
  double _fitScale = 1;

  int? _hit(Offset p) {
    final minHit = 16 / _screenScale; // at least ~16 screen px
    int? best;
    var bestD = double.infinity;
    for (var i = 0; i < _colonies.length; i++) {
      final c = _colonies[i];
      final d = (Offset(c.x, c.y) - p).distance;
      if (d <= math.max(c.radiusPx * 1.3, minHit) && d < bestD) {
        best = i;
        bestD = d;
      }
    }
    return best;
  }

  double get _typicalRadius {
    final r = [
      for (final c in _colonies)
        if (!c.manual && c.n == 1) c.radiusPx,
    ]..sort();
    if (r.isEmpty) return 0.5 / (_plate?.mmPerPx ?? 0.05);
    return r[r.length ~/ 2];
  }

  bool _insidePlate(Offset p) {
    final pl = _plate;
    if (pl == null) return false;
    return (p - Offset(pl.cx, pl.cy)).distance <= pl.radius * kRimFraction;
  }

  void _push() {
    _undo.add((_colonies, _spots));
    _dirty = true;
  }

  void _onTap(Offset p) {
    if (_mode == _Mode.spots) {
      final i = _hitSpot(p);
      if (i != null) {
        _editSpot(i);
      } else if (_insidePlate(p)) {
        setState(() {
          _push();
          _spots = [
            ..._spots,
            _labelSpot(Spot(p.dx, p.dy, _dropRadiusPx), _spots.length),
          ];
        });
      }
      return;
    }
    if (_mode == _Mode.colour) {
      final i = _hit(p);
      if (i == null) return;
      setState(() {
        _push();
        _colonies = [..._colonies]
          ..[i] = _colonies[i].withCls(1 - _colonies[i].cls);
      });
      return;
    }
    if (_mode != _Mode.edit) return;
    final i = _hit(p);
    setState(() {
      if (i != null) {
        _push();
        _colonies = [..._colonies]..removeAt(i);
      } else if (_insidePlate(p)) {
        _push();
        _colonies = [
          ..._colonies,
          Colony(p.dx, p.dy, _typicalRadius, manual: true),
        ];
      }
    });
  }

  Future<void> _onLongPress(Offset p) async {
    if (_mode != _Mode.edit) return;
    final i = _hit(p);
    if (i == null) return;
    final n = await showDialog<int>(
      context: context,
      builder: (context) => _ClusterDialog(initial: _colonies[i].n),
    );
    if (n == null || n == _colonies[i].n) return;
    setState(() {
      _push();
      _colonies = [..._colonies]..[i] = _colonies[i].withN(n);
    });
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    setState(() {
      final (colonies, spots) = _undo.removeLast();
      _colonies = colonies;
      _spots = spots;
    });
  }

  void _panStart(Offset p) {
    if (_mode != _Mode.spots) return;
    _dragSpot = _hitSpot(p);
    if (_dragSpot != null) _push();
  }

  void _panUpdate(Offset delta) {
    if (_mode == _Mode.plate) return _movePlate(delta);
    final i = _dragSpot;
    if (i == null) return;
    setState(() {
      final s = _spots[i];
      _spots = [..._spots]
        ..[i] = s.copyWith(cx: s.cx + delta.dx, cy: s.cy + delta.dy);
    });
  }

  void _movePlate(Offset delta) {
    final pl = _plate;
    if (pl == null) return;
    setState(
      () => _plate = pl.copyWith(cx: pl.cx + delta.dx, cy: pl.cy + delta.dy),
    );
  }

  Future<void> _applyPlate() async {
    if (!await _confirmDiscardEdits()) return;
    await _recount(plate: _plate);
    if (mounted) setState(() => _mode = _Mode.edit);
  }

  Future<void> _adjustSensitivity() async {
    final value = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (context) => _SensitivitySheet(initial: _kSigma),
    );
    if (value == null || value == _kSigma) return;
    if (!await _confirmDiscardEdits()) return;
    _kSigma = value;
    await _recount(plate: _plate);
  }

  Future<void> _save() async {
    final plate = _plate;
    if (plate == null) return;
    final existing = widget.record;
    final draft = PlateRecord(
      id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      createdAt: existing?.createdAt ?? DateTime.now(),
      imagePath: existing?.imagePath ?? '',
      imageWidth: _imageW,
      imageHeight: _imageH,
      plate: plate,
      colonies: _colonies,
      autoCount: _autoCount,
      flags: _flags,
      sampleId: existing?.sampleId ?? widget.preset?.info.sampleId ?? '',
      dilutionExp:
          existing?.dilutionExp ?? widget.preset?.slot.dilutionExp ?? 0,
      volumeMl:
          existing?.volumeMl ??
          widget.preset?.info.unitVolumeMl ??
          (_drop ? 0.01 : widget.store.defaultVolumeMl),
      notes: existing?.notes ?? '',
      spreader: existing?.spreader ?? _flags.contains('spreader'),
      tntc: existing?.tntc ?? _flags.contains('tntc'),
      guided: existing?.guided ?? widget.guided,
      kSigma: _kSigma,
      replicate: existing?.replicate ?? widget.preset?.slot.replicate ?? 1,
      spots: _drop ? _spots : const [],
      colourMode: _colourMode,
    );
    final result = await showModalBottomSheet<PlateRecord>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SaveSheet(
        store: widget.store,
        draft: draft,
        fixedSample: widget.preset != null,
      ),
    );
    if (result == null) return;
    var record = result;
    if (existing == null) {
      final name = await widget.store.savePhoto(_photo!, record.id);
      record = PlateRecord.fromJson({...record.toJson(), 'image': name});
    }
    await widget.store.upsert(record);
    _dirty = false;
    if (mounted) Navigator.of(context).pop();
  }

  // --- UI ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard this count?'),
            content: const Text('It has not been saved.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        );
        if ((leave ?? false) && context.mounted) {
          _dirty = false;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Review count'),
          actions: [
            IconButton(
              tooltip: 'Undo',
              onPressed: _undo.isEmpty ? null : _undoLast,
              icon: const Icon(Icons.undo),
            ),
            IconButton(
              tooltip: 'Detection sensitivity',
              onPressed: _busy || _plate == null || _photo == null
                  ? null
                  : _adjustSensitivity,
              icon: const Icon(Icons.tune),
            ),
            PopupMenuButton<Object>(
              enabled: _plate != null,
              tooltip: 'Plate type and colours',
              onSelected: (v) =>
                  v is ColourMode ? _setColourMode(v) : _setDrop(!_drop),
              itemBuilder: (_) => [
                CheckedPopupMenuItem(
                  value: 'drop',
                  checked: _drop,
                  child: const Text('Drop plate'),
                ),
                const PopupMenuDivider(),
                for (final m in ColourMode.values)
                  CheckedPopupMenuItem(
                    value: m,
                    checked: _colourMode == m,
                    child: Text('Colours: ${m.label}'),
                  ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(child: _buildImage()),
            if (_plate != null) _buildPanel(),
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
    if (_imageW == 0 || photo == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Counting colonies…'),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        _fitScale = math.min(box.maxWidth / _imageW, box.maxHeight / _imageH);
        final plateMode = _mode == _Mode.plate;
        // Dragging moves the plate circle or a drop instead of the view.
        final lockView = plateMode || _mode == _Mode.spots;
        return Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black,
                child: InteractiveViewer(
                  transformationController: _viewer,
                  maxScale: 12,
                  panEnabled: !lockView,
                  scaleEnabled: !lockView,
                  onInteractionUpdate: (_) =>
                      setState(() {}), // keep stroke widths crisp
                  child: Center(
                    child: FittedBox(
                      child: SizedBox(
                        width: _imageW.toDouble(),
                        height: _imageH.toDouble(),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (d) => _onTap(d.localPosition),
                          onLongPressStart: (d) =>
                              _onLongPress(d.localPosition),
                          onPanStart: lockView
                              ? (d) => _panStart(d.localPosition)
                              : null,
                          onPanUpdate: lockView
                              ? (d) => _panUpdate(d.delta)
                              : null,
                          onPanEnd: lockView ? (_) => _dragSpot = null : null,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(
                                photo,
                                fit: BoxFit.fill,
                                gaplessPlayback: true,
                              ),
                              CustomPaint(
                                painter: _OverlayPainter(
                                  plate: _plate,
                                  colonies: _colonies,
                                  scale: _screenScale,
                                  plateMode: plateMode,
                                  spots: _drop ? _spots : const [],
                                  colourMode: _colourMode,
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

  Widget _buildPanel() {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final edits = [
      if (_added > 0) '+$_added added',
      if (_removed > 0) '−$_removed removed',
      if (_removed < 0) '+${-_removed} in clusters',
    ];
    final modes = [
      (_Mode.zoom, Icons.zoom_in, 'Zoom'),
      (_Mode.edit, Icons.touch_app, 'Edit'),
      (_Mode.plate, Icons.radio_button_unchecked, 'Plate'),
      if (_drop) (_Mode.spots, Icons.bubble_chart_outlined, 'Drops'),
      if (_colourMode != ColourMode.none)
        (_Mode.colour, Icons.palette_outlined, 'Colour'),
    ];
    if (!modes.any((m) => m.$1 == _mode)) _mode = _Mode.edit;
    final compact = modes.length > 3;
    return Material(
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Details scroll on short phones; the Save / Recount actions below
            // always stay visible.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.4,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$_count',
                          style: t.displaySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('CFU', style: t.titleMedium),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Text(
                              edits.isEmpty
                                  ? 'automatic'
                                  : 'auto $_autoCount · ${edits.join(' · ')}',
                              style: t.bodySmall,
                              textAlign: TextAlign.end,
                              maxLines: 2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_colourMode != ColourMode.none) _classSummary(t),
                    if (_drop) _dropSummary(t),
                    if (_flags.isNotEmpty)
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final f in _flags)
                            Chip(
                              label: Text(flagLabel(f)),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: f == 'clusters_estimated'
                                  ? null
                                  : cs.errorContainer,
                            ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    SegmentedButton<_Mode>(
                      showSelectedIcon: !compact,
                      segments: [
                        for (final (mode, icon, label) in modes)
                          ButtonSegment(
                            value: mode,
                            icon: compact ? null : Icon(icon),
                            label: Text(label),
                          ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (s) =>
                          setState(() => _mode = s.first),
                    ),
                    const SizedBox(height: 6),
                    Text(switch (_mode) {
                      _Mode.zoom => 'Pinch to zoom, drag to pan.',
                      _Mode.edit =>
                        'Tap a mark to remove it, tap empty agar to add one. '
                            'Long-press a mark to set how many colonies it contains.',
                      _Mode.plate => 'Drag to move the circle, use the slider to resize it, then recount.',
                      _Mode.spots =>
                        'Tap a drop to set its dilution and replicate, tap empty agar to add a drop, '
                            'drag a drop to move it.',
                      _Mode.colour =>
                        'Tap a colony to switch its colour class.',
                    }, style: t.bodySmall),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_mode == _Mode.plate && _plate != null) ...[
                    Slider(
                      value: _plate!.radius.clamp(
                        _imageW * 0.15,
                        _imageW * 0.7,
                      ),
                      min: _imageW * 0.15,
                      max: _imageW * 0.7,
                      onChanged: (v) =>
                          setState(() => _plate = _plate!.copyWith(radius: v)),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _busy || _photo == null ? null : _applyPlate,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Recount with this circle'),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: FilledButton.icon(
                        onPressed: _busy || _plate == null || _photo == null
                            ? null
                            : _save,
                        icon: const Icon(Icons.check),
                        label: Text(
                          widget.record == null ? 'Save plate' : 'Save changes',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _classSummary(TextTheme t) {
    final counts = List.filled(_colourMode.classNames.length, 0);
    for (final c in _colonies) {
      counts[c.cls.clamp(0, counts.length - 1)] += c.n;
    }
    final total = counts.fold(0, (a, b) => a + b);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        spacing: 14,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var k = 0; k < counts.length; k++)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ClassDot(colour: _classColour(_colourMode, k)),
                const SizedBox(width: 4),
                Text(
                  '${_colourMode.classNames[k]} ${counts[k]}',
                  style: t.bodyMedium,
                ),
              ],
            ),
          if (total > 0)
            Text(
              '${(counts[1] / total * 100).toStringAsFixed(1)} % '
              '${_colourMode.classNames[1].toLowerCase()}',
              style: t.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _dropSummary(TextTheme t) {
    if (_spots.isEmpty) {
      return Text(
        'No drops marked yet: use Drops to add them.',
        style: t.bodySmall,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (var i = 0; i < _spots.length; i++)
            ActionChip(
              visualDensity: VisualDensity.compact,
              label: Text(
                '${i + 1}: ${dilutionLabel(_spots[i].dilutionExp)} R${_spots[i].replicate} · '
                '${_spots[i].tntc ? 'TNTC' : countInSpot(_spots[i], _colonies)}',
              ),
              onPressed: () => _editSpot(i),
            ),
        ],
      ),
    );
  }
}

Color _classColour(ColourMode mode, int cls) => switch ((mode, cls)) {
  (ColourMode.blueWhite, 1) => const Color(0xFF40C4FF),
  (ColourMode.twoColours, 1) => const Color(0xFFFF4081),
  _ => Colors.greenAccent,
};

class _ClassDot extends StatelessWidget {
  const _ClassDot({required this.colour});

  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: colour, width: 2.5),
    ),
  );
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter({
    required this.plate,
    required this.colonies,
    required this.scale,
    required this.plateMode,
    required this.spots,
    required this.colourMode,
  });

  final List<Spot> spots;
  final ColourMode colourMode;
  final Plate? plate;
  final List<Colony> colonies;

  /// Image pixels to screen pixels, so strokes stay ~2 px on screen at any zoom.
  final double scale;
  final bool plateMode;

  @override
  void paint(Canvas canvas, Size size) {
    final px = 1 / scale;
    final pl = plate;
    if (pl != null) {
      canvas.drawCircle(
        Offset(pl.cx, pl.cy),
        pl.radius * kRimFraction,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (plateMode ? 3 : 1.5) * px
          ..color = plateMode
              ? Colors.amberAccent
              : Colors.cyanAccent.withValues(alpha: 0.8),
      );
      if (plateMode) {
        canvas.drawCircle(
          Offset(pl.cx, pl.cy),
          pl.radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1 * px
            ..color = Colors.amberAccent.withValues(alpha: 0.5),
        );
      }
    }
    for (var i = 0; i < spots.length; i++) {
      final sp = spots[i];
      canvas.drawCircle(
        Offset(sp.cx, sp.cy),
        sp.radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * px
          ..color = sp.tntc ? Colors.redAccent : Colors.amberAccent,
      );
      final label = TextPainter(
        text: TextSpan(
          text: '${i + 1} · ${sp.tntc ? 'TNTC' : countInSpot(sp, colonies)}',
          style: TextStyle(
            color: Colors.black,
            backgroundColor: sp.tntc ? Colors.redAccent : Colors.amberAccent,
            fontSize: 13 * px,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(
        canvas,
        Offset(
          sp.cx - label.width / 2,
          sp.cy - sp.radius - label.height - 2 * px,
        ),
      );
    }
    final auto = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * px
      ..color = Colors.greenAccent;
    final class1 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 * px
      ..color = _classColour(colourMode, 1);
    final manual = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * px
      ..color = Colors.pinkAccent;
    final cluster = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 * px
      ..color = Colors.orangeAccent;
    for (final c in colonies) {
      final r = math.max(c.radiusPx * 1.25, 5 * px);
      final paint = c.n > 1
          ? cluster
          : (c.manual
                ? manual
                : (colourMode != ColourMode.none && c.cls == 1
                      ? class1
                      : auto));
      canvas.drawCircle(Offset(c.x, c.y), r, paint);
      if (c.n > 1) {
        final tp = TextPainter(
          text: TextSpan(
            text: '×${c.n}',
            style: TextStyle(
              color: Colors.orangeAccent,
              fontSize: 13 * px,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(c.x + r, c.y - tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter old) =>
      old.plate != plate ||
      old.colonies != colonies ||
      old.scale != scale ||
      old.plateMode != plateMode ||
      old.spots != spots ||
      old.colourMode != colourMode;
}

class _ClusterDialog extends StatefulWidget {
  const _ClusterDialog({required this.initial});

  final int initial;

  @override
  State<_ClusterDialog> createState() => _ClusterDialogState();
}

class _ClusterDialogState extends State<_ClusterDialog> {
  late int _n = widget.initial;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Colonies in this mark'),
      content: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton.outlined(
            onPressed: _n > 1 ? () => setState(() => _n--) : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 64,
            child: Text(
              '$_n',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          IconButton.outlined(
            onPressed: _n < 50 ? () => setState(() => _n++) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _n),
          child: const Text('Set'),
        ),
      ],
    );
  }
}

class _SensitivitySheet extends StatefulWidget {
  const _SensitivitySheet({required this.initial});

  final double initial;

  @override
  State<_SensitivitySheet> createState() => _SensitivitySheetState();
}

class _SensitivitySheetState extends State<_SensitivitySheet> {
  // The slider shows sensitivity; the detector threshold k·σ runs the other way.
  late double _k = widget.initial;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Detection sensitivity', style: t.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Higher finds fainter and smaller colonies but may count debris. '
            'Default: 6.5.',
            style: t.bodySmall,
          ),
          Row(
            children: [
              const Text('Low'),
              Expanded(
                child: Slider(
                  value: 10.5 - _k,
                  min: 2.5,
                  max: 8,
                  divisions: 11,
                  label: (10.5 - _k).toStringAsFixed(1),
                  onChanged: (v) => setState(() => _k = 10.5 - v),
                ),
              ),
              const Text('High'),
            ],
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _k),
            child: const Text('Recount'),
          ),
        ],
      ),
    );
  }
}

class _SpotDialog extends StatefulWidget {
  const _SpotDialog({
    required this.spot,
    required this.index,
    required this.count,
    required this.mmPerPx,
  });

  final Spot spot;
  final int index;
  final int count;
  final double mmPerPx;

  @override
  State<_SpotDialog> createState() => _SpotDialogState();
}

class _SpotDialogState extends State<_SpotDialog> {
  late Spot _s = widget.spot;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final diameterMm = _s.radius * 2 * widget.mmPerPx;
    return AlertDialog(
      title: Text('Drop ${widget.index + 1} · ${widget.count} colonies'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _s.dilutionExp,
                  decoration: const InputDecoration(
                    labelText: 'Dilution',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (var e = 0; e <= 10; e++)
                      DropdownMenuItem(value: e, child: Text(dilutionLabel(e))),
                  ],
                  onChanged: (v) =>
                      setState(() => _s = _s.copyWith(dilutionExp: v)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _s.replicate,
                  decoration: const InputDecoration(
                    labelText: 'Replicate',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (var r = 1; r <= 12; r++)
                      DropdownMenuItem(value: r, child: Text('R$r')),
                  ],
                  onChanged: (v) =>
                      setState(() => _s = _s.copyWith(replicate: v)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Too numerous to count'),
            subtitle: const Text('Confluent drop'),
            value: _s.tntc,
            onChanged: (v) => setState(() => _s = _s.copyWith(tntc: v)),
          ),
          Text('Size ${diameterMm.toStringAsFixed(1)} mm', style: t.bodySmall),
          Slider(
            value: diameterMm.clamp(2, 20),
            min: 2,
            max: 20,
            onChanged: (v) => setState(
              () => _s = _s.copyWith(radius: v / 2 / widget.mmPerPx),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 'delete'),
          child: const Text('Delete drop'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _s),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
