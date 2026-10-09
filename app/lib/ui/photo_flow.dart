import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../core/labels.dart';
import '../core/plate.dart';
import '../data/plate_record.dart';
import '../data/plate_store.dart';
import '../data/sample_info.dart';
import '../l10n/l10n.dart';
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

/// A plate photo as encoded bytes, whether it came through the in-app camera
/// with its guide, and that camera's name for the lens ('' otherwise).
typedef PlatePhoto = ({Uint8List bytes, bool guided, String camera});

/// Takes (or imports) a plate photo; null when the user backs out.
///
/// [fromGallery] picks an existing photo. Otherwise phones use the in-app
/// camera with its guide (shaped for [format], with [tip] over the preview);
/// browsers open the phone's own camera.
Future<PlatePhoto?> takePlatePhoto(
  BuildContext context, {
  bool fromGallery = false,
  PlateFormat format = PlateFormat.dish90,
  String? tip,
}) async {
  if (fromGallery || kIsWeb) {
    final picked = await ImagePicker().pickImage(
      source: fromGallery ? ImageSource.gallery : ImageSource.camera,
      maxWidth: kIsWeb ? _webMaxSide : null,
      maxHeight: kIsWeb ? _webMaxSide : null,
      imageQuality: kIsWeb ? 92 : null,
    );
    if (picked == null) return null;
    return (bytes: await picked.readAsBytes(), guided: false, camera: '');
  }
  final shot = await Navigator.of(context).push<CapturedPhoto>(
    MaterialPageRoute(
      builder: (_) => CaptureScreen(
        square: format.shape == PlateShape.square,
        film: format.isFilm,
        tip: tip,
      ),
    ),
  );
  if (shot == null) return null;
  return (
    bytes: await XFile(shot.path).readAsBytes(),
    guided: true,
    camera: shot.camera,
  );
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
  PlateRecord? laterPhotoOf,
}) async {
  final photo = await takePlatePhoto(
    context,
    fromGallery: fromGallery,
    format: laterPhotoOf?.format ?? preset?.info.format ?? store.defaultFormat,
  );
  if (photo == null || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ReviewScreen(
        store: store,
        photo: photo.bytes,
        guided: photo.guided,
        preset: preset,
        laterPhotoOf: laterPhotoOf,
      ),
    ),
  );
}

/// Photographs (or picks) a plate label and reads its QR code. Shows a message
/// and returns null when no Colony Counter label is found.
Future<PlateLabel?> scanPlateLabel(
  BuildContext context, {
  bool fromGallery = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final picked = await ImagePicker().pickImage(
    source: fromGallery ? ImageSource.gallery : ImageSource.camera,
    maxWidth: 2000,
    maxHeight: 2000,
  );
  if (picked == null) return null;
  final bytes = await picked.readAsBytes();
  messenger.showSnackBar(
    SnackBar(
      content: Text(tr.photoReadingLabel),
      duration: const Duration(seconds: 1),
    ),
  );
  final label = await compute(readLabelFromPhoto, bytes);
  if (label == null) {
    messenger.showSnackBar(SnackBar(content: Text(tr.photoNoLabelFound)));
  }
  return label;
}

/// Shares a generated file; browsers that cannot share files download it.
Future<void> shareBytes(
  Uint8List bytes,
  String name,
  String mimeType, {
  String? subject,
}) => SharePlus.instance.share(
  ShareParams(
    files: [XFile.fromData(bytes, mimeType: mimeType, name: name)],
    fileNameOverrides: [name],
    subject: subject ?? name,
  ),
);
