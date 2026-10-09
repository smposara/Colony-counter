import 'dart:math' as math;

import '../core/zone_calibration.dart';
import 'zone_record.dart';

/// Calibration of zone measurement against the user's calliper (or ruler) on a
/// used zone plate: the saved profile, its plates and how a zone plate matches it.
/// Check only: nothing here changes a measurement. See
/// docs/ZONE_CALIBRATION_IMPLEMENTATION.md.

/// A profile is due for a re-check after this many days.
const int kCalibrationMaxAgeDays = 90;

/// On the stand, the plate rim radius (px) must stay within this fraction of the
/// profile's for the setup to count as the same.
const double kSetupRimTolerance = 0.03;

enum CalibrationSetup { stand, handheld }

/// How a zone plate stands against the active profile.
enum CalibrationStatus {
  calibrated,
  uncalibrated,
  old,
  otherCamera,
  setupChanged,
}

/// One zone on a calibration plate, as it was when the plate was added.
class CalibrationZone {
  const CalibrationZone({
    required this.mark,
    required this.appMm,
    required this.userMm,
    required this.radialFraction,
    this.included = true,
  });

  /// Index of the mark on the zone plate.
  final int mark;
  final List<double> appMm;

  /// One reading, or two at right angles for a zone that isn't round.
  final List<double> userMm;
  final double radialFraction;
  final bool included;

  CalZone get calZone => CalZone(
    appMm: appMm,
    userMm: userMm,
    radialFraction: radialFraction,
    included: included,
  );

  Map<String, dynamic> toJson() => {
    'mark': mark,
    'app_mm': appMm,
    'user_mm': userMm,
    'rf': radialFraction,
    if (!included) 'included': false,
  };

  factory CalibrationZone.fromJson(Map<String, dynamic> j) => CalibrationZone(
    mark: (j['mark'] as num).toInt(),
    appMm: [for (final v in j['app_mm'] as List) (v as num).toDouble()],
    userMm: [for (final v in j['user_mm'] as List) (v as num).toDouble()],
    radialFraction: (j['rf'] as num?)?.toDouble() ?? 0,
    included: j['included'] as bool? ?? true,
  );
}

/// One used zone plate measured by the user.
class CalibrationPlate {
  const CalibrationPlate({
    required this.zoneRecordId,
    required this.addedAt,
    required this.zones,
    this.spanMarks,
    this.appSpanMm,
    this.userSpanMm,
    this.spanPx,
  });

  final String zoneRecordId;
  final DateTime addedAt;
  final List<CalibrationZone> zones;

  /// The two marks the span was measured across (the farthest apart).
  final (int, int)? spanMarks;
  final double? appSpanMm;
  final double? userSpanMm;

  /// The span in photo pixels (outer edge to outer edge).
  final double? spanPx;

  /// True mm per photo pixel at agar height, from the user's span.
  double? get trueMmPerPx =>
      userSpanMm != null && userSpanMm! > 0 && spanPx != null && spanPx! > 0
      ? userSpanMm! / spanPx!
      : null;

  bool get hasSpan =>
      appSpanMm != null &&
      userSpanMm != null &&
      appSpanMm! > 0 &&
      userSpanMm! > 0;

  /// A snapshot of [record]: every mark with a calliper reading (marks without
  /// one are left out), and the span when [userSpanMm] is given.
  factory CalibrationPlate.fromRecord(
    ZoneRecord record, {
    double? userSpanMm,
    Set<int> excluded = const {},
    DateTime? addedAt,
  }) {
    final p = record.plate;
    final zones = <CalibrationZone>[];
    for (var i = 0; i < record.marks.length; i++) {
      final m = record.marks[i];
      final user = m.calliperMm;
      if (user.isEmpty) continue;
      final rf =
          math.sqrt(math.pow(m.x - p.cx, 2) + math.pow(m.y - p.cy, 2)) /
          p.radius;
      final app = m.reportedMm(record.diskMm);
      zones.add(
        CalibrationZone(
          mark: i,
          appMm: app.isFinite ? [app] : const [],
          userMm: user,
          radialFraction: rf,
          // Zones the detector was unsure of are left out unless chosen.
          included: !excluded.contains(i) && app.isFinite,
        ),
      );
    }
    final pair = spanPair(record);
    return CalibrationPlate(
      zoneRecordId: record.id,
      addedAt: addedAt ?? DateTime.now(),
      zones: zones,
      spanMarks: pair,
      appSpanMm: pair == null ? null : recordSpanMm(record, pair),
      userSpanMm: userSpanMm,
      spanPx: pair == null ? null : recordSpanMm(record, pair) / record.mmPerPx,
    );
  }

  Map<String, dynamic> toJson() => {
    'zone_plate': zoneRecordId,
    'added_at': addedAt.toIso8601String(),
    'zones': [for (final z in zones) z.toJson()],
    if (spanMarks != null) 'span_marks': [spanMarks!.$1, spanMarks!.$2],
    'app_span_mm': ?appSpanMm,
    'user_span_mm': ?userSpanMm,
    'span_px': ?spanPx,
  };

