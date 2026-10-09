import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/zone_calibration.dart';
import '../core/zones.dart';
import '../data/plate_store.dart';
import '../data/zone_calibration_record.dart';
import '../data/zone_record.dart';
import '../l10n/l10n.dart';
import 'chart_colours.dart';
import 'format.dart';
import 'insets.dart';
import 'zones_tab.dart';

/// Calibration of zone measurement against the user's own calliper (or ruler)
/// on a used zone plate. Check only: it never changes a measurement. See
/// docs/ZONE_CALIBRATION_IMPLEMENTATION.md.

/// Opens the list of calibrations, or straight into a new one ([wizard]).
Future<void> openZoneCalibration(
  BuildContext context,
  PlateStore store, {
  bool wizard = false,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => wizard
        ? ZoneCalibrationWizard(store: store)
        : ZoneCalibrationScreen(store: store),
  ),
);

String _platform() => kIsWeb
    ? 'web'
    : switch (defaultTargetPlatform) {
        TargetPlatform.iOS => 'ios',
        TargetPlatform.android => 'android',
        final p => p.name,
      };

String _mm(double v) => v.toStringAsFixed(1);
String _signed(double v) =>
    '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(1)}';

double? _parseMm(String s) {
  final t = s.trim().replaceAll(',', '.');
  return t.isEmpty ? null : double.tryParse(t);
}

String verdictText(CalibrationVerdict v) => switch (v) {
  CalibrationVerdict.good => tr.calVerdictGood,
  CalibrationVerdict.usable => tr.calVerdictUsable,
  CalibrationVerdict.poor => tr.calVerdictPoor,
  CalibrationVerdict.tooFew => tr.calVerdictTooFew,
};

String verdictShort(CalibrationVerdict v) => switch (v) {
  CalibrationVerdict.good => tr.calShortGood,
  CalibrationVerdict.usable => tr.calShortUsable,
  CalibrationVerdict.poor => tr.calShortPoor,
  CalibrationVerdict.tooFew => tr.calShortTooFew,
};

/// The calibration chip's text for a zone plate.
String calibrationChipText(
  ZoneRecord r,
  CalibrationStatus status,
  CalibrationProfile? profile,
) {
  if (r.usedForCalibration) return tr.calChipPlate;
  return switch (status) {
    CalibrationStatus.calibrated when profile != null => () {
      final s = profile.summary;
      return tr.calChipCalibrated(
        verdictShort(s.verdict),
        s.bias.isFinite ? _signed(s.bias) : '–',
      );
    }(),
    CalibrationStatus.uncalibrated => tr.calChipNone,
    _ => tr.calChipAgain,
  };
}

/// Lines to show on a zone plate about its calibration: why to calibrate
/// again, and a scale that disagrees with the calibrated one.
List<String> calibrationNotes(
  ZoneRecord r,
  CalibrationStatus status,
  CalibrationProfile? profile,
) {
  if (r.usedForCalibration) return const [];
  final notes = <String>[
    if (status == CalibrationStatus.old) tr.calReasonOld,
    if (status == CalibrationStatus.otherCamera) tr.calReasonCamera,
    if (status == CalibrationStatus.setupChanged) tr.calReasonSetup,
  ];
  final d = scaleAgainstCalibration(r, status, profile);
  if (d != null && d.abs() > kScaleDisagree) {
    final pct = (d.abs() * 100).toStringAsFixed(0);
    notes.add(
      '${d < 0 ? tr.calScaleSmall(pct) : tr.calScaleLarge(pct)} '
      '${r.assay == ZoneAssay.well ? tr.calScaleWellsHint : tr.calScaleDisksHint}',
    );
  }
  return notes;
}

