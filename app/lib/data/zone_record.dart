import 'dart:math' as math;

import '../core/plate.dart';
import '../core/zones.dart';

/// Inhibition-zone plates (disk or agar-well diffusion), kept apart from
/// [PlateRecord] so the colony code paths (estimates, CSVs, accuracy checks,
/// training export) never see them. See docs/AST_IMPLEMENTATION.md. Measurement
/// only: no S/I/R interpretation anywhere.

/// One disk or well on a zone plate and its zone, as measured and as edited.
class ZoneMark {
  ZoneMark({
    required this.x,
    required this.y,
    required this.diskRadiusPx,
    required this.radiusPx,
    required this.diameterMm,
    required this.autoDiameterMm,
    this.confidence = 0,
    this.edgeWidthMm = 0,
    this.flags = const [],
    this.label = '',
    this.noZone = false,
    this.manual = false,
    this.opened = false,
    this.calliperMm = const [],
  });

  /// From an automatic measurement.
  factory ZoneMark.fromZone(Zone z) => ZoneMark(
    x: z.x,
    y: z.y,
    diskRadiusPx: z.diskRadiusPx,
    radiusPx: z.radiusPx,
    diameterMm: z.diameterMm,
    autoDiameterMm: z.diameterMm,
    confidence: z.confidence,
    edgeWidthMm: z.edgeWidthMm,
    flags: List.of(z.flags),
    noZone: z.flags.contains('no_zone'),
  );

  /// Disk or well centre and radius, photo pixels.
  final double x;
  final double y;
  final double diskRadiusPx;

  /// Zone radius as drawn (NaN when not measured).
  final double radiusPx;

  /// Zone diameter in mm as it stands (after edits; NaN when not measured).
  final double diameterMm;

  /// What the app measured (NaN for disks added by hand or not measured).
  final double autoDiameterMm;
  final double confidence;
  final double edgeWidthMm;

  /// From the detector: no_zone, overlap, hits_rim, hazy, colonies_in_zone,
  /// low_confidence, unmeasured.
  final List<String> flags;

  /// Test item, e.g. "EtOH extract" or "Amp 10".
  final String label;

  /// No inhibition: the zone is reported as the disk (or well) diameter.
  final bool noZone;

  /// Added by the user (a disk or well the app missed).
  final bool manual;

  /// The user has looked at it (opened its sheet).
  final bool opened;

  /// The user's own calliper (or ruler) reading(s) of the zone in mm, for
  /// calibration: one, or two at right angles for a zone that isn't round.
  /// Kept apart from [diameterMm] and never changes it.
  final List<double> calliperMm;

  bool get measured => noZone || diameterMm.isFinite;

  /// Needs a look before the plate counts as checked.
  bool get lowConfidence =>
      !measured ||
      flags.any(
        (f) => const {
          'low_confidence',
          'unmeasured',
          'overlap',
          'hazy',
        }.contains(f),
      );

  bool get edited =>
      manual ||
      noZone != flags.contains('no_zone') ||
      (diameterMm.isFinite != autoDiameterMm.isFinite) ||
      (diameterMm.isFinite && (diameterMm - autoDiameterMm).abs() > 1e-6);

  /// The diameter reported for [diskMm] disks or wells: the disk size when
  /// there is no zone.
  double reportedMm(double diskMm) => noZone ? diskMm : diameterMm;

  /// Whole mm as shown on screen (EUCAST reads to the nearest mm).
  int? roundedMm(double diskMm) {
    final v = reportedMm(diskMm);
    return v.isFinite ? (v + 0.5).floor() : null;
  }

  ZoneMark copyWith({
    double? x,
    double? y,
    double? diskRadiusPx,
    double? radiusPx,
    double? diameterMm,
    String? label,
    bool? noZone,
    bool? opened,
    List<double>? calliperMm,
  }) => ZoneMark(
    x: x ?? this.x,
    y: y ?? this.y,
    diskRadiusPx: diskRadiusPx ?? this.diskRadiusPx,
    radiusPx: radiusPx ?? this.radiusPx,
    diameterMm: diameterMm ?? this.diameterMm,
    autoDiameterMm: autoDiameterMm,
    confidence: confidence,
    edgeWidthMm: edgeWidthMm,
    flags: flags,
    label: label ?? this.label,
    noZone: noZone ?? this.noZone,
    manual: manual,
    opened: opened ?? this.opened,
    calliperMm: calliperMm ?? this.calliperMm,
  );

