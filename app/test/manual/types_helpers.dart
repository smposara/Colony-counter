// A fake camera for the manual, so the in-app camera screen (with its plate
// guide) can be shown: the preview is a still photo, the frames are its grey
// levels, and the phone lies level.

import 'dart:async';

// The camera plugin's platform interface (a dependency of `camera`), to put a
// still photo behind the guide.
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

class _FakeCamera extends CameraPlatform {
  _FakeCamera(this.preview, this.frame, this.w, this.h);

  final Uint8List preview;
  final Uint8List frame;
  final int w, h;
  final _never = StreamController<Never>.broadcast();
  Timer? _timer;

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
    CameraDescription(
      name: '0',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
  ];

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) async => 1;

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          h.toDouble(), // the sensor's long side
          w.toDouble(),
          ExposureMode.auto,
          true,
          FocusMode.auto,
          true,
        ),
      );

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => _never.stream.cast();

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      _never.stream.cast();

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {}

  @override
  bool supportsImageStreaming() => true;

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) {
    final frames = StreamController<CameraImageData>();
    frames.onListen = () => _timer = Timer.periodic(
      const Duration(milliseconds: 300),
      (_) => frames.add(
        CameraImageData(
          format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 35),
          planes: [
            CameraImagePlane(
              bytes: frame,
              bytesPerRow: w,
              bytesPerPixel: 1,
              width: w,
              height: h,
            ),
          ],
          height: h,
          width: w,
        ),
      ),
    );
    frames.onCancel = () => _timer?.cancel();
    return frames.stream;
  }

  @override
  Widget buildPreview(int cameraId) => Image.memory(preview, fit: BoxFit.fill);

  @override
  Future<void> dispose(int cameraId) async => _timer?.cancel();
}

/// Puts [photo] (a portrait JPEG) in the camera, and holds the phone level.
void fakeCamera(WidgetTester tester, Uint8List photo) {
  final im = img.decodeImage(photo)!;
  final grey = Uint8List(im.width * im.height);
  var i = 0;
  for (final p in im) {
    grey[i++] = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
  }
  CameraPlatform.instance = _FakeCamera(photo, grey, im.width, im.height);
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/sensors/method'),
    (_) async => null,
  );
  messenger.setMockStreamHandler(
    const EventChannel('dev.fluttercommunity.plus/sensors/accelerometer'),
    MockStreamHandler.inline(
      onListen: (_, sink) => sink.success(<double>[0, 0, 9.81, 0]),
    ),
  );
}
