import 'dart:typed_data';

import '../classical.dart';
import '../annotate.dart';
import '../colour.dart';
import '../labels.dart';
import '../spots.dart';
import '../../data/export_metadata.dart';
import '../../data/training_metadata.dart';
import '../drop_layout.dart';
import '../normalize.dart';
import '../petrifilm.dart';
import '../pipeline.dart';
import '../plate.dart';
import '../zones.dart';

// The worker and UI share these codecs. Only plain JSON and transferred image
// bytes cross the boundary; no Flutter objects or detector code run on the UI.
Map<String, dynamic> object(Object? value) =>
    (value as Map).cast<String, dynamic>();
double number(Object? value) => (value as num).toDouble();
List<String> strings(Object? value) => (value as List).cast<String>();
Plate? optionalPlate(Object? value) =>
    value == null ? null : Plate.fromJson(object(value));
List<Colony> colonies(Object? value) => [
  for (final c in value as List) Colony.fromJson(object(c)),
];

Map<String, dynamic> countJob(CountOptions o) => {
  'kind': 'count',
  'plate': o.plate?.toJson(),
  'format': o.format.name,
  'rim': o.rimFraction,
  'polarity': o.polarity.name,
  'params': [
    o.params.minDiameterMm,
    o.params.kSigma,
    o.params.minContrast,
    o.params.peakSeparation,
    o.params.spreaderFraction,
  ],
};
CountResult readCount(Map<String, dynamic> j) => CountResult(
  colonies: colonies(j['colonies']),
  plate: Plate.fromJson(object(j['plate'])),
  polarity: Polarity.values.byName(j['polarity'] as String),
  flags: strings(j['flags']),
  coverage: number(j['coverage']),
  imageWidth: j['width'] as int,
  imageHeight: j['height'] as int,
);
Map<String, dynamic> filmJob(FilmJob job) => {
  'kind': 'film',
  'type': job.type,
  'plate': job.area?.toJson(),
};
FilmResult readFilm(Map<String, dynamic> j) => FilmResult(
  type: j['type'] as String,
  plate: Plate.fromJson(object(j['plate'])),
  grid: FilmGrid.fromJson(object(j['grid'])),
  colonies: [
    for (final entry in j['colonies'] as List) ...[
      () {
        final c = object(entry);
        return FilmColony(
          number(c['x']),
          number(c['y']),
          number(c['r']),
          c['kind'] as String,
          n: c['n'] as int,
          gas: c['gas'] == true,
          yellow: c['yellow'] == true,
        );
      }(),
    ],
  ],
  bubbles: [
    for (final b in j['bubbles'] as List)
      (number((b as List)[0]), number(b[1]), number(b[2])),
  ],
  counts: object(j['counts']).map((k, v) => MapEntry(k, (v as num).toInt())),
  estimates: j['estimates'] == null
      ? null
      : object(j['estimates']).map((k, v) => MapEntry(k, number(v))),
  squaresUsed: j['squares_used'] as int,
  flags: strings(j['flags']),
  imageWidth: j['width'] as int,
  imageHeight: j['height'] as int,
);
Map<String, dynamic> dropJob(DropJob job) {
  final (_, template, dilutions, volume, format, plate) = job;
  final t = switch (template) {
    SectorTemplate() => {
      'type': 'ring',
      'n': template.n,
      'ring': template.ringMm,
      'per': template.dropsPerDilution,
    },
    GridTemplate() => {
      'type': 'grid',
      'rows': template.rows,
      'cols': template.cols,
      'pitch': template.pitchMm,
    },
    FreeTemplate() => {'type': 'free'},
  };
  return {
    'kind': 'drop',
    'template': t,
    'dilutions': dilutions,
    'volume': volume,
    'format': format.name,
    'plate': plate?.toJson(),
  };
}