/// The calibration line of a shared zone photo (the image fonts are ASCII only,
/// so it is in English like the rest of the banner).
String calibrationBannerLine(
  ZoneRecord r,
  CalibrationStatus status,
  CalibrationProfile? profile,
) {
  if (r.usedForCalibration) return 'Calibration plate (calliper readings)';
  return switch (status) {
    CalibrationStatus.calibrated when profile != null => () {
      final s = profile.summary;
      final v = switch (s.verdict) {
        CalibrationVerdict.good => 'good',
        CalibrationVerdict.usable => 'usable',
        CalibrationVerdict.poor => 'not good enough',
        CalibrationVerdict.tooFew => 'too few zones',
      };
      return 'Calibrated against a calliper: $v, bias '
          '${s.bias.isFinite ? s.bias.toStringAsFixed(1) : '-'} mm '
          '(${shortDate(profile.updatedAt)})';
    }(),
    CalibrationStatus.uncalibrated => 'Not calibrated against a calliper',
    CalibrationStatus.old => 'Calibration more than 90 days old',
    CalibrationStatus.otherCamera => 'Calibrated for another camera',
    CalibrationStatus.setupChanged => 'Calibrated at another stand height',
    CalibrationStatus.calibrated => 'Not calibrated against a calliper',
  };
}

String profileTitle(CalibrationProfile p) => p.name.isNotEmpty
    ? p.name
    : '${p.setup == CalibrationSetup.stand ? tr.calSetupStand : tr.calSetupHandheld}'
          ' · ${shortDate(p.updatedAt)}';

/// Saved calibrations, newest first.
class ZoneCalibrationScreen extends StatelessWidget {
  const ZoneCalibrationScreen({super.key, required this.store});

