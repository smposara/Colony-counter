import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/pipeline.dart';
import '../core/plate.dart';
import '../data/plate_record.dart';
import '../data/plate_store.dart';
import '../data/sample_info.dart';
import '../l10n/l10n.dart';
import 'format.dart';
import 'photo_flow.dart';
import 'review_screen.dart';

/// Takes or picks a photo with several plates and opens [MultiPlateScreen].
/// With [info], the plates are assigned to that sample's remaining plates
/// in reading order.
Future<void> countSeveralPlates(
  BuildContext context,
  PlateStore store, {
  SampleInfo? info,
}) async {
  final format = info?.format ?? store.defaultFormat;
  if (format.shape == PlateShape.square) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr.multiRoundOnly)));
    return;
  }
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(tr.multiLayPlates),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: Text(tr.multiTakePhoto),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(tr.multiChoosePhoto),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return;
  final picked = await ImagePicker().pickImage(
    source: source,
    maxWidth: kIsWeb ? 4000 : null,
    maxHeight: kIsWeb ? 4000 : null,
  );
  if (picked == null) return;
  final bytes = await picked.readAsBytes();
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => MultiPlateScreen(
        store: store,
        photo: bytes,
        format: format,
        info: info,
      ),
    ),
  );
}

/// Finds every plate in one photo; each is then counted and saved on its own.
class MultiPlateScreen extends StatefulWidget {
  const MultiPlateScreen({
    super.key,
    required this.store,
    required this.photo,
    this.format = PlateFormat.dish90,
    this.info,
  });

  final PlateStore store;
  final Uint8List photo;
  final PlateFormat format;
  final SampleInfo? info;

  @override
  State<MultiPlateScreen> createState() => _MultiPlateScreenState();
}

class _MultiPlateScreenState extends State<MultiPlateScreen> {
  List<Plate> _plates = [];
  int _w = 0, _h = 0;
  bool _busy = true;
  bool _editing = false;
  String? _error;

  /// Saved record per plate index.
  final Map<int, PlateRecord> _done = {};

  @override
  void initState() {
    super.initState();
    _find();
  }