  static double? _num(Object? v) => (v as num?)?.toDouble();

  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'disk_r': diskRadiusPx,
    'r': radiusPx.isFinite ? radiusPx : null,
    'mm': diameterMm.isFinite ? diameterMm : null,
    'auto_mm': autoDiameterMm.isFinite ? autoDiameterMm : null,
    'conf': confidence,
    'edge_mm': edgeWidthMm,
    if (flags.isNotEmpty) 'flags': flags,
    if (label.isNotEmpty) 'label': label,
    if (noZone) 'no_zone': true,
    if (manual) 'manual': true,
    if (opened) 'opened': true,
    if (calliperMm.isNotEmpty) 'calliper_mm': calliperMm,
  };

  factory ZoneMark.fromJson(Map<String, dynamic> j) => ZoneMark(
    x: _num(j['x'])!,
    y: _num(j['y'])!,
    diskRadiusPx: _num(j['disk_r'])!,
    radiusPx: _num(j['r']) ?? double.nan,
    diameterMm: _num(j['mm']) ?? double.nan,
    autoDiameterMm: _num(j['auto_mm']) ?? double.nan,
    confidence: _num(j['conf']) ?? 0,
    edgeWidthMm: _num(j['edge_mm']) ?? 0,
    flags: [for (final f in j['flags'] as List? ?? const []) f as String],
    label: j['label'] as String? ?? '',
    noZone: j['no_zone'] as bool? ?? false,
    manual: j['manual'] as bool? ?? false,
    opened: j['opened'] as bool? ?? false,
    calliperMm: [
      for (final v in j['calliper_mm'] as List? ?? const [])
        (v as num).toDouble(),
    ],
  );
}

/// One photographed zone plate.
class ZoneRecord {
  ZoneRecord({
    required this.id,
    required this.createdAt,
    required this.imagePath,
    required this.imageWidth,
    required this.imageHeight,
    required this.plate,
    required this.mmPerPx,
    required this.marks,
    this.format = PlateFormat.dish90,
    this.assay = ZoneAssay.disk,
    this.diskMm = 6.0,
    this.flags = const [],
    this.experiment = '',
    this.organism = '',
    this.replicate = 1,
    this.panel = '',
    this.notes = '',
    this.camera = '',
    this.calibrationId = '',
    this.usedForCalibration = false,
  });

  final String id;
  final DateTime createdAt;

  /// File name of the photo inside the app's photo folder.
  final String imagePath;
  final int imageWidth;
  final int imageHeight;
  final Plate plate;

  /// Scale used for the zones (from the 6 mm disks when they agree with the
  /// plate, else the plate's).
  final double mmPerPx;
  final List<ZoneMark> marks;
  final PlateFormat format;
  final ZoneAssay assay;

  /// Disk diameter, or the well diameter.
  final double diskMm;

  /// Plate-level flags from the detector: scale_mismatch, scale_unchecked,
  /// no_disks.
  final List<String> flags;
  final String experiment;

  /// Test organism, e.g. "S. aureus ATCC 25923".
  final String organism;
  final int replicate;

  /// Name of the label panel used, if any.
  final String panel;
  final String notes;

  /// The camera plugin's name for the lens the photo was taken with ('' when
  /// not known: gallery photos and the web).
  final String camera;

  /// The calibration profile active when the plate was saved ('' for none).
  final String calibrationId;

  /// The plate was measured with a calliper to calibrate the app.
  final bool usedForCalibration;

  /// Every zone the app was unsure of has been looked at.
  bool get checked => marks.every((m) => !m.lowConfidence || m.opened);

  int get edits => marks.where((m) => m.edited).length;

  ZoneRecord copyWith({
    Plate? plate,
    double? mmPerPx,
    List<ZoneMark>? marks,
    List<String>? flags,
    String? experiment,
    String? organism,
    int? replicate,
    String? panel,
    String? notes,
    String? camera,
    String? calibrationId,
    bool? usedForCalibration,
  }) => ZoneRecord(
    id: id,
    createdAt: createdAt,
    imagePath: imagePath,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    plate: plate ?? this.plate,
    mmPerPx: mmPerPx ?? this.mmPerPx,
    marks: marks ?? this.marks,
    format: format,
    assay: assay,
    diskMm: diskMm,
    flags: flags ?? this.flags,
    experiment: experiment ?? this.experiment,
    organism: organism ?? this.organism,
    replicate: replicate ?? this.replicate,
    panel: panel ?? this.panel,
    notes: notes ?? this.notes,
    camera: camera ?? this.camera,
    calibrationId: calibrationId ?? this.calibrationId,
    usedForCalibration: usedForCalibration ?? this.usedForCalibration,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'created_at': createdAt.toIso8601String(),
    'image': imagePath,
    'image_width': imageWidth,
    'image_height': imageHeight,
    'plate': plate.toJson(),
    'mm_per_px': mmPerPx,
    'marks': [for (final m in marks) m.toJson()],
    'format': format.name,
    'assay': assay.name,
    'disk_mm': diskMm,
    if (flags.isNotEmpty) 'flags': flags,
    'experiment': experiment,
    'organism': organism,
    'replicate': replicate,
    if (panel.isNotEmpty) 'panel': panel,
    if (notes.isNotEmpty) 'notes': notes,
    if (camera.isNotEmpty) 'camera': camera,
    if (calibrationId.isNotEmpty) 'calibration': calibrationId,
    if (usedForCalibration) 'used_for_calibration': true,
  };

