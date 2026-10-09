import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/plate.dart';
import '../core/zones.dart';
import '../data/plate_store.dart';
import '../data/zone_record.dart';
import '../l10n/l10n.dart';
import '../l10n/labels.dart';
import 'insets.dart';

/// Plate types zone plates come on.
const List<PlateFormat> kZoneFormats = [
  PlateFormat.dish90,
  PlateFormat.dish100,
  PlateFormat.dish150,
  PlateFormat.square100,
  PlateFormat.square120,
];

/// What the setup sheet returns: the setup, and how to get the photo.
typedef ZoneSetupChoice = ({ZoneSetup setup, bool fromGallery});

/// The replicate after the highest one already saved for [experiment] and
/// [organism], or [fallback] when there is none.
int nextZoneReplicate(
  PlateStore store,
  String experiment,
  String organism, {
  int fallback = 1,
}) {
  var top = 0;
  for (final r in store.zoneRecords) {
    if (r.experiment == experiment && r.organism == organism) {
      if (r.replicate > top) top = r.replicate;
    }
  }
  return top == 0 ? fallback : top + 1;
}

/// Asks for the method, plate, organism, experiment, replicate and labels
/// before a zone plate is photographed. The choices are remembered.
Future<ZoneSetupChoice?> showZoneSetupSheet(
  BuildContext context,
  PlateStore store,
) => showModalBottomSheet<ZoneSetupChoice>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => ZoneSetupSheet(store: store),
);

/// Edits a saved zone plate's experiment, organism and replicate.
Future<ZoneSetup?> showZoneDetailsSheet(
  BuildContext context,
  PlateStore store,
  ZoneRecord record,
) async {
  final choice = await showModalBottomSheet<ZoneSetupChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ZoneSetupSheet(
      store: store,
      details: ZoneSetup(
        assay: record.assay,
        diskMm: record.diskMm,
        format: record.format,
        experiment: record.experiment,
        organism: record.organism,
        replicate: record.replicate,
        panel: record.panel,
      ),
    ),
  );
  return choice?.setup;
}

/// The setup form. With [details] (a saved plate), only the experiment,
/// organism and replicate can be changed.
class ZoneSetupSheet extends StatefulWidget {
  const ZoneSetupSheet({super.key, required this.store, this.details});

  final PlateStore store;
  final ZoneSetup? details;

  @override
  State<ZoneSetupSheet> createState() => _ZoneSetupSheetState();
}

class _ZoneSetupSheetState extends State<ZoneSetupSheet> {
  PlateStore get store => widget.store;
  bool get _details => widget.details != null;
  late final ZoneSetup _start = widget.details ?? store.zoneSetup;

  late ZoneAssay _assay = _start.assay;
  late PlateFormat _format = kZoneFormats.contains(_start.format)
      ? _start.format
      : PlateFormat.dish90;
  late final _size = TextEditingController(text: _fmt(_start.diskMm));
  late final _experiment = TextEditingController(text: _start.experiment);
  late final _organism = TextEditingController(text: _start.organism);
  late int _replicate = _details
      ? _start.replicate
      : nextZoneReplicate(
          store,
          _start.experiment,
          _start.organism,
          fallback: _start.replicate,
        );
  late String _panel = store.zonePanels.any((p) => p.name == _start.panel)
      ? _start.panel
      : '';

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  double? get _sizeMm {
    final v = double.tryParse(_size.text.trim().replaceAll(',', '.'));
    return v != null && v >= 3 && v <= 15 ? v : null;
  }

  ZoneSetup get _setup => ZoneSetup(
    assay: _assay,
    diskMm: _sizeMm ?? 6,
    format: _format,
    experiment: _experiment.text.trim(),
    organism: _organism.text.trim(),
    replicate: _replicate,
    panel: _panel,
  );

  @override
  void dispose() {
    _size.dispose();
    _experiment.dispose();
    _organism.dispose();
    super.dispose();
  }

  Future<void> _done(bool fromGallery) async {
    final setup = _setup;
    if (!_details) await store.setZoneSetup(setup);
    if (!mounted) return;
    Navigator.pop(context, (setup: setup, fromGallery: fromGallery));
  }

  Future<void> _newPanel() async {
    final panel = await showDialog<ZonePanel>(
      context: context,
      builder: (_) => const _PanelDialog(),
    );
    if (panel == null) return;
    await store.savePanel(panel);
    if (mounted) setState(() => _panel = panel.name);
  }

