import 'package:flutter/material.dart';

/// Keep the photo beside a readable controls panel on desktop/tablet screens.
/// Compact screens retain the established photo-above-controls arrangement.
class ReviewLayout extends StatelessWidget {
  const ReviewLayout({super.key, required this.image, this.panel});
  final Widget image;
  final Widget? panel;

  /// Whether [context] is in the side panel of the wide layout, which
  /// scrolls as a whole and has the full screen height.
  static bool inSidePanel(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SidePanel>() != null;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (panel == null) return image;
      if (box.maxWidth >= 900 && box.maxHeight >= 500) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: image),
            SizedBox(
              width: 400,
              child: SingleChildScrollView(child: _SidePanel(child: panel!)),
            ),
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

/// Panel details that scroll on their own below the photo, capped at 40 %
/// of the screen height so the actions after them stay in view on short
/// phones. The side panel has room for them in full.
class ReviewDetails extends StatelessWidget {
  const ReviewDetails({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: ReviewLayout.inSidePanel(context)
          ? double.infinity
          : MediaQuery.sizeOf(context).height * 0.4,
    ),
    child: child,
  );
}

class _SidePanel extends InheritedWidget {
  const _SidePanel({required super.child});

  @override
  bool updateShouldNotify(_SidePanel oldWidget) => false;
}
