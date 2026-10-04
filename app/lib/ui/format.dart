import '../data/plate_record.dart';
import '../l10n/l10n.dart';

const _superscripts = {
  '0': '⁰',
  '1': '¹',
  '2': '²',
  '3': '³',
  '4': '⁴',
  '5': '⁵',
  '6': '⁶',
  '7': '⁷',
  '8': '⁸',
  '9': '⁹',
};

/// "10⁻⁴" for exponent 4; "Neat" for 0.
String dilutionLabel(int exp) => exp == 0
    ? tr.neat
    : '10⁻${exp.toString().split('').map((d) => _superscripts[d]).join()}';

/// "1.7 × 10^4" -> "1.7 × 10⁴".
String prettySci(String s) {
  final i = s.indexOf('^');
  if (i < 0) return s;
  // Only the exponent itself, not digits later in the text ("CFU/100 mL").
  final m = RegExp(r'^-?\d+').firstMatch(s.substring(i + 1));
  if (m == null) return s;
  final sup = m
      .group(0)!
      .split('')
      .map((c) => c == '-' ? '⁻' : _superscripts[c] ?? c)
      .join();
  return '${s.substring(0, i)}$sup${s.substring(i + 1 + m.end)}';
}

String flagLabel(String flag) => switch (flag) {
  'spreader' => tr.flagSpreader,
  'tntc' => tr.flagTntc,
  'clusters_estimated' => tr.flagClusters,
  'crowded' => tr.flagCrowded,
  'many_clusters' => tr.flagManyClusters,
  'low_contrast' => tr.flagLowContrast,
  _ => flag,
};

String shortDate(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

/// "Lake-A · 10⁻⁴ · R2", or "Lake-A · drop plate (6 drops)".
String plateLabel(PlateRecord r) {
  final sample = r.sampleId.isEmpty ? tr.unlabelled : r.sampleId;
  if (r.isDropPlate) return '$sample · ${tr.dropPlateDrops(r.spots.length)}';
  return '$sample · ${dilutionLabel(r.dilutionExp)} · R${r.replicate}';
}

/// "1.23e6"-style CFU/mL value as "1.2 × 10⁶".
String sciValue(double v) =>
    v.isFinite && v > 0 ? prettySci(formatSciValue(v)) : '—';

String formatSciValue(double v) {
  final e = (v.abs()).toStringAsExponential(1).split('e');
  final exp = int.parse(e[1]);
  return '${e[0]} × 10^$exp';
}

String fixed(double v, [int digits = 2]) =>
    v.isFinite ? v.toStringAsFixed(digits) : '—';
