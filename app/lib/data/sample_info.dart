import 'dart:math' as math;

import '../core/calculator.dart';
import '../core/colour.dart';
import '../core/drop_layout.dart';
import '../core/drop_stats.dart';
import '../core/petrifilm.dart';
import '../core/plate.dart';
import '../core/stats.dart';
import 'drop_results.dart';
import 'plate_record.dart';

enum PlatingMethod {
  spread('Spread / pour plate'),
  drop('Drop plate (Miles–Misra)'),
  membrane('Membrane filtration'),

  /// Dry films such as Neogen® Petrifilm®: one film per dilution, 1 mL each.
  film('Petrifilm (dry film)');

  const PlatingMethod(this.label);
  final String label;
}

/// What the drops on one drop plate are.
enum DropLayout {
  /// One plate per dilution; its drops are replicates.
  replicates('One dilution per plate, drops = replicates'),

  /// One plate per replicate; each drop is a different dilution.
  dilutions('All dilutions on one plate, one drop each');

  const DropLayout(this.label);
  final String label;
}

/// Where the drops sit on a drop plate.
enum DropArrangement {
  /// Found from their colonies, numbered in reading order (as before 0.7).
  free,

  /// Evenly round a ring, clockwise from the top (the classic Miles–Misra
  /// sectors).
  sectors,

  /// Rows and columns: a row per dilution, a column per drop of it (or one
  /// row of replicates).
  grid,
}

/// One plate still to be photographed (or already done) in a sample's plan.
class Slot {
  const Slot({this.dilutionExp, this.replicate});

  /// Null when the plate holds every dilution (drop plate, dilutions layout).
  final int? dilutionExp;

  /// Null when the plate holds every replicate (drop plate, replicates layout).
  final int? replicate;

  bool matches(PlateRecord r) =>
      (dilutionExp == null || r.dilutionExp == dilutionExp) &&
      (replicate == null || r.replicate == replicate);
}

