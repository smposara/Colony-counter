import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:colony_counter/data/zone_calibration_record.dart';
import 'package:colony_counter/data/zone_record.dart';
import 'package:colony_counter/l10n/l10n.dart';
import 'package:colony_counter/ui/zone_calibration_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';
import 'zones_helpers.dart';

/// What a calliper reads on the plate in zones_reflected.jpg: the true sizes
/// from its .json, to 0.1 mm, give or take a little.
({double span, List<double> zones}) _calliper(ZoneRecord r) {
  final j = jsonDecode(
    File('test/fixtures/zones_reflected.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final mmPerPx =
      (j['plate_mm'] as num) / 2 / ((j['plate'] as Map)['radius'] as num);
  final disk = (j['disk_mm'] as num).toDouble();
  final truth = [
    for (final t in j['true'] as List)
      (
        x: (t['x'] as num).toDouble(),
        y: (t['y'] as num).toDouble(),
        mm: (t['diameter_mm'] as num).toDouble(),
      ),
  ];
  // The true disk nearest each of the app's marks.
  final near = [
    for (final m in r.marks)
      truth.reduce(
        (a, b) =>
            math.pow(a.x - m.x, 2) + math.pow(a.y - m.y, 2) <
                math.pow(b.x - m.x, 2) + math.pow(b.y - m.y, 2)
            ? a
            : b,
      ),
  ];
  const wobble = [0.2, -0.1, 0.1, -0.2, 0.0, 0.1];
  final (a, b) = spanPair(r)!;
  final span =
      math.sqrt(
            math.pow(near[a].x - near[b].x, 2) +
                math.pow(near[a].y - near[b].y, 2),
          ) *
          mmPerPx +
      disk;
  return (
    span: span + 0.1,
    zones: [
      for (var i = 0; i < near.length; i++)
        near[i].mm + wobble[i % wobble.length],
    ],
  );
}

String _mm(double v) => v.toStringAsFixed(1);

/// The setup sheet, then the photo, then the review screen.
Future<void> _photograph(Manual m) async {
  nextPhoto = fixture('zones_reflected.jpg');
  await m.tap(find.text(tr.zoneTakePhoto));
}

void main() {
  chapter('calibration', (m) async {
    await m.start(seed: (store) => store.acceptZoneDisclaimer());
    await m.tap(find.text(tr.homeZones).last);

    // Where to start.
    await snap(m, '1-zones', [
      (find.byIcon(Icons.more_vert), Mark.tap),
      (find.text(tr.calCalibrate), Mark.tap),
    ]);
    await m.tap(find.byIcon(Icons.more_vert));
    await snap(m, '2-menu', [(find.text(tr.calMenu), Mark.tap)]);
    await m.tap(find.text(tr.calMenu));
    await snap(m, '3-none', [(find.text(tr.calNew), Mark.tap)]);
    await m.tap(find.text(tr.calNew));

    // What you need.
    await snap(m, '4-intro', [
      (find.text(tr.calNeedTool), Mark.look),
      (find.text(tr.calNeedPlate), Mark.look),
      (find.byWidgetPredicate((w) => w is SegmentedButton).first, Mark.look),
    ]);
    await m.show(find.text(tr.calUseRecent));
    await snap(m, '5-start', [
      (find.byWidgetPredicate((w) => w is SegmentedButton).last, Mark.look),
      (find.text(tr.calPhotograph), Mark.tap),
      (find.text(tr.calUseRecent), Mark.tap),
    ]);

    // Photograph the used plate and save it.
    await m.tap(find.text(tr.calPhotograph));
    await m.enter(
      find.byType(TextField).at(2),
      m.t('Calliper check', 'ตรวจกับเวอร์เนียร์'),
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await m.settle();
    await m.show(find.text(tr.zoneTakePhoto));
    await snap(m, '6-photo', [(find.text(tr.zoneTakePhoto), Mark.tap)]);
    await _photograph(m);
    await snap(m, '7-check', [
      (find.byKey(const ValueKey('zonePhoto')), Mark.look),
      (find.text(tr.reviewSavePlate), Mark.tap),
    ]);
    await m.tap(find.text(tr.reviewSavePlate));
    await m.settle(
      until: () => find.text(tr.calSpanTitle).evaluate().isNotEmpty,
    );

    // Your readings: the span, then each zone.
    final r = m.store.zoneRecords.first;
    final read = _calliper(r);
    final numbers = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is CalibrationNumbersPainter,
    );
    await m.enter(find.byKey(const ValueKey('calSpan')), _mm(read.span));
    await m.show(find.text(tr.calReadingsHelp));
    await snap(m, '8-span', [
      (numbers, Mark.look),
      (find.text(tr.calReadingsHelp), Mark.look),
      (find.byKey(const ValueKey('calSpan')), Mark.type),
    ]);
    for (var i = 0; i < r.marks.length; i++) {
      final box = find.byKey(ValueKey('calInclude$i'));
      if (m.tester.widget<Checkbox>(box).value != true) {
        await m.tap(box);
      }
      await m.enter(find.byKey(ValueKey('calZone$i')), _mm(read.zones[i]));
    }
    // Back to zone 2, to show it lit up on the photo.
    await m.enter(find.byKey(const ValueKey('calZone1')), _mm(read.zones[1]));
    await m.show(find.byKey(const ValueKey('calZone1')));
    await snap(m, '9-zones', [
      (numbers, Mark.look),
      (find.byKey(const ValueKey('calZone1')), Mark.type),
      (find.byTooltip(tr.calNotRound).at(1), Mark.tap),
    ]);
    await m.show(find.byKey(const ValueKey('calInclude0')));
    await snap(m, '10-tick', [
      (find.byKey(const ValueKey('calInclude0')), Mark.tap),
      (find.text(tr.calDoubtful), Mark.look),
    ]);
    FocusManager.instance.primaryFocus?.unfocus();
    await m.settle();
    await m.show(find.byKey(const ValueKey('calSeeResult')));
    await snap(m, '11-see', [
      (find.byKey(const ValueKey('calSeeResult')), Mark.tap),
    ]);
    await m.tap(find.byKey(const ValueKey('calSeeResult')));

    // The result.
    await snap(m, '12-result', [
      (find.byKey(const ValueKey('calVerdict')), Mark.look),
      (
        find.textContaining(tr.calStats('', '', '', 0).split(' ').first).first,
        Mark.look,
      ),
      (
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is AgreementPlotPainter,
        ),
        Mark.look,
      ),
    ]);
    await m.show(find.byKey(const ValueKey('calSave')));
    await snap(m, '13-save', [
      (find.byType(Table), Mark.look),
      (find.byKey(const ValueKey('calSave')), Mark.tap),
      (find.text(tr.calAddPlate), Mark.tap),
    ]);
    await m.tap(find.byKey(const ValueKey('calSave')));
    await m.settle(until: () => m.store.calibrations.isNotEmpty);

    // The list of calibrations.
    await snap(m, '14-list', [
      (find.byType(Card), Mark.look),
      (find.byKey(const ValueKey('calGate')), Mark.look),
      (find.byTooltip(tr.calShareData), Mark.tap),
    ]);
    await m.back();
    await snap(m, '15-banner', [
      (find.byKey(const ValueKey('calBanner')), Mark.look),
      (find.text(m.t('Calliper check', 'ตรวจกับเวอร์เนียร์')), Mark.look),
    ]);

    // A plate measured afterwards shows its calibration.
    await m.tap(find.text(tr.zonesMeasure));
    await m.enter(
      find.byType(TextField).at(2),
      m.t('Plant extracts', 'สารสกัดสมุนไพร'),
    );
    // A new experiment: replicate 1.
    await m.tap(find.byIcon(Icons.remove));
    FocusManager.instance.primaryFocus?.unfocus();
    await m.settle();
    await m.show(find.text(tr.zoneTakePhoto));
    await _photograph(m);
    await snap(m, '16-chip', [
      (find.byKey(const ValueKey('calChip')), Mark.tap),
    ]);
    await m.tap(find.text(tr.reviewSavePlate));

    // 90 days later.
    final p = m.store.calibrations.single;
    await m.tester.runAsync(
      () => m.store.upsertCalibration(
        p.copyWith(
          updatedAt: DateTime.now().subtract(const Duration(days: 100)),
        ),
      ),
    );
    await m.settle();
    await snap(m, '17-old', [
      (find.text(tr.calBannerOld), Mark.look),
      (find.text(tr.calCalibrate), Mark.tap),
    ]);
    await m.tap(find.text(tr.zonesMeasure));
    await snap(m, '18-again', [
      (find.text(tr.calAgainTitle), Mark.look),
      (find.text(tr.calNow), Mark.tap),
    ]);
    await m.tap(find.text(tr.calLater));
    await m.show(find.text(tr.zoneTakePhoto));
    await _photograph(m);
    await snap(m, '19-reason', [
      (find.byKey(const ValueKey('calChip')), Mark.look),
      (find.text(tr.calReasonOld), Mark.look),
    ]);
  });
}
