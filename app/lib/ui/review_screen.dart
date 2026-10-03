import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/classical.dart';
import '../core/pipeline.dart';
import '../core/plate.dart';
import '../data/plate_record.dart';
import '../data/plate_store.dart';
import 'format.dart';
import 'save_sheet.dart';

const double kRimFraction = 0.95;

enum _Mode { zoom, edit, plate }

/// Shows the automatic count over the photo and lets the user correct it.
///
/// Open with [photo] for a new capture (it is counted on arrival) or with
/// [record] to revisit a saved plate.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({
    super.key,
    required this.store,
    this.photo,
    this.record,
    this.guided = false,
  }) : assert(photo != null || record != null);

  final PlateStore store;
  final File? photo;
  final PlateRecord? record;
  final bool guided;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final _viewer = TransformationController();
  late final File _photo;

  bool _busy = false;
  String? _error;
  _Mode _mode = _Mode.edit;

  int _imageW = 0, _imageH = 0;
  Plate? _plate;
  List<Colony> _colonies = [];
  int _autoCount = 0;
  List<String> _flags = [];
  double _kSigma = 4.0;
  final List<List<Colony>> _undo = [];
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    if (r != null) {
      _photo = widget.store.photoFile(r);
      _imageW = r.imageWidth;
      _imageH = r.imageHeight;
      _plate = r.plate;
      _colonies = List.of(r.colonies);
      _autoCount = r.autoCount;
      _flags = List.of(r.flags);
      _kSigma = r.kSigma;
    } else {
      _photo = widget.photo!;
      _recount();
    }
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
      final bytes = await _photo.readAsBytes();
      final res = await countPhotoInBackground(
        bytes,
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
        _colonies = res.colonies;
        _autoCount = res.count;
        _flags = res.flags;
        _undo.clear();
        _dirty = true;
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
    _undo.add(_colonies);
    _dirty = true;
  }

  void _onTap(Offset p) {
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
    setState(() => _colonies = _undo.removeLast());
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
      sampleId: existing?.sampleId ?? _lastSampleId(),
      dilutionExp: existing?.dilutionExp ?? 0,
      volumeMl: existing?.volumeMl ?? widget.store.defaultVolumeMl,
      notes: existing?.notes ?? '',
      spreader: existing?.spreader ?? _flags.contains('spreader'),
      tntc: existing?.tntc ?? _flags.contains('tntc'),
      guided: existing?.guided ?? widget.guided,
      kSigma: _kSigma,
    );
    final result = await showModalBottomSheet<PlateRecord>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SaveSheet(store: widget.store, draft: draft),
    );
    if (result == null) return;
    var record = result;
    if (existing == null) {
      final name = await widget.store.importPhoto(_photo, record.id);
      record = PlateRecord.fromJson({...record.toJson(), 'image': name});
    }
    await widget.store.upsert(record);
    _dirty = false;
    if (mounted) Navigator.of(context).pop();
  }

  String _lastSampleId() =>
      widget.store.records.isEmpty ? '' : widget.store.records.first.sampleId;

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
              onPressed: _busy || _plate == null ? null : _adjustSensitivity,
              icon: const Icon(Icons.tune),
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
    if (_imageW == 0) {
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
        return Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black,
                child: InteractiveViewer(
                  transformationController: _viewer,
                  maxScale: 12,
                  panEnabled: !plateMode,
                  scaleEnabled: !plateMode,
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
                          onPanUpdate: plateMode
                              ? (d) => _movePlate(d.delta)
                              : null,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(
                                _photo,
                                fit: BoxFit.fill,
                                gaplessPlayback: true,
                              ),
                              CustomPaint(
                                painter: _OverlayPainter(
                                  plate: _plate,
                                  colonies: _colonies,
                                  scale: _screenScale,
                                  plateMode: plateMode,
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
    return Material(
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                segments: const [
                  ButtonSegment(
                    value: _Mode.zoom,
                    icon: Icon(Icons.zoom_in),
                    label: Text('Zoom'),
                  ),
                  ButtonSegment(
                    value: _Mode.edit,
                    icon: Icon(Icons.touch_app),
                    label: Text('Edit'),
                  ),
                  ButtonSegment(
                    value: _Mode.plate,
                    icon: Icon(Icons.radio_button_unchecked),
                    label: Text('Plate'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(height: 6),
              Text(switch (_mode) {
                _Mode.zoom => 'Pinch to zoom, drag to pan.',
                _Mode.edit =>
                  'Tap a mark to remove it, tap empty agar to add one. '
                      'Long-press a mark to set how many colonies it contains.',
                _Mode.plate => 'Drag to move the circle, use the slider to resize it, then recount.',
              }, style: t.bodySmall),
              if (_mode == _Mode.plate && _plate != null) ...[
                Slider(
                  value: _plate!.radius.clamp(_imageW * 0.15, _imageW * 0.7),
                  min: _imageW * 0.15,
                  max: _imageW * 0.7,
                  onChanged: (v) =>
                      setState(() => _plate = _plate!.copyWith(radius: v)),
                ),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _applyPlate,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Recount with this circle'),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: FilledButton.icon(
                    onPressed: _busy || _plate == null ? null : _save,
                    icon: const Icon(Icons.check),
                    label: Text(
                      widget.record == null ? 'Save plate' : 'Save changes',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter({
    required this.plate,
    required this.colonies,
    required this.scale,
    required this.plateMode,
  });

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
    final auto = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * px
      ..color = Colors.greenAccent;
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
      final paint = c.n > 1 ? cluster : (c.manual ? manual : auto);
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
      old.plateMode != plateMode;
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
