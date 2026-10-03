import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../core/capture_quality.dart';

/// Guide circle diameter as a fraction of the preview's shorter side.
const double kGuideFraction = 0.8;
const double kMaxTiltDeg = 3;
const double kMaxGlare = 0.005;

/// Camera with a plate guide and live checks (level, focus, glare).
/// Pops with the path of the captured photo.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  String? _error;
  StreamSubscription<AccelerometerEvent>? _accel;
  final _sharpTracker = SharpnessTracker();
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);

  double _tilt = 90;
  bool _sharp = false;
  double _glare = 0;
  bool _locked = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _accel = accelerometerEventStream(samplingPeriod: SensorInterval.uiInterval)
        .listen((e) {
          final t = tiltDegrees(e.x, e.y, e.z);
          if ((t - _tilt).abs() > 0.2 && mounted) setState(() => _tilt = t);
        }, onError: (_) {});
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final c = CameraController(
        back,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      await c.initialize();
      await c.setFlashMode(FlashMode.off);
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _controller = c);
      await _startStream();
    } on CameraException catch (e) {
      setState(() => _error = e.description ?? e.code);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _startStream() async {
    final c = _controller;
    if (c == null || c.value.isStreamingImages) return;
    await c.startImageStream(_onFrame);
  }

  void _onFrame(CameraImage frame) {
    final now = DateTime.now();
    if (now.difference(_lastFrame).inMilliseconds < 250) return;
    _lastFrame = now;
    final plane = frame.planes.first;
    final bgra = frame.format.group == ImageFormatGroup.bgra8888;
    final q = measureFrame(
      plane.bytes,
      width: frame.width,
      height: frame.height,
      rowStride: plane.bytesPerRow,
      pixelStride: bgra ? 4 : (plane.bytesPerPixel ?? 1),
      offset: bgra ? 1 : 0,
      guideFraction: kGuideFraction,
    );
    final sharp = _sharpTracker.add(q.sharpness);
    if (mounted) {
      setState(() {
        _sharp = sharp;
        _glare = q.glareFraction;
      });
    }
  }

  Future<void> _toggleLock() async {
    final c = _controller;
    if (c == null) return;
    final lock = !_locked;
    try {
      await c.setFocusMode(lock ? FocusMode.locked : FocusMode.auto);
      await c.setExposureMode(lock ? ExposureMode.locked : ExposureMode.auto);
      setState(() => _locked = lock);
    } on CameraException catch (e) {
      _snack('Lock not supported: ${e.description ?? e.code}');
    }
  }

  Future<void> _focusAt(TapUpDetails d, BoxConstraints box) async {
    final c = _controller;
    if (c == null || _locked) return;
    final p = Offset(
      d.localPosition.dx / box.maxWidth,
      d.localPosition.dy / box.maxHeight,
    );
    try {
      await c.setFocusPoint(p);
      await c.setExposurePoint(p);
    } on CameraException {
      // Some devices do not support metering points; ignore.
    }
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || _busy) return;
    setState(() => _busy = true);
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
      final file = await c.takePicture();
      if (mounted) Navigator.of(context).pop(file.path);
    } on CameraException catch (e) {
      _snack('Capture failed: ${e.description ?? e.code}');
      await _startStream();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller = null;
      c.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accel?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Photograph plate'),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Camera unavailable: $_error',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : c == null || !c.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1 / c.value.aspectRatio, // portrait
                      child: LayoutBuilder(
                        builder: (context, box) => GestureDetector(
                          onTapUp: (d) => _focusAt(d, box),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CameraPreview(c),
                              CustomPaint(painter: _GuidePainter(ok: _allOk)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _ChecksBar(
                  tiltOk: _tilt <= kMaxTiltDeg,
                  tilt: _tilt,
                  sharp: _sharp,
                  glareOk: _glare <= kMaxGlare,
                ),
                _Controls(
                  locked: _locked,
                  busy: _busy,
                  onLock: _toggleLock,
                  onCapture: _capture,
                ),
              ],
            ),
    );
  }

  bool get _allOk => _tilt <= kMaxTiltDeg && _sharp && _glare <= kMaxGlare;
}

class _GuidePainter extends CustomPainter {
  _GuidePainter({required this.ok});

  final bool ok;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide * kGuideFraction / 2;
    // Dim everything outside the guide circle.
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: center, radius: r));
    canvas.drawPath(
      outside,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = ok ? Colors.greenAccent : Colors.white70,
    );
    // Cross-hair to centre the dish.
    final p = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1;
    canvas.drawLine(
      center - const Offset(12, 0),
      center + const Offset(12, 0),
      p,
    );
    canvas.drawLine(
      center - const Offset(0, 12),
      center + const Offset(0, 12),
      p,
    );
  }

  @override
  bool shouldRepaint(_GuidePainter old) => old.ok != ok;
}

class _ChecksBar extends StatelessWidget {
  const _ChecksBar({
    required this.tiltOk,
    required this.tilt,
    required this.sharp,
    required this.glareOk,
  });

  final bool tiltOk;
  final double tilt;
  final bool sharp;
  final bool glareOk;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, bool ok) => Chip(
      avatar: Icon(
        ok ? Icons.check_circle : Icons.error_outline,
        size: 18,
        color: ok ? Colors.greenAccent : Colors.amberAccent,
      ),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Wrap(
        spacing: 8,
        alignment: WrapAlignment.center,
        children: [
          chip(tiltOk ? 'Level' : 'Tilt ${tilt.toStringAsFixed(0)}°', tiltOk),
          chip(sharp ? 'Sharp' : 'Focusing…', sharp),
          chip(glareOk ? 'No glare' : 'Glare: remove lid / dim light', glareOk),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.locked,
    required this.busy,
    required this.onLock,
    required this.onCapture,
  });

  final bool locked;
  final bool busy;
  final VoidCallback onLock;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton.filledTonal(
              tooltip: locked
                  ? 'Unlock focus & exposure'
                  : 'Lock focus & exposure',
              onPressed: onLock,
              icon: Icon(locked ? Icons.lock : Icons.lock_open),
            ),
            SizedBox(
              width: 76,
              height: 76,
              child: FilledButton(
                style: FilledButton.styleFrom(shape: const CircleBorder()),
                onPressed: busy ? null : onCapture,
                child: busy
                    ? const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      )
                    : const Icon(Icons.camera, size: 36),
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }
}
