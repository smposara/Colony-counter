import 'package:flutter/material.dart';

/// Categorical series colours (fixed order, never cycled), light and dark steps.
const seriesLight = [
  Color(0xFF2A78D6),
  Color(0xFFEB6834),
  Color(0xFF1BAF7A),
  Color(0xFFEDA100),
  Color(0xFFE87BA4),
  Color(0xFF008300),
  Color(0xFF4A3AA7),
  Color(0xFFE34948),
];
const seriesDark = [
  Color(0xFF3987E5),
  Color(0xFFD95926),
  Color(0xFF199E70),
  Color(0xFFC98500),
  Color(0xFFD55181),
  Color(0xFF008300),
  Color(0xFF9085E9),
  Color(0xFFE66767),
];

/// The [i]-th categorical colour for the current theme brightness.
Color seriesColour(BuildContext context, int i) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final p = dark ? seriesDark : seriesLight;
  return p[i % p.length];
}