  Widget _suggestField(
    TextEditingController c,
    String label,
    List<String> options, {
    String? hint,
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
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final panel = store.zonePanels.where((p) => p.name == _panel).firstOrNull;
    final sizeOk = _sizeMm != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: scrollPadding(
          context,
          const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _details ? tr.zoneDetails : tr.zoneSetupTitle,
              style: t.titleLarge,
            ),
            const SizedBox(height: 16),
            if (!_details) ...[
              Text(tr.zoneAssay, style: t.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<ZoneAssay>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: ZoneAssay.disk,
                    label: Text(tr.zoneAssayDisk),
                  ),
                  ButtonSegment(
                    value: ZoneAssay.well,
                    label: Text(tr.zoneAssayWell),
                  ),
                ],
                selected: {_assay},
                onSelectionChanged: (s) => setState(() => _assay = s.first),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('zoneSize'),
                      controller: _size,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: _assay == ZoneAssay.disk
                            ? tr.zoneDiskSize
                            : tr.zoneWellSize,
                        errorText: sizeOk ? null : tr.zoneSizeInvalid,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<PlateFormat>(
                      isExpanded: true,
                      initialValue: _format,
                      decoration: InputDecoration(
                        labelText: tr.reviewPlateType,
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        for (final f in kZoneFormats)
                          DropdownMenuItem(
                            value: f,
                            child: Text(
                              f.text,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (f) => setState(() => _format = f ?? _format),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            _suggestField(
              _organism,
              tr.zoneOrganism,
              store.zoneOrganisms(),
              hint: tr.zoneOrganismHint,
            ),
            const SizedBox(height: 12),
            _suggestField(
              _experiment,
              tr.zoneExperiment,
              store.zoneExperiments(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: Text(tr.zoneReplicate, style: t.titleSmall)),
                IconButton(
                  onPressed: _replicate > 1
                      ? () => setState(() => _replicate--)
                      : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 32,
                  child: Text(
                    '$_replicate',
                    textAlign: TextAlign.center,
                    style: t.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _replicate++),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            if (!_details) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('panel$_panel'),
                      isExpanded: true,
                      initialValue: _panel,
                      decoration: InputDecoration(
                        labelText: tr.zonePanel,
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: '',
                          child: Text(tr.zonePanelNone),
                        ),
                        for (final p in store.zonePanels)
                          DropdownMenuItem(
                            value: p.name,
                            child: Text(
                              p.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _panel = v ?? ''),
                    ),
                  ),
                  IconButton(
                    tooltip: tr.zonePanelNew,
                    onPressed: _newPanel,
                    icon: const Icon(Icons.playlist_add),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: Text(
                  panel == null
                      ? tr.zonePanelHelp
                      : '${panel.labels.join(' · ')}\n${tr.zonePanelHelp}',
                  style: t.bodySmall,
                ),
              ),
              const SizedBox(height: 12),
              Text(tr.zoneCaptureTip, style: t.bodyMedium),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: sizeOk ? () => _done(true) : null,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(tr.zoneFromGallery),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: sizeOk ? () => _done(false) : null,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: Text(tr.zoneTakePhoto),
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _done(false),
                child: Text(tr.multiDone),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A new list of test-item labels.
class _PanelDialog extends StatefulWidget {
  const _PanelDialog();

  @override
  State<_PanelDialog> createState() => _PanelDialogState();
}

class _PanelDialogState extends State<_PanelDialog> {
  final _name = TextEditingController();
  final _labels = TextEditingController();

  List<String> get _list => [
    for (final l in _labels.text.split('\n'))
      if (l.trim().isNotEmpty) l.trim(),
  ];

  @override
  void dispose() {
    _name.dispose();
    _labels.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _name.text.trim().isNotEmpty && _list.isNotEmpty;
    return AlertDialog(
      title: Text(tr.zonePanelNew),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _name,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: tr.zonePanelName,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _labels,
                minLines: 4,
                maxLines: 8,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: tr.zonePanelLabels,
                  helperText: tr.zonePanelHelp,
                  helperMaxLines: 3,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr.homeCancel),
        ),
        FilledButton(
          onPressed: ok
              ? () =>
                    Navigator.pop(context, ZonePanel(_name.text.trim(), _list))
              : null,
          child: Text(tr.multiDone),
        ),
      ],
    );
  }
}
