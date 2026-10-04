import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/calculator.dart';
import '../data/plate_record.dart';
import '../data/plate_store.dart';
import 'format.dart';
import 'photo_flow.dart';

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
  late bool _verified = widget.draft.verified;
  late final bool _membrane = widget.draft.format.membrane;
  late final _hours = TextEditingController(
    text: widget.draft.incubationH == null
        ? ''
        : _fmtVolume(widget.draft.incubationH!),
  );

  /// Bumped when a scanned label fills the fields, so they rebuild with it.
  int _scanned = 0;

  Future<void> _scanLabel() async {
    final label = await scanPlateLabel(context);
    if (label == null || !mounted) return;
    setState(() {
      _sample.text = label.sampleId;
      final d = label.dilutionExp;
      if (d != null && d >= 0 && d <= 10) _dilutionExp = d;
      final r = label.replicate;
      if (r != null && r >= 1 && r <= 12) _replicate = r;
      _scanned++;
    });
  }

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
      verified: _verified,
      incubationH: double.tryParse(_hours.text.trim().replaceAll(',', '.')),
      clearIncubation: _hours.text.trim().isEmpty,
    );
  }

  @override
  void dispose() {
    _sample.dispose();
    _volume.dispose();
    _notes.dispose();
    _hours.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final record = _build();
    final rule = widget.store.rule;
    final sample = _sample.text.trim();
    final membraneRule = widget.store.hasPlan(sample)
        ? widget.store.sampleInfo(sample).membraneRule
        : CountingRule.membrane80;
    final est = record?.estimateAlone(rule, membraneRule: membraneRule);
    final knownSamples = [
      for (final s in widget.store.allSamples()) s.sampleId,
    ];
    final ruleLabel = _drop
        ? CountingRule.dropPlate.label
        : _membrane
        ? membraneRule.label
        : rule.label;

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
                key: ValueKey('sample$_scanned'),
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
                    decoration: InputDecoration(
                      labelText: 'Sample ID',
                      helperText: 'Plates with the same sample ID are pooled for CFU/mL',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip: 'Scan plate label',
                        icon: const Icon(Icons.qr_code_scanner),
                        onPressed: _scanLabel,
                      ),
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
                      key: ValueKey('dilution$_scanned'),
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
                      key: ValueKey('replicate$_scanned'),
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
                labelText: _drop
                    ? 'Drop volume'
                    : _membrane
                    ? 'Volume filtered'
                    : 'Volume',
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
              controller: _hours,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Incubation time (optional)',
                suffixText: 'h',
                helperText: 'Hours since plating, for time-lapse photos',
                border: OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Checked every colony'),
              subtitle: const Text(
                'Use this plate as a reference count for accuracy tracking',
              ),
              value: _verified,
              onChanged: (v) => setState(() => _verified = v),
            ),
            const SizedBox(height: 8),
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
                      est == null
                          ? '—'
                          : prettySci(
                              _membrane
                                  ? est.describe(
                                      factor: 100,
                                      unit: 'CFU/100 mL',
                                    )
                                  : est.toString(),
                            ),
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
