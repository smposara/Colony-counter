import 'dart:math' as math;

/// Drop-plate statistics: the per-dilution drop table and CFU/mL
/// (mirrors ml/colonycounter/drop_stats.py).
///
/// For each dilution: the drop counts, mean, SD and the index of dispersion
/// (VMR). Drops of a well-mixed suspension are Poisson, so
/// χ² = Σ(x − m)²/m (m the mean) with N − 1 degrees of freedom tests whether they agree
/// (Miles & Misra 1938). Then CFU/mL:
/// - [DropMode.pooled]: ΣC / Σ(V·d) over the drops inside the counting window;
/// - [DropMode.first]: the mean of the first (least diluted) countable
///   dilution ÷ (V·d), as most protocols do.
///
/// Both give a Poisson 95 % interval from the total count (Garwood) and a "<"
/// detection limit of 1 / (N·V·d) over all drops of the least diluted dilution
/// when nothing grew.

/// Colonies per 10 µL drop (Naghili et al. 2013).
const kDropWindow = (3, 30);
const double kOverdispersedP = 0.01;
const double kOutlierZ = 3.0;

/// Acceptable ratio of the means of neighbouring dilutions (expected 10).
const kTenfold = (3.0, 30.0);

class DropCount {
  const DropCount(
    this.dilutionExp,
    this.replicate,
    this.count, {
    this.tntc = false,
    this.excluded = false,
  });

  final int dilutionExp;
  final int replicate;
  final int count;

  /// Confluent or marked too numerous to count.
  final bool tntc;

  /// Left out by the user.
  final bool excluded;
}

class DilutionRow {
  DilutionRow({
    required this.dilutionExp,
    required this.counts,
    required this.tntc,
    required this.excluded,
    required this.mean,
    required this.sd,
    required this.vmr,
    required this.chi2,
    required this.p,
  });

  final int dilutionExp;

  /// Usable drops (not excluded, not TNTC).
  final List<int> counts;

  /// Drops too numerous to count.
  final int tntc;
  final int excluded;
  final double mean;
  final double sd;

  /// Variance / mean (index of dispersion).
  final double vmr;
  final double chi2;

  /// Dispersion test p-value (1 when it cannot be computed).
  final double p;

  /// Indices into [counts].
  final List<int> outliers = [];

  /// `overdispersed`, `outlier_drop`, `not_tenfold`.
  final List<String> flags = [];

  int get total => counts.fold(0, (s, c) => s + c);
}

List<DilutionRow> dilutionTable(List<DropCount> drops) {
  final rows = <DilutionRow>[];
  final dils = {for (final d in drops) d.dilutionExp}.toList()..sort();
  for (final d in dils) {
    final mine = drops.where((x) => x.dilutionExp == d).toList();
    final cs = [
      for (final x in mine)
        if (!x.excluded && !x.tntc) x.count,
    ];
    final nT = mine.where((x) => x.tntc && !x.excluded).length;
    final nE = mine.where((x) => x.excluded).length;
    final n = cs.length;
    final mean = n == 0 ? 0.0 : cs.fold(0, (s, c) => s + c) / n;
    final ss = cs.fold(0.0, (s, c) => s + (c - mean) * (c - mean));
    final sd = n > 1 ? math.sqrt(ss / (n - 1)) : 0.0;
    final ok = mean > 0 && n > 1;
    final row = DilutionRow(
      dilutionExp: d,
      counts: cs,
      tntc: nT,
      excluded: nE,
      mean: mean,
      sd: sd,
      vmr: ok ? sd * sd / mean : 1.0,
      chi2: ok ? ss / mean : 0.0,
      p: ok ? chi2Sf(ss / mean, n - 1) : 1.0,
    );
    if (n >= 3 && row.p < kOverdispersedP) row.flags.add('overdispersed');
    if (mean > 0 && n >= 3) {
      for (var i = 0; i < n; i++) {
        var rest = 0;
        for (var j = 0; j < n; j++) {
          if (j != i) rest += cs[j];
        }
        final m = rest / (n - 1);
        if (m > 0 && (cs[i] - m).abs() / math.sqrt(m) > kOutlierZ) {
          row.outliers.add(i);
        }
      }
      if (row.outliers.isNotEmpty) row.flags.add('outlier_drop');
    }
    rows.add(row);
  }
  // Neighbouring dilutions should differ about tenfold.
  for (var i = 0; i + 1 < rows.length; i++) {
    final a = rows[i], b = rows[i + 1];
    if (a.tntc > 0 || b.tntc > 0 || a.total < 5 || b.total < 5) continue;
    final step = math.pow(10.0, b.dilutionExp - a.dilutionExp);
    final ratio = a.mean / b.mean / step * 10;
    if (ratio < kTenfold.$1 || ratio > kTenfold.$2) a.flags.add('not_tenfold');
  }
  return rows;
}

