// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get aboutTitle => 'About';

  @override
  String get aboutTagline =>
      'Count colonies (CFU) on agar plates with your phone camera.';

  @override
  String aboutVersion(String version, int build) {
    return 'Version $version (build $build)';
  }

  @override
  String get aboutDeveloper => 'Developer';

  @override
  String get aboutEmail => 'Email';

  @override
  String get aboutWebsite => 'Website';

  @override
  String get aboutSource => 'Source code';

  @override
  String get aboutLicense => 'Licence';

  @override
  String get aboutLicenseText =>
      'Free and open-source software. You may use, study, share and change it. Changed versions offered to others, including as a website, must share their source code under the same licence.';

  @override
  String get aboutOpenSource => 'Open-source licences';

  @override
  String get aboutOpenSourceSub => 'Libraries and fonts used by the app';

  @override
  String get aboutPrivacy => 'Privacy';

  @override
  String get aboutPrivacyText =>
      'Counting runs on this device. Photos and results stay on this device (or in this browser) unless you export or share them.';

  @override
  String get aboutIntendedUse => 'Intended use';

  @override
  String get aboutIntendedUseText =>
      'For research and teaching. Not a medical or diagnostic device. Always check the automatic count.';

  @override
  String aboutCopyright(int year, String developer) {
    return '© $year $developer';
  }

  @override
  String aboutCannotOpen(String target) {
    return 'Could not open $target';
  }

  @override
  String get aboutPrivacyPolicy => 'Privacy policy';

  @override
  String get aboutStand => '3D-printed photo stand';

  @override
  String get sampleKind => 'Sample';

  @override
  String get sampleLiquid => 'Liquid (CFU/mL)';

  @override
  String get sampleSolid => 'Solid (CFU/g)';

  @override
  String get sampleWeight => 'Sample weight';

  @override
  String get diluentVolume => 'Diluent';

  @override
  String get solidTenfold =>
      'The initial suspension is 1:10, so it is the 10⁻¹ dilution. Label plates with the total dilution of the sample (e.g. 10⁻² for the next tube).';

  @override
  String solidOther(String ratio, String factor) {
    return 'The initial suspension is 1:$ratio. Label plates as if it were the 10⁻¹ dilution; results are corrected by ×$factor.';
  }

  @override
  String get homeSamples => 'Samples';

  @override
  String get homeCompare => 'Compare';

  @override
  String get homePlates => 'Plates';

  @override
  String get homeSeveralPlates => 'Several plates in one photo';

  @override
  String get homeImportPhoto => 'Import photo';

  @override
  String get homeScanLabel => 'Scan plate label';

  @override
  String get homeCountPlate => 'Count plate';

  @override
  String get homeNewSample => 'New sample';

  @override
  String get homeShareCounts => 'Colony counts';

  @override
  String get homeShareTraining => 'Colony Counter training data';

  @override
  String get homeShareBackup => 'Colony Counter backup';

  @override
  String get homeExportTraining => 'Export training data';

  @override
  String get homeTrainingInfo =>
      'Photos with every colony mark, in COCO and YOLO formats, for training a colony detector on your own plates.';

  @override
  String get homeNoPlatesToExport => 'No plates to export.';

  @override
  String get homePreparingExport => 'Preparing export…';

  @override
  String get homePreparingBackup => 'Preparing backup…';

  @override
  String homeNPlates(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n plates',
      one: '1 plate',
    );
    return '$_temp0';
  }

  @override
  String homeNSamples(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n samples',
      one: '1 sample',
    );
    return '$_temp0';
  }

  @override
  String homeRestored(String plates, String samples) {
    return 'Restored $plates and $samples.';
  }

  @override
  String homeRestoredKept(String plates, String samples, int skipped) {
    return 'Restored $plates and $samples ($skipped already here, kept).';
  }

  @override
  String get homeExportCsv => 'Export CSV';

  @override
  String get homeBackUpAll => 'Back up all data';

  @override
  String get homeRestore => 'Restore from backup';

  @override
  String get homeSettings => 'Settings';

  @override
  String get homeCountingRule => 'Counting rule';

  @override
  String homeCountableRange(int min, int max) {
    return 'Countable range: $min–$max colonies per plate';
  }

  @override
  String get homeDefaultVolume => 'Default plated volume';

  @override
  String get homeDefaultPlateType => 'Default plate type';

  @override
  String get homeDefaultPlateTypeHelp => 'For quick counts and new samples';

  @override
  String get homeNoPlates => 'No plates yet';

  @override
  String get homeEmptyHint =>
      'Place a 90 mm Nutrient Agar plate in the lightbox with the lid off, then tap “Count plate”.';

  @override
  String get homeDeletePlate => 'Delete plate?';

  @override
  String get homeDeletePlateBody =>
      'The photo and its count will be removed from this phone.';

  @override
  String get homeCancel => 'Cancel';

  @override
  String get homeDelete => 'Delete';

  @override
  String get homeFlagged => 'Flagged for checking';

  @override
  String get homeChecked => 'Checked every colony';

  @override
  String get homeTimelapse => 'Time-lapse';

  @override
  String get accuracyTitle => 'Counting accuracy';

  @override
  String get accuracyNoChecked => 'No checked plates yet';

  @override
  String get accuracyHowTo =>
      'Now and then, check every colony on a plate: zoom in, remove wrong marks, add missed colonies, and set clusters. Then turn on \"Checked every colony\" when saving. The app compares its own count with yours and shows here how accurate it is on your plates.';

  @override
  String accuracyCheckedPlates(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n checked plates',
      one: '1 checked plate',
    );
    return '$_temp0';
  }

  @override
  String accuracyWithin10(String pct) {
    return '$pct % of plates within ±10 %';
  }

  @override
  String accuracyOfChecked(String plates) {
    return 'of the checked count · $plates';
  }

  @override
  String get accuracyMeanError => 'mean error';

  @override
  String get accuracyBias => 'bias';

  @override
  String get accuracyColoniesOff => 'colonies off, on average';

  @override
  String get accuracyPrecision => 'of marks were colonies';

  @override
  String get accuracyRecall => 'of colonies found';

  @override
  String get accuracyFootnote =>
      'Percentages use plates with 10 or more colonies. Negative bias means the app counts too few.';

  @override
  String get accuracyScatterTitle => 'Automatic vs checked count';

  @override
  String get accuracyNotFlagged => 'Not flagged';

  @override
  String get accuracyScatterHint =>
      'Tap a dot for details. Dots below the line: the app counted too few. Shaded: within ±10 %.';

  @override
  String accuracyPointDetail(String plate, String date, int auto, int checked) {
    return '$plate · $date: app $auto, checked $checked';
  }

  @override
  String get accuracyAxisChecked => 'checked count →';

  @override
  String accuracyRangeColonies(String range) {
    return '$range colonies';
  }

  @override
  String get accuracyErrorsTitle => 'Where the errors are';

  @override
  String get accuracyColPlates => 'plates';

  @override
  String get accuracyWarningsUseful =>
      'If the warnings are useful, flagged plates have the larger errors.';

  @override
  String get accuracyCheckedPlatesTitle => 'Checked plates';

  @override
  String accuracyAppVsChecked(int auto, int checked) {
    return 'app $auto · checked $checked';
  }

  @override
  String get accuracyAskCheck => 'Ask me to check a plate';

  @override
  String get accuracyNever => 'Never';

  @override
  String accuracyEvery(int n) {
    return 'Every ${n}th';
  }

  @override
  String get accuracyAskCheckHelp =>
      'The review screen then asks you to check every colony on that plate before saving.';

  @override
  String timelapseHours(String h) {
    return '$h h';
  }

  @override
  String get timelapseNoPhotos => 'No photos in this series.';

  @override
  String get timelapseShareCsv => 'Share colony table (CSV)';

  @override
  String get timelapseAddLater => 'Add a later photo';

  @override
  String timelapsePhotos(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n photos',
      one: '1 photo',
    );
    return '$_temp0';
  }

  @override
  String get timelapseSincePlating => 'hours since plating';

  @override
  String get timelapseSinceFirst => 'hours since the first photo';

  @override
  String timelapseColoniesAt(int n, String time) {
    return '$n colonies at $time';
  }

  @override
  String timelapseAppeared(int n, String time) {
    return '$n appeared after the first photo · half had appeared by $time';
  }

  @override
  String timelapseGrowth(String rate) {
    return 'Median growth $rate mm/h in diameter';
  }

  @override
  String get timelapseAddLaterHint =>
      'Add a later photo of the same plate to see when colonies appear and how fast they grow.';

  @override
  String get timelapseMatching =>
      'Colonies are matched between photos by position, after turning and mirroring the earlier photo to fit the later one. Put the plate the same way up each time if few colonies are visible early on.';

  @override
  String get timelapseChartTitle => 'Colonies counted over time';

  @override
  String get timelapsePhotosTitle => 'Photos';

  @override
  String timelapsePhotoRow(String time, int n) {
    return '$time · $n colonies';
  }

  @override
  String timelapseFirstSeen(int n) {
    return '$n first seen here';
  }

  @override
  String timelapseTurned(int deg) {
    return 'turned $deg° to fit the next';
  }

  @override
  String timelapseTurnedMirrored(int deg) {
    return 'turned $deg°, mirrored to fit the next';
  }

  @override
  String get timelapseAppearanceTitle => 'When each colony appeared';

  @override
  String timelapseBy(String time) {
    return 'by $time';
  }

  @override
  String get compareEmpty =>
      'Give samples the same Experiment name and a Condition (e.g. Control / Treated), and optionally a time point, to compare them here: log reduction, % kill, and time-kill or growth curves.';

  @override
  String get compareExperiment => 'Experiment';

  @override
  String get compareControl => 'Control';

  @override
  String compareOverTime(String unit) {
    return 'log₁₀ $unit over time';
  }

  @override
  String get compareChartHint =>
      'Mean ± SD of replicates; tap a point for its value.';

  @override
  String get compareResults => 'Results';

  @override
  String get compareCondition => 'Condition';

  @override
  String compareReductionVs(String control) {
    return 'Reduction vs $control';
  }

  @override
  String get compareReductionHelp =>
      'log reduction = mean log₁₀(control) − mean log₁₀(treated); SD combines both groups. % kill from the geometric means.';

  @override
  String get compareTime => 'Time';

  @override
  String get compareLogReduction => 'log reduction';

  @override
  String get compareKill => '% kill';

  @override
  String get compareSamples => 'Samples';

  @override
  String get appTitle => 'Colony Counter';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get languageSystem => 'Phone setting';

  @override
  String get settingsTheme => 'Appearance';

  @override
  String get themeSystem => 'Automatic';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get restoreNotZip =>
      'This file is not a Colony Counter backup (not a zip).';

  @override
  String get restoreNotBackup => 'This zip is not a Colony Counter backup.';

  @override
  String get methodFilm => 'Petrifilm (dry film)';

  @override
  String get formatFilmAc => 'Petrifilm AC (aerobic count)';

  @override
  String get formatFilmEc => 'Petrifilm EC (E. coli/coliform)';

  @override
  String get formatFilmCc => 'Petrifilm CC (coliform)';

  @override
  String get formatFilmEb => 'Petrifilm EB (Enterobacteriaceae)';

  @override
  String get formatFilmYm => 'Petrifilm YM (yeast & mold)';

  @override
  String get setupFilm => 'Film';

  @override
  String get filmType => 'Film type';

  @override
  String filmRangeFromType(int min, int max) {
    return 'Counting range $min–$max per film, from the film type. Volume is usually 1 mL.';
  }

  @override
  String get resultAerobic => 'Aerobic count';

  @override
  String get resultEcoli => 'E. coli';

  @override
  String get resultColiform => 'Coliforms';

  @override
  String get resultEnterobacteriaceae => 'Enterobacteriaceae';

  @override
  String get resultYeast => 'Yeasts';

  @override
  String get resultMold => 'Molds';

  @override
  String get kindColony => 'Colony';

  @override
  String get kindRed => 'Red';

  @override
  String get kindBlue => 'Blue';

  @override
  String get kindYeast => 'Yeast';

  @override
  String get kindMold => 'Mold';

  @override
  String get reviewModeKind => 'Kind';

  @override
  String get reviewModeGas => 'Gas';

  @override
  String get reviewModeSquares => 'Squares';

  @override
  String get reviewHintSquares =>
      'Tap a grid square to leave it out of the estimate (a bubble, a fold, a spreader), or tap it again to add it back.';

  @override
  String reviewFilmSquaresLeftOut(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n squares left out.',
      one: '1 square left out.',
    );
    return '$_temp0';
  }

  @override
  String reviewFilmGasSplit(String kind, int withGas, int without) {
    return '$kind: $withGas with gas, $without without';
  }

  @override
  String get reviewModeYellow => 'Zone';

  @override
  String reviewHintKind(Object a, Object b) {
    return 'Tap a colony to switch it between $a and $b.';
  }

  @override
  String get reviewHintGas =>
      'Tap a colony to mark or unmark a gas bubble next to it (white ring).';

  @override
  String get reviewHintYellow =>
      'Tap a colony to mark or unmark a yellow zone around it (yellow ring).';

  @override
  String reviewFilmMarks(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'marks',
      one: 'mark',
    );
    return '$_temp0';
  }

  @override
  String reviewFilmRedNoGas(int n) {
    return '$n red without gas (not counted)';
  }

  @override
  String reviewFilmNotCounted(int n) {
    return '$n not counted (no gas or zone)';
  }

  @override
  String reviewFilmEstimate(int n) {
    return 'Above the counting range: estimated from $n complete grid squares × 20 cm².';
  }

  @override
  String get reviewFilmFewSquares =>
      'Above the counting range, but fewer than 3 complete grid squares were found, so the count is shown.';

  @override
  String get reviewFilmNoGrid =>
      'The printed grid was not found, so the scale and this count may be wrong. Is this a Petrifilm plate, flat, in focus and without glare? Retake the photo or check every colony.';

  @override
  String get reviewFilmAid =>
      'Automatic film counts are an aid: check them against the interpretation guide.';

  @override
  String get flagEstimated => 'Estimated from squares';

  @override
  String get flagGridNotFound => 'Grid not found';

  @override
  String get flagAreaSize => 'Growth area size unexpected';

  @override
  String get captureFilmTip =>
      'Lay the film flat on a plain background, photograph straight down and avoid glare on the clear top film.';

  @override
  String get aboutPetrifilmTitle => 'Dry films';

  @override
  String get aboutPetrifilm =>
      'Reads Neogen® Petrifilm® AC, EC, CC, EB and YM plates. Petrifilm and Neogen are trademarks of Neogen Corporation; this app is not made or endorsed by Neogen. Counts are an aid to be checked, not an AOAC-validated result.';

  @override
  String get photoReadingLabel => 'Reading label…';

  @override
  String get photoNoLabelFound =>
      'No plate label found. Fill the frame with the QR code and try again.';

  @override
  String captureLockNotSupported(String error) {
    return 'Lock not supported: $error';
  }

  @override
  String captureFailed(String error) {
    return 'Capture failed: $error';
  }

  @override
  String get capturePhotographPlate => 'Photograph plate';

  @override
  String captureCameraUnavailable(String error) {
    return 'Camera unavailable: $error';
  }

  @override
  String get captureLevel => 'Level';

  @override
  String captureTilt(String deg) {
    return 'Tilt $deg°';
  }

  @override
  String get captureSharp => 'Sharp';

  @override
  String get captureFocusing => 'Focusing…';

  @override
  String get captureNoGlare => 'No glare';

  @override
  String get captureGlare => 'Glare: remove lid / dim light';

  @override
  String get captureUnlock => 'Unlock focus & exposure';

  @override
  String get captureLock => 'Lock focus & exposure';

  @override
  String get multiRoundOnly =>
      'Several plates in one photo works with round dishes only.';

  @override
  String get multiLayPlates =>
      'Lay the plates side by side, lids off, on a dark surface, and photograph them from straight above.';

  @override
  String get multiTakePhoto => 'Take photo';

  @override
  String get multiChoosePhoto => 'Choose photo';

  @override
  String get multiNoPlatesFound => 'No plates found in this photo.';

  @override
  String get multiPlatesInPhoto => 'Plates in photo';

  @override
  String multiPlatesFound(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n plates found',
      one: '1 plate found',
    );
    return '$_temp0';
  }

  @override
  String get multiDone => 'Done';

  @override
  String get multiAddRemove => 'Add or remove plates';

  @override
  String get multiEditHint =>
      'Tap a circle to remove it, or tap the centre of a missed plate to add one.';

  @override
  String get multiUsePencil => 'Use the pencil to mark the plates.';

  @override
  String get multiAllSaved => 'All plates are saved.';

  @override
  String multiTapToCount(int n) {
    return 'Tap a plate to count it. $n still to save.';
  }

  @override
  String get reviewPhotoMissing => 'The photo for this plate is missing.';

  @override
  String reviewCouldNotCount(String error) {
    return 'Could not count this photo: $error';
  }

  @override
  String get reviewRecountTitle => 'Recount plate?';

  @override
  String get reviewRecountBody =>
      'Your manual additions and removals will be discarded.';

  @override
  String get reviewCancel => 'Cancel';

  @override
  String get reviewRecount => 'Recount';

  @override
  String get reviewPlateType => 'Plate type';

  @override
  String get reviewShareSubject => 'Colony count';

  @override
  String reviewCouldNotShare(String error) {
    return 'Could not share the photo: $error';
  }

  @override
  String get reviewDiscardTitle => 'Discard this count?';

  @override
  String get reviewDiscardBody => 'It has not been saved.';

  @override
  String get reviewKeep => 'Keep';

  @override
  String get reviewDiscard => 'Discard';

  @override
  String get reviewTitle => 'Review count';

  @override
  String get reviewUndo => 'Undo';

  @override
  String get reviewHideMarks => 'Hide marks';

  @override
  String get reviewShowMarks => 'Show marks';

  @override
  String get reviewHintMarksHidden =>
      'Marks are hidden, so you can look over the plate. Tap the eye to show them again and edit.';

  @override
  String get reviewSensitivity => 'Detection sensitivity';

  @override
  String get reviewMenuTooltip => 'Plate type and colours';

  @override
  String get reviewShareAnnotated => 'Share annotated photo';

  @override
  String get reviewAddLaterPhoto => 'Add a later photo (time-lapse)';

  @override
  String get reviewTimelapse => 'Time-lapse';

  @override
  String reviewPlateTypeItem(String type) {
    return 'Plate type: $type…';
  }

  @override
  String get reviewDropPlate => 'Drop plate';

  @override
  String reviewColoursItem(String mode) {
    return 'Colours: $mode';
  }

  @override
  String get reviewCounting => 'Counting colonies…';

  @override
  String reviewAdded(int n) {
    return '+$n added';
  }

  @override
  String reviewRemoved(int n) {
    return '−$n removed';
  }

  @override
  String reviewInClusters(int n) {
    return '+$n in clusters';
  }

  @override
  String get reviewModeZoom => 'Zoom';

  @override
  String get reviewModeEdit => 'Edit';

  @override
  String get reviewModePlate => 'Plate';

  @override
  String get reviewModeDrops => 'Drops';

  @override
  String get reviewModeColour => 'Colour';

  @override
  String get reviewAutomatic => 'automatic';

  @override
  String reviewAutoEdits(int auto, String edits) {
    return 'auto $auto · $edits';
  }

  @override
  String get reviewHintZoom => 'Pinch to zoom, drag to pan.';

  @override
  String get reviewHintEdit =>
      'Tap a mark to remove it, tap empty agar to add one. Long-press a mark to set how many colonies it contains.';

  @override
  String get reviewHintSquare =>
      'Drag to move the square, use the sliders to resize and turn it, then recount.';

  @override
  String get reviewHintCircle =>
      'Drag to move the circle, use the slider to resize it, then recount.';

  @override
  String get reviewHintDrops =>
      'Tap a drop to set its dilution and replicate, tap empty agar to add a drop, drag a drop to move it.';

  @override
  String get reviewHintColour => 'Tap a colony to switch its colour class.';

  @override
  String get reviewSize => 'Size';

  @override
  String get reviewRecountSquare => 'Recount with this square';

  @override
  String get reviewRecountCircle => 'Recount with this circle';

  @override
  String get reviewSavePlate => 'Save plate';

  @override
  String get reviewSaveChanges => 'Save changes';

  @override
  String reviewCheckCount(String warnings) {
    return 'Check this count ($warnings). Zoom in and correct any missed or extra marks before saving.';
  }

  @override
  String get reviewAccuracyCheck =>
      'Accuracy check: please check every colony on this plate. It is saved as a reference count to track how well the automatic count works on your plates.';

  @override
  String reviewClassCount(String name, int n) {
    return '$name $n';
  }

  @override
  String reviewClassPercent(String percent, String name) {
    return '$percent % $name';
  }

  @override
  String get reviewNoDrops => 'No drops marked yet: use Drops to add them.';

  @override
  String get reviewClusterTitle => 'Colonies in this mark';

  @override
  String get reviewSet => 'Set';

  @override
  String get reviewSensitivityHelp =>
      'Higher finds fainter and smaller colonies but may count debris. Default: 6.5.';

  @override
  String get reviewLow => 'Low';

  @override
  String get reviewHigh => 'High';

  @override
  String reviewDropTitle(int index, int n) {
    return 'Drop $index · $n colonies';
  }

  @override
  String get reviewDilution => 'Dilution';

  @override
  String get reviewReplicate => 'Replicate';

  @override
  String get reviewTntc => 'Too numerous to count';

  @override
  String get reviewConfluent => 'Confluent drop';

  @override
  String reviewDropSize(String mm) {
    return 'Size $mm mm';
  }

  @override
  String get reviewDeleteDrop => 'Delete drop';

  @override
  String get reviewOk => 'OK';

  @override
  String samplesNotFoundTitle(Object id) {
    return 'Sample “$id” not found';
  }

  @override
  String get samplesSetUpNow => 'Set up this sample now?';

  @override
  String get samplesCancel => 'Cancel';

  @override
  String get samplesSetUp => 'Set up';

  @override
  String get samplesPhotographNow => 'Photograph this plate now?';

  @override
  String get samplesJustOpen => 'Just open sample';

  @override
  String get samplesPhotograph => 'Photograph';

  @override
  String samplesAlreadyCounted(Object plate) {
    return '$plate is already counted.';
  }

  @override
  String get samplesNoResult => 'No result yet';

  @override
  String get samplesEstimated => 'est.';

  @override
  String samplesHours(Object h) {
    return '$h h';
  }

  @override
  String get samplesEmpty =>
      'Set up a sample to plan its dilution series and replicates. The app then tells you which plate to photograph next and reports mean ± SD and log₁₀ CFU/mL across replicates.';

  @override
  String get samplesSearchHint => 'Search sample, strain, operator, tag…';

  @override
  String get samplesNoMatch => 'No samples match.';

  @override
  String get samplesNoExperiment => 'No experiment';

  @override
  String samplesPlatesDone(int done, int total) {
    return '$done/$total plates';
  }

  @override
  String samplesPlateCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n plates',
      one: '1 plate',
    );
    return '$_temp0';
  }

  @override
  String get samplesSlotPlate => 'plate';

  @override
  String samplesLabelsSubject(Object id) {
    return 'Plate labels for $id';
  }

  @override
  String samplesDeleteTitle(Object id) {
    return 'Delete $id?';
  }

  @override
  String get samplesDeletePlanOnly => 'The sample plan will be removed.';

  @override
  String samplesDeleteAsk(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n plates',
      one: '1 plate',
    );
    return 'Remove only the plan and keep its $_temp0, or delete the plates too?';
  }

  @override
  String get samplesKeepPlates => 'Keep plates';

  @override
  String get samplesDeleteAll => 'Delete all';

  @override
  String get samplesDelete => 'Delete';

  @override
  String get samplesEditPlan => 'Edit plan';

  @override
  String get samplesCreatePlan => 'Create plan';

  @override
  String get samplesNewLikeThis => 'New sample like this';

  @override
  String get samplesMulti => 'Photograph several plates at once';

  @override
  String get samplesPrintLabels => 'Print plate labels (PDF)';

  @override
  String get samplesDeleteSample => 'Delete sample';

  @override
  String get samplesPlates => 'Plates';

  @override
  String samplesDropsUl(Object v) {
    return '$v µL drops';
  }

  @override
  String samplesMlFiltered(Object v) {
    return '$v mL filtered';
  }

  @override
  String samplesMlPerPlate(Object v) {
    return '$v mL per plate';
  }

  @override
  String samplesPhotographSlot(Object slot) {
    return 'Photograph $slot';
  }

  @override
  String samplesImportFor(Object slot) {
    return 'Import photo for $slot';
  }

  @override
  String get samplesAllDone => 'All planned plates are done.';

  @override
  String get samplesNoPlan =>
      'This sample has no plan (its plates were saved one by one). Use “Create plan” in the menu for a guided plate list.';

  @override
  String get samplesNoCountable => 'No countable plates yet';

  @override
  String samplesReplicateCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n replicates',
      one: '1 replicate',
    );
    return 'n = $_temp0';
  }

  @override
  String samplesPoolDrops(Object range, Object rule) {
    return 'Each replicate pools its countable drops ($range colonies, $rule) as ΣC / Σ(V × d); log₁₀ is the mean ± SD of the replicates\' log values.';
  }

  @override
  String samplesPoolFilters(Object range, Object rule) {
    return 'Each replicate pools its countable filters ($range colonies, $rule) as ΣC / Σ(V × d); log₁₀ is the mean ± SD of the replicates\' log values.';
  }

  @override
  String samplesPoolPlates(Object range, Object rule) {
    return 'Each replicate pools its countable plates ($range colonies, $rule) as ΣC / Σ(V × d); log₁₀ is the mean ± SD of the replicates\' log values.';
  }

  @override
  String get samplesStrain => 'Strain';

  @override
  String get samplesMedium => 'Medium';

  @override
  String samplesBatch(Object batch) {
    return 'batch $batch';
  }

  @override
  String get samplesIncubation => 'Incubation';

  @override
  String samplesIncubationAt(Object hours, Object temp) {
    return '$hours at $temp';
  }

  @override
  String get samplesOperator => 'Operator';

  @override
  String get samplesTags => 'Tags';

  @override
  String get samplesNotes => 'Notes';

  @override
  String get samplesDetails => 'Details';

  @override
  String get setupRequired => 'Required';

  @override
  String get setupIdTaken => 'This sample ID already exists';

  @override
  String get setupNewSample => 'New sample';

  @override
  String setupEditTitle(Object id) {
    return 'Edit $id';
  }

  @override
  String get setupSampleId => 'Sample ID';

  @override
  String get setupExperiment => 'Experiment (optional)';

  @override
  String get setupExperimentHelp => 'Samples of one experiment can be compared';

  @override
  String get setupCondition => 'Condition';

  @override
  String get setupConditionHelp => 'e.g. Control, 1 % NaOCl';

  @override
  String get setupTimePoint => 'Time point';

  @override
  String get setupHoursUnit => 'h';

  @override
  String get setupOptional => 'optional';

  @override
  String get setupPlating => 'Plating';

  @override
  String get setupSpread => 'Spread';

  @override
  String get setupDrop => 'Drop';

  @override
  String get setupMembrane => 'Membrane';

  @override
  String get setupMembraneRange => 'Countable range per filter';

  @override
  String get setupMembraneUnit => 'Results are reported as CFU/100 mL';

  @override
  String get setupPlateType => 'Plate type';

  @override
  String get setupFrom => 'From';

  @override
  String get setupTo => 'To';

  @override
  String get setupReplicates => 'Replicates';

  @override
  String get setupVolumeFiltered => 'Volume filtered';

  @override
  String get setupVolumePerPlate => 'Volume per plate';

  @override
  String get setupDropVolume => 'Drop volume';

  @override
  String setupFilterCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n filters',
      one: '1 filter',
    );
    return '$_temp0.';
  }

  @override
  String setupPlateCount(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n plates',
      one: '1 plate',
    );
    return '$_temp0.';
  }

  @override
  String setupPlateCountDrops(int n, int drops) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n plates',
      one: '1 plate',
    );
    return '$_temp0 with $drops drops each.';
  }

  @override
  String get setupColonyColours => 'Colony colours';

  @override
  String get setupColourNone => 'All colonies are counted together.';

  @override
  String get setupColourBlueWhite =>
      'Blue and white colonies are counted separately (X-gal screening).';

  @override
  String get setupColourTwo =>
      'Colonies are split into two colour groups (e.g. chromogenic agar).';

  @override
  String get setupNotes => 'Notes';

  @override
  String get setupSave => 'Save sample';

  @override
  String get setupDetails => 'Experiment details';

  @override
  String get setupDetailsSummary =>
      'Strain, medium, incubation, operator, tags';

  @override
  String get setupStrain => 'Strain / organism';

  @override
  String get setupMedium => 'Medium';

  @override
  String get setupBatch => 'Batch / lot';

  @override
  String get setupIncubation => 'Incubation';

  @override
  String get setupTemperature => 'Temperature';

  @override
  String get setupOperator => 'Operator';

  @override
  String get setupTags => 'Tags';

  @override
  String get setupTagsHelp => 'Comma-separated, e.g. thesis, batch 3';

  @override
  String get saveSheetTitle => 'Plate details';

  @override
  String get saveSheetSampleId => 'Sample ID';

  @override
  String get saveSheetSampleHelp =>
      'Plates with the same sample ID are pooled for CFU/mL';

  @override
  String get saveSheetScan => 'Scan plate label';

  @override
  String get saveSheetDilution => 'Plated dilution';

  @override
  String get saveSheetReplicate => 'Replicate';

  @override
  String get saveSheetDropVolume => 'Drop volume';

  @override
  String get saveSheetVolumeFiltered => 'Volume filtered';

  @override
  String get saveSheetVolume => 'Volume';

  @override
  String get saveSheetEnterVolume => 'Enter a volume';

  @override
  String get saveSheetDropNote =>
      'Drop plate: each drop has its own dilution and replicate (set them in Drops).';

  @override
  String get saveSheetSpreader => 'Spreader on plate';

  @override
  String get saveSheetSpreaderHelp => 'Excluded from CFU/mL';

  @override
  String get saveSheetTntc => 'Too numerous to count';

  @override
  String get saveSheetTntcHelp => 'Count is a lower bound';

  @override
  String get saveSheetIncubation => 'Incubation time (optional)';

  @override
  String get saveSheetHoursUnit => 'h';

  @override
  String get saveSheetIncubationHelp =>
      'Hours since plating, for time-lapse photos';

  @override
  String get saveSheetVerified => 'Checked every colony';

  @override
  String get saveSheetVerifiedHelp =>
      'Use this plate as a reference count for accuracy tracking';

  @override
  String get saveSheetNotes => 'Notes';

  @override
  String saveSheetAlone(Object rule) {
    return 'This plate alone ($rule)';
  }

  @override
  String get saveSheetSave => 'Save';

  @override
  String get methodSpread => 'Spread / pour plate';

  @override
  String get methodDrop => 'Drop plate (Miles–Misra)';

  @override
  String get methodMembrane => 'Membrane filtration';

  @override
  String get layoutReplicates => 'One dilution per plate, drops = replicates';

  @override
  String get layoutDilutions => 'All dilutions on one plate, one drop each';

  @override
  String get colourOff => 'Off';

  @override
  String get colourBlueWhite => 'Blue / white';

  @override
  String get colourTwo => 'Two colours';

  @override
  String get classAll => 'All';

  @override
  String get classWhite => 'White';

  @override
  String get classBlue => 'Blue';

  @override
  String get classColourA => 'Colour A';

  @override
  String get classColourB => 'Colour B';

  @override
  String get formatDish90 => '90 mm dish';

  @override
  String get formatDish60 => '60 mm dish';

  @override
  String get formatDish100 => '100 mm dish';

  @override
  String get formatDish150 => '150 mm dish';

  @override
  String get formatSquare100 => '100 mm square plate';

  @override
  String get formatSquare120 => '120 mm square plate';

  @override
  String get formatMembrane47 => '47 mm membrane filter';

  @override
  String get ruleDrop => 'Drop 3–30';

  @override
  String get ruleMembrane80 => 'Membrane 20–80';

  @override
  String get ruleMembrane200 => 'Membrane 20–200';

  @override
  String get trainingChecked => 'Checked plates only';

  @override
  String get trainingCorrected => 'Checked and corrected plates';

  @override
  String get trainingAll => 'All plates';

  @override
  String get flagSpreader => 'Spreader';

  @override
  String get flagTntc => 'Too many to count';

  @override
  String get flagClusters => 'Clusters estimated';

  @override
  String get flagCrowded => 'Crowded plate';

  @override
  String get flagManyClusters => 'Many touching colonies';

  @override
  String get flagLowContrast => 'Faint colonies';

  @override
  String get neat => 'Neat';

  @override
  String get unlabelled => 'Unlabelled';

  @override
  String dropPlateDrops(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n drops',
      one: '1 drop',
    );
    return 'drop plate ($_temp0)';
  }

  @override
  String get noteAllSpreaders => 'all plates have spreaders';

  @override
  String get noteNoColonies => 'no colonies on least diluted plate';

  @override
  String noteBelowRange(Object range) {
    return 'below countable range ($range)';
  }

  @override
  String noteAboveRange(Object range) {
    return 'above countable range ($range)';
  }

  @override
  String get noteTntc => 'too numerous to count';

  @override
  String get noteNoPlateInRange => 'no plate in countable range';

  @override
  String get estimatePrefix => 'est. ';

  @override
  String get noEstimate => 'no estimate';
}
