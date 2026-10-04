import '../core/calculator.dart';
import '../core/colour.dart';
import '../core/plate.dart';
import '../data/sample_info.dart';
import '../data/training_export.dart';
import 'l10n.dart';

/// Names of the app's options in the current language. The enums' own
/// `label`s stay in English for CSV files and backups.

extension PlatingMethodText on PlatingMethod {
  String get text => switch (this) {
    PlatingMethod.spread => tr.methodSpread,
    PlatingMethod.drop => tr.methodDrop,
    PlatingMethod.membrane => tr.methodMembrane,
  };
}

extension DropLayoutText on DropLayout {
  String get text => switch (this) {
    DropLayout.replicates => tr.layoutReplicates,
    DropLayout.dilutions => tr.layoutDilutions,
  };
}

extension ColourModeText on ColourMode {
  String get text => switch (this) {
    ColourMode.none => tr.colourOff,
    ColourMode.blueWhite => tr.colourBlueWhite,
    ColourMode.twoColours => tr.colourTwo,
  };

  /// Name of colour class [k].
  String className(int k) => switch ((this, k)) {
    (ColourMode.none, _) => tr.classAll,
    (ColourMode.blueWhite, 0) => tr.classWhite,
    (ColourMode.blueWhite, _) => tr.classBlue,
    (ColourMode.twoColours, 0) => tr.classColourA,
    (ColourMode.twoColours, _) => tr.classColourB,
  };
}

extension PlateFormatText on PlateFormat {
  String get text => switch (this) {
    PlateFormat.dish90 => tr.formatDish90,
    PlateFormat.dish60 => tr.formatDish60,
    PlateFormat.dish100 => tr.formatDish100,
    PlateFormat.dish150 => tr.formatDish150,
    PlateFormat.square100 => tr.formatSquare100,
    PlateFormat.square120 => tr.formatSquare120,
    PlateFormat.membrane47 => tr.formatMembrane47,
  };
}

extension CountingRuleText on CountingRule {
  String get text => switch (this) {
    CountingRule.dropPlate => tr.ruleDrop,
    CountingRule.membrane80 => tr.ruleMembrane80,
    CountingRule.membrane200 => tr.ruleMembrane200,
    _ => label, // FDA BAM, ISO 7218, 30–300
  };
}

extension TrainingSelectionText on TrainingSelection {
  String get text => switch (this) {
    TrainingSelection.checked => tr.trainingChecked,
    TrainingSelection.corrected => tr.trainingCorrected,
    TrainingSelection.all => tr.trainingAll,
  };
}

/// The calculator's note about how an estimate was made.
String estimateNote(Estimate e) {
  final range = '${e.rule.min}–${e.rule.max}';
  final n = e.note;
  if (n.isEmpty) return '';
  if (n.startsWith('all plates')) return tr.noteAllSpreaders;
  if (n.startsWith('no colonies')) return tr.noteNoColonies;
  if (n.startsWith('below')) return tr.noteBelowRange(range);
  if (n.startsWith('above')) return tr.noteAboveRange(range);
  if (n.startsWith('too numerous')) return tr.noteTntc;
  if (n.startsWith('no plate')) return tr.noteNoPlateInRange;
  return n;
}

/// e.g. "est. 1.2 × 10^4 CFU/mL" (use `prettySci` for superscripts).
String estimateText(Estimate e, {double factor = 1, String unit = 'CFU/mL'}) {
  if (e.value.isNaN) return tr.noEstimate;
  final q = switch (e.qualifier) {
    Qualifier.exact => '',
    Qualifier.estimated => tr.estimatePrefix,
    Qualifier.lessThan => '< ',
    Qualifier.greaterThan => '> ',
  };
  return '$q${formatSci(e.value * factor)} $unit';
}