DropPlateResult readDrop(Map<String, dynamic> j) {
  final fit = j['fit'] as List?;
  return DropPlateResult(
    plate: Plate.fromJson(object(j['plate'])),
    colonies: colonies(j['colonies']),
    drops: [
      for (final entry in j['drops'] as List) ...[
        () {
          final d = object(entry);
          return FoundDrop(
            x: number(d['x']),
            y: number(d['y']),
            radiusPx: number(d['r']),
            position: d['position'] as int?,
            dilutionExp: d['dilution'] as int,
            replicate: d['replicate'] as int,
            count: d['count'] as int,
            confluent: d['confluent'] as bool,
            crowded: d['crowded'] as bool,
            colonies: (d['colonies'] as List).cast<int>(),
          );
        }(),
      ],
    ],
    strays: (j['strays'] as List).cast<int>(),
    fit: fit == null
        ? null
        : LayoutFit(
            number(fit[0]),
            number(fit[1]),
            number(fit[2]),
            number(fit[3]),
            fit[4] as int,
            fit[5] as int,
          ),
    flags: strings(j['flags']),
    imageWidth: j['width'] as int,
    imageHeight: j['height'] as int,
  );
}

Map<String, dynamic> zoneJob(ZoneOptions o) => {
  'kind': 'zones',
  'format': o.format.name,
  'assay': o.assay.name,
  'disk': o.diskMm,
  'plate': o.plate?.toJson(),
  'disks': o.disks == null
      ? null
      : [
          for (final d in o.disks!) [d.x, d.y, d.radiusPx, d.score, d.measured],
        ],
  'params': [
    o.params.edgeLevel,
    o.params.persistMm,
    o.params.startGapMm,
    o.params.minContrast,
    o.params.maxZoneMm,
    o.params.hazyWidthMm,
    o.params.scaleTolerance,
  ],
};
ZoneResult readZones(Map<String, dynamic> j) => ZoneResult(
  plate: Plate.fromJson(object(j['plate'])),
  assay: ZoneAssay.values.byName(j['assay'] as String),
  zones: [for (final z in j['zones'] as List) Zone.fromJson(object(z))],
  polarity: j['polarity'] as String,
  diskScaleRatio: number(j['ratio']),
  flags: strings(j['flags']),
  imageWidth: j['width'] as int,
  imageHeight: j['height'] as int,
);

Map<String, dynamic> annotationJob(AnnotationJob job) => {
  'kind': 'annotate',
  'plate': job.plate.toJson(),
  'colonies': [for (final c in job.colonies) c.toJson()],
  'spots': [for (final s in job.spots) s.toJson()],
  'zones': [
    for (final z in job.zones)
      [
        z.x,
        z.y,
        z.diskRadiusPx,
        z.radiusPx.isFinite ? z.radiusPx : null,
        z.text,
        z.unsure,
      ],
  ],
  'colour': job.colourMode.name,
  'header': job.header,
  'rim': job.rimFraction,
  'max_side': job.maxSide,
};

