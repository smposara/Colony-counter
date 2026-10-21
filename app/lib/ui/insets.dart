import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// [padding] plus the height of the system navigation bar at the bottom.
///
/// Android 15 draws apps edge to edge, behind the navigation bar. Scrolling
/// pages and bottom sheets add this so their last item (often a Save button)
/// can be scrolled clear of the bar. It adds nothing where the bar is already
/// accounted for (below a bottom tab bar, or while the keyboard is open).
EdgeInsets scrollPadding(BuildContext context, EdgeInsets padding) => padding
    .copyWith(bottom: padding.bottom + MediaQuery.paddingOf(context).bottom);

/// The widest a full-screen page's content gets (logical pixels).
const double kReadableWidth = 720;

/// [scrollPadding] for a full-screen page, widened at the sides so that on a
/// tablet or desktop the content is centred and no wider than
/// [kReadableWidth] instead of stretching edge to edge. The same as
/// [scrollPadding] on phones.
EdgeInsets readablePadding(BuildContext context, EdgeInsets padding) {
  final side = math.max(
    0.0,
    (MediaQuery.sizeOf(context).width - padding.horizontal - kReadableWidth) /
        2,
  );
  return scrollPadding(
    context,
    padding.copyWith(left: padding.left + side, right: padding.right + side),
  );
}

/// A chart's largest height (logical pixels), so that on a tablet or desktop
/// the whole chart fits on screen.
const double kMaxChartHeight = 380;

/// [child] across the full width at [aspectRatio] (width / height) on phones,
/// but no taller than [kMaxChartHeight] on tablets and desktops.
class ChartBox extends StatelessWidget {
  const ChartBox({super.key, required this.aspectRatio, required this.child});

  final double aspectRatio;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => SizedBox(
      width: box.maxWidth,
      height: math.min(box.maxWidth / aspectRatio, kMaxChartHeight),
      child: child,
    ),
  );
}

/// The largest side of a photo of the plate shown within a page (logical
/// pixels), for the same reason.
const double kMaxPlatePhotoSide = 480;

/// A segmented-button label on one line, shrunk to fit a narrow segment
/// instead of breaking mid-word ("Membra/ne") on a phone.
Widget segmentLabel(String text) => FittedBox(
  fit: BoxFit.scaleDown,
  child: Text(text, maxLines: 1, softWrap: false),
);
