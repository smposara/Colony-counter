import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/calculator.dart';
import '../core/colour.dart';
import '../core/drop_layout.dart';
import '../core/drop_stats.dart';
import '../core/petrifilm.dart';
import '../core/plate.dart';
import '../data/plate_store.dart';
import '../data/sample_info.dart';
import '../l10n/l10n.dart';
import '../l10n/labels.dart';
import 'format.dart';
import 'insets.dart';

/// Create or edit a sample's plating plan. Pops with the saved [SampleInfo].
class SampleSetupScreen extends StatefulWidget {
  const SampleSetupScreen({
    super.key,
    required this.store,
    this.edit,
    this.template,
    this.initialId,
  });

  final PlateStore store;

  /// Existing sample to edit.
  final SampleInfo? edit;

  /// Settings to start a new sample from ("New sample like this").
  final SampleInfo? template;

  /// Sample ID to start with (e.g. from a scanned label).
  final String? initialId;

  @override
  State<SampleSetupScreen> createState() => _SampleSetupScreenState();
}

class _SampleSetupScreenState extends State<SampleSetupScreen> {
  late final SampleInfo? _base = widget.edit ?? widget.template;
  late final _id = TextEditingController(
    text: widget.edit?.sampleId ?? widget.initialId ?? _suggestId(),
  );
  late final _experiment = TextEditingController(text: _base?.experiment ?? '');
  late final _condition = TextEditingController(text: _base?.condition ?? '');
  late final _time = TextEditingController(
    text: _base?.timeH == null
        ? ''
        : fixed(_base!.timeH!, _base.timeH! % 1 == 0 ? 0 : 1),
  );
  late final _volume = TextEditingController(
    text:
        '${_base?.volumeMl ?? (widget.store.defaultFormat.isFilm ? 1.0 : widget.store.defaultVolumeMl)}',
  );
  late final _dropVolume = TextEditingController(
    text: fixed(_base?.dropVolumeUl ?? 10, 0),
  );
  late final _notes = TextEditingController(text: _base?.notes ?? '');
  late final _strain = TextEditingController(text: _base?.strain ?? '');
  late final _medium = TextEditingController(
    text: _base?.medium ?? widget.store.defaultMedium,
  );
  late final _mediumBatch = TextEditingController(
    text: _base?.mediumBatch ?? '',
  );
  late final _incTemp = TextEditingController(
    text: _base?.incubationTempC == null
        ? ''
        : fixed(
            _base!.incubationTempC!,
            _base.incubationTempC! % 1 == 0 ? 0 : 1,
          ),
  );
  late final _incHours = TextEditingController(
    text: _base?.incubationH == null
        ? ''
        : fixed(_base!.incubationH!, _base.incubationH! % 1 == 0 ? 0 : 1),
  );
  late final _operator = TextEditingController(
    text: _base?.operator ?? widget.store.defaultOperator,
  );
  late final _tags = TextEditingController(text: _base?.tags.join(', ') ?? '');
  late PlatingMethod _method =
      _base?.method ??
      (widget.store.defaultFormat.isFilm
          ? PlatingMethod.film
          : PlatingMethod.spread);
  late PlateFormat _format = _base?.format ?? widget.store.defaultFormat;
  late bool _solid = _base?.solid ?? false;
  late final _weight = TextEditingController(
    text: fixed(_base?.sampleWeightG ?? 25, 0),
  );
  late final _diluent = TextEditingController(
    text: fixed(_base?.diluentMl ?? 225, 0),
  );
  late CountingRule _membraneRule =
      _base?.membraneRule ?? CountingRule.membrane80;
  late DropLayout _layout = _base?.dropLayout ?? DropLayout.replicates;

  /// New samples start with the classic ring; older ones keep "free".
  late DropArrangement _arrangement =
      _base?.dropArrangement ?? DropArrangement.sectors;
  late int _perDilution = _base?.dropsPerDilution ?? 1;
  late DropMode _dropMode = _base?.dropMode ?? DropMode.pooled;
  late final _windowLo = TextEditingController(
    text: '${(_base?.dropWindow ?? kDropWindow).$1}',
  );
  late final _windowHi = TextEditingController(
    text: '${(_base?.dropWindow ?? kDropWindow).$2}',
  );

