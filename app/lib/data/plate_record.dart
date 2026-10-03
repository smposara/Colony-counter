import 'dart:math' as math;

import '../core/calculator.dart';
import '../core/classical.dart';
import '../core/plate.dart';

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

  Estimate estimateAlone(CountingRule rule) =>
      estimate([toPlateCount()], rule: rule);

  PlateRecord copyWith({
    String? sampleId,
    int? dilutionExp,
    double? volumeMl,
    String? notes,
    bool? spreader,
    bool? tntc,
    List<Colony>? colonies,
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
  );
}

/// CSV with one row per plate, plus the pooled estimate for its sample.
String recordsToCsv(List<PlateRecord> records, CountingRule rule) {
  String esc(Object? v) {
    final s = '$v';
    return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
  }

  final bySample = <String, List<PlateRecord>>{};
  for (final r in records) {
    if (r.sampleId.isNotEmpty) (bySample[r.sampleId] ??= []).add(r);
  }
  final sampleEstimate = {
    for (final e in bySample.entries)
      e.key: estimate([for (final r in e.value) r.toPlateCount()], rule: rule),
  };

  final rows = <List<Object?>>[
    [
      'plate_id',
      'date',
      'sample_id',
      'dilution',
      'volume_ml',
      'auto_count',
      'final_count',
      'added',
      'flags',
      'spreader',
      'tntc',
      'plate_cfu_per_ml',
      'sample_cfu_per_ml',
      'sample_qualifier',
      'rule',
      'notes',
      'image',
    ],
    for (final r in records)
      [
        r.id,
        r.createdAt.toIso8601String(),
        r.sampleId,
        '1e-${r.dilutionExp}',
        r.volumeMl,
        r.autoCount,
        r.count,
        r.added,
        r.flags.join(';'),
        r.spreader,
        r.tntc,
        r.spreader ? '' : cfuPerMl(r.count, r.dilution, r.volumeMl),
        sampleEstimate[r.sampleId]?.value ?? '',
        sampleEstimate[r.sampleId]?.qualifier.name ?? '',
        rule.label,
        r.notes,
        r.imagePath,
      ],
  ];
  return '${rows.map((row) => row.map(esc).join(',')).join('\n')}\n';
}
