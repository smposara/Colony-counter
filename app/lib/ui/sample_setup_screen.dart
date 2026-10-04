import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/colour.dart';
import '../data/plate_store.dart';
import '../data/sample_info.dart';
import 'format.dart';

/// Create or edit a sample's plating plan. Pops with the saved [SampleInfo].
class SampleSetupScreen extends StatefulWidget {
  const SampleSetupScreen({
    super.key,
    required this.store,
    this.edit,
    this.template,
  });

  final PlateStore store;

  /// Existing sample to edit.
  final SampleInfo? edit;

  /// Settings to start a new sample from ("New sample like this").
  final SampleInfo? template;

  @override
  State<SampleSetupScreen> createState() => _SampleSetupScreenState();
}

class _SampleSetupScreenState extends State<SampleSetupScreen> {
  late final SampleInfo? _base = widget.edit ?? widget.template;
  late final _id = TextEditingController(
    text: widget.edit?.sampleId ?? _suggestId(),
  );
  late final _experiment = TextEditingController(text: _base?.experiment ?? '');
  late final _condition = TextEditingController(text: _base?.condition ?? '');
  late final _time = TextEditingController(
    text: _base?.timeH == null
        ? ''
        : fixed(_base!.timeH!, _base.timeH! % 1 == 0 ? 0 : 1),
  );
  late final _volume = TextEditingController(
    text: '${_base?.volumeMl ?? widget.store.defaultVolumeMl}',
  );
  late final _dropVolume = TextEditingController(
    text: fixed(_base?.dropVolumeUl ?? 10, 0),
  );
  late final _notes = TextEditingController(text: _base?.notes ?? '');
  late PlatingMethod _method = _base?.method ?? PlatingMethod.spread;
  late DropLayout _layout = _base?.dropLayout ?? DropLayout.replicates;
  late ColourMode _colour = _base?.colourMode ?? ColourMode.none;
  late int _from = _base?.dilutions.first ?? 4;
  late int _to = _base?.dilutions.last ?? 6;
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

  double? _num(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  void _save() {
    final id = _id.text.trim();
    final taken =
        widget.store.allSamples().any((s) => s.sampleId == id) &&
        id != widget.edit?.sampleId;
    setState(
      () => _idError = id.isEmpty
          ? 'Required'
          : (taken ? 'This sample ID already exists' : null),
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
      colourMode: _colour,
      notes: _notes.text.trim(),
      createdAt: widget.edit?.createdAt,
    );
    widget.store.upsertSample(info, previousId: widget.edit?.sampleId);
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
      _notes,
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
    final dilutionCount = _to - _from + 1;
    final plates = !drop
        ? dilutionCount * _replicates
        : (_layout == DropLayout.replicates ? dilutionCount : _replicates);
    final perPlate = !drop
        ? ''
        : ' with ${_layout == DropLayout.replicates ? _replicates : dilutionCount} drops each';
    const gap = SizedBox(height: 16);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.edit == null ? 'New sample' : 'Edit ${widget.edit!.sampleId}',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _id,
            decoration: InputDecoration(
              labelText: 'Sample ID',
              errorText: _idError,
              border: const OutlineInputBorder(),
            ),
          ),
          gap,
          _suggestField(
            _experiment,
            'Experiment (optional)',
            experiments,
            helper: 'Samples of one experiment can be compared',
          ),
          gap,
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _suggestField(
                  _condition,
                  'Condition',
                  conditions,
                  helper: 'e.g. Control, 1 % NaOCl',
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
                  decoration: const InputDecoration(
                    labelText: 'Time point',
                    suffixText: 'h',
                    helperText: 'optional',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Plating', style: t.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<PlatingMethod>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: PlatingMethod.spread,
                label: Text('Spread / pour'),
              ),
              ButtonSegment(
                value: PlatingMethod.drop,
                label: Text('Drop plate'),
              ),
            ],
            selected: {_method},
            onSelectionChanged: (s) => setState(() => _method = s.first),
          ),
          gap,
          Row(
            children: [
              Expanded(
                child: _dilutionPicker(
                  'From',
                  _from,
                  (v) => setState(() {
                    _from = v;
                    if (_to < v) _to = v;
                  }),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _dilutionPicker(
                  'To',
                  _to,
                  (v) => setState(() {
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
              Text('Replicates', style: t.bodyLarge),
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
              decoration: const InputDecoration(
                labelText: 'Volume per plate',
                suffixText: 'mL',
                border: OutlineInputBorder(),
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
              decoration: const InputDecoration(
                labelText: 'Drop volume',
                suffixText: 'µL',
                border: OutlineInputBorder(),
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
                      title: Text(l.label),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '$plates plate${plates == 1 ? '' : 's'}$perPlate.',
            style: t.bodyMedium,
          ),
          const SizedBox(height: 24),
          Text('Colony colours', style: t.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<ColourMode>(
            showSelectedIcon: false,
            segments: [
              for (final m in ColourMode.values)
                ButtonSegment(value: m, label: Text(m.label)),
            ],
            selected: {_colour},
            onSelectionChanged: (s) => setState(() => _colour = s.first),
          ),
          const SizedBox(height: 4),
          Text(switch (_colour) {
            ColourMode.none => 'All colonies are counted together.',
            ColourMode.blueWhite => 'Blue and white colonies are counted separately (X-gal screening).',
            ColourMode.twoColours => 'Colonies are split into two colour groups (e.g. chromogenic agar).',
          }, style: t.bodySmall),
          gap,
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes (strain, medium batch, incubation…)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('Save sample')),
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