  /// The window as typed, or the default when it does not make sense.
  (int, int) get _dropWindow {
    final lo = int.tryParse(_windowLo.text.trim());
    final hi = int.tryParse(_windowHi.text.trim());
    return lo != null && hi != null && lo >= 0 && hi > lo
        ? (lo, hi)
        : kDropWindow;
  }

  late final _pitch = TextEditingController(
    text: fixed(
      _base?.dropPitchMm ?? 11,
      _base?.dropPitchMm == null || _base!.dropPitchMm % 1 == 0 ? 0 : 1,
    ),
  );
  late ColourMode _colour = _base?.colourMode ?? ColourMode.none;
  // Films are usually plated from 10⁻¹, dishes from 10⁻⁴.
  late final bool _filmStart = _method == PlatingMethod.film;
  late int _from = _base?.dilutions.first ?? (_filmStart ? 1 : 4);
  late int _to = _base?.dilutions.last ?? (_filmStart ? 3 : 6);

  /// The dilution range was set by the user (or comes from an existing
  /// sample), so switching the plating method keeps it.
  late bool _rangeSet = _base != null;
  late int _replicates = _base?.replicates ?? 3;
  String? _idError;

  /// "Lake-A-2" after "Lake-A", or "S1", "S2"… for a fresh start.
  String _suggestId() {
    final t = widget.template;
    final existing = widget.store.allSamples().map((s) => s.sampleId).toSet();
    final stem = t == null ? 'S' : '${t.sampleId}-';
    for (var i = t == null ? 1 : 2; ; i++) {
      final id = '$stem$i';
      if (!existing.contains(id)) return id;
    }
  }

  void _setMethod(PlatingMethod m) {
    setState(() {
      final wasMembrane = _method == PlatingMethod.membrane;
      final wasFilm = _method == PlatingMethod.film;
      _method = m;
      if (m == PlatingMethod.film && !wasFilm) {
        // One film per dilution, 1 mL each.
        final d = widget.store.defaultFormat;
        _format = d.isFilm ? d : PlateFormat.filmAc;
        _volume.text = '1.0';
        // Films are usually plated from the 10⁻¹ dilution; keep a range the
        // user has set (membrane's forced "neat" is not one).
        if (!_rangeSet || (wasMembrane && _from == 0 && _to == 0)) {
          _from = 1;
          _to = 3;
        }
        return;
      }
      if (m != PlatingMethod.film && wasFilm) {
        final d = widget.store.defaultFormat;
        _format = d.isDish ? d : PlateFormat.dish90;
        _volume.text = '${widget.store.defaultVolumeMl}';
        if (!_rangeSet) {
          _from = 4;
          _to = 6;
        }
        if (m != PlatingMethod.membrane) return;
      }
      if (m == PlatingMethod.membrane && !wasMembrane) {
        // Water samples are usually filtered neat, 100 mL at a time.
        _format = PlateFormat.membrane47;
        _from = 0;
        _to = 0;
        _volume.text = '100';
      } else if (m != PlatingMethod.membrane && wasMembrane) {
        final d = widget.store.defaultFormat;
        _format = d.isDish ? d : PlateFormat.dish90;
        _volume.text = '${widget.store.defaultVolumeMl}';
        if (!_rangeSet) {
          _from = 4;
          _to = 6;
        }
      }
    });
  }

  Widget _numberField(TextEditingController c, String label, String unit) =>
      TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        decoration: InputDecoration(
          labelText: label,
          suffixText: unit,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      );

  /// How the initial suspension of a solid sample enters the result.
  String _suspensionHint() {
    final w = _num(_weight) ?? 0, v = _num(_diluent) ?? 0;
    if (w <= 0) return '';
    final f = (w + v) / w;
    if ((f - 10).abs() < 1e-6) return tr.solidTenfold;
    return tr.solidOther(fixed(f, f % 1 == 0 ? 0 : 2), fixed(f / 10, 3));
  }

