import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/timelapse.dart';
import '../data/plate_record.dart';
import '../data/plate_store.dart';
import '../data/timelapse_data.dart';
import 'chart_colours.dart';
import 'format.dart';
import 'photo_flow.dart';
import 'review_screen.dart';

String _h(double h) => '${fixed(h, h % 1 == 0 ? 0 : 1)} h';

/// Photos of one plate over time: count growth, when colonies appeared and
/// how fast they grow.
class TimelapseScreen extends StatelessWidget {
  const TimelapseScreen({
    super.key,
    required this.store,
    required this.seriesId,
  });

  final PlateStore store;
  final String seriesId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final photos = seriesPhotos(store, seriesId);
        if (photos.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Time-lapse')),
            body: const Center(child: Text('No photos in this series.')),
          );
        }
        final res = analyseSeries(photos);
        final t = Theme.of(context).textTheme;
        final timesKnown = photos.every((p) => p.incubationH != null);
        // Photos in the order of res.frames (sorted by time).
        final ordered = [
          for (final f in res.frames)
            photos.firstWhere((p) => identical(p.plate, f.plate)),
        ];
        final latest = ordered.last;
        final appearedLater = res.tracks
            .where((tr) => tr.appearedH > res.frames.first.hours)
            .length;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Time-lapse'),
            actions: [
              IconButton(
                tooltip: 'Share colony table (CSV)',
                icon: const Icon(Icons.ios_share),
                onPressed: () => shareBytes(
                  Uint8List.fromList(utf8.encode(timelapseCsv(res))),
                  'timelapse_${latest.sampleId.isEmpty ? latest.id : latest.sampleId}.csv',
                  'text/csv',
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () =>
                countNewPlate(context, store, laterPhotoOf: latest),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Add a later photo'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              Text(plateLabel(latest), style: t.titleMedium),
              Text(
                '${photos.length} photo${photos.length == 1 ? '' : 's'} · '
                '${timesKnown ? 'hours since plating' : 'hours since the first photo'}',
                style: t.bodySmall,
              ),
              const SizedBox(height: 12),
              Card.filled(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${res.tracks.length} colonies at ${_h(res.frames.last.hours)}',
                        style: t.headlineSmall,
                      ),
                      const SizedBox(height: 4),
                      if (res.frames.length > 1) ...[
                        Text(
                          '$appearedLater appeared after the first photo · '
                          'half had appeared by ${_h(res.medianAppearanceH!)}',
                          style: t.bodyMedium,
                        ),
                        if (res.medianGrowthMmPerH != null)
                          Text(
                            'Median growth ${fixed(res.medianGrowthMmPerH!, 3)} mm/h '
                            'in diameter',
                            style: t.bodyMedium,
                          ),
                      ] else
                        Text(
                          'Add a later photo of the same plate to see when '
                          'colonies appear and how fast they grow.',
                          style: t.bodyMedium,
                        ),
                    ],
                  ),
                ),
              ),
              if (res.frames.length > 1) ...[
                const SizedBox(height: 16),
                _CountChart(res: res),
              ],
              const SizedBox(height: 16),
              _Table(res: res, photos: ordered, store: store),
              const SizedBox(height: 16),
              if (res.frames.length > 1)
                _AppearanceMap(store: store, latest: latest, res: res),
              const SizedBox(height: 8),
              Text(
                'Colonies are matched between photos by position, after '
                'turning and mirroring the earlier photo to fit the later one. '
                'Put the plate the same way up each time if few colonies are '
                'visible early on.',
                style: t.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Colonies counted in each photo over time (one series).
class _CountChart extends StatelessWidget {
  const _CountChart({required this.res});

  final TimelapseResult res;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Colonies counted over time', style: t.titleMedium),
            const SizedBox(height: 8),
            AspectRatio(
              aspectRatio: 1.8,
              child: CustomPaint(
                painter: _LinePainter(
                  points: [
                    for (final f in res.frames)
                      (
                        f.hours,
                        f.colonies.fold(0, (s, c) => s + c.n).toDouble(),
                      ),
                  ],
                  colour: seriesColour(context, 0),
                  ink: cs.onSurfaceVariant,
                  grid: cs.outlineVariant.withValues(alpha: 0.5),
                  surface: cs.surfaceContainerLow,
                  labelStyle: t.labelSmall!.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.points,
    required this.colour,
    required this.ink,
    required this.grid,
    required this.surface,
    required this.labelStyle,
  });

  final List<(double, double)> points;
  final Color colour, ink, grid, surface;
  final TextStyle labelStyle;

  static const _left = 36.0, _bottom = 22.0, _top = 8.0, _right = 12.0;

  void _text(Canvas c, String s, Offset at, {bool right = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, at + Offset(right ? -tp.width : -tp.width / 2, -tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final xMax = math.max(1.0, points.map((p) => p.$1).reduce(math.max));
    final yRaw = math.max(5.0, points.map((p) => p.$2).reduce(math.max));
    final yStep = [
      1,
      2,
      5,
      10,
      20,
      25,
      50,
      100,
      200,
      250,
      500,
      1000,
    ].firstWhere((s) => yRaw / s <= 5, orElse: () => 2000).toDouble();
    final yMax = (yRaw / yStep).ceil() * yStep;
    Offset pos(double x, double y) => Offset(
      _left + x / xMax * (size.width - _left - _right),
      _top + (1 - y / yMax) * (size.height - _top - _bottom),
    );
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var y = 0.0; y <= yMax + 1e-9; y += yStep) {
      canvas.drawLine(pos(0, y), pos(xMax, y), gridPaint);
      _text(
        canvas,
        y.toStringAsFixed(0),
        pos(0, y) - const Offset(6, 0),
        right: true,
      );
    }
    for (final p in points) {
      _text(canvas, _h(p.$1), pos(p.$1, 0) + const Offset(0, 11));
    }
    canvas.drawLine(
      pos(0, 0),
      pos(xMax, 0),
      Paint()
        ..color = ink
        ..strokeWidth = 1,
    );
    final pts = [for (final p in points) pos(p.$1, p.$2)];
    canvas.drawPath(
      Path()..addPolygon(pts, false),
      Paint()
        ..color = colour
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    for (var i = 0; i < pts.length; i++) {
      canvas.drawCircle(pts[i], 5.5, Paint()..color = surface);
      canvas.drawCircle(pts[i], 4, Paint()..color = colour);
    }
    // Direct label on the last point only.
    _text(
      canvas,
      points.last.$2.toStringAsFixed(0),
      pts.last - const Offset(0, 14),
    );
  }

  @override
  bool shouldRepaint(_LinePainter old) => true;
}

class _Table extends StatelessWidget {
  const _Table({required this.res, required this.photos, required this.store});

  final TimelapseResult res;
  final List<PlateRecord> photos;
  final PlateStore store;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final fresh = res.newPerFrame;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Photos', style: t.titleMedium),
        for (var i = 0; i < photos.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              child: Text('${i + 1}', style: t.labelMedium),
            ),
            title: Text(
              '${_h(res.frames[i].hours)} · ${photos[i].count} colonies',
            ),
            subtitle: Text(
              [
                if (res.frames.length > 1) '${fresh[i]} first seen here',
                if (i < res.alignments.length &&
                    res.alignments[i].angle.abs() > 0.05)
                  'turned ${(res.alignments[i].angle * 180 / math.pi).round()}°'
                      '${res.alignments[i].mirrored ? ', mirrored' : ''} to fit the next',
                shortDate(photos[i].createdAt),
              ].join(' · '),
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ReviewScreen(store: store, record: photos[i]),
              ),
            ),
          ),
      ],
    );
  }
}

