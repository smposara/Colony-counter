import 'dart:math' as math;

import '../core/calculator.dart';
import '../core/classical.dart';
import '../core/colour.dart';
import '../core/plate.dart';
import '../core/spots.dart';
import '../core/stats.dart';

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

  bool get isDropPlate => spots.isNotEmpty;

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

  PlateCount toPlateCount() => PlateCount(
    count,
    dilution,
    volumeMl: volumeMl,
    spreader: spreader,
    tntc: tntc,
  );

  /// The countable units of this plate: the whole plate, or each drop.
  List<Observation> observations() {
    if (!isDropPlate) return [Observation(toPlateCount(), replicate)];
    return [
      for (final s in spots)
        Observation(
          PlateCount(
            countInSpot(s, colonies),
            math.pow(10, -s.dilutionExp).toDouble(),
            volumeMl: volumeMl,
            tntc: s.tntc,
          ),
          s.replicate,
        ),
    ];
  }

  /// CFU/mL from this plate alone (all its drops pooled for a drop plate).
  Estimate estimateAlone(CountingRule spreadRule) => estimate([
    for (final o in observations()) o.count,
  ], rule: isDropPlate ? CountingRule.dropPlate : spreadRule);

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
  }) => PlateRecord(
    id: id,
    createdAt: createdAt,
    imagePath: imagePath,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    plate: plate,
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
  );
}