  factory ZoneRecord.fromJson(Map<String, dynamic> j) {
    final plate = Plate.fromJson(j['plate'] as Map<String, dynamic>);
    return ZoneRecord(
      id: j['id'] as String,
      createdAt: DateTime.parse(j['created_at'] as String),
      imagePath: j['image'] as String,
      imageWidth: (j['image_width'] as num).toInt(),
      imageHeight: (j['image_height'] as num).toInt(),
      plate: plate,
      mmPerPx: (j['mm_per_px'] as num?)?.toDouble() ?? plate.mmPerPx,
      marks: [
        for (final m in j['marks'] as List? ?? const [])
          ZoneMark.fromJson(m as Map<String, dynamic>),
      ],
      format: PlateFormat.byName(j['format'] as String?),
      assay: ZoneAssay.values.firstWhere(
        (a) => a.name == j['assay'],
        orElse: () => ZoneAssay.disk,
      ),
      diskMm: (j['disk_mm'] as num?)?.toDouble() ?? 6.0,
      flags: [for (final f in j['flags'] as List? ?? const []) f as String],
      experiment: j['experiment'] as String? ?? '',
      organism: j['organism'] as String? ?? '',
      replicate: (j['replicate'] as num?)?.toInt() ?? 1,
      panel: j['panel'] as String? ?? '',
      notes: j['notes'] as String? ?? '',
      camera: j['camera'] as String? ?? '',
      calibrationId: j['calibration'] as String? ?? '',
      usedForCalibration: j['used_for_calibration'] as bool? ?? false,
    );
  }

  /// A new record from an automatic measurement, labelled from [labels]
  /// (clockwise from 12 o'clock).
  factory ZoneRecord.fromResult(
    ZoneResult r, {
    required String id,
    required String imagePath,
    required DateTime createdAt,
    PlateFormat format = PlateFormat.dish90,
    double diskMm = 6.0,
    List<String> labels = const [],
    String experiment = '',
    String organism = '',
    int replicate = 1,
    String panel = '',
    String camera = '',
  }) => ZoneRecord(
    id: id,
    createdAt: createdAt,
    imagePath: imagePath,
    imageWidth: r.imageWidth,
    imageHeight: r.imageHeight,
    plate: r.plate,
    mmPerPx: zoneScale(r),
    marks: assignLabels(
      [for (final z in r.zones) ZoneMark.fromZone(z)],
      r.plate,
      labels,
    ),
    format: format,
    assay: r.assay,
    diskMm: diskMm,
    flags: List.of(r.flags),
    experiment: experiment,
    organism: organism,
    replicate: replicate,
    panel: panel,
    camera: camera,
  );
}

/// mm per photo pixel the zones were measured at: the measured zones'
/// own ratio (the detector scales by the 6 mm disks), else the plate's
/// corrected by the disks.
double zoneScale(ZoneResult r) {
  final ratios = [
    for (final z in r.zones)
      if (z.diameterMm.isFinite && z.radiusPx > 0)
        z.diameterMm / (2 * z.radiusPx),
  ]..sort();
  if (ratios.isNotEmpty) return ratios[ratios.length ~/ 2];
  final k = r.diskScaleRatio.isFinite && r.diskScaleRatio > 0
      ? r.diskScaleRatio
      : 1.0;
  return r.plate.mmPerPx / k;
}

/// Angle of (x, y) clockwise from 12 o'clock around the plate centre, 0–2π.
double clockAngle(Plate plate, double x, double y) {
  final a = math.atan2(x - plate.cx, -(y - plate.cy));
  return a < 0 ? a + 2 * math.pi : a;
}