/// A sample's plating plan and experiment details.
class SampleInfo {
  SampleInfo({
    required this.sampleId,
    this.experiment = '',
    this.condition = '',
    this.timeH,
    this.method = PlatingMethod.spread,
    this.dilutions = const [4, 5, 6],
    this.replicates = 3,
    this.volumeMl = 0.1,
    this.dropVolumeUl = 10,
    this.dropLayout = DropLayout.replicates,
    this.dropArrangement = DropArrangement.free,
    this.dropsPerDilution = 1,
    this.dropPitchMm = 11,
    this.dropMode = DropMode.pooled,
    this.dropWindow = kDropWindow,
    this.colourMode = ColourMode.none,
    this.notes = '',
    this.strain = '',
    this.medium = '',
    this.mediumBatch = '',
    this.incubationTempC,
    this.incubationH,
    this.operator = '',
    this.tags = const [],
    this.format = PlateFormat.dish90,
    this.membraneRule = CountingRule.membrane80,
    this.solid = false,
    this.sampleWeightG = 25,
    this.diluentMl = 225,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String sampleId;

  /// Groups samples for comparison, e.g. "Disinfectant test 2026-10".
  final String experiment;

  /// e.g. "Control", "Treatment 1 %".
  final String condition;

  /// Sampling time point in hours (time-kill / growth curves).
  final double? timeH;
  final PlatingMethod method;

  /// Dilutions plated, as powers of ten (4 → 10⁻⁴), ascending.
  final List<int> dilutions;
  final int replicates;

  /// Volume spread on a whole plate, or filtered through a membrane.
  final double volumeMl;

  /// Dish or filter type.
  final PlateFormat format;

  /// Countable range for membrane filters.
  final CountingRule membraneRule;

  /// A solid sample (food, soil…) reported per gram: [sampleWeightG] g was
  /// suspended in [diluentMl] mL of diluent to make the initial suspension.
  final bool solid;
  final double sampleWeightG;
  final double diluentMl;

  /// Dilution of the initial suspension, e.g. 10 for 25 g in 225 mL (1:10).
  double get initialDilution =>
      sampleWeightG > 0 ? (sampleWeightG + diluentMl) / sampleWeightG : 10;

  /// Volume of one drop on a drop plate.
  final double dropVolumeUl;
  final DropLayout dropLayout;

  /// Where the drops sit on each plate.
  final DropArrangement dropArrangement;

  /// All dilutions on one plate: drops of each dilution.
  final int dropsPerDilution;

  /// Grid: centre-to-centre distance between neighbouring drops.
  final double dropPitchMm;

  /// CFU/mL from all drops in the window pooled, or from the first (least
  /// diluted) countable dilution.
  final DropMode dropMode;

  /// Countable colonies per drop (inclusive), 3–30 by default.
  final (int, int) dropWindow;

  /// Drops planned on each plate.
  int get dropsPerPlate => dropLayout == DropLayout.replicates
      ? replicates
      : dilutions.length * dropsPerDilution;

  /// Dilutions on the plate of [slot], in layout order (one for the
  /// replicates layout).
  List<int> dropDilutions(Slot slot) => dropLayout == DropLayout.replicates
      ? [slot.dilutionExp ?? dilutions.first]
      : dilutions;

  /// The layout to fit to a plate's photo; [FreeTemplate] when the drops are
  /// found from their colonies alone.
  DropTemplate get dropTemplate {
    final n = dropsPerPlate;
    final replicates = dropLayout == DropLayout.replicates;
    return switch (dropArrangement) {
      DropArrangement.free => const FreeTemplate(),
      // Drops half-way between the centre and the rim of the dish.
      DropArrangement.sectors => SectorTemplate(
        n: n,
        ringMm: 0.28 * format.sizeMm,
        dropsPerDilution: replicates ? n : dropsPerDilution,
      ),
      DropArrangement.grid => GridTemplate(
        rows: replicates ? 1 : dilutions.length,
        cols: replicates ? n : dropsPerDilution,
        pitchMm: dropPitchMm,
      ),
    };
  }

  /// Dilution, replicate and flags of the [i]-th drop of [slot]'s plate when
  /// drops are numbered in reading order: drops beyond the plan keep the last
  /// dilution and are flagged `unplanned` (they used to wrap round silently).
  ({int dilutionExp, int replicate, bool unplanned}) dropLabel(
    Slot slot,
    int i,
  ) {
    final unplanned = i >= dropsPerPlate;
    if (dropLayout == DropLayout.replicates) {
      return (
        dilutionExp: slot.dilutionExp ?? dilutions.first,
        replicate: i + 1,
        unplanned: unplanned,
      );
    }
    final k = math.min(
      i ~/ math.max(1, dropsPerDilution),
      dilutions.length - 1,
    );
    return (
      dilutionExp: dilutions[k],
      replicate: slot.replicate ?? 1,
      unplanned: unplanned,
    );
  }

  final ColourMode colourMode;
  final String notes;

  // Experiment details, kept with the results and exported.
  final String strain;
  final String medium;
  final String mediumBatch;
  final double? incubationTempC;
  final double? incubationH;
  final String operator;

  /// Free labels for finding samples later, e.g. "thesis", "batch 3".
  final List<String> tags;

  /// True when [query] (case-insensitive, every word) appears in any of the
  /// sample's text fields.
  bool matches(String query) {
    final hay = [
      sampleId,
      experiment,
      condition,
      strain,
      medium,
      mediumBatch,
      operator,
      notes,
      ...tags,
    ].join(' ').toLowerCase();
    return query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .every(hay.contains);
  }

  final DateTime createdAt;

  bool get isDrop => method == PlatingMethod.drop;
  bool get isMembrane => method == PlatingMethod.membrane;
  bool get isFilm => method == PlatingMethod.film && format.isFilm;

  /// What a dry film reports (e.g. E. coli and coliforms); empty otherwise.
  List<String> get filmResults =>
      isFilm ? kFilmTypes[format.film]!.results : const [];

  bool get isSolid => solid && !isMembrane;

  /// From CFU per mL (as computed from the plate dilutions) to the reported
  /// unit. Membranes: per 100 mL of water. Solid samples: the initial
  /// suspension counts as the 10⁻¹ dilution, as is usual; a suspension that
  /// is not 1:10 is corrected for here.
  double get unitFactor => isMembrane
      ? 100
      : isSolid
      ? initialDilution / 10
      : 1;
  String get unitLabel => isMembrane
      ? 'CFU/100 mL'
      : isSolid
      ? 'CFU/g'
      : 'CFU/mL';

  /// Volume per counted unit (plate or drop), in mL.
  double get unitVolumeMl => isDrop ? dropVolumeUl / 1000 : volumeMl;

  CountingRule ruleFor(CountingRule spreadRule) => isDrop
      ? CountingRule.dropPlate
      : isMembrane
      ? membraneRule
      : isFilm
      ? filmCountingRule(format.film!)
      : spreadRule;

  /// Every plate in the plan, in the order to photograph them.
  List<Slot> get slots {
    if (!isDrop) {
      return [
        for (final d in dilutions)
          for (var r = 1; r <= replicates; r++)
            Slot(dilutionExp: d, replicate: r),
      ];
    }
    return dropLayout == DropLayout.replicates
        ? [for (final d in dilutions) Slot(dilutionExp: d)]
        : [for (var r = 1; r <= replicates; r++) Slot(replicate: r)];
  }

  Slot? nextSlot(List<PlateRecord> plates) {
    for (final s in slots) {
      if (!plates.any(s.matches)) return s;
    }
    return null;
  }

  /// CFU per unit from the sample's plates. For a dry film, of [result]
  /// (default: the film type's first result, e.g. E. coli on EC). Drop
  /// plates use the sample's window and calculation (see drop_results.dart).
  SampleResult analyse(
    List<PlateRecord> plates,
    CountingRule spreadRule, {
    String? result,
  }) => isDrop
      ? analyseDrops(this, plates)
      : analyseReplicates([
          for (final p in latestOfSeries(plates))
            ...p.observations(result: isFilm && p.isFilm ? result : null),
        ], ruleFor(spreadRule));

  SampleInfo copyWith({String? sampleId}) => SampleInfo.fromJson({
    ...toJson(),
    'sample_id': sampleId ?? this.sampleId,
  });

  Map<String, dynamic> toJson() => {
    'sample_id': sampleId,
    'experiment': experiment,
    'condition': condition,
    'time_h': timeH,
    'method': method.name,
    'dilutions': dilutions,
    'replicates': replicates,
    'volume_ml': volumeMl,
    'drop_volume_ul': dropVolumeUl,
    'drop_layout': dropLayout.name,
    'drop_arrangement': dropArrangement.name,
    'drops_per_dilution': dropsPerDilution,
    'drop_pitch_mm': dropPitchMm,
    'drop_mode': dropMode.name,
    'drop_window': [dropWindow.$1, dropWindow.$2],
    'colour_mode': colourMode.name,
    'notes': notes,
    'strain': strain,
    'medium': medium,
    'medium_batch': mediumBatch,
    'incubation_temp_c': incubationTempC,
    'incubation_h': incubationH,
    'operator': operator,
    'tags': tags,
    'format': format.name,
    'membrane_rule': membraneRule.name,
    if (solid) 'solid': true,
    if (solid) 'sample_g': sampleWeightG,
    if (solid) 'diluent_ml': diluentMl,
    'created_at': createdAt.toIso8601String(),
  };

  factory SampleInfo.fromJson(Map<String, dynamic> j) => SampleInfo(
    sampleId: j['sample_id'] as String,
    experiment: j['experiment'] as String? ?? '',
    condition: j['condition'] as String? ?? '',
    timeH: (j['time_h'] as num?)?.toDouble(),
    method: PlatingMethod.values.firstWhere(
      (m) => m.name == j['method'],
      orElse: () => PlatingMethod.spread,
    ),
    dilutions: [
      for (final d in j['dilutions'] as List? ?? const [4, 5, 6])
        (d as num).toInt(),
    ],
    replicates: (j['replicates'] as num?)?.toInt() ?? 1,
    volumeMl: (j['volume_ml'] as num?)?.toDouble() ?? 0.1,
    dropVolumeUl: (j['drop_volume_ul'] as num?)?.toDouble() ?? 10,
    dropLayout: DropLayout.values.firstWhere(
      (m) => m.name == j['drop_layout'],
      orElse: () => DropLayout.replicates,
    ),
    dropArrangement: DropArrangement.values.firstWhere(
      (m) => m.name == j['drop_arrangement'],
      orElse: () => DropArrangement.free,
    ),
    dropsPerDilution: (j['drops_per_dilution'] as num?)?.toInt() ?? 1,
    dropPitchMm: (j['drop_pitch_mm'] as num?)?.toDouble() ?? 11,
    dropMode: DropMode.values.firstWhere(
      (m) => m.name == j['drop_mode'],
      orElse: () => DropMode.pooled,
    ),
    dropWindow: switch (j['drop_window']) {
      [final num lo, final num hi] when lo >= 0 && hi > lo => (
        lo.toInt(),
        hi.toInt(),
      ),
      _ => kDropWindow,
    },
    colourMode: ColourMode.values.firstWhere(
      (m) => m.name == j['colour_mode'],
      orElse: () => ColourMode.none,
    ),
    notes: j['notes'] as String? ?? '',
    strain: j['strain'] as String? ?? '',
    medium: j['medium'] as String? ?? '',
    mediumBatch: j['medium_batch'] as String? ?? '',
    incubationTempC: (j['incubation_temp_c'] as num?)?.toDouble(),
    incubationH: (j['incubation_h'] as num?)?.toDouble(),
    operator: j['operator'] as String? ?? '',
    tags: [for (final t in j['tags'] as List? ?? const []) t as String],
    format: PlateFormat.byName(j['format'] as String?),
    membraneRule: CountingRule.membraneRules.firstWhere(
      (r) => r.name == j['membrane_rule'],
      orElse: () => CountingRule.membrane80,
    ),
    solid: j['solid'] as bool? ?? false,
    sampleWeightG: (j['sample_g'] as num?)?.toDouble() ?? 25,
    diluentMl: (j['diluent_ml'] as num?)?.toDouble() ?? 225,
    createdAt: DateTime.tryParse(j['created_at'] as String? ?? ''),
  );

  /// A plan inferred from plates saved without one (older versions, quick counts).
  factory SampleInfo.inferred(String id, List<PlateRecord> plates) {
    // A drop plate's dilutions are on its drops.
    final ds = {
      for (final p in plates)
        if (p.isDropPlate)
          for (final s in p.spots) s.dilutionExp
        else
          p.dilutionExp,
    }.toList()..sort();
    final reps = plates
        .map((p) => p.replicate)
        .fold(1, (a, b) => a > b ? a : b);
    final drop = plates.any((p) => p.isDropPlate);
    // Drops of several dilutions on one plate: the dilutions layout.
    final mixed = plates.any(
      (p) => {for (final s in p.spots) s.dilutionExp}.length > 1,
    );
    final perPlate = plates
        .map((p) => p.spots.length)
        .fold(0, (a, b) => a > b ? a : b);
    final membrane = !drop && plates.any((p) => p.format.membrane);
    final film = !drop && plates.any((p) => p.isFilm);
    return SampleInfo(
      sampleId: id,
      method: drop
          ? PlatingMethod.drop
          : membrane
          ? PlatingMethod.membrane
          : film
          ? PlatingMethod.film
          : PlatingMethod.spread,
      format: plates.isEmpty ? PlateFormat.dish90 : plates.first.format,
      dilutions: ds.isEmpty ? const [0] : ds,
      replicates: drop && !mixed ? math.max(reps, perPlate) : reps,
      volumeMl: plates.isEmpty || drop ? 0.1 : plates.first.volumeMl,
      dropVolumeUl: drop
          ? plates.firstWhere((p) => p.isDropPlate).volumeMl * 1000
          : 10,
      dropLayout: mixed ? DropLayout.dilutions : DropLayout.replicates,
      dropsPerDilution: mixed && ds.isNotEmpty
          ? math.max(1, (perPlate / ds.length).round())
          : 1,
      createdAt: plates.isEmpty
          ? null
          : plates
                .map((p) => p.createdAt)
                .reduce((a, b) => a.isBefore(b) ? a : b),
    );
  }
}