enum DropMode { pooled, first }

class DropEstimate {
  DropEstimate(
    this.cfuPerMl,
    this.qualifier,
    this.low,
    this.high,
    this.dilutionsUsed,
    this.dropsUsed, [
    this.note = '',
  ]);

  final double cfuPerMl;

  /// `exact`, `estimated`, `<` or `>`.
  final String qualifier;

  /// 95 % interval.
  final double low;
  final double high;
  final List<int> dilutionsUsed;
  final int dropsUsed;
  final String note;
}

DropEstimate estimateDrops(
  List<DilutionRow> rows,
  double volumeUl, {
  DropMode mode = DropMode.pooled,
  (int, int) window = kDropWindow,
}) {
  final (lo, hi) = window;
  final v = volumeUl / 1000;
  double vd(int dil, int n) => n * v * math.pow(10.0, -dil);

  DropEstimate make(
    int total,
    double vdSum,
    List<int> dils,
    int n,
    String qual, [
    String note = '',
    double? value,
  ]) {
    final (cLo, cHi) = poissonInterval(total);
    return DropEstimate(
      value ?? total / vdSum,
      qual,
      cLo / vdSum,
      cHi / vdSum,
      dils,
      n,
      note,
    );
  }

  final usable = [
    for (final r in rows)
      if (r.counts.isNotEmpty || r.tntc > 0) r,
  ];
  if (usable.isEmpty) {
    return DropEstimate(
      double.nan,
      'estimated',
      double.nan,
      double.nan,
      [],
      0,
      'no drops',
    );
  }
  if (mode == DropMode.first) {
    for (final r in usable) {
      if (r.tntc == 0 && r.counts.isNotEmpty && r.mean >= lo && r.mean <= hi) {
        final n = r.counts.length;
        return make(r.total, vd(r.dilutionExp, n), [r.dilutionExp], n, 'exact');
      }
    }
  } else {
    var total = 0, n = 0;
    var vdSum = 0.0;
    final dils = <int>[];
    for (final r in usable) {
      final inside = [
        for (final c in r.counts)
          if (c >= lo && c <= hi) c,
      ];
      if (inside.isEmpty) continue;
      total += inside.fold(0, (s, c) => s + c);
      vdSum += vd(r.dilutionExp, inside.length);
      dils.add(r.dilutionExp);
      n += inside.length;
    }
    if (n > 0) return make(total, vdSum, dils, n, 'exact');
  }
  // Nothing in the window.
  final below = usable.every(
    (r) => r.tntc == 0 && r.counts.every((c) => c < lo),
  );
  if (below) {
    final r = usable.first; // least diluted
    final n = r.counts.length;
    final vdSum = vd(r.dilutionExp, n);
    if (r.total == 0) {
      return make(
        0,
        vdSum,
        [r.dilutionExp],
        n,
        '<',
        'no colonies in any drop',
        1 / vdSum,
      );
    }
    return make(
      r.total,
      vdSum,
      [r.dilutionExp],
      n,
      'estimated',
      'below the counting window ($lo–$hi)',
    );
  }
  final r = usable.last; // most diluted
  if (r.tntc > 0 || r.counts.isEmpty) {
    final n = r.tntc + r.counts.length;
    return make(
      hi * n,
      vd(r.dilutionExp, n),
      [r.dilutionExp],
      n,
      '>',
      'too numerous to count',
    );
  }
  final n = r.counts.length;
  return make(
    r.total,
    vd(r.dilutionExp, n),
    [r.dilutionExp],
    n,
    'estimated',
    'above the counting window ($lo–$hi)',
  );
}

