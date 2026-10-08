import 'dart:math' as math;

import '../core/calculator.dart';
import '../core/classical.dart';
import '../core/colour.dart';
import '../core/drop_stats.dart';
import '../core/petrifilm.dart';
import '../core/plate.dart';
import '../core/spots.dart';
import '../core/stats.dart';
import 'drop_results.dart';

/// One counted plate, as saved in the history.
class PlateRecord {
  PlateRecord({
    required this.id,
    required this.createdAt,
    required this.imagePath,
    required this.imageWidth,
    required this.imageHeight,
    required this.plate,
    required this.colonies,
    required this.autoCount,
    this.flags = const [],
    this.sampleId = '',
    this.dilutionExp = 0,
    this.volumeMl = 0.1,
    this.notes = '',
    this.spreader = false,
    this.tntc = false,
    this.guided = false,
    this.kSigma = 4.0,
    this.replicate = 1,
    this.spots = const [],
    this.colourMode = ColourMode.none,
    this.format = PlateFormat.dish90,
    this.verified = false,
    this.rejected = const [],
    this.seriesId = '',
    this.incubationH,
    this.filmGrid,
    this.excludedSquares = const [],
  });

  final String id;
  final DateTime createdAt;

  /// File name of the photo inside the app's photo folder.
  final String imagePath;
  final int imageWidth;
  final int imageHeight;
  final Plate plate;
  final List<Colony> colonies;

  /// Count before any manual edits.
  final int autoCount;
  final List<String> flags;
  final String sampleId;

  /// Plated dilution as a power of ten: 4 means 10⁻⁴.
  final int dilutionExp;
  final double volumeMl;
  final String notes;
  final bool spreader;
  final bool tntc;

  /// Taken with the in-app camera guide (vs imported from the gallery).
  final bool guided;
  final double kSigma;

  /// Replicate number within its sample (1-based).
  final int replicate;

  /// Drops on a drop plate; empty for spread / pour plates. For drop plates
  /// [volumeMl] is the volume of one drop.
  final List<Spot> spots;
  final ColourMode colourMode;

  /// Dish or filter type.
  final PlateFormat format;

  /// The user checked every colony, so [count] is a reference count and
  /// [autoCount] can be scored against it (accuracy tracking).
  final bool verified;

  /// Automatic detections the user removed (false positives); kept as
  /// negative examples for training a detector.
  final List<Colony> rejected;

  /// Time-lapse: photos of the same plate share the first photo's id.
  final String seriesId;

  /// Hours since plating when photographed, if known.
  final double? incubationH;

  /// Dry films: the printed grid found in the photo (for square estimates).
  final FilmGrid? filmGrid;

  /// Dry films: grid squares (i, j) the user left out of the estimate.
  final List<(int, int)> excludedSquares;

  bool get isDropPlate => spots.isNotEmpty;

  bool get isFilm => format.isFilm;

  /// Dry-film type ('ac', 'ec', …), null for dishes and filters.
  String? get filmType => format.film;

  /// Counts per result of a dry film, with square estimates above its range.
  FilmTally get filmTally => tallyFilm(
    filmType!,
    filmColoniesOf(filmType!, colonies),
    filmGrid,
    plate,
    excluded: excludedSquares.toSet(),
  );

  /// Whether [result] (default: the type's first) is a square estimate.
  bool filmEstimated([String? result]) =>
      filmTally.estimates?[result ?? kFilmTypes[filmType!]!.results.first] !=
      null;

  /// Per-plate value of [result]: the square estimate when there is one,
  /// else the count. [result] defaults to the film type's first result.
  double filmValue([String? result]) {
    final t = filmTally;
    final k = result ?? kFilmTypes[filmType!]!.results.first;
    return t.estimates?[k] ?? (t.counts[k] ?? 0).toDouble();
  }

  /// Colonies per colour class (index = class).
  List<int> get classCounts {
    final out = List.filled(colourMode.classNames.length, 0);
    for (final c in colonies) {
      out[c.cls.clamp(0, out.length - 1)] += c.n;
    }
    return out;
  }