  factory CalibrationPlate.fromJson(Map<String, dynamic> j) {
    final sm = j['span_marks'] as List?;
    return CalibrationPlate(
      zoneRecordId: j['zone_plate'] as String,
      addedAt: DateTime.parse(j['added_at'] as String),
      zones: [
        for (final z in j['zones'] as List? ?? const [])
          CalibrationZone.fromJson(z as Map<String, dynamic>),
      ],
      spanMarks: sm == null || sm.length != 2
          ? null
          : ((sm[0] as num).toInt(), (sm[1] as num).toInt()),
      appSpanMm: (j['app_span_mm'] as num?)?.toDouble(),
      userSpanMm: (j['user_span_mm'] as num?)?.toDouble(),
      spanPx: (j['span_px'] as num?)?.toDouble(),
    );
  }
}

/// Zones that make poor calibration zones: offered, but left out unless the
/// user includes them. A disk with no zone only checks the disk size, not
/// where a zone edge is read.
bool doubtfulForCalibration(ZoneMark m) =>
    !m.measured ||
    m.noZone ||
    m.flags.any((f) => const {'overlap', 'hazy', 'unmeasured'}.contains(f));

/// The two marks of [record] farthest apart (outer edge to outer edge), or null
/// with fewer than two.
(int, int)? spanPair(ZoneRecord record) => record.marks.length < 2
    ? null
    : farthestPair([for (final m in record.marks) (m.x, m.y, m.diskRadiusPx)]);

/// The app's outer-edge to outer-edge span across marks [pair], in mm.
double recordSpanMm(ZoneRecord record, (int, int) pair) {
  final a = record.marks[pair.$1], b = record.marks[pair.$2];
  return appSpanMm(
    (a.x, a.y, a.diskRadiusPx),
    (b.x, b.y, b.diskRadiusPx),
    record.mmPerPx,
  );
}

/// The calibration of one camera and setup: one or more used zone plates.
class CalibrationProfile {
  const CalibrationProfile({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.cameraName,
    required this.imageWidth,
    required this.imageHeight,
    required this.platform,
    required this.setup,
    required this.rimRadiusPx,
    required this.tool,
    required this.plates,
    this.name = '',
  });

  final String id;
  final DateTime createdAt;

  /// When the last plate was added: the 90-day re-check counts from here.
  final DateTime updatedAt;
  final String name;

  /// The camera plugin's name for the lens ('' on the web).
  final String cameraName;
  final int imageWidth;
  final int imageHeight;

  /// 'android', 'ios' or 'web'.
  final String platform;
  final CalibrationSetup setup;

  /// Plate rim radius in photo pixels on the calibration plates (to recognise
  /// the same stand height).
  final double rimRadiusPx;
  final CalibrationTool tool;
  final List<CalibrationPlate> plates;

  /// Pooled over every plate: the span check is the mean of the plates' span
  /// ratios.
  CalSummary get summary {
    final spans = [
      for (final p in plates)
        if (p.hasSpan) p.appSpanMm! / p.userSpanMm!,
    ];
    final ratio = spans.isEmpty
        ? null
        : spans.reduce((a, b) => a + b) / spans.length;
    return calibrationSummary(
      [
        for (final p in plates)
          for (final z in p.zones) z.calZone,
      ],
      appSpan: ratio,
      userSpan: ratio == null ? null : 1.0,
      tool: tool,
    );
  }

  /// True mm per photo pixel at agar height on this setup (mean over plates),
  /// or null without a span.
  double? get trueMmPerPx {
    final v = [for (final p in plates) ?p.trueMmPerPx];
    return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
  }

  bool isOld(DateTime now) =>
      now.difference(updatedAt).inDays > kCalibrationMaxAgeDays;

  /// Same lens and photo size.
  bool sameCamera(String camera, int width, int height) =>
      camera == cameraName &&
      ((width == imageWidth && height == imageHeight) ||
          (width == imageHeight && height == imageWidth));

  /// On the stand, the rim radius shows the camera height; a hand-held profile
  /// has no fixed height to compare.
  bool sameSetup(double rimRadius) =>
      setup == CalibrationSetup.handheld ||
      (rimRadius - rimRadiusPx).abs() <= kSetupRimTolerance * rimRadiusPx;

  CalibrationProfile copyWith({
    DateTime? updatedAt,
    String? name,
    CalibrationTool? tool,
    List<CalibrationPlate>? plates,
  }) => CalibrationProfile(
    id: id,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    name: name ?? this.name,
    cameraName: cameraName,
    imageWidth: imageWidth,
    imageHeight: imageHeight,
    platform: platform,
    setup: setup,
    rimRadiusPx: rimRadiusPx,
    tool: tool ?? this.tool,
    plates: plates ?? this.plates,
  );