/// [marks] in clockwise order from 12 o'clock, labelled in turn from
/// [labels] (marks beyond the list keep their own label). A disk at the
/// centre (within a fifth of the radius) comes last, as panels usually put
/// the control there.
///
/// The order starts half the spacing between ring disks before 12 o'clock,
/// so a disk placed at 12 but a little to the left still comes first.
List<ZoneMark> assignLabels(
  List<ZoneMark> marks,
  Plate plate,
  List<String> labels,
) {
  bool central(ZoneMark m) =>
      math.sqrt(math.pow(m.x - plate.cx, 2) + math.pow(m.y - plate.cy, 2)) <
      plate.radius * 0.2;
  final ring = marks.where((m) => !central(m)).length;
  final lead = ring > 0 ? math.pi / ring : 0.0;
  double angle(ZoneMark m) =>
      (clockAngle(plate, m.x, m.y) + lead) % (2 * math.pi);
  final ordered = List.of(marks)
    ..sort((a, b) {
      final ca = central(a), cb = central(b);
      if (ca != cb) return ca ? 1 : -1;
      return angle(a).compareTo(angle(b));
    });
  return [
    for (var i = 0; i < ordered.length; i++)
      i < labels.length ? ordered[i].copyWith(label: labels[i]) : ordered[i],
  ];
}

/// A saved list of test-item labels in placement order (clockwise from 12
/// o'clock, any centre disk last), e.g. "Extract set A".
class ZonePanel {
  const ZonePanel(this.name, this.labels);

  final String name;
  final List<String> labels;

  Map<String, dynamic> toJson() => {'name': name, 'labels': labels};

  factory ZonePanel.fromJson(Map<String, dynamic> j) => ZonePanel(
    j['name'] as String,
    [for (final l in j['labels'] as List? ?? const []) l as String],
  );
}

/// Zone diameters of one test item across replicate plates.
class ZoneSummary {
  ZoneSummary(this.experiment, this.organism, this.label, this.values);

  final String experiment;
  final String organism;
  final String label;

  /// Unrounded diameters in mm, one per zone.
  final List<double> values;

  int get n => values.length;
  double get mean => n == 0 ? double.nan : values.reduce((a, b) => a + b) / n;
  double get sd {
    if (n < 2) return double.nan;
    final m = mean;
    return math.sqrt(
      values.fold(0.0, (s, v) => s + (v - m) * (v - m)) / (n - 1),
    );
  }
}

/// Mean ± SD per experiment, organism and label over [records]. Zones without
/// a label or a measurement are left out; "no zone" counts as the disk size.
List<ZoneSummary> summariseZones(List<ZoneRecord> records) {
  final groups = <(String, String, String), List<double>>{};
  for (final r in records) {
    for (final m in r.marks) {
      final v = m.reportedMm(r.diskMm);
      if (m.label.isEmpty || !v.isFinite) continue;
      (groups[(r.experiment, r.organism, m.label)] ??= []).add(v);
    }
  }
  final keys = groups.keys.toList()
    ..sort((a, b) {
      for (final (x, y) in [(a.$1, b.$1), (a.$2, b.$2), (a.$3, b.$3)]) {
        final c = x.compareTo(y);
        if (c != 0) return c;
      }
      return 0;
    });
  return [for (final k in keys) ZoneSummary(k.$1, k.$2, k.$3, groups[k]!)];
}

/// The choices made before photographing a zone plate; the last ones are
/// remembered for the next plate.
class ZoneSetup {
  const ZoneSetup({
    this.assay = ZoneAssay.disk,
    this.diskMm = 6.0,
    this.format = PlateFormat.dish90,
    this.experiment = '',
    this.organism = '',
    this.replicate = 1,
    this.panel = '',
  });

  final ZoneAssay assay;

  /// Disk diameter, or the well diameter.
  final double diskMm;
  final PlateFormat format;
  final String experiment;
  final String organism;
  final int replicate;

  /// Name of the label panel, or empty for none.
  final String panel;

  ZoneSetup copyWith({
    ZoneAssay? assay,
    double? diskMm,
    PlateFormat? format,
    String? experiment,
    String? organism,
    int? replicate,
    String? panel,
  }) => ZoneSetup(
    assay: assay ?? this.assay,
    diskMm: diskMm ?? this.diskMm,
    format: format ?? this.format,
    experiment: experiment ?? this.experiment,
    organism: organism ?? this.organism,
    replicate: replicate ?? this.replicate,
    panel: panel ?? this.panel,
  );

  Map<String, dynamic> toJson() => {
    'assay': assay.name,
    'disk_mm': diskMm,
    'format': format.name,
    'experiment': experiment,
    'organism': organism,
    'replicate': replicate,
    'panel': panel,
  };

  factory ZoneSetup.fromJson(Map<String, dynamic> j) => ZoneSetup(
    assay: ZoneAssay.values.firstWhere(
      (a) => a.name == j['assay'],
      orElse: () => ZoneAssay.disk,
    ),
    diskMm: (j['disk_mm'] as num?)?.toDouble() ?? 6.0,
    format: PlateFormat.byName(j['format'] as String?),
    experiment: j['experiment'] as String? ?? '',
    organism: j['organism'] as String? ?? '',
    replicate: (j['replicate'] as num?)?.toInt() ?? 1,
    panel: j['panel'] as String? ?? '',
  );
}