  final PlateStore store;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr.calTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ZoneCalibrationWizard(store: store),
          ),
        ),
        icon: const Icon(Icons.straighten),
        label: Text(tr.calNew),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final list = store.calibrations;
          final t = Theme.of(context).textTheme;
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  tr.calNone,
                  textAlign: TextAlign.center,
                  style: t.bodyLarge,
                ),
              ),
            );
          }
          return ListView(
            padding: scrollPadding(
              context,
              const EdgeInsets.fromLTRB(16, 8, 16, 96),
            ),
            children: [
              for (final p in list) _ProfileCard(store: store, profile: p),
            ],
          );
        },
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.store, required this.profile});

  final PlateStore store;
  final CalibrationProfile profile;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = profile.summary;
    final old = profile.isOld(DateTime.now());
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(profileTitle(profile), style: t.titleMedium),
            const SizedBox(height: 4),
            Text(
              old ? tr.calOld : verdictText(s.verdict),
              style: t.bodyMedium?.copyWith(
                color: old || s.verdict != CalibrationVerdict.good
                    ? Theme.of(context).colorScheme.tertiary
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
            if (s.n > 0)
              Text(
                tr.calStats(
                  _signed(s.bias),
                  _signed(s.loaLow),
                  _signed(s.loaHigh),
                  s.n,
                ),
                style: t.bodySmall,
              ),
            Text(
              tr.calPlatesTool(
                profile.plates.length,
                profile.tool == CalibrationTool.ruler
                    ? tr.calToolRuler
                    : tr.calToolCalliper,
              ),
              style: t.bodySmall,
            ),
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ZoneCalibrationWizard(
                            store: store,
                            profile: profile,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.add),
                      label: Text(
                        tr.calAddPlate,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: tr.homeDelete,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(tr.calDeleteTitle),
                        content: Text(tr.calDeleteBody),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(tr.homeCancel),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: Text(tr.homeDelete),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) await store.deleteCalibration(profile);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _Step { intro, readings, result }

/// The calibration wizard: what you need → photograph and check a used plate →
/// measure the span and the zones → result. With [profile], adds a plate to it.
class ZoneCalibrationWizard extends StatefulWidget {
  const ZoneCalibrationWizard({super.key, required this.store, this.profile});

  final PlateStore store;
  final CalibrationProfile? profile;

  @override
  State<ZoneCalibrationWizard> createState() => _ZoneCalibrationWizardState();
}

class _ZoneCalibrationWizardState extends State<ZoneCalibrationWizard> {
  PlateStore get store => widget.store;
  _Step _step = _Step.intro;
  late CalibrationTool _tool = widget.profile?.tool ?? CalibrationTool.calliper;
  late CalibrationSetup _setup =
      widget.profile?.setup ?? CalibrationSetup.stand;

  /// Plates measured in this run, with their readings, saved together.
  final List<ZoneRecord> _done = [];
  late CalibrationProfile? _draft = widget.profile;

  /// The plate being measured now.
  ZoneRecord? _plate;
  Uint8List? _photo;
  bool _busy = false;

  bool get _dirty => _done.isNotEmpty || _plate != null;

  /// A fresh profile for the camera and setup of [r].
  CalibrationProfile _newProfile(ZoneRecord r) {
    final now = DateTime.now();
    return CalibrationProfile(
      id: 'cal_${now.millisecondsSinceEpoch}',
      createdAt: now,
      updatedAt: now,
      cameraName: r.camera,
      imageWidth: r.imageWidth,
      imageHeight: r.imageHeight,
      platform: _platform(),
      setup: _setup,
      rimRadiusPx: r.plate.radius,
      tool: _tool,
      plates: const [],
    );
  }

  Future<void> _use(ZoneRecord? r) async {
    if (r == null || !mounted) return;
    final d = _draft;
    if (d != null &&
        (!d.sameCamera(r.camera, r.imageWidth, r.imageHeight) ||
            !d.sameSetup(r.plate.radius))) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr.calOtherSetup)));
      return;
    }
    setState(() => _busy = true);
    final bytes = await store.readPhotoPath(r.imagePath);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _plate = r;
      _photo = bytes;
      _step = _Step.readings;
    });
  }

  Future<void> _photograph() async =>
      _use(await photographZonePlate(context, store, forCalibration: true));

  Future<void> _pickRecent() async {
    final since = DateTime.now().subtract(const Duration(days: 1));
    final recent = [
      for (final r in store.zoneRecords)
        if (r.createdAt.isAfter(since) && !_done.any((d) => d.id == r.id)) r,
    ];
    if (recent.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr.calNoRecent)));
      return;
    }
    final r = await showDialog<ZoneRecord>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(tr.calUseRecent),
        children: [
          for (final r in recent)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, r),
              child: Text(
                '${r.experiment.isEmpty ? tr.zoneSetupTitle : r.experiment}'
                ' · ${tr.zoneNZones(r.marks.length)}'
                ' · ${shortDate(r.createdAt)}',
              ),
            ),
        ],
      ),
    );
    await _use(r);
  }

  void _onReadings(ZoneRecord measured, double span, Set<int> excluded) {
    final plate = CalibrationPlate.fromRecord(
      measured,
      userSpanMm: span,
      excluded: excluded,
    );
    setState(() {
      _done.removeWhere((r) => r.id == measured.id);
      _done.add(measured);
      _draft = (_draft ?? _newProfile(measured)).withPlate(plate);
      _plate = null;
      _photo = null;
      _step = _Step.result;
    });
  }

  Future<void> _save() async {
    final d = _draft;
    if (d == null) return;
    setState(() => _busy = true);
    for (final r in _done) {
      await store.upsertZone(
        r.copyWith(usedForCalibration: true, calibrationId: d.id),
      );
    }
    await store.upsertCalibration(d);
    if (!mounted) return;
    _done.clear();
    Navigator.of(context).pop();
  }

  void _tryAgain() => setState(() {
    // Drop the last plate measured in this run.
    if (_done.isNotEmpty) {
      final last = _done.removeLast();
      final d = _draft!;
      final left = d.plates.where((p) => p.zoneRecordId != last.id).toList();
      _draft = left.isEmpty && widget.profile == null
          ? null
          : d.copyWith(plates: left);
    }
    _step = _Step.intro;
  });

  Future<bool> _confirmLeave() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr.calLeaveTitle),
          content: Text(tr.calLeaveBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr.reviewKeep),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr.reviewDiscard),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final body = switch (_step) {
      _Step.intro => _intro(context),
      _Step.readings => _ReadingsStep(
        key: ValueKey(_plate!.id),
        record: _plate!,
        photo: _photo,
        tool: _tool,
        onDone: _onReadings,
      ),
      _Step.result => _ResultStep(
        profile: _draft!,
        onSave: _busy ? null : _save,
        onAddPlate: () => setState(() => _step = _Step.intro),
        onTryAgain: _tryAgain,
      ),
    };
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_step == _Step.readings) {
          setState(() {
            _plate = null;
            _step = _done.isEmpty ? _Step.intro : _Step.result;
          });
          return;
        }
        if (await _confirmLeave() && context.mounted) {
          _done.clear();
          _plate = null;
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(tr.calTitle)),
        body: Stack(
          children: [
            Positioned.fill(child: body),
            if (_busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x66000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _intro(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final adding = _draft != null;
    return SingleChildScrollView(
      padding: scrollPadding(context, const EdgeInsets.fromLTRB(16, 8, 16, 24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            adding ? tr.calAddPlateTitle : tr.calIntroTitle,
            style: t.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(tr.calIntro, style: t.bodyMedium),
          const SizedBox(height: 12),
          _Bullet(Icons.straighten, tr.calNeedTool),
          _Bullet(Icons.science_outlined, tr.calNeedPlate),
          _Bullet(Icons.camera_alt_outlined, tr.calNeedSetup),
          _Bullet(Icons.health_and_safety_outlined, tr.calBiosafety),
          const SizedBox(height: 16),
          if (!adding) ...[
            Text(tr.calToolQuestion, style: t.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<CalibrationTool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: CalibrationTool.calliper,
                  label: Text(tr.calToolCalliper),
                ),
                ButtonSegment(
                  value: CalibrationTool.ruler,
                  label: Text(tr.calToolRuler),
                ),
              ],
              selected: {_tool},
              onSelectionChanged: (v) => setState(() => _tool = v.first),
            ),
            const SizedBox(height: 4),
            Text(
              tr.calMinZones(CalibrationLimits.of(_tool).minZones),
              style: t.bodySmall,
            ),
            const SizedBox(height: 16),
            Text(tr.calSetupQuestion, style: t.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<CalibrationSetup>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: CalibrationSetup.stand,
                  label: Text(tr.calSetupStand),
                ),
                ButtonSegment(
                  value: CalibrationSetup.handheld,
                  label: Text(tr.calSetupHandheld),
                ),
              ],
              selected: {_setup},
              onSelectionChanged: (v) => setState(() => _setup = v.first),
            ),
            const SizedBox(height: 24),
          ],
          FilledButton.icon(
            onPressed: _busy ? null : _photograph,
            icon: const Icon(Icons.camera_alt_outlined),
            label: Text(tr.calPhotograph),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickRecent,
            icon: const Icon(Icons.history),
            label: Text(tr.calUseRecent),
          ),
          if (_done.isNotEmpty) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _step = _Step.result),
              child: Text(tr.calBackToResult),
            ),
          ],
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

