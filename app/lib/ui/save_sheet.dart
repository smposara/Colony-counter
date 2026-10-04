import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/calculator.dart';
import '../data/plate_record.dart';
import '../data/plate_store.dart';
import 'format.dart';

/// Sample details for a plate, with a live CFU/mL preview. Pops with the
/// updated [PlateRecord].
class SaveSheet extends StatefulWidget {
  const SaveSheet({
    super.key,
    required this.store,
    required this.draft,
    this.fixedSample = false,
  });

  final PlateStore store;
  final PlateRecord draft;

  /// The plate was opened from a sample plan: sample, dilution and replicate
  /// are already set (they can still be changed except the sample).
  final bool fixedSample;

  @override
  State<SaveSheet> createState() => _SaveSheetState();
}

class _SaveSheetState extends State<SaveSheet> {
  late final _sample = TextEditingController(text: widget.draft.sampleId);
  late final bool _drop = widget.draft.isDropPlate;
  // Drop plates enter the drop volume in µL.
  late final _volume = TextEditingController(
    text: _fmtVolume(
      _drop ? widget.draft.volumeMl * 1000 : widget.draft.volumeMl,
    ),
  );
  late int _replicate = widget.draft.replicate;
  late final _notes = TextEditingController(text: widget.draft.notes);
  late int _dilutionExp = widget.draft.dilutionExp;
  late bool _spreader = widget.draft.spreader;
  late bool _tntc = widget.draft.tntc;

  static String _fmtVolume(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  double? get _volumeMl {
    final v = double.tryParse(_volume.text.replaceAll(',', '.'));
    if (v == null || v <= 0) return null;
    return _drop ? v / 1000 : v;
  }

  PlateRecord? _build() {
    final v = _volumeMl;
    if (v == null) return null;
    return widget.draft.copyWith(
      sampleId: _sample.text.trim(),
      dilutionExp: _dilutionExp,
      volumeMl: v,
      notes: _notes.text.trim(),
      spreader: _spreader,
      tntc: _tntc,
      replicate: _replicate,
    );
  }

  @override
  void dispose() {
    _sample.dispose();
    _volume.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final record = _build();
    final rule = widget.store.rule;
    final est = record?.estimateAlone(rule);
    final knownSamples = [
      for (final s in widget.store.allSamples()) s.sampleId,
    ];
    final ruleLabel = _drop ? CountingRule.dropPlate.label : rule.label;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Plate details', style: t.titleLarge),
            const SizedBox(height: 16),
            if (widget.fixedSample)
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Sample ID',
                  border: OutlineInputBorder(),
                ),
                child: Text(_sample.text),
              )
            else
              Autocomplete<String>(
                initialValue: TextEditingValue(text: _sample.text),
                optionsBuilder: (v) => knownSamples.where(
                  (s) =>
                      s.toLowerCase().contains(v.text.toLowerCase()) &&
                      s != v.text,
                ),
                onSelected: (s) => setState(() => _sample.text = s),
                fieldViewBuilder: (context, controller, focus, onSubmit) {
                  return TextField(
                    controller: controller,
                    focusNode: focus,
                    decoration: const InputDecoration(
                      labelText: 'Sample ID',
                      helperText: 'Plates with the same sample ID are pooled for CFU/mL',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.next,
                    onChanged: (v) => setState(() => _sample.text = v),
                  );
                },
              ),
            const SizedBox(height: 16),
            if (!_drop) ...[
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _dilutionExp,
                      decoration: const InputDecoration(
                        labelText: 'Plated dilution',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (var e = 0; e <= 10; e++)
                          DropdownMenuItem(
                            value: e,
                            child: Text(dilutionLabel(e)),
                          ),
                      ],
                      onChanged: (v) => setState(() => _dilutionExp = v ?? 0),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _replicate,
                      decoration: const InputDecoration(
                        labelText: 'Replicate',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (var r = 1; r <= 12; r++)
                          DropdownMenuItem(value: r, child: Text('R$r')),
                      ],
                      onChanged: (v) => setState(() => _replicate = v ?? 1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _volume,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText: _drop ? 'Drop volume' : 'Volume',
                suffixText: _drop ? 'µL' : 'mL',
                border: const OutlineInputBorder(),
                errorText: _volumeMl == null ? 'Enter a volume' : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            if (_drop)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Drop plate: each drop has its own dilution and replicate (set them in Drops).',
                  style: t.bodySmall,
                ),
              )
            else ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Spreader on plate'),
                subtitle: const Text('Excluded from CFU/mL'),
                value: _spreader,
                onChanged: (v) => setState(() => _spreader = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Too numerous to count'),
                subtitle: const Text('Count is a lower bound'),
                value: _tntc,
                onChanged: (v) => setState(() => _tntc = v),
              ),
            ],
            TextField(
              controller: _notes,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            Card.filled(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('This plate alone ($ruleLabel)', style: t.labelMedium),
                    const SizedBox(height: 4),
                    Text(
                      est == null ? '—' : prettySci(est.toString()),
                      style: t.titleLarge,
                    ),
                    if (est != null && est.note.isNotEmpty)
                      Text(est.note, style: t.bodySmall),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: record == null
                  ? null
                  : () => Navigator.pop(context, record),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
