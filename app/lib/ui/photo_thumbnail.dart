import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/plate_store.dart';

/// A stored plate photo as a 48 px list thumbnail.
class PhotoThumbnail extends StatefulWidget {
  const PhotoThumbnail({super.key, required this.store, required this.path});

  final PlateStore store;

  /// The photo's stored name.
  final String path;

  @override
  State<PhotoThumbnail> createState() => _PhotoThumbnailState();
}

class _PhotoThumbnailState extends State<PhotoThumbnail> {
  late Future<Uint8List?> _photo = widget.store.readPhotoPath(widget.path);

  @override
  void didUpdateWidget(PhotoThumbnail old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _photo = widget.store.readPhotoPath(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    const empty = SizedBox(width: 48, height: 48);
    return FutureBuilder<Uint8List?>(
      future: _photo,
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) return empty;
        return Image.memory(
          bytes,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          cacheWidth: 144,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => empty,
        );
      },
    );
  }
}