/// The span and each zone's reading. The app's diameters are not shown, so the
/// readings are the user's own.
class _ReadingsStep extends StatefulWidget {
  const _ReadingsStep({
    super.key,
    required this.record,
    required this.photo,
    required this.tool,
    required this.onDone,
  });

  final ZoneRecord record;
  final Uint8List? photo;
  final CalibrationTool tool;
  final void Function(ZoneRecord measured, double span, Set<int> excluded)
  onDone;

  @override
  State<_ReadingsStep> createState() => _ReadingsStepState();
}

class _ReadingsStepState extends State<_ReadingsStep> {
  ZoneRecord get r => widget.record;
  late final (int, int)? _pair = spanPair(r);
  final _span = TextEditingController();
  late final List<TextEditingController> _a = [
    for (final m in r.marks)
      TextEditingController(
        text: m.calliperMm.isEmpty ? '' : _mm(m.calliperMm.first),
      ),
  ];
  late final List<TextEditingController> _b = [
    for (final m in r.marks)
      TextEditingController(
        text: m.calliperMm.length < 2 ? '' : _mm(m.calliperMm[1]),
      ),
  ];
  late final List<bool> _second = [
    for (final m in r.marks) m.calliperMm.length > 1,
  ];
  late final List<bool> _include = [
    for (final m in r.marks) !doubtfulForCalibration(m),
  ];
  late final List<FocusNode> _focus = [for (final _ in r.marks) FocusNode()];
  final _spanFocus = FocusNode();

  /// Highlighted on the photo: a zone, or -1 for the span.
  int? _focused;

