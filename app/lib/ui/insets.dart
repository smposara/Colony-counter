import 'package:flutter/widgets.dart';

/// [padding] plus the height of the system navigation bar at the bottom.
///
/// Android 15 draws apps edge to edge, behind the navigation bar. Scrolling
/// pages and bottom sheets add this so their last item (often a Save button)
/// can be scrolled clear of the bar. It adds nothing where the bar is already
/// accounted for (below a bottom tab bar, or while the keyboard is open).
EdgeInsets scrollPadding(BuildContext context, EdgeInsets padding) => padding
    .copyWith(bottom: padding.bottom + MediaQuery.paddingOf(context).bottom);

/// A segmented-button label on one line, shrunk to fit a narrow segment
/// instead of breaking mid-word ("Membra/ne") on a phone.
Widget segmentLabel(String text) => FittedBox(
  fit: BoxFit.scaleDown,
  child: Text(text, maxLines: 1, softWrap: false),
);
