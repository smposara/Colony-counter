import 'plate_record.dart';
import 'export_source.dart';

/// Which plates go into a training export.
enum TrainingSelection {
  /// Plates checked colony by colony: complete labels.
  checked('Checked plates only'),

  /// Checked plates plus any plate the user corrected: labels are complete
  /// where the user looked, but may miss colonies nobody checked.
  corrected('Checked and corrected plates'),

  /// Every saved plate, including uncorrected automatic counts.
  all('All plates');

  const TrainingSelection(this.label);
  final String label;
}

bool correctedPlate(PlateRecord r) =>
    r.rejected.isNotEmpty ||
    r.colonies.any((c) => c.manual) ||
    r.count != r.autoCount;

/// Plates matching [selection], newest first. Example plates (see
/// [isExamplePlate]) are never training data.
List<PlateRecord> trainingPlates(
  ExportSource store,
  TrainingSelection selection,
) => [
  for (final r in store.records)
    if (!isExamplePlate(store, r) &&
        switch (selection) {
          TrainingSelection.checked => r.verified,
          TrainingSelection.corrected => r.verified || correctedPlate(r),
          TrainingSelection.all => true,
        })
      r,
];