  double? _num(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  void _save() {
    final id = _id.text.trim();
    final taken =
        widget.store.allSamples().any((s) => s.sampleId == id) &&
        id != widget.edit?.sampleId;
    setState(
      () => _idError = id.isEmpty
          ? tr.setupRequired
          : (taken ? tr.setupIdTaken : null),
    );
    if (_idError != null) return;
    final info = SampleInfo(
      sampleId: id,
      experiment: _experiment.text.trim(),
      condition: _condition.text.trim(),
      timeH: _num(_time),
      method: _method,
      dilutions: [for (var d = _from; d <= _to; d++) d],
      replicates: _replicates,
      volumeMl: _num(_volume) ?? 0.1,
      dropVolumeUl: _num(_dropVolume) ?? 10,
      dropLayout: _layout,
      dropArrangement: _arrangement,
      dropsPerDilution: _perDilution,
      dropPitchMm: _num(_pitch) ?? 11,
      dropMode: _dropMode,
      dropWindow: _dropWindow,
      colourMode: _method == PlatingMethod.film ? ColourMode.none : _colour,
      notes: _notes.text.trim(),
      strain: _strain.text.trim(),
      medium: _medium.text.trim(),
      mediumBatch: _mediumBatch.text.trim(),
      incubationTempC: _num(_incTemp),
      incubationH: _num(_incHours),
      operator: _operator.text.trim(),
      tags: [
        for (final t in _tags.text.split(','))
          if (t.trim().isNotEmpty) t.trim(),
      ],
      format: _format,
      membraneRule: _membraneRule,
      solid: _solid && _method != PlatingMethod.membrane,
      sampleWeightG: _num(_weight) ?? 25,
      diluentMl: _num(_diluent) ?? 225,
      createdAt: widget.edit?.createdAt,
    );
    widget.store.upsertSample(info, previousId: widget.edit?.sampleId);
    // Remember operator and medium for the next sample.
    widget.store.setDefaults(
      operator: info.operator,
      medium: info.medium,
      format: _format.isDish ? _format : null,
    );
    Navigator.of(context).pop(info);
  }

  @override
  void dispose() {
    for (final c in [
      _id,
      _experiment,
      _condition,
      _time,
      _volume,
      _dropVolume,
      _pitch,
      _windowLo,
      _windowHi,
      _weight,
      _diluent,
      _notes,
      _strain,
      _medium,
      _mediumBatch,
      _incTemp,
      _incHours,
      _operator,
      _tags,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _suggestField(
    TextEditingController c,
    String label,
    List<String> options, {
    String? helper,
  }) => Autocomplete<String>(
    initialValue: TextEditingValue(text: c.text),
    optionsBuilder: (v) => options.where(
      (o) => o.toLowerCase().contains(v.text.toLowerCase()) && o != v.text,
    ),
    onSelected: (v) => c.text = v,
    fieldViewBuilder: (context, controller, focus, _) => TextField(
      controller: controller,
      focusNode: focus,
      onChanged: (v) => c.text = v,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  /// The plan as it stands in the form, for the layout preview.
  SampleInfo get _draftDrops => SampleInfo(
    sampleId: '',
    method: PlatingMethod.drop,
    dilutions: [for (var d = _from; d <= _to; d++) d],
    replicates: _replicates,
    dropVolumeUl: _num(_dropVolume) ?? 10,
    dropLayout: _layout,
    dropArrangement: _arrangement,
    dropsPerDilution: _perDilution,
    dropPitchMm: _num(_pitch) ?? 11,
    format: _format,
  );

  List<Widget> _arrangementSection(TextTheme t) {
    final row = _layout == DropLayout.replicates;
    return [
      const SizedBox(height: 8),
      Text(tr.setupDropArrangement, style: t.titleSmall),
      const SizedBox(height: 8),
      SegmentedButton<DropArrangement>(
        showSelectedIcon: false,
        segments: [
          for (final a in DropArrangement.values)
            ButtonSegment(value: a, label: Text(a.text)),
        ],
        selected: {_arrangement},
        onSelectionChanged: (v) => setState(() => _arrangement = v.first),
      ),
      const SizedBox(height: 4),
      Text(switch (_arrangement) {
        DropArrangement.free => tr.setupDropFreeHelp,
        DropArrangement.sectors => tr.setupDropSectorsHelp,
        DropArrangement.grid when row => tr.setupDropGridRowHelp,
        DropArrangement.grid => tr.setupDropGridHelp,
      }, style: t.bodySmall),
      if (!row) ...[
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: Text(tr.setupDropsPerDilution)),
            IconButton(
              onPressed: _perDilution > 1
                  ? () => setState(() => _perDilution--)
                  : null,
              icon: const Icon(Icons.remove),
            ),
            Text('$_perDilution', style: t.titleMedium),
            IconButton(
              onPressed: _perDilution < 6
                  ? () => setState(() => _perDilution++)
                  : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
      if (_arrangement == DropArrangement.grid) ...[
        const SizedBox(height: 8),
        TextField(
          controller: _pitch,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: tr.setupDropPitch,
            suffixText: 'mm',
            border: const OutlineInputBorder(),
          ),
        ),
      ],
      if (_arrangement != DropArrangement.free) ...[
        const SizedBox(height: 12),
        Semantics(
          label: tr.setupDropLayoutPreview,
          child: SizedBox(
            height: 180,
            child: CustomPaint(
              painter: _DropLayoutPreview(
                _draftDrops,
                Theme.of(context).colorScheme,
              ),
              size: Size.infinite,
            ),
          ),
        ),
      ],
      const SizedBox(height: 16),
      Text(tr.setupDropWindow, style: t.titleSmall),
      const SizedBox(height: 8),
      Row(
        children: [
          for (final (c, label) in [
            (_windowLo, tr.setupDropWindowFrom),
            (_windowHi, tr.setupDropWindowTo),
          ]) ...[
            Expanded(
              child: TextField(
                controller: c,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: label,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            if (c == _windowLo) const SizedBox(width: 12),
          ],
        ],
      ),
      const SizedBox(height: 4),
      Text(tr.setupDropWindowHelp, style: t.bodySmall),
      const SizedBox(height: 16),
      Text(tr.setupDropMode, style: t.titleSmall),
      const SizedBox(height: 8),
      SegmentedButton<DropMode>(
        showSelectedIcon: false,
        segments: [
          for (final m in DropMode.values)
            ButtonSegment(value: m, label: Text(m.text)),
        ],
        selected: {_dropMode},
        onSelectionChanged: (v) => setState(() => _dropMode = v.first),
      ),
      const SizedBox(height: 4),
      Text(
        _dropMode == DropMode.pooled
            ? tr.setupDropPooledHelp
            : tr.setupDropFirstHelp,
        style: t.bodySmall,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final samples = widget.store.allSamples();
    final experiments = widget.store.experiments();
    final conditions = {
      for (final s in samples)
        if (s.condition.isNotEmpty) s.condition,
    }.toList()..sort();
    final drop = _method == PlatingMethod.drop;
    final membrane = _method == PlatingMethod.membrane;
    final film = _method == PlatingMethod.film;
    final dilutionCount = _to - _from + 1;
    final plates = !drop
        ? dilutionCount * _replicates
        : (_layout == DropLayout.replicates ? dilutionCount : _replicates);
    final dropsPerPlate = _layout == DropLayout.replicates
        ? _replicates
        : dilutionCount * _perDilution;
    const gap = SizedBox(height: 16);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.edit == null
              ? tr.setupNewSample
              : tr.setupEditTitle(widget.edit!.sampleId),
        ),
      ),
      body: ListView(
        padding: scrollPadding(
          context,
          const EdgeInsets.fromLTRB(16, 8, 16, 32),
        ),
        children: [
          TextField(
            controller: _id,
            decoration: InputDecoration(
              labelText: tr.setupSampleId,
              errorText: _idError,
              border: const OutlineInputBorder(),
            ),
          ),
          gap,
          _suggestField(
            _experiment,
            tr.setupExperiment,
            experiments,
            helper: tr.setupExperimentHelp,
          ),
          gap,
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _suggestField(
                  _condition,
                  tr.setupCondition,
                  conditions,
                  helper: tr.setupConditionHelp,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _time,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: tr.setupTimePoint,
                    suffixText: tr.setupHoursUnit,
                    helperText: tr.setupOptional,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(tr.setupPlating, style: t.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<PlatingMethod>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: PlatingMethod.spread,
                label: Text(tr.setupSpread),
              ),
              ButtonSegment(
                value: PlatingMethod.drop,
                label: Text(tr.setupDrop),
              ),
              ButtonSegment(
                value: PlatingMethod.membrane,
                label: Text(tr.setupMembrane),
              ),
              ButtonSegment(
                value: PlatingMethod.film,
                label: Text(tr.setupFilm),
              ),
            ],
            selected: {_method},
            onSelectionChanged: (s) => _setMethod(s.first),
          ),
          const SizedBox(height: 4),
          Text(_method.text, style: t.bodySmall),
          gap,
          if (membrane) ...[
            DropdownButtonFormField<CountingRule>(
              isExpanded: true,
              initialValue: _membraneRule,
              decoration: InputDecoration(
                labelText: tr.setupMembraneRange,
                helperText: tr.setupMembraneUnit,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final r in CountingRule.membraneRules)
                  DropdownMenuItem(value: r, child: Text(r.text)),
              ],
              onChanged: (v) => setState(() => _membraneRule = v!),
            ),
          ] else ...[
            Text(tr.sampleKind, style: t.bodyLarge),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: Text(tr.sampleLiquid)),
                ButtonSegment(value: true, label: Text(tr.sampleSolid)),
              ],
              selected: {_solid},
              onSelectionChanged: (v) => setState(() => _solid = v.first),
            ),
            if (_solid) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _numberField(_weight, tr.sampleWeight, 'g')),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _numberField(_diluent, tr.diluentVolume, 'mL'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(_suspensionHint(), style: t.bodySmall),
            ],
            gap,
          ],
          if (!membrane)
            DropdownButtonFormField<PlateFormat>(
              isExpanded: true,
              key: ValueKey(_method),
              initialValue: film
                  ? (_format.isFilm ? _format : PlateFormat.filmAc)
                  : (_format.isDish ? _format : PlateFormat.dish90),
              decoration: InputDecoration(
                labelText: film ? tr.filmType : tr.setupPlateType,
                helperText: film && _format.isFilm
                    ? tr.filmRangeFromType(
                        filmCountingRule(_format.film!).min,
                        filmCountingRule(_format.film!).max,
                      )
                    : null,
                helperMaxLines: 3,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final f in PlateFormat.values)
                  if (film ? f.isFilm : f.isDish)
                    DropdownMenuItem(value: f, child: Text(f.text)),
              ],
              onChanged: (v) => setState(() => _format = v!),
            ),
          gap,
          Row(
            children: [
              Expanded(
                child: _dilutionPicker(
                  tr.setupFrom,
                  _from,
                  (v) => setState(() {
                    _rangeSet = true;
                    _from = v;
                    if (_to < v) _to = v;
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _dilutionPicker(
                  tr.setupTo,
                  _to,
                  (v) => setState(() {
                    _rangeSet = true;
                    _to = v;
                    if (_from > v) _from = v;
                  }),
                ),
              ),
            ],
          ),
          gap,
          Row(
            children: [
              Text(tr.setupReplicates, style: t.bodyLarge),
              const Spacer(),
              IconButton.outlined(
                onPressed: _replicates > 1
                    ? () => setState(() => _replicates--)
                    : null,
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '$_replicates',
                  textAlign: TextAlign.center,
                  style: t.titleLarge,
                ),
              ),
              IconButton.outlined(
                onPressed: _replicates < 12
                    ? () => setState(() => _replicates++)
                    : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          gap,
          if (!drop)
            TextField(
              controller: _volume,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText: membrane
                    ? tr.setupVolumeFiltered
                    : tr.setupVolumePerPlate,
                suffixText: 'mL',
                border: const OutlineInputBorder(),
              ),
            )
          else ...[
            TextField(
              controller: _dropVolume,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText: tr.setupDropVolume,
                suffixText: 'µL',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            RadioGroup<DropLayout>(
              groupValue: _layout,
              onChanged: (v) => setState(() => _layout = v!),
              child: Column(
                children: [
                  for (final l in DropLayout.values)
                    RadioListTile<DropLayout>(
                      contentPadding: EdgeInsets.zero,
                      value: l,
                      title: Text(l.text),
                    ),
                ],
              ),
            ),
            ..._arrangementSection(t),
          ],
          const SizedBox(height: 8),
          Text(
            membrane
                ? tr.setupFilterCount(plates)
                : drop
                ? tr.setupPlateCountDrops(plates, dropsPerPlate)
                : tr.setupPlateCount(plates),
            style: t.bodyMedium,
          ),
          if (!film) ...[
            const SizedBox(height: 24),
            Text(tr.setupColonyColours, style: t.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<ColourMode>(
              showSelectedIcon: false,
              segments: [
                for (final m in ColourMode.values)
                  ButtonSegment(value: m, label: Text(m.text)),
              ],
              selected: {_colour},
              onSelectionChanged: (s) => setState(() => _colour = s.first),
            ),
            const SizedBox(height: 4),
            Text(switch (_colour) {
              ColourMode.none => tr.setupColourNone,
              ColourMode.blueWhite => tr.setupColourBlueWhite,
              ColourMode.twoColours => tr.setupColourTwo,
            }, style: t.bodySmall),
          ],
          gap,
          _detailsSection(),
          gap,
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: tr.setupNotes,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: Text(tr.setupSave)),
        ],
      ),
    );
  }

  /// Strain, medium, incubation, operator and tags: optional, collapsed when
  /// empty so quick setups stay short.
  Widget _detailsSection() {
    final strains = {
      for (final s in widget.store.allSamples())
        if (s.strain.isNotEmpty) s.strain,
    }.toList()..sort();
    final operators = {
      for (final s in widget.store.allSamples())
        if (s.operator.isNotEmpty) s.operator,
    }.toList()..sort();
    final hasAny = [
      _strain,
      _mediumBatch,
      _incTemp,
      _incHours,
      _tags,
    ].any((c) => c.text.isNotEmpty);
    InputDecoration deco(String label, {String? suffix, String? helper}) =>
        InputDecoration(
          labelText: label,
          suffixText: suffix,
          helperText: helper,
          border: const OutlineInputBorder(),
        );
    final number = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    const gap = SizedBox(height: 12);
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: hasAny,
        shape: const Border(),
        title: Text(tr.setupDetails),
        subtitle: Text(tr.setupDetailsSummary),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          _suggestField(_strain, tr.setupStrain, strains),
          gap,
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _medium,
                  decoration: deco(tr.setupMedium),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _mediumBatch,
                  decoration: deco(tr.setupBatch),
                ),
              ),
            ],
          ),
          gap,
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _incHours,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: number,
                  decoration: deco(
                    tr.setupIncubation,
                    suffix: tr.setupHoursUnit,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _incTemp,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: number,
                  decoration: deco(tr.setupTemperature, suffix: '°C'),
                ),
              ),
            ],
          ),
          gap,
          _suggestField(_operator, tr.setupOperator, operators),
          gap,
          TextField(
            controller: _tags,
            decoration: deco(tr.setupTags, helper: tr.setupTagsHelp),
          ),
        ],
      ),
    );
  }

  Widget _dilutionPicker(
    String label,
    int value,
    ValueChanged<int> onChanged,
  ) => DropdownButtonFormField<int>(
    // Re-created when the other picker pushes this value along.
    key: ValueKey('$label$value'),
    initialValue: value,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    items: [
      for (var e = 0; e <= 10; e++)
        DropdownMenuItem(value: e, child: Text(dilutionLabel(e))),
    ],
    onChanged: (v) => onChanged(v ?? value),
  );
}