  int get count => colonies.fold(0, (s, c) => s + c.n);
  int get added => colonies.where((c) => c.manual).length;
  double get dilution => math.pow(10, -dilutionExp).toDouble();

  PlateCount toPlateCount({String? result}) => PlateCount(
    isFilm ? filmValue(result).round() : count,
    dilution,
    volumeMl: volumeMl,
    spreader: spreader,
    tntc: tntc,
  );

  /// The countable units of this plate: the whole plate, or each drop that
  /// was not left out. For a
  /// dry film, the plate's [result] (default: the type's first result).
  List<Observation> observations({String? result}) {
    if (!isDropPlate) {
      return [Observation(toPlateCount(result: result), replicate)];
    }
    // Drops the user left out do not count; a spreader on the plate affects
    // every drop on it.
    return [
      for (final s in spots)
        if (!s.isExcluded)
          Observation(
            PlateCount(
              countInSpot(s, colonies),
              math.pow(10, -s.dilutionExp).toDouble(),
              volumeMl: volumeMl,
              spreader: spreader,
              tntc: s.tntc,
            ),
            s.replicate,
          ),
    ];
  }

  /// CFU/mL from this plate alone (all its drops through the drop table for
  /// a drop plate, with the sample's [dropWindow] and [dropMode]).
  Estimate estimateAlone(
    CountingRule spreadRule, {
    CountingRule membraneRule = CountingRule.membrane80,
    String? result,
    DropMode dropMode = DropMode.pooled,
    (int, int) dropWindow = kDropWindow,
  }) {
    if (isDropPlate) {
      return estimateOfDrops(
        estimateDrops(
          dilutionTable(
            dropCountsFromSpots(spots, colonies, spreader: spreader),
          ),
          volumeMl * 1000,
          mode: dropMode,
          window: dropWindow,
        ),
        dropWindow,
      );
    }
    return estimate(
      [for (final o in observations(result: result)) o.count],
      rule: isFilm
          ? filmCountingRule(filmType!)
          : format.membrane
          ? membraneRule
          : spreadRule,
    );
  }

  PlateRecord copyWith({
    String? sampleId,
    int? dilutionExp,
    double? volumeMl,
    String? notes,
    bool? spreader,
    bool? tntc,
    List<Colony>? colonies,
    int? replicate,
    List<Spot>? spots,
    ColourMode? colourMode,
    PlateFormat? format,
    Plate? plate,
    bool? verified,
    List<Colony>? rejected,
    String? seriesId,
    double? incubationH,
    bool clearIncubation = false,
    FilmGrid? filmGrid,
    List<(int, int)>? excludedSquares,
  }) => PlateRecord(
    id: id,
    createdAt: createdAt,
    imagePath: imagePath,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    plate: plate ?? this.plate,
    colonies: colonies ?? this.colonies,
    autoCount: autoCount,
    flags: flags,
    sampleId: sampleId ?? this.sampleId,
    dilutionExp: dilutionExp ?? this.dilutionExp,
    volumeMl: volumeMl ?? this.volumeMl,
    notes: notes ?? this.notes,
    spreader: spreader ?? this.spreader,
    tntc: tntc ?? this.tntc,
    guided: guided,
    kSigma: kSigma,
    replicate: replicate ?? this.replicate,
    spots: spots ?? this.spots,
    colourMode: colourMode ?? this.colourMode,
    format: format ?? this.format,
    verified: verified ?? this.verified,
    rejected: rejected ?? this.rejected,
    seriesId: seriesId ?? this.seriesId,
    incubationH: clearIncubation ? null : incubationH ?? this.incubationH,
    filmGrid: filmGrid ?? this.filmGrid,
    excludedSquares: excludedSquares ?? this.excludedSquares,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'created_at': createdAt.toIso8601String(),
    'image': imagePath,
    'image_width': imageWidth,
    'image_height': imageHeight,
    'plate': plate.toJson(),
    'colonies': [for (final c in colonies) c.toJson()],
    'auto_count': autoCount,
    'flags': flags,
    'sample_id': sampleId,
    'dilution_exp': dilutionExp,
    'volume_ml': volumeMl,
    'notes': notes,
    'spreader': spreader,
    'tntc': tntc,
    'guided': guided,
    'k_sigma': kSigma,
    'replicate': replicate,
    if (spots.isNotEmpty) 'spots': [for (final s in spots) s.toJson()],
    if (colourMode != ColourMode.none) 'colour_mode': colourMode.name,
    if (format != PlateFormat.dish90) 'format': format.name,
    if (verified) 'verified': true,
    if (rejected.isNotEmpty) 'rejected': [for (final c in rejected) c.toJson()],
    if (seriesId.isNotEmpty) 'series_id': seriesId,
    if (incubationH != null) 'incubation_h': incubationH,
    if (filmGrid != null) 'film_grid': filmGrid!.toJson(),
    if (excludedSquares.isNotEmpty)
      'excluded_squares': [
        for (final (i, j) in excludedSquares) [i, j],
      ],
  };