/// The last photo with each colony coloured by the photo it first appeared in.
class _AppearanceMap extends StatefulWidget {
  const _AppearanceMap({
    required this.store,
    required this.latest,
    required this.res,
  });

  final PlateStore store;
  final PlateRecord latest;
  final TimelapseResult res;

  @override
  State<_AppearanceMap> createState() => _AppearanceMapState();
}

class _AppearanceMapState extends State<_AppearanceMap> {
  late final Future<Uint8List?> _photo = widget.store.readPhoto(widget.latest);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final res = widget.res;
    final hours = [for (final f in res.frames) f.hours];
    // At most 8 categorical colours; later photos share the last one.
    final colours = [
      for (var i = 0; i < hours.length; i++)
        seriesColour(context, math.min(i, 7)),
    ];
    final r = widget.latest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('When each colony appeared', style: t.titleMedium),
        const SizedBox(height: 4),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (var i = 0; i < hours.length; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: colours[i], width: 2.5),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('by ${_h(hours[i])}', style: t.bodySmall),
                ],
              ),
          ],
        ),
        const SizedBox(height: 8),
        FutureBuilder<Uint8List?>(
          future: _photo,
          builder: (context, snap) {
            final bytes = snap.data;
            if (bytes == null) return const SizedBox(height: 200);
            return AspectRatio(
              aspectRatio: r.imageWidth / r.imageHeight,
              child: FittedBox(
                child: SizedBox(
                  width: r.imageWidth.toDouble(),
                  height: r.imageHeight.toDouble(),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(bytes, fit: BoxFit.fill),
                      CustomPaint(
                        painter: _AppearancePainter(
                          frame: res.frames.last,
                          tracks: res.tracks,
                          hours: hours,
                          colours: colours,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _AppearancePainter extends CustomPainter {
  _AppearancePainter({
    required this.frame,
    required this.tracks,
    required this.hours,
    required this.colours,
  });

  final TimelapseFrame frame;
  final List<ColonyTrack> tracks;
  final List<double> hours;
  final List<Color> colours;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width / 250;
    for (final tr in tracks) {
      final (x, y) = frame.toImage(tr.x, tr.y);
      final d = tr.sizes.last.$2 / frame.plate.mmPerPx;
      final i = hours.indexOf(tr.appearedH);
      canvas.drawCircle(
        Offset(x, y),
        math.max(d * 0.65, w * 3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w
          ..color = colours[i < 0 ? 0 : i],
      );
    }
  }

  @override
  bool shouldRepaint(_AppearancePainter old) => true;
}