// ---------------------------------------------------------------------------
// Distributions (no dependency needed)

/// Exact (Garwood) 95 % interval for a Poisson count.
(double, double) poissonInterval(int total, [double level = 0.95]) {
  final a = (1 - level) / 2;
  final lo = total > 0 ? gammaQuantile(a, total.toDouble()) : 0.0;
  final hi = gammaQuantile(1 - a, total + 1.0);
  return (lo, hi);
}

/// Upper tail of the χ² distribution with [df] degrees of freedom.
double chi2Sf(double x, int df) {
  if (x <= 0) return 1;
  return 1 - regularizedGammaP(df / 2, x / 2);
}

/// The [q] quantile of a Gamma([shape], 1) distribution (bisection on
/// [regularizedGammaP]).
double gammaQuantile(double q, double shape) {
  var lo = 0.0, hi = math.max(1.0, shape);
  while (regularizedGammaP(shape, hi) < q) {
    hi *= 2;
  }
  for (var i = 0; i < 200 && hi - lo > 1e-12 * math.max(1, hi); i++) {
    final mid = (lo + hi) / 2;
    if (regularizedGammaP(shape, mid) < q) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return (lo + hi) / 2;
}

/// Lower regularized incomplete gamma P(a, x) (Numerical Recipes: series
/// below a + 1, continued fraction above).
double regularizedGammaP(double a, double x) {
  if (x <= 0) return 0;
  final lnPre = a * math.log(x) - x - logGamma(a);
  if (x < a + 1) {
    var sum = 1 / a, term = sum, ap = a;
    for (var n = 0; n < 1000; n++) {
      ap += 1;
      term *= x / ap;
      sum += term;
      if (term.abs() < sum.abs() * 1e-16) break;
    }
    return sum * math.exp(lnPre);
  }
  const tiny = 1e-300;
  var b = x + 1 - a, c = 1 / tiny, d = 1 / b, h = d;
  for (var i = 1; i < 1000; i++) {
    final an = -i * (i - a);
    b += 2;
    d = an * d + b;
    if (d.abs() < tiny) d = tiny;
    c = b + an / c;
    if (c.abs() < tiny) c = tiny;
    d = 1 / d;
    final del = d * c;
    h *= del;
    if ((del - 1).abs() < 1e-16) break;
  }
  return 1 - math.exp(lnPre) * h;
}

/// ln Γ(x) for x > 0 (Lanczos, g = 7).
double logGamma(double x) {
  const g = 7.0;
  const c = [
    0.99999999999980993,
    676.5203681218851,
    -1259.1392167224028,
    771.32342877765313,
    -176.61502916214059,
    12.507343278686905,
    -0.13857109526572012,
    9.9843695780195716e-6,
    1.5056327351493116e-7,
  ];
  if (x < 0.5) {
    return math.log(math.pi / math.sin(math.pi * x)) - logGamma(1 - x);
  }
  x -= 1;
  var a = c[0];
  final t = x + g + 0.5;
  for (var i = 1; i < 9; i++) {
    a += c[i] / (x + i);
  }
  return 0.5 * math.log(2 * math.pi) +
      (x + 0.5) * math.log(t) -
      t +
      math.log(a);
}