  factory PlateRecord.fromJson(Map<String, dynamic> j) => PlateRecord(
    id: j['id'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
    imagePath: j['image'] as String,
    imageWidth: j['image_width'] as int,
    imageHeight: j['image_height'] as int,
    plate: Plate.fromJson(j['plate'] as Map<String, dynamic>),
    colonies: [
      for (final c in j['colonies'] as List)
        Colony.fromJson(c as Map<String, dynamic>),
    ],
    autoCount: j['auto_count'] as int,
    flags: [for (final f in j['flags'] as List? ?? const []) f as String],
    sampleId: j['sample_id'] as String? ?? '',
    dilutionExp: j['dilution_exp'] as int? ?? 0,
    volumeMl: (j['volume_ml'] as num?)?.toDouble() ?? 0.1,
    notes: j['notes'] as String? ?? '',
    spreader: j['spreader'] as bool? ?? false,
    tntc: j['tntc'] as bool? ?? false,
    guided: j['guided'] as bool? ?? false,
    kSigma: (j['k_sigma'] as num?)?.toDouble() ?? 4.0,
    replicate: (j['replicate'] as num?)?.toInt() ?? 1,
    spots: [
      for (final s in j['spots'] as List? ?? const [])
        Spot.fromJson(s as Map<String, dynamic>),
    ],
    colourMode: ColourMode.values.firstWhere(
      (m) => m.name == j['colour_mode'],
      orElse: () => ColourMode.none,
    ),
    format: PlateFormat.byName(j['format'] as String?),
    verified: j['verified'] as bool? ?? false,
    rejected: [
      for (final c in j['rejected'] as List? ?? const [])
        Colony.fromJson(c as Map<String, dynamic>),
    ],
    seriesId: j['series_id'] as String? ?? '',
    incubationH: (j['incubation_h'] as num?)?.toDouble(),
    filmGrid: j['film_grid'] == null
        ? null
        : FilmGrid.fromJson(j['film_grid'] as Map<String, dynamic>),
    excludedSquares: [
      for (final s in j['excluded_squares'] as List? ?? const [])
        ((s as List)[0] as int, s[1] as int),
    ],
  );
}

/// Whether [a] was photographed later than [b] in incubation time.
bool _later(PlateRecord a, PlateRecord b) {
  final ha = a.incubationH, hb = b.incubationH;
  if (ha != null && hb != null && ha != hb) return ha > hb;
  return a.createdAt.isAfter(b.createdAt);
}

/// Time-lapse photos are one plate: only the latest photo of each series
/// counts towards CFU/mL.
List<PlateRecord> latestOfSeries(List<PlateRecord> plates) {
  final latest = <String, PlateRecord>{};
  for (final p in plates) {
    if (p.seriesId.isEmpty) continue;
    final cur = latest[p.seriesId];
    if (cur == null || _later(p, cur)) latest[p.seriesId] = p;
  }
  return [
    for (final p in plates)
      if (p.seriesId.isEmpty || identical(latest[p.seriesId], p)) p,
  ];
}