/// A plate seen from above with the planned drops, each labelled with its
/// dilution; the first drop is filled.
class _DropLayoutPreview extends CustomPainter {
  _DropLayoutPreview(this.info, this.colours);

  final SampleInfo info;
  final ColorScheme colours;

  @override
  void paint(Canvas canvas, Size size) {
    final slot = info.slots.isEmpty ? const Slot() : info.slots.first;
    final drops = templatePositionsMm(
      info.dropTemplate,
      info.dropDilutions(slot),
    );
    final plateMm = info.format.sizeMm;
    final k = math.min(size.width, size.height) / plateMm;
    final c = size.center(Offset.zero);
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = colours.outline;
    final half = plateMm / 2 * k;
    if (info.format.shape == PlateShape.square) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: c, width: 2 * half, height: 2 * half),
          Radius.circular(half * kSquareCorner),
        ),
        rim,
      );
    } else {
      canvas.drawCircle(c, half, rim);
    }
    final r = dropDiameterMm(info.dropVolumeUl) / 2 * k;
    for (var i = 0; i < drops.length; i++) {
      final d = drops[i];
      final p = c + Offset(d.x * k, d.y * k);
      canvas.drawCircle(
        p,
        r,
        Paint()
          ..style = i == 0 ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = i == 0 ? colours.primaryContainer : colours.primary,
      );
      final label = TextPainter(
        text: TextSpan(
          text: dilutionLabel(d.dilutionExp),
          style: TextStyle(
            fontSize: math.max(8, math.min(11, r * 0.75)),
            color: colours.onSurface,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, p - Offset(label.width / 2, label.height / 2));
    }
  }

  @override
  bool shouldRepaint(_DropLayoutPreview old) => true;
}
