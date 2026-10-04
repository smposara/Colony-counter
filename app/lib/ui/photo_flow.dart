import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/plate_store.dart';
import '../data/sample_info.dart';
import 'capture_screen.dart';
import 'review_screen.dart';

/// Web photos are scaled to at most this many pixels on the long side. The
/// browser also applies the photo's rotation while scaling, so the pixels are
/// upright, and storage stays small.
const double _webMaxSide = 3000;

/// What is already known about the plate about to be photographed.
class PlatePreset {
  const PlatePreset({required this.info, required this.slot});

  final SampleInfo info;
  final Slot slot;
}

/// Takes (or imports) a plate photo and opens the review screen for it.
///
/// [fromGallery] picks an existing photo. Otherwise phones use the in-app
/// camera with its guide; browsers open the phone's own camera.
Future<void> countNewPlate(
  BuildContext context,
  PlateStore store, {
  bool fromGallery = false,
  PlatePreset? preset,
}) async {
  Uint8List? bytes;
  var guided = false;
  if (fromGallery || kIsWeb) {
    final picked = await ImagePicker().pickImage(
      source: fromGallery ? ImageSource.gallery : ImageSource.camera,
      maxWidth: kIsWeb ? _webMaxSide : null,
      maxHeight: kIsWeb ? _webMaxSide : null,
      imageQuality: kIsWeb ? 92 : null,
    );
    if (picked == null) return;
    bytes = await picked.readAsBytes();
  } else {
    final path = await Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const CaptureScreen()));
    if (path == null) return;
    bytes = await XFile(path).readAsBytes();
    guided = true;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ReviewScreen(
        store: store,
        photo: bytes,
        guided: guided,
        preset: preset,
      ),
    ),
  );
}