  @override
  void initState() {
    super.initState();
    _spanFocus.addListener(() {
      if (_spanFocus.hasFocus) setState(() => _focused = -1);
    });
    for (var i = 0; i < _focus.length; i++) {
      _focus[i].addListener(() {
        if (_focus[i].hasFocus) setState(() => _focused = i);
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_span, ..._a, ..._b]) {
      c.dispose();
    }
    for (final f in [_spanFocus, ..._focus]) {
      f.dispose();
    }
    super.dispose();
  }

  List<double> _readings(int i) => [
    for (final c in [_a[i], if (_second[i]) _b[i]]) ?_parseMm(c.text),
  ];

  Future<void> _done() async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String s) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s)));
    final span = _parseMm(_span.text);
    if (_pair != null && (span == null || span < 20 || span > 90)) {
      say(tr.calSpanInvalid);
      _spanFocus.requestFocus();
      return;
    }
    for (var i = 0; i < r.marks.length; i++) {
      for (final v in _readings(i)) {
        if (v < 2 || v > 90) {
          say(tr.calReadingInvalid(i + 1));
          _focus[i].requestFocus();
          return;
        }
      }
    }
    final measured = [
      for (var i = 0; i < r.marks.length; i++)
        if (_include[i] && _readings(i).isNotEmpty) i,
    ];
    final need = CalibrationLimits.of(widget.tool).minZones;
    if (measured.length < need) {
      say(tr.calNeedZones(need, measured.length));
      return;
    }
    // A reading far from the app's is often typed into the wrong zone.
    final far = [
      for (final i in measured)
        if ((_mean(_readings(i)) - r.marks[i].reportedMm(r.diskMm)).abs() > 3)
          i + 1,
    ];
    if (far.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr.calCheckTitle),
          content: Text(tr.calCheckBody(far.join(', '))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr.calCheckFix),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr.calCheckOk),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    final marks = [
      for (var i = 0; i < r.marks.length; i++)
        r.marks[i].copyWith(calliperMm: _readings(i)),
    ];
    widget.onDone(r.copyWith(marks: marks), span ?? 0, {
      for (var i = 0; i < r.marks.length; i++)
        if (!_include[i]) i,
    });
  }

  static double _mean(List<double> v) => v.reduce((a, b) => a + b) / v.length;

  InputDecoration _dec(String label) => InputDecoration(
    labelText: label,
    suffixText: 'mm',
    isDense: true,
    border: const OutlineInputBorder(),
  );

  static final _numbers = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final pair = _pair;
    return Column(
      children: [
        SizedBox(
          height: 260,
          child: ColoredBox(
            color: Colors.black,
            child: widget.photo == null
                ? const SizedBox.expand()
                : FittedBox(
                    child: SizedBox(
                      width: r.imageWidth.toDouble(),
                      height: r.imageHeight.toDouble(),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(widget.photo!, fit: BoxFit.fill),
                          CustomPaint(
                            painter: CalibrationNumbersPainter(
                              record: r,
                              focused: _focused,
                              pair: pair,
                              included: _include,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: scrollPadding(
              context,
              const EdgeInsets.fromLTRB(16, 12, 16, 24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr.calReadingsHelp, style: t.bodySmall),
                const SizedBox(height: 12),
                if (pair != null) ...[
                  Text(tr.calSpanTitle, style: t.titleSmall),
                  Text(
                    tr.calSpanHelp(pair.$1 + 1, pair.$2 + 1),
                    style: t.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const ValueKey('calSpan'),
                    controller: _span,
                    focusNode: _spanFocus,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: _numbers,
                    textInputAction: TextInputAction.next,
                    decoration: _dec(tr.calSpanLabel),
                  ),
                  const SizedBox(height: 16),
                ],
                Text(tr.calZonesTitle, style: t.titleSmall),
                const SizedBox(height: 8),
                for (var i = 0; i < r.marks.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 40,
                          child: Checkbox(
                            key: ValueKey('calInclude$i'),
                            value: _include[i],
                            onChanged: (v) =>
                                setState(() => _include[i] = v ?? false),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                key: ValueKey('calZone$i'),
                                controller: _a[i],
                                focusNode: _focus[i],
                                enabled: _include[i],
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: _numbers,
                                textInputAction: i == r.marks.length - 1
                                    ? TextInputAction.done
                                    : TextInputAction.next,
                                decoration:
                                    _dec(
                                      r.marks[i].label.isEmpty
                                          ? tr.calZoneN(i + 1)
                                          : '${i + 1} · ${r.marks[i].label}',
                                    ).copyWith(
                                      helperText:
                                          doubtfulForCalibration(r.marks[i])
                                          ? tr.calDoubtful
                                          : null,
                                    ),
                              ),
                              if (_second[i]) ...[
                                const SizedBox(height: 6),
                                TextField(
                                  key: ValueKey('calZoneB$i'),
                                  controller: _b[i],
                                  enabled: _include[i],
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  inputFormatters: _numbers,
                                  decoration: _dec(tr.calSecondReading),
                                ),
                              ],
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: _second[i]
                              ? tr.calOneReading
                              : tr.calNotRound,
                          onPressed: _include[i]
                              ? () => setState(() => _second[i] = !_second[i])
                              : null,
                          icon: Icon(
                            _second[i]
                                ? Icons.remove_circle_outline
                                : Icons.add,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton(
                  key: const ValueKey('calSeeResult'),
                  onPressed: _done,
                  child: Text(tr.calSeeResult),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Numbers on the disks (no sizes, so they don't steer the readings), the
/// zone being read and the span to measure.
class CalibrationNumbersPainter extends CustomPainter {
  CalibrationNumbersPainter({
    required this.record,
    required this.focused,
    required this.pair,
    required this.included,
  });

  final ZoneRecord record;
  final int? focused;
  final (int, int)? pair;
  final List<bool> included;

  @override
  void paint(Canvas canvas, Size size) {
    // Sized for the 260 px preview: the numbers come out about 16 px tall.
    final px = record.plate.radius / 300;
    final pl = record.plate;
    canvas.drawCircle(
      Offset(pl.cx, pl.cy),
      pl.radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * px
        ..color = Colors.cyanAccent.withValues(alpha: 0.6),
    );
    final p = pair;
    if (p != null) {
      final a = record.marks[p.$1], b = record.marks[p.$2];
      final dir = Offset(b.x - a.x, b.y - a.y);
      final u = dir / dir.distance;
      final from = Offset(a.x, a.y) - u * a.diskRadiusPx;
      final to = Offset(b.x, b.y) + u * b.diskRadiusPx;
      canvas.drawLine(
        from,
        to,
        Paint()
          ..strokeWidth = (focused == -1 ? 5 : 2.5) * px
          ..color = focused == -1
              ? Colors.amberAccent
              : Colors.amberAccent.withValues(alpha: 0.6),
      );
    }
    for (var i = 0; i < record.marks.length; i++) {
      final m = record.marks[i];
      final on = focused == i;
      final colour = !included[i]
          ? Colors.grey
          : on
          ? Colors.amberAccent
          : Colors.white;
      canvas.drawCircle(
        Offset(m.x, m.y),
        m.diskRadiusPx * (on ? 2.6 : 1.3),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (on ? 6 : 3) * px
          ..color = colour,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: Colors.black,
            backgroundColor: colour,
            fontSize: 44 * px,
            fontFamily: 'Roboto',
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(m.x - tp.width / 2, m.y - m.diskRadiusPx * 1.4 - tp.height),
      );
    }
  }

  @override
  bool shouldRepaint(CalibrationNumbersPainter old) =>
      old.focused != focused ||
      old.record != record ||
      !listEquals(old.included, included);
}

/// The verdict, the agreement and the per-zone table.
class _ResultStep extends StatelessWidget {
  const _ResultStep({
    required this.profile,
    required this.onSave,
    required this.onAddPlate,
    required this.onTryAgain,
  });

  final CalibrationProfile profile;
  final VoidCallback? onSave;
  final VoidCallback onAddPlate;
  final VoidCallback onTryAgain;

  String _advice(CalSummary s) => switch (s.hint) {
    CalibrationHint.none => '',
    CalibrationHint.scale => tr.calHintScale,
    CalibrationHint.lens => tr.calHintLens,
    CalibrationHint.edge =>
      s.bias >= 0
          ? tr.calHintEdgeLarger(_mm(s.bias.abs()))
          : tr.calHintEdgeSmaller(_mm(s.bias.abs())),
    CalibrationHint.spread => tr.calHintSpread,
  };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final s = profile.summary;
    final good = s.verdict == CalibrationVerdict.good;
    final rows = [
      for (final p in profile.plates)
        for (final z in p.zones)
          if (z.included && z.appMm.isNotEmpty) z,
    ];
    final advice = _advice(s);
    return SingleChildScrollView(
      padding: scrollPadding(
        context,
        const EdgeInsets.fromLTRB(16, 12, 16, 24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: good ? cs.primaryContainer : cs.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    verdictText(s.verdict),
                    key: const ValueKey('calVerdict'),
                    style: t.titleMedium,
                  ),
                  if (s.verdict == CalibrationVerdict.tooFew)
                    Text(
                      tr.calMinZones(
                        CalibrationLimits.of(profile.tool).minZones,
                      ),
                    ),
                  if (advice.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(advice, key: const ValueKey('calAdvice')),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (s.n > 0) ...[
            Text(
              tr.calStats(
                _signed(s.bias),
                _signed(s.loaLow),
                _signed(s.loaHigh),
                s.n,
              ),
              style: t.bodyMedium,
            ),
            Text(
              tr.calWithin1(((s.within1mm) * 100).round()),
              style: t.bodySmall,
            ),
          ],
          if (s.scaleError != null)
            Text(
              tr.calScaleCheck(
                '${s.scaleError! >= 0 ? '+' : '−'}'
                '${(s.scaleError!.abs() * 100).toStringAsFixed(1)}',
              ),
              style: t.bodySmall,
            ),
          if (s.repeatabilitySd != null)
            Text(
              tr.calRepeatability(_mm(s.repeatabilitySd!)),
              style: t.bodySmall,
            ),
          const SizedBox(height: 12),
          if (rows.length >= 2)
            SizedBox(
              height: 200,
              child: CustomPaint(
                size: Size.infinite,
                painter: AgreementPlotPainter(
                  points: [
                    for (final z in rows)
                      (
                        (_avg(z.appMm) + _avg(z.userMm)) / 2,
                        _avg(z.appMm) - _avg(z.userMm),
                      ),
                  ],
                  bias: s.bias,
                  loaLow: s.loaLow,
                  loaHigh: s.loaHigh,
                  dot: seriesColour(context, 0),
                  ink: cs.onSurface,
                  muted: cs.onSurfaceVariant,
                  style: t.bodySmall!,
                ),
              ),
            ),
          Text(tr.calPlotCaption, style: t.bodySmall),
          const SizedBox(height: 12),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(),
              1: IntrinsicColumnWidth(),
              2: IntrinsicColumnWidth(),
              3: IntrinsicColumnWidth(),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                children: [
                  _cell(tr.calColZone, t.labelLarge),
                  _cell(tr.calColYours, t.labelLarge),
                  _cell(tr.calColApp, t.labelLarge),
                  _cell(tr.calColDiff, t.labelLarge),
                ],
              ),
              for (final (pi, p) in profile.plates.indexed)
                for (final z in p.zones)
                  TableRow(
                    children: [
                      _cell(
                        profile.plates.length > 1
                            ? '${pi + 1}.${z.mark + 1}'
                            : '${z.mark + 1}',
                        t.bodyMedium,
                      ),
                      _cell(_mm(_avg(z.userMm)), t.bodyMedium),
                      _cell(
                        z.appMm.isEmpty ? '–' : _mm(_avg(z.appMm)),
                        t.bodyMedium,
                      ),
                      _cell(
                        !z.included || z.appMm.isEmpty
                            ? tr.calLeftOut
                            : _signed(_avg(z.appMm) - _avg(z.userMm)),
                        t.bodyMedium,
                      ),
                    ],
                  ),
            ],
          ),
          const SizedBox(height: 16),
          Text(tr.calWhatChecked, style: t.bodySmall),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('calSave'),
            onPressed: onSave,
            icon: const Icon(Icons.save_outlined),
            label: Text(tr.calSave),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onAddPlate,
            icon: const Icon(Icons.add),
            label: Text(tr.calAddPlate),
          ),
          TextButton(onPressed: onTryAgain, child: Text(tr.calTryAgain)),
        ],
      ),
    );
  }

  static double _avg(List<double> v) => v.reduce((a, b) => a + b) / v.length;

  Widget _cell(String text, TextStyle? style) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
    child: Text(text, style: style),
  );
}

/// Bland–Altman plot: app − yours against the mean of the two, with the bias,
/// the 95 % limits of agreement and the ±1 mm band.
class AgreementPlotPainter extends CustomPainter {
  AgreementPlotPainter({
    required this.points,
    required this.bias,
    required this.loaLow,
    required this.loaHigh,
    required this.dot,
    required this.ink,
    required this.muted,
    required this.style,
  });

  final List<(double, double)> points;
  final double bias;
  final double loaLow;
  final double loaHigh;
  final Color dot;
  final Color ink;
  final Color muted;
  final TextStyle style;

  TextPainter _text(String s) => TextPainter(
    text: TextSpan(
      text: s,
      style: style.copyWith(
        color: muted,
        fontFamily: 'Roboto',
        fontFamilyFallback: const ['ColonySymbols'],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    const left = 36.0, bottom = 22.0, top = 6.0, right = 8.0;
    final w = size.width - left - right, h = size.height - top - bottom;
    final xs = [for (final p in points) p.$1];
    var x0 = xs.reduce(math.min), x1 = xs.reduce(math.max);
    if (x1 - x0 < 4) {
      x0 -= 2;
      x1 += 2;
    }
    x0 = (x0 / 5).floor() * 5.0;
    x1 = (x1 / 5).ceil() * 5.0;
    final ys = [
      for (final p in points) p.$2,
      loaLow,
      loaHigh,
      -1.0,
      1.0,
    ].where((v) => v.isFinite);
    final yMax = ys.map((v) => v.abs()).reduce(math.max).ceilToDouble() + 0.5;
    double xOf(double v) => left + w * (v - x0) / (x1 - x0);
    double yOf(double v) => top + h * (yMax - v) / (2 * yMax);

    // ±1 mm band (half the 1 mm reading step either side).
    canvas.drawRect(
      Rect.fromLTRB(left, yOf(1), left + w, yOf(-1)),
      Paint()..color = muted.withValues(alpha: 0.10),
    );
    final grid = Paint()
      ..color = muted.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(left, yOf(0)), Offset(left + w, yOf(0)), grid);
    void dashed(double v, Paint p) {
      for (var x = left; x < left + w; x += 8) {
        canvas.drawLine(
          Offset(x, yOf(v)),
          Offset(math.min(x + 4, left + w), yOf(v)),
          p,
        );
      }
    }

    if (bias.isFinite) {
      canvas.drawLine(
        Offset(left, yOf(bias)),
        Offset(left + w, yOf(bias)),
        Paint()
          ..color = ink
          ..strokeWidth = 1.5,
      );
    }
    final loa = Paint()
      ..color = ink.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    if (loaLow.isFinite) dashed(loaLow, loa);
    if (loaHigh.isFinite) dashed(loaHigh, loa);
    for (final v in [-yMax.floorToDouble(), 0.0, yMax.floorToDouble()]) {
      final tp = _text(v == 0 ? '0' : _signed(v));
      tp.paint(canvas, Offset(left - tp.width - 4, yOf(v) - tp.height / 2));
    }
    for (var v = x0; v <= x1 + 1e-9; v += 5) {
      final tp = _text(v.toStringAsFixed(0));
      tp.paint(canvas, Offset(xOf(v) - tp.width / 2, top + h + 4));
    }
    final fill = Paint()..color = dot;
    for (final (x, y) in points) {
      canvas.drawCircle(Offset(xOf(x), yOf(y)), 4, fill);
    }
  }

  @override
  bool shouldRepaint(AgreementPlotPainter old) =>
      !listEquals(old.points, points) || old.bias != bias || old.ink != ink;
}