  Future<void> _find() async {
    try {
      final job = (widget.photo, widget.format);
      final res = kIsWeb
          ? await Future<void>.delayed(const Duration(milliseconds: 60))
                .then((_) => findPlatesInPhoto(job))
          : await compute(findPlatesInPhoto, job);
      if (!mounted) return;
      setState(() {
        _plates = res.plates;
        _w = res.width;
        _h = res.height;
      });
    } catch (e) {
      if (mounted) setState(() => _error = tr.multiNoPlatesFound);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The sample plan's plate for each plate not yet saved, in order.
  Map<int, Slot> get _slots {
    final info = widget.info;
    if (info == null) return const {};
    final saved = widget.store.platesOf(info.sampleId);
    final left = [
      for (final s in info.slots)
        if (!saved.any(s.matches)) s,
    ];
    final out = <int, Slot>{};
    var k = 0;
    for (var i = 0; i < _plates.length && k < left.length; i++) {
      if (!_done.containsKey(i)) out[i] = left[k++];
    }
    return out;
  }

  int? _hit(Offset p) {
    for (var i = 0; i < _plates.length; i++) {
      if (_plates[i].contains(p.dx, p.dy)) return i;
    }
    return null;
  }

  void _tap(Offset p) {
    final i = _hit(p);
    if (!_editing) {
      if (i != null) _open(i);
      return;
    }
    setState(() {
      if (i != null) {
        if (_done.containsKey(i)) return;
        _plates = [..._plates]..removeAt(i);
        // Saved plates keep their index.
        final moved = {
          for (final e in _done.entries)
            (e.key > i ? e.key - 1 : e.key): e.value,
        };
        _done
          ..clear()
          ..addAll(moved);
      } else {
        final radii = [for (final pl in _plates) pl.radius]..sort();
        final r = radii.isEmpty
            ? math.min(_w, _h) * 0.2
            : radii[radii.length ~/ 2];
        _plates = [
          ..._plates,
          Plate(p.dx, p.dy, r, diameterMm: widget.format.sizeMm),
        ];
      }
    });
  }

  Future<void> _open(int i) async {
    if (_done.containsKey(i)) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReviewScreen(store: widget.store, record: _done[i]!),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    final job = (widget.photo, _plates[i]);
    final (crop, plate) = kIsWeb
        ? cropToPlate(job)
        : await compute(cropToPlate, job);
    if (!mounted) return;
    setState(() => _busy = false);
    final slot = _slots[i];
    final record = await Navigator.of(context).push<PlateRecord>(
      MaterialPageRoute(
        builder: (_) => ReviewScreen(
          store: widget.store,
          photo: crop,
          initialPlate: plate,
          preset: slot == null
              ? null
              : PlatePreset(info: widget.info!, slot: slot),
        ),
      ),
    );
    if (record != null && mounted) setState(() => _done[i] = record);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final slots = _slots;
    final left = _plates.length - _done.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _plates.isEmpty
              ? tr.multiPlatesInPhoto
              : tr.multiPlatesFound(_plates.length),
        ),
        actions: [
          if (_plates.isNotEmpty || _error == null)
            IconButton(
              tooltip: _editing ? tr.multiDone : tr.multiAddRemove,
              isSelected: _editing,
              onPressed: _busy
                  ? null
                  : () => setState(() => _editing = !_editing),
              icon: Icon(_editing ? Icons.check : Icons.edit_outlined),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _error != null && _plates.isEmpty && !_editing
                ? Center(child: Text(_error!))
                : _w == 0
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                    children: [
                      Positioned.fill(
                        child: ColoredBox(
                          color: Colors.black,
                          child: InteractiveViewer(
                            maxScale: 6,
                            child: Center(
                              child: FittedBox(
                                child: SizedBox(
                                  width: _w.toDouble(),
                                  height: _h.toDouble(),
                                  child: GestureDetector(
                                    onTapUp: (d) => _tap(d.localPosition),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.memory(
                                          widget.photo,
                                          fit: BoxFit.fill,
                                        ),
                                        CustomPaint(
                                          painter: _PlatesPainter(
                                            plates: _plates,
                                            done: _done,
                                            editing: _editing,
                                            labelSize: math.max(_w, _h) / 30,
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
                  ),
          ),
          Material(
            elevation: 3,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _editing
                          ? tr.multiEditHint
                          : _plates.isEmpty
                          ? tr.multiUsePencil
                          : left == 0
                          ? tr.multiAllSaved
                          : tr.multiTapToCount(left),
                      style: t.bodyMedium,
                    ),
                    if (_plates.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (var i = 0; i < _plates.length; i++)
                            ActionChip(
                              avatar: Icon(
                                _done.containsKey(i)
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                size: 18,
                              ),
                              label: Text(
                                _done.containsKey(i)
                                    ? '${i + 1}: ${plateLabel(_done[i]!)} · ${_done[i]!.count}'
                                    : slots[i] == null
                                    ? '${i + 1}'
                                    : '${i + 1}: ${_slotLabel(slots[i]!)}',
                              ),
                              onPressed: _busy || _editing
                                  ? null
                                  : () => _open(i),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _slotLabel(Slot s) => [
    if (s.dilutionExp != null) dilutionLabel(s.dilutionExp!),
    if (s.replicate != null) 'R${s.replicate}',
  ].join(' · ');
}

class _PlatesPainter extends CustomPainter {
  _PlatesPainter({
    required this.plates,
    required this.done,
    required this.editing,
    required this.labelSize,
  });

  final List<Plate> plates;
  final Map<int, PlateRecord> done;
  final bool editing;
  final double labelSize;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < plates.length; i++) {
      final p = plates[i];
      final saved = done.containsKey(i);
      final colour = saved
          ? Colors.greenAccent
          : editing
          ? Colors.amberAccent
          : Colors.cyanAccent;
      canvas.drawCircle(
        Offset(p.cx, p.cy),
        p.radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = labelSize / 8
          ..color = colour,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: Colors.black,
            backgroundColor: colour,
            fontSize: labelSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(p.cx - tp.width / 2, p.cy - p.radius - tp.height * 0.6),
      );
    }
  }

  @override
  bool shouldRepaint(_PlatesPainter old) => true;
}