/// Pure-Dart dispatch, also exercised by native regression tests.
Map<String, dynamic> processPhotoJob(Uint8List bytes, Map<String, dynamic> j) {
  final plate = optionalPlate(j['plate']);
  switch (j['kind']) {
    case 'training':
      return {'files': trainingMetadata(j)};
    case 'export':
      return exportMetadata(j);
    case 'find_plates':
      final r = findPlatesInPhoto((
        bytes,
        PlateFormat.byName(j['format'] as String),
      ));
      return {
        'plates': [for (final p in r.plates) p.toJson()],
        'width': r.width,
        'height': r.height,
        'other_sizes': r.otherSizes,
      };
    case 'crop':
      final (crop, p) = cropToPlate((bytes, plate!));
      return {'binary': crop, 'plate': p.toJson()};
    case 'label':
      return {'label': readLabelFromPhoto(bytes)?.encode()};
    case 'annotate':
      final result = annotatePhoto(
        AnnotationJob(
          photo: bytes,
          plate: plate!,
          colonies: colonies(j['colonies']),
          spots: [for (final s in j['spots'] as List) Spot.fromJson(object(s))],
          zones: [
            for (final z in j['zones'] as List)
              AnnotatedZone(
                number(z[0]),
                number(z[1]),
                number(z[2]),
                z[3] == null ? double.nan : number(z[3]),
                z[4] as String,
                unsure: z[5] as bool,
              ),
          ],
          colourMode: ColourMode.values.byName(j['colour'] as String),
          header: strings(j['header']),
          rimFraction: number(j['rim']),
          maxSide: j['max_side'] as int,
        ),
      );
      return {'binary': result};
    case 'count':
      final p = j['params'] as List;
      final r = countPhoto(
        bytes,
        CountOptions(
          plate: plate,
          format: PlateFormat.byName(j['format'] as String),
          rimFraction: number(j['rim']),
          polarity: Polarity.values.byName(j['polarity'] as String),
          params: DetectParams(
            minDiameterMm: number(p[0]),
            kSigma: number(p[1]),
            minContrast: number(p[2]),
            peakSeparation: number(p[3]),
            spreaderFraction: number(p[4]),
          ),
        ),
      );
      return {
        'plate': r.plate.toJson(),
        'colonies': [for (final c in r.colonies) c.toJson()],
        'polarity': r.polarity.name,
        'coverage': r.coverage,
        'flags': r.flags,
        'width': r.imageWidth,
        'height': r.imageHeight,
      };
    case 'film':
      final r = countFilmJob(FilmJob(bytes, j['type'] as String, area: plate));
      return {...r.toJson(), 'width': r.imageWidth, 'height': r.imageHeight};
    case 'drop':
      final t = object(j['template']);
      final DropTemplate template = switch (t['type']) {
        'ring' => SectorTemplate(
          n: t['n'] as int,
          ringMm: number(t['ring']),
          dropsPerDilution: t['per'] as int,
        ),
        'grid' => GridTemplate(
          rows: t['rows'] as int,
          cols: t['cols'] as int,
          pitchMm: number(t['pitch']),
        ),
        _ => const FreeTemplate(),
      };
      final r = countDropPlateInPhoto((
        bytes,
        template,
        (j['dilutions'] as List).cast<int>(),
        number(j['volume']),
        PlateFormat.byName(j['format'] as String),
        plate,
      ));
      final f = r.fit;
      return {
        'plate': r.plate.toJson(),
        'colonies': [for (final c in r.colonies) c.toJson()],
        'drops': [
          for (final d in r.drops)
            {
              'x': d.x,
              'y': d.y,
              'r': d.radiusPx,
              'position': d.position,
              'dilution': d.dilutionExp,
              'replicate': d.replicate,
              'count': d.count,
              'confluent': d.confluent,
              'crowded': d.crowded,
              'colonies': d.colonies,
            },
        ],
        'strays': r.strays,
        'fit': f == null
            ? null
            : [f.rotationDeg, f.scale, f.cx, f.cy, f.matched, f.outside],
        'flags': r.flags,
        'width': r.imageWidth,
        'height': r.imageHeight,
      };
    case 'zones':
      final p = j['params'] as List;
      final r = measureZonesInPhoto((
        bytes,
        ZoneOptions(
          format: PlateFormat.byName(j['format'] as String),
          assay: ZoneAssay.values.byName(j['assay'] as String),
          diskMm: number(j['disk']),
          plate: plate,
          disks: j['disks'] == null
              ? null
              : [
                  for (final d in j['disks'] as List)
                    Disk(
                      number((d as List)[0]),
                      number(d[1]),
                      number(d[2]),
                      score: number(d[3]),
                      measured: d[4] as bool,
                    ),
                ],
          params: ZoneParams(
            edgeLevel: number(p[0]),
            persistMm: number(p[1]),
            startGapMm: number(p[2]),
            minContrast: number(p[3]),
            maxZoneMm: number(p[4]),
            hazyWidthMm: number(p[5]),
            scaleTolerance: number(p[6]),
          ),
        ),
      ));
      return {
        'plate': r.plate.toJson(),
        'assay': r.assay.name,
        'zones': [for (final z in r.zones) z.toJson()],
        'polarity': r.polarity,
        'ratio': r.diskScaleRatio,
        'flags': r.flags,
        'width': r.imageWidth,
        'height': r.imageHeight,
      };
    default:
      throw ArgumentError('Unknown photo job');
  }
}
