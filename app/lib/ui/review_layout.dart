import 'package:flutter/material.dart';

/// Keep the photo beside a readable controls panel on desktop/tablet screens.
/// Compact screens retain the established photo-above-controls arrangement.
class ReviewLayout extends StatelessWidget {
  const ReviewLayout({super.key, required this.image, this.panel});
  final Widget image;
  final Widget? panel;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (panel == null) return image;
      if (box.maxWidth >= 900 && box.maxHeight >= 500) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: image),
            SizedBox(width: 400, child: SingleChildScrollView(child: panel!)),
          ],
        );
      }
      return Column(
        children: [
          Expanded(child: image),
          panel!,
        ],
      );
    },
  );
}
