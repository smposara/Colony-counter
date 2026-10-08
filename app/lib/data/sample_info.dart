import '../core/calculator.dart';
import '../core/colour.dart';
import '../core/petrifilm.dart';
import '../core/plate.dart';
import '../core/stats.dart';
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
  /// (default: the film type's first result, e.g. E. coli on EC).
  SampleResult analyse(
    List<PlateRecord> plates,
    CountingRule spreadRule, {
    String? result,
  }) => analyseReplicates([
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
    final ds = {for (final p in plates) p.dilutionExp}.toList()..sort();
    final reps = plates
        .map((p) => p.replicate)
        .fold(1, (a, b) => a > b ? a : b);
    final drop = plates.any((p) => p.isDropPlate);
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
      replicates: reps,
      volumeMl: plates.isEmpty || drop ? 0.1 : plates.first.volumeMl,
      dropVolumeUl: drop ? plates.first.volumeMl * 1000 : 10,
      createdAt: plates.isEmpty
          ? null
          : plates
                .map((p) => p.createdAt)
                .reduce((a, b) => a.isBefore(b) ? a : b),
    );
  }
}
