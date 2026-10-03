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
    ? 'Neat'
    : '10⁻${exp.toString().split('').map((d) => _superscripts[d]).join()}';

/// "1.7 × 10^4" -> "1.7 × 10⁴".
String prettySci(String s) {
  final i = s.indexOf('^');
  if (i < 0) return s;
  final exp = s.substring(i + 1);
  final sup = exp
      .split('')
      .map((c) => c == '-' ? '⁻' : _superscripts[c] ?? c)
      .join();
  return '${s.substring(0, i)}$sup';
}

String flagLabel(String flag) => switch (flag) {
  'spreader' => 'Spreader',
  'tntc' => 'Too many to count',
  'clusters_estimated' => 'Clusters estimated',
  _ => flag,
};

String shortDate(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