  /// With [plate] added (replacing an earlier snapshot of the same zone plate).
  CalibrationProfile withPlate(CalibrationPlate plate) => copyWith(
    updatedAt: plate.addedAt,
    plates: [
      for (final p in plates)
        if (p.zoneRecordId != plate.zoneRecordId) p,
      plate,
    ],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    if (name.isNotEmpty) 'name': name,
    'camera': cameraName,
    'image_width': imageWidth,
    'image_height': imageHeight,
    'platform': platform,
    'setup': setup.name,
    'rim_radius_px': rimRadiusPx,
    'tool': tool.name,
    'plates': [for (final p in plates) p.toJson()],
  };

  factory CalibrationProfile.fromJson(Map<String, dynamic> j) =>
      CalibrationProfile(
        id: j['id'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
        updatedAt: DateTime.parse(
          j['updated_at'] as String? ?? j['created_at'] as String,
        ),
        name: j['name'] as String? ?? '',
        cameraName: j['camera'] as String? ?? '',
        imageWidth: (j['image_width'] as num?)?.toInt() ?? 0,
        imageHeight: (j['image_height'] as num?)?.toInt() ?? 0,
        platform: j['platform'] as String? ?? '',
        setup: CalibrationSetup.values.firstWhere(
          (s) => s.name == j['setup'],
          orElse: () => CalibrationSetup.handheld,
        ),
        rimRadiusPx: (j['rim_radius_px'] as num?)?.toDouble() ?? 0,
        tool: CalibrationTool.values.firstWhere(
          (t) => t.name == j['tool'],
          orElse: () => CalibrationTool.calliper,
        ),
        plates: [
          for (final p in j['plates'] as List? ?? const [])
            CalibrationPlate.fromJson(p as Map<String, dynamic>),
        ],
      );
}

/// The newest profile for [camera] at this photo size, or null.
CalibrationProfile? activeCalibration(
  List<CalibrationProfile> profiles, {
  required String camera,
  required int width,
  required int height,
}) {
  CalibrationProfile? best;
  for (final p in profiles) {
    if (!p.sameCamera(camera, width, height)) continue;
    if (best == null || p.updatedAt.isAfter(best.updatedAt)) best = p;
  }
  return best;
}

/// How a photo taken with [camera] at [width] × [height], with the plate rim at
/// [rimRadiusPx] (null: not known yet), on day [at], stands against [profile];
/// [anyProfiles] tells "never calibrated" from "calibrated, but not this lens".
CalibrationStatus statusAgainst(
  CalibrationProfile? profile, {
  required String camera,
  required int width,
  required int height,
  required DateTime at,
  double? rimRadiusPx,
  bool anyProfiles = false,
}) {
  if (profile == null) {
    return anyProfiles
        ? CalibrationStatus.otherCamera
        : CalibrationStatus.uncalibrated;
  }
  if (!profile.sameCamera(camera, width, height)) {
    return CalibrationStatus.otherCamera;
  }
  if (rimRadiusPx != null && !profile.sameSetup(rimRadiusPx)) {
    return CalibrationStatus.setupChanged;
  }
  if (at.difference(profile.updatedAt).inDays > kCalibrationMaxAgeDays) {
    return CalibrationStatus.old;
  }
  return CalibrationStatus.calibrated;
}

/// How the saved zone plate [record] stands: against the profile it was saved
/// with, else the active one for its camera, judged on the day it was
/// photographed.
(CalibrationStatus, CalibrationProfile?) recordCalibration(
  ZoneRecord record,
  List<CalibrationProfile> profiles,
) {
  final profile =
      profiles.where((p) => p.id == record.calibrationId).firstOrNull ??
      activeCalibration(
        profiles,
        camera: record.camera,
        width: record.imageWidth,
        height: record.imageHeight,
      );
  return (
    statusAgainst(
      profile,
      camera: record.camera,
      width: record.imageWidth,
      height: record.imageHeight,
      at: record.createdAt,
      rimRadiusPx: record.plate.radius,
      anyProfiles: profiles.isNotEmpty,
    ),
    profile,
  );
}

/// Plate flags for [status] (empty when calibrated).
List<String> calibrationFlags(CalibrationStatus status) => switch (status) {
  CalibrationStatus.calibrated => const [],
  CalibrationStatus.uncalibrated => const ['uncalibrated'],
  CalibrationStatus.old => const ['calibration_old'],
  CalibrationStatus.otherCamera => const ['calibration_other_camera'],
  CalibrationStatus.setupChanged => const ['calibration_setup_changed'],
};

/// A plate's scale (mm per pixel, from the disks or for wells the rim) against
/// the true scale its calibration measured on this setup: the fraction by which
/// its zones read large (+) or small (−). Null unless [status] is calibrated, the
/// profile is from the stand (a fixed height) and has a span.
double? scaleAgainstCalibration(
  ZoneRecord record,
  CalibrationStatus status,
  CalibrationProfile? profile,
) {
  if (status != CalibrationStatus.calibrated || profile == null) return null;
  if (profile.setup != CalibrationSetup.stand) return null;
  final truth = profile.trueMmPerPx;
  if (truth == null || truth <= 0) return null;
  return record.mmPerPx / truth - 1;
}

/// Above this fraction the plate's scale and the calibration's disagree.
const double kScaleDisagree = 0.02;
