import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_th.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('th'),
  ];

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutTitle;

  /// No description provided for @aboutTagline.
  ///
  /// In en, this message translates to:
  /// **'Count colonies (CFU) on agar plates with your phone camera.'**
  String get aboutTagline;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version} (build {build})'**
  String aboutVersion(String version, int build);

  /// No description provided for @aboutDeveloper.
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get aboutDeveloper;

  /// No description provided for @aboutEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get aboutEmail;

  /// No description provided for @aboutWebsite.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get aboutWebsite;

  /// No description provided for @aboutSource.
  ///
  /// In en, this message translates to:
  /// **'Source code'**
  String get aboutSource;

  /// No description provided for @aboutLicense.
  ///
  /// In en, this message translates to:
  /// **'Licence'**
  String get aboutLicense;

  /// No description provided for @aboutLicenseText.
  ///
  /// In en, this message translates to:
  /// **'Free and open-source software. You may use, study, share and change it. Changed versions offered to others, including as a website, must share their source code under the same licence.'**
  String get aboutLicenseText;

  /// No description provided for @aboutOpenSource.
  ///
  /// In en, this message translates to:
  /// **'Open-source licences'**
  String get aboutOpenSource;

  /// No description provided for @aboutOpenSourceSub.
  ///
  /// In en, this message translates to:
  /// **'Libraries and fonts used by the app'**
  String get aboutOpenSourceSub;

  /// No description provided for @aboutPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get aboutPrivacy;

  /// No description provided for @aboutPrivacyText.
  ///
  /// In en, this message translates to:
  /// **'Counting runs on this device. Photos and results stay on this device (or in this browser) unless you export or share them.'**
  String get aboutPrivacyText;

  /// No description provided for @aboutIntendedUse.
  ///
  /// In en, this message translates to:
  /// **'Intended use'**
  String get aboutIntendedUse;

  /// No description provided for @aboutIntendedUseText.
  ///
  /// In en, this message translates to:
  /// **'For research and teaching. Not a medical or diagnostic device. Always check the automatic count.'**
  String get aboutIntendedUseText;

  /// No description provided for @aboutCopyright.
  ///
  /// In en, this message translates to:
  /// **'© {year} {developer}'**
  String aboutCopyright(int year, String developer);

  /// No description provided for @aboutCannotOpen.
  ///
  /// In en, this message translates to:
  /// **'Could not open {target}'**
  String aboutCannotOpen(String target);

  /// No description provided for @aboutPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy policy'**
  String get aboutPrivacyPolicy;

  /// No description provided for @aboutStand.
  ///
  /// In en, this message translates to:
  /// **'3D-printed photo stand'**
  String get aboutStand;

  /// No description provided for @sampleKind.
  ///
  /// In en, this message translates to:
  /// **'Sample'**
  String get sampleKind;

  /// No description provided for @sampleLiquid.
  ///
  /// In en, this message translates to:
  /// **'Liquid (CFU/mL)'**
  String get sampleLiquid;

  /// No description provided for @sampleSolid.
  ///
  /// In en, this message translates to:
  /// **'Solid (CFU/g)'**
  String get sampleSolid;

  /// No description provided for @sampleWeight.
  ///
  /// In en, this message translates to:
  /// **'Sample weight'**
  String get sampleWeight;

  /// No description provided for @diluentVolume.
  ///
  /// In en, this message translates to:
  /// **'Diluent'**
  String get diluentVolume;

  /// No description provided for @solidTenfold.
  ///
  /// In en, this message translates to:
  /// **'The initial suspension is 1:10, so it is the 10⁻¹ dilution. Label plates with the total dilution of the sample (e.g. 10⁻² for the next tube).'**
  String get solidTenfold;

  /// No description provided for @solidOther.
  ///
  /// In en, this message translates to:
  /// **'The initial suspension is 1:{ratio}. Label plates as if it were the 10⁻¹ dilution; results are corrected by ×{factor}.'**
  String solidOther(String ratio, String factor);

  /// No description provided for @setupDropArrangement.
  ///
  /// In en, this message translates to:
  /// **'Where the drops are'**
  String get setupDropArrangement;

  /// No description provided for @dropArrangementFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get dropArrangementFree;

  /// No description provided for @dropArrangementSectors.
  ///
  /// In en, this message translates to:
  /// **'Ring'**
  String get dropArrangementSectors;

  /// No description provided for @dropArrangementGrid.
  ///
  /// In en, this message translates to:
  /// **'Rows'**
  String get dropArrangementGrid;

  /// No description provided for @setupDropFreeHelp.
  ///
  /// In en, this message translates to:
  /// **'Drops are found from their colonies and numbered in reading order. Empty and confluent drops must be added by hand.'**
  String get setupDropFreeHelp;

  /// No description provided for @setupDropSectorsHelp.
  ///
  /// In en, this message translates to:
  /// **'Drops evenly round a ring, clockwise from the top: the first dilution at 12 o\'clock. Empty and confluent drops are found from the ring.'**
  String get setupDropSectorsHelp;

  /// No description provided for @setupDropGridHelp.
  ///
  /// In en, this message translates to:
  /// **'A row per dilution, top to bottom, with its drops side by side. Empty and confluent drops are found from the rows.'**
  String get setupDropGridHelp;

  /// No description provided for @setupDropGridRowHelp.
  ///
  /// In en, this message translates to:
  /// **'One row of drops, left to right. Empty and confluent drops are found from the row.'**
  String get setupDropGridRowHelp;

  /// No description provided for @setupDropsPerDilution.
  ///
  /// In en, this message translates to:
  /// **'Drops of each dilution'**
  String get setupDropsPerDilution;

  /// No description provided for @setupDropPitch.
  ///
  /// In en, this message translates to:
  /// **'Distance between drops'**
  String get setupDropPitch;

  /// No description provided for @setupDropLayoutPreview.
  ///
  /// In en, this message translates to:
  /// **'How the drops sit on each plate'**
  String get setupDropLayoutPreview;

  /// No description provided for @reviewFindDrops.
  ///
  /// In en, this message translates to:
  /// **'Find drops again'**
  String get reviewFindDrops;

  /// No description provided for @reviewTurnLabels.
  ///
  /// In en, this message translates to:
  /// **'Turn labels by one drop'**
  String get reviewTurnLabels;

  /// No description provided for @reviewHintDropsLayout.
  ///
  /// In en, this message translates to:
  /// **'Tap a drop to change its label, mark it TNTC or leave it out; tap empty agar to add one. Drag a drop to move it, or drag the agar to move them all.'**
  String get reviewHintDropsLayout;

  /// No description provided for @reviewLeaveOut.
  ///
  /// In en, this message translates to:
  /// **'Leave this drop out'**
  String get reviewLeaveOut;

  /// No description provided for @reviewLeaveOutHelp.
  ///
  /// In en, this message translates to:
  /// **'It stays on the photo, crossed out, and does not count towards CFU/mL.'**
  String get reviewLeaveOutHelp;

  /// No description provided for @reviewLeaveOutWhy.
  ///
  /// In en, this message translates to:
  /// **'Why'**
  String get reviewLeaveOutWhy;

  /// No description provided for @dropExclusionSplash.
  ///
  /// In en, this message translates to:
  /// **'Splashed or smeared'**
  String get dropExclusionSplash;

  /// No description provided for @dropExclusionMerged.
  ///
  /// In en, this message translates to:
  /// **'Ran into a neighbour'**
  String get dropExclusionMerged;

  /// No description provided for @dropExclusionBubble.
  ///
  /// In en, this message translates to:
  /// **'Bubble or scratch'**
  String get dropExclusionBubble;

  /// No description provided for @dropExclusionContaminated.
  ///
  /// In en, this message translates to:
  /// **'Contaminant'**
  String get dropExclusionContaminated;

  /// No description provided for @dropExclusionOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get dropExclusionOther;

  /// No description provided for @reviewDropLeftOut.
  ///
  /// In en, this message translates to:
  /// **'left out'**
  String get reviewDropLeftOut;

  /// No description provided for @reviewDropCrowded.
  ///
  /// In en, this message translates to:
  /// **'Crowded: merged colonies are partly counted by their area. Check the count, or read the plate earlier next time.'**
  String get reviewDropCrowded;

  /// No description provided for @reviewDropUnplanned.
  ///
  /// In en, this message translates to:
  /// **'More drops than the plan: check this drop\'s label.'**
  String get reviewDropUnplanned;

  /// No description provided for @flagOutsideDrops.
  ///
  /// In en, this message translates to:
  /// **'Colonies between drops (not counted)'**
  String get flagOutsideDrops;

  /// No description provided for @flagLayoutUncertain.
  ///
  /// In en, this message translates to:
  /// **'Drop layout uncertain: check the drops'**
  String get flagLayoutUncertain;

  /// No description provided for @setupDropWindow.
  ///
  /// In en, this message translates to:
  /// **'Counting window (colonies per drop)'**
  String get setupDropWindow;

  /// No description provided for @setupDropWindowFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get setupDropWindowFrom;

  /// No description provided for @setupDropWindowTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get setupDropWindowTo;

  /// No description provided for @setupDropWindowHelp.
  ///
  /// In en, this message translates to:
  /// **'3–30 per 10 µL drop is the usual window; for other drop volumes, use your protocol\'s.'**
  String get setupDropWindowHelp;

  /// No description provided for @setupDropMode.
  ///
  /// In en, this message translates to:
  /// **'Calculation'**
  String get setupDropMode;

  /// No description provided for @dropModePooled.
  ///
  /// In en, this message translates to:
  /// **'Pooled'**
  String get dropModePooled;

  /// No description provided for @dropModeFirst.
  ///
  /// In en, this message translates to:
  /// **'First countable'**
  String get dropModeFirst;

  /// No description provided for @setupDropPooledHelp.
  ///
  /// In en, this message translates to:
  /// **'Every drop in the window, of all dilutions: ΣC ÷ Σ(V × d).'**
  String get setupDropPooledHelp;

  /// No description provided for @setupDropFirstHelp.
  ///
  /// In en, this message translates to:
  /// **'The mean of the least diluted dilution whose drops are in the window, as most protocols do.'**
  String get setupDropFirstHelp;

  /// No description provided for @dropTableTitle.
  ///
  /// In en, this message translates to:
  /// **'Drops per dilution'**
  String get dropTableTitle;

  /// No description provided for @dropRowMean.
  ///
  /// In en, this message translates to:
  /// **'mean {mean}'**
  String dropRowMean(String mean);

  /// No description provided for @dropRowLeftOut.
  ///
  /// In en, this message translates to:
  /// **'{n} left out'**
  String dropRowLeftOut(int n);

  /// No description provided for @dropUsedPooled.
  ///
  /// In en, this message translates to:
  /// **'Pooled from {dilutions} ({n, plural, =1{1 drop} other{{n} drops}})'**
  String dropUsedPooled(String dilutions, int n);

  /// No description provided for @dropUsedFirst.
  ///
  /// In en, this message translates to:
  /// **'From {dilution}, the first countable dilution ({n, plural, =1{1 drop} other{{n} drops}})'**
  String dropUsedFirst(String dilution, int n);

  /// No description provided for @dropCi.
  ///
  /// In en, this message translates to:
  /// **'95 % CI {low}–{high}'**
  String dropCi(String low, String high);

  /// No description provided for @dropRuleLine.
  ///
  /// In en, this message translates to:
  /// **'{mode} · {range} colonies per drop. Each replicate goes through its drop table; log₁₀ is the mean ± SD of the replicates\' log values.'**
  String dropRuleLine(String mode, String range);

  /// No description provided for @dropWarnOverdispersed.
  ///
  /// In en, this message translates to:
  /// **'Drops of a dilution disagree more than chance allows: check mixing and pipetting.'**
  String get dropWarnOverdispersed;

  /// No description provided for @dropWarnOutlier.
  ///
  /// In en, this message translates to:
  /// **'A drop is far from the others of its dilution: check it, or leave it out.'**
  String get dropWarnOutlier;

  /// No description provided for @dropWarnNotTenfold.
  ///
  /// In en, this message translates to:
  /// **'Neighbouring dilutions do not differ about tenfold: check the dilution series.'**
  String get dropWarnNotTenfold;

  /// No description provided for @dropWarnCrowded.
  ///
  /// In en, this message translates to:
  /// **'Crowded drops: read the plates earlier, or count a higher dilution.'**
  String get dropWarnCrowded;

  /// No description provided for @dropWarnNotAsPlanned.
  ///
  /// In en, this message translates to:
  /// **'The drops do not match the plan ({found} found, {planned} planned): check their labels.'**
  String dropWarnNotAsPlanned(int found, int planned);

  /// No description provided for @noteNoDropColonies.
  ///
  /// In en, this message translates to:
  /// **'no colonies in any drop'**
  String get noteNoDropColonies;

  /// No description provided for @noteNoDilutionInWindow.
  ///
  /// In en, this message translates to:
  /// **'no dilution in the counting window ({range}): the closest one'**
  String noteNoDilutionInWindow(Object range);

  /// No description provided for @noteNoDrops.
  ///
  /// In en, this message translates to:
  /// **'no drops'**
  String get noteNoDrops;

  /// No description provided for @dropUsedFrom.
  ///
  /// In en, this message translates to:
  /// **'From {dilutions} ({n, plural, =1{1 drop} other{{n} drops}})'**
  String dropUsedFrom(String dilutions, int n);

  /// No description provided for @homeSamples.
  ///
  /// In en, this message translates to:
  /// **'Samples'**
  String get homeSamples;

  /// No description provided for @homeCompare.
  ///
  /// In en, this message translates to:
  /// **'Compare'**
  String get homeCompare;

  /// No description provided for @homePlates.
  ///
  /// In en, this message translates to:
  /// **'Plates'**
  String get homePlates;

  /// No description provided for @homeSeveralPlates.
  ///
  /// In en, this message translates to:
  /// **'Several plates in one photo'**
  String get homeSeveralPlates;

  /// No description provided for @homeImportPhoto.
  ///
  /// In en, this message translates to:
  /// **'Import photo'**
  String get homeImportPhoto;

  /// No description provided for @homeScanLabel.
  ///
  /// In en, this message translates to:
  /// **'Scan plate label'**
  String get homeScanLabel;

  /// No description provided for @homeCountPlate.
  ///
  /// In en, this message translates to:
  /// **'Count plate'**
  String get homeCountPlate;

  /// No description provided for @homeNewSample.
  ///
  /// In en, this message translates to:
  /// **'New sample'**
  String get homeNewSample;

  /// No description provided for @homeShareCounts.
  ///
  /// In en, this message translates to:
  /// **'Colony counts'**
  String get homeShareCounts;

  /// No description provided for @homeShareTraining.
  ///
  /// In en, this message translates to:
  /// **'Colony Counter training data'**
  String get homeShareTraining;

  /// No description provided for @homeShareBackup.
  ///
  /// In en, this message translates to:
  /// **'Colony Counter backup'**
  String get homeShareBackup;

  /// No description provided for @homeExportTraining.
  ///
  /// In en, this message translates to:
  /// **'Export training data'**
  String get homeExportTraining;

  /// No description provided for @homeTrainingInfo.
  ///
  /// In en, this message translates to:
  /// **'Photos with every colony mark, in COCO and YOLO formats, for training a colony detector on your own plates.'**
  String get homeTrainingInfo;

  /// No description provided for @homeNoPlatesToExport.
  ///
  /// In en, this message translates to:
  /// **'No plates to export.'**
  String get homeNoPlatesToExport;

  /// No description provided for @homePreparingExport.
  ///
  /// In en, this message translates to:
  /// **'Preparing export…'**
  String get homePreparingExport;

  /// No description provided for @homePreparingBackup.
  ///
  /// In en, this message translates to:
  /// **'Preparing backup…'**
  String get homePreparingBackup;

  /// No description provided for @homeNPlates.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 plate} other{{n} plates}}'**
  String homeNPlates(int n);

  /// No description provided for @homeNSamples.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 sample} other{{n} samples}}'**
  String homeNSamples(int n);

  /// No description provided for @homeRestored.
  ///
  /// In en, this message translates to:
  /// **'Restored {plates} and {samples}.'**
  String homeRestored(String plates, String samples);

  /// No description provided for @homeRestoredKept.
  ///
  /// In en, this message translates to:
  /// **'Restored {plates} and {samples} ({skipped} already here, kept).'**
  String homeRestoredKept(String plates, String samples, int skipped);

  /// No description provided for @homeExportCsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get homeExportCsv;

  /// No description provided for @homeBackUpAll.
  ///
  /// In en, this message translates to:
  /// **'Back up all data'**
  String get homeBackUpAll;

  /// No description provided for @homeRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore from backup'**
  String get homeRestore;

  /// No description provided for @homeSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get homeSettings;

  /// No description provided for @homeCountingRule.
  ///
  /// In en, this message translates to:
  /// **'Counting rule'**
  String get homeCountingRule;

  /// No description provided for @homeCountableRange.
  ///
  /// In en, this message translates to:
  /// **'Countable range: {min}–{max} colonies per plate'**
  String homeCountableRange(int min, int max);

  /// No description provided for @homeDefaultVolume.
  ///
  /// In en, this message translates to:
  /// **'Default plated volume'**
  String get homeDefaultVolume;

  /// No description provided for @homeDefaultPlateType.
  ///
  /// In en, this message translates to:
  /// **'Default plate type'**
  String get homeDefaultPlateType;

  /// No description provided for @homeDefaultPlateTypeHelp.
  ///
  /// In en, this message translates to:
  /// **'For quick counts and new samples'**
  String get homeDefaultPlateTypeHelp;

  /// No description provided for @homeNoPlates.
  ///
  /// In en, this message translates to:
  /// **'No plates yet'**
  String get homeNoPlates;

  /// No description provided for @homeEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Place a 90 mm Nutrient Agar plate in the lightbox with the lid off, then tap “Count plate”.'**
  String get homeEmptyHint;

  /// No description provided for @homeDeletePlate.
  ///
  /// In en, this message translates to:
  /// **'Delete plate?'**
  String get homeDeletePlate;

  /// No description provided for @homeDeletePlateBody.
  ///
  /// In en, this message translates to:
  /// **'The photo and its count will be removed from this phone.'**
  String get homeDeletePlateBody;

  /// No description provided for @homeCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get homeCancel;

  /// No description provided for @homeDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get homeDelete;

  /// No description provided for @homeFlagged.
  ///
  /// In en, this message translates to:
  /// **'Flagged for checking'**
  String get homeFlagged;

  /// No description provided for @homeChecked.
  ///
  /// In en, this message translates to:
  /// **'Checked every colony'**
  String get homeChecked;

  /// No description provided for @homeTimelapse.
  ///
  /// In en, this message translates to:
  /// **'Time-lapse'**
  String get homeTimelapse;

  /// No description provided for @accuracyTitle.
  ///
  /// In en, this message translates to:
  /// **'Counting accuracy'**
  String get accuracyTitle;

  /// No description provided for @accuracyNoChecked.
  ///
  /// In en, this message translates to:
  /// **'No checked plates yet'**
  String get accuracyNoChecked;

  /// No description provided for @accuracyHowTo.
  ///
  /// In en, this message translates to:
  /// **'Now and then, check every colony on a plate: zoom in, remove wrong marks, add missed colonies, and set clusters. Then turn on \"Checked every colony\" when saving. The app compares its own count with yours and shows here how accurate it is on your plates.'**
  String get accuracyHowTo;

  /// No description provided for @accuracyCheckedPlates.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 checked plate} other{{n} checked plates}}'**
  String accuracyCheckedPlates(int n);

  /// No description provided for @accuracyWithin10.
  ///
  /// In en, this message translates to:
  /// **'{pct} % of plates within ±10 %'**
  String accuracyWithin10(String pct);

  /// No description provided for @accuracyOfChecked.
  ///
  /// In en, this message translates to:
  /// **'of the checked count · {plates}'**
  String accuracyOfChecked(String plates);

  /// No description provided for @accuracyMeanError.
  ///
  /// In en, this message translates to:
  /// **'mean error'**
  String get accuracyMeanError;

  /// No description provided for @accuracyBias.
  ///
  /// In en, this message translates to:
  /// **'bias'**
  String get accuracyBias;

  /// No description provided for @accuracyColoniesOff.
  ///
  /// In en, this message translates to:
  /// **'colonies off, on average'**
  String get accuracyColoniesOff;

  /// No description provided for @accuracyPrecision.
  ///
  /// In en, this message translates to:
  /// **'of marks were colonies'**
  String get accuracyPrecision;

  /// No description provided for @accuracyRecall.
  ///
  /// In en, this message translates to:
  /// **'of colonies found'**
  String get accuracyRecall;

  /// No description provided for @accuracyFootnote.
  ///
  /// In en, this message translates to:
  /// **'Percentages use plates with 10 or more colonies. Negative bias means the app counts too few.'**
  String get accuracyFootnote;

  /// No description provided for @accuracyScatterTitle.
  ///
  /// In en, this message translates to:
  /// **'Automatic vs checked count'**
  String get accuracyScatterTitle;

  /// No description provided for @accuracyNotFlagged.
  ///
  /// In en, this message translates to:
  /// **'Not flagged'**
  String get accuracyNotFlagged;

  /// No description provided for @accuracyScatterHint.
  ///
  /// In en, this message translates to:
  /// **'Tap a dot for details. Dots below the line: the app counted too few. Shaded: within ±10 %.'**
  String get accuracyScatterHint;

  /// No description provided for @accuracyPointDetail.
  ///
  /// In en, this message translates to:
  /// **'{plate} · {date}: app {auto}, checked {checked}'**
  String accuracyPointDetail(String plate, String date, int auto, int checked);

  /// No description provided for @accuracyAxisChecked.
  ///
  /// In en, this message translates to:
  /// **'checked count →'**
  String get accuracyAxisChecked;

  /// No description provided for @accuracyRangeColonies.
  ///
  /// In en, this message translates to:
  /// **'{range} colonies'**
  String accuracyRangeColonies(String range);

  /// No description provided for @accuracyErrorsTitle.
  ///
  /// In en, this message translates to:
  /// **'Where the errors are'**
  String get accuracyErrorsTitle;

  /// No description provided for @accuracyColPlates.
  ///
  /// In en, this message translates to:
  /// **'plates'**
  String get accuracyColPlates;

  /// No description provided for @accuracyWarningsUseful.
  ///
  /// In en, this message translates to:
  /// **'If the warnings are useful, flagged plates have the larger errors.'**
  String get accuracyWarningsUseful;

  /// No description provided for @accuracyCheckedPlatesTitle.
  ///
  /// In en, this message translates to:
  /// **'Checked plates'**
  String get accuracyCheckedPlatesTitle;

  /// No description provided for @accuracyAppVsChecked.
  ///
  /// In en, this message translates to:
  /// **'app {auto} · checked {checked}'**
  String accuracyAppVsChecked(int auto, int checked);

  /// No description provided for @accuracyAskCheck.
  ///
  /// In en, this message translates to:
  /// **'Ask me to check a plate'**
  String get accuracyAskCheck;

  /// No description provided for @accuracyNever.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get accuracyNever;

  /// No description provided for @accuracyEvery.
  ///
  /// In en, this message translates to:
  /// **'Every {n}th'**
  String accuracyEvery(int n);

  /// No description provided for @accuracyAskCheckHelp.
  ///
  /// In en, this message translates to:
  /// **'The review screen then asks you to check every colony on that plate before saving.'**
  String get accuracyAskCheckHelp;

  /// No description provided for @timelapseHours.
  ///
  /// In en, this message translates to:
  /// **'{h} h'**
  String timelapseHours(String h);

  /// No description provided for @timelapseNoPhotos.
  ///
  /// In en, this message translates to:
  /// **'No photos in this series.'**
  String get timelapseNoPhotos;

  /// No description provided for @timelapseShareCsv.
  ///
  /// In en, this message translates to:
  /// **'Share colony table (CSV)'**
  String get timelapseShareCsv;

  /// No description provided for @timelapseAddLater.
  ///
  /// In en, this message translates to:
  /// **'Add a later photo'**
  String get timelapseAddLater;

  /// No description provided for @timelapsePhotos.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 photo} other{{n} photos}}'**
  String timelapsePhotos(int n);

  /// No description provided for @timelapseSincePlating.
  ///
  /// In en, this message translates to:
  /// **'hours since plating'**
  String get timelapseSincePlating;

  /// No description provided for @timelapseSinceFirst.
  ///
  /// In en, this message translates to:
  /// **'hours since the first photo'**
  String get timelapseSinceFirst;

  /// No description provided for @timelapseColoniesAt.
  ///
  /// In en, this message translates to:
  /// **'{n} colonies at {time}'**
  String timelapseColoniesAt(int n, String time);

  /// No description provided for @timelapseAppeared.
  ///
  /// In en, this message translates to:
  /// **'{n} appeared after the first photo · half had appeared by {time}'**
  String timelapseAppeared(int n, String time);

  /// No description provided for @timelapseGrowth.
  ///
  /// In en, this message translates to:
  /// **'Median growth {rate} mm/h in diameter'**
  String timelapseGrowth(String rate);

  /// No description provided for @timelapseAddLaterHint.
  ///
  /// In en, this message translates to:
  /// **'Add a later photo of the same plate to see when colonies appear and how fast they grow.'**
  String get timelapseAddLaterHint;

  /// No description provided for @timelapseMatching.
  ///
  /// In en, this message translates to:
  /// **'Colonies are matched between photos by position, after turning and mirroring the earlier photo to fit the later one. Put the plate the same way up each time if few colonies are visible early on.'**
  String get timelapseMatching;

  /// No description provided for @timelapseChartTitle.
  ///
  /// In en, this message translates to:
  /// **'Colonies counted over time'**
  String get timelapseChartTitle;

  /// No description provided for @timelapsePhotosTitle.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get timelapsePhotosTitle;

  /// No description provided for @timelapsePhotoRow.
  ///
  /// In en, this message translates to:
  /// **'{time} · {n} colonies'**
  String timelapsePhotoRow(String time, int n);

  /// No description provided for @timelapseFirstSeen.
  ///
  /// In en, this message translates to:
  /// **'{n} first seen here'**
  String timelapseFirstSeen(int n);

  /// No description provided for @timelapseTurned.
  ///
  /// In en, this message translates to:
  /// **'turned {deg}° to fit the next'**
  String timelapseTurned(int deg);

  /// No description provided for @timelapseTurnedMirrored.
  ///
  /// In en, this message translates to:
  /// **'turned {deg}°, mirrored to fit the next'**
  String timelapseTurnedMirrored(int deg);

  /// No description provided for @timelapseAppearanceTitle.
  ///
  /// In en, this message translates to:
  /// **'When each colony appeared'**
  String get timelapseAppearanceTitle;

  /// No description provided for @timelapseBy.
  ///
  /// In en, this message translates to:
  /// **'by {time}'**
  String timelapseBy(String time);

  /// No description provided for @compareEmpty.
  ///
  /// In en, this message translates to:
  /// **'Give samples the same Experiment name and a Condition (e.g. Control / Treated), and optionally a time point, to compare them here: log reduction, % kill, and time-kill or growth curves.'**
  String get compareEmpty;

  /// No description provided for @compareExperiment.
  ///
  /// In en, this message translates to:
  /// **'Experiment'**
  String get compareExperiment;

  /// No description provided for @compareControl.
  ///
  /// In en, this message translates to:
  /// **'Control'**
  String get compareControl;

  /// No description provided for @compareOverTime.
  ///
  /// In en, this message translates to:
  /// **'log₁₀ {unit} over time'**
  String compareOverTime(String unit);

  /// No description provided for @compareChartHint.
  ///
  /// In en, this message translates to:
  /// **'Mean ± SD of replicates; tap a point for its value.'**
  String get compareChartHint;

  /// No description provided for @compareResults.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get compareResults;

  /// No description provided for @compareCondition.
  ///
  /// In en, this message translates to:
  /// **'Condition'**
  String get compareCondition;

  /// No description provided for @compareReductionVs.
  ///
  /// In en, this message translates to:
  /// **'Reduction vs {control}'**
  String compareReductionVs(String control);

  /// No description provided for @compareReductionHelp.
  ///
  /// In en, this message translates to:
  /// **'log reduction = mean log₁₀(control) − mean log₁₀(treated); SD combines both groups. % kill from the geometric means.'**
  String get compareReductionHelp;

  /// No description provided for @compareTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get compareTime;

  /// No description provided for @compareLogReduction.
  ///
  /// In en, this message translates to:
  /// **'log reduction'**
  String get compareLogReduction;

  /// No description provided for @compareKill.
  ///
  /// In en, this message translates to:
  /// **'% kill'**
  String get compareKill;

  /// No description provided for @compareSamples.
  ///
  /// In en, this message translates to:
  /// **'Samples'**
  String get compareSamples;

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Colony Counter'**
  String get appTitle;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'Phone setting'**
  String get languageSystem;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsTheme;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @restoreNotZip.
  ///
  /// In en, this message translates to:
  /// **'This file is not a Colony Counter backup (not a zip).'**
  String get restoreNotZip;

  /// No description provided for @restoreNotBackup.
  ///
  /// In en, this message translates to:
  /// **'This zip is not a Colony Counter backup.'**
  String get restoreNotBackup;

  /// No description provided for @methodFilm.
  ///
  /// In en, this message translates to:
  /// **'Petrifilm (dry film)'**
  String get methodFilm;

  /// No description provided for @formatFilmAc.
  ///
  /// In en, this message translates to:
  /// **'Petrifilm AC (aerobic count)'**
  String get formatFilmAc;

  /// No description provided for @formatFilmEc.
  ///
  /// In en, this message translates to:
  /// **'Petrifilm EC (E. coli/coliform)'**
  String get formatFilmEc;

  /// No description provided for @formatFilmCc.
  ///
  /// In en, this message translates to:
  /// **'Petrifilm CC (coliform)'**
  String get formatFilmCc;

  /// No description provided for @formatFilmEb.
  ///
  /// In en, this message translates to:
  /// **'Petrifilm EB (Enterobacteriaceae)'**
  String get formatFilmEb;

  /// No description provided for @formatFilmYm.
  ///
  /// In en, this message translates to:
  /// **'Petrifilm YM (yeast & mold)'**
  String get formatFilmYm;

  /// No description provided for @setupFilm.
  ///
  /// In en, this message translates to:
  /// **'Film'**
  String get setupFilm;

  /// No description provided for @filmType.
  ///
  /// In en, this message translates to:
  /// **'Film type'**
  String get filmType;

  /// No description provided for @filmRangeFromType.
  ///
  /// In en, this message translates to:
  /// **'Counting range {min}–{max} per film, from the film type. Volume is usually 1 mL.'**
  String filmRangeFromType(int min, int max);

  /// No description provided for @resultAerobic.
  ///
  /// In en, this message translates to:
  /// **'Aerobic count'**
  String get resultAerobic;

  /// No description provided for @resultEcoli.
  ///
  /// In en, this message translates to:
  /// **'E. coli'**
  String get resultEcoli;

  /// No description provided for @resultColiform.
  ///
  /// In en, this message translates to:
  /// **'Coliforms'**
  String get resultColiform;

  /// No description provided for @resultEnterobacteriaceae.
  ///
  /// In en, this message translates to:
  /// **'Enterobacteriaceae'**
  String get resultEnterobacteriaceae;

  /// No description provided for @resultYeast.
  ///
  /// In en, this message translates to:
  /// **'Yeasts'**
  String get resultYeast;

  /// No description provided for @resultMold.
  ///
  /// In en, this message translates to:
  /// **'Molds'**
  String get resultMold;

  /// No description provided for @kindColony.
  ///
  /// In en, this message translates to:
  /// **'Colony'**
  String get kindColony;

  /// No description provided for @kindRed.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get kindRed;

  /// No description provided for @kindBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get kindBlue;

  /// No description provided for @kindYeast.
  ///
  /// In en, this message translates to:
  /// **'Yeast'**
  String get kindYeast;

  /// No description provided for @kindMold.
  ///
  /// In en, this message translates to:
  /// **'Mold'**
  String get kindMold;

  /// No description provided for @reviewModeKind.
  ///
  /// In en, this message translates to:
  /// **'Kind'**
  String get reviewModeKind;

  /// No description provided for @reviewModeGas.
  ///
  /// In en, this message translates to:
  /// **'Gas'**
  String get reviewModeGas;

  /// No description provided for @reviewModeSquares.
  ///
  /// In en, this message translates to:
  /// **'Squares'**
  String get reviewModeSquares;

  /// No description provided for @reviewHintSquares.
  ///
  /// In en, this message translates to:
  /// **'Tap a grid square to leave it out of the estimate (a bubble, a fold, a spreader), or tap it again to add it back.'**
  String get reviewHintSquares;

  /// No description provided for @reviewFilmSquaresLeftOut.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 square left out.} other{{n} squares left out.}}'**
  String reviewFilmSquaresLeftOut(int n);

  /// No description provided for @reviewFilmGasSplit.
  ///
  /// In en, this message translates to:
  /// **'{kind}: {withGas} with gas, {without} without'**
  String reviewFilmGasSplit(String kind, int withGas, int without);

  /// No description provided for @reviewModeYellow.
  ///
  /// In en, this message translates to:
  /// **'Zone'**
  String get reviewModeYellow;

  /// No description provided for @reviewHintKind.
  ///
  /// In en, this message translates to:
  /// **'Tap a colony to switch it between {a} and {b}.'**
  String reviewHintKind(Object a, Object b);

  /// No description provided for @reviewHintGas.
  ///
  /// In en, this message translates to:
  /// **'Tap a colony to mark or unmark a gas bubble next to it (white ring).'**
  String get reviewHintGas;

  /// No description provided for @reviewHintYellow.
  ///
  /// In en, this message translates to:
  /// **'Tap a colony to mark or unmark a yellow zone around it (yellow ring).'**
  String get reviewHintYellow;

  /// No description provided for @reviewFilmMarks.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{mark} other{marks}}'**
  String reviewFilmMarks(int n);

  /// No description provided for @reviewFilmRedNoGas.
  ///
  /// In en, this message translates to:
  /// **'{n} red without gas (not counted)'**
  String reviewFilmRedNoGas(int n);

  /// No description provided for @reviewFilmNotCounted.
  ///
  /// In en, this message translates to:
  /// **'{n} not counted (no gas or zone)'**
  String reviewFilmNotCounted(int n);

  /// No description provided for @reviewFilmEstimate.
  ///
  /// In en, this message translates to:
  /// **'Above the counting range: estimated from {n} complete grid squares × 20 cm².'**
  String reviewFilmEstimate(int n);

  /// No description provided for @reviewFilmFewSquares.
  ///
  /// In en, this message translates to:
  /// **'Above the counting range, but fewer than 3 complete grid squares were found, so the count is shown.'**
  String get reviewFilmFewSquares;

  /// No description provided for @reviewFilmNoGrid.
  ///
  /// In en, this message translates to:
  /// **'The printed grid was not found, so the scale and this count may be wrong. Is this a Petrifilm plate, flat, in focus and without glare? Retake the photo or check every colony.'**
  String get reviewFilmNoGrid;

  /// No description provided for @reviewFilmAid.
  ///
  /// In en, this message translates to:
  /// **'Automatic film counts are an aid: check them against the interpretation guide.'**
  String get reviewFilmAid;

  /// No description provided for @flagEstimated.
  ///
  /// In en, this message translates to:
  /// **'Estimated from squares'**
  String get flagEstimated;

  /// No description provided for @flagGridNotFound.
  ///
  /// In en, this message translates to:
  /// **'Grid not found'**
  String get flagGridNotFound;

  /// No description provided for @flagAreaSize.
  ///
  /// In en, this message translates to:
  /// **'Growth area size unexpected'**
  String get flagAreaSize;

  /// No description provided for @captureFilmTip.
  ///
  /// In en, this message translates to:
  /// **'Lay the film flat on a plain background, photograph straight down and avoid glare on the clear top film.'**
  String get captureFilmTip;

  /// No description provided for @aboutPetrifilmTitle.
  ///
  /// In en, this message translates to:
  /// **'Dry films'**
  String get aboutPetrifilmTitle;

  /// No description provided for @aboutPetrifilm.
  ///
  /// In en, this message translates to:
  /// **'Reads Neogen® Petrifilm® AC, EC, CC, EB and YM plates. Petrifilm and Neogen are trademarks of Neogen Corporation; this app is not made or endorsed by Neogen. Counts are an aid to be checked, not an AOAC-validated result.'**
  String get aboutPetrifilm;

  /// No description provided for @photoReadingLabel.
  ///
  /// In en, this message translates to:
  /// **'Reading label…'**
  String get photoReadingLabel;

  /// No description provided for @photoNoLabelFound.
  ///
  /// In en, this message translates to:
  /// **'No plate label found. Fill the frame with the QR code and try again.'**
  String get photoNoLabelFound;

  /// No description provided for @captureLockNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Lock not supported: {error}'**
  String captureLockNotSupported(String error);

  /// No description provided for @captureFailed.
  ///
  /// In en, this message translates to:
  /// **'Capture failed: {error}'**
  String captureFailed(String error);

  /// No description provided for @capturePhotographPlate.
  ///
  /// In en, this message translates to:
  /// **'Photograph plate'**
  String get capturePhotographPlate;

  /// No description provided for @captureCameraUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Camera unavailable: {error}'**
  String captureCameraUnavailable(String error);

  /// No description provided for @captureLevel.
  ///
  /// In en, this message translates to:
  /// **'Level'**
  String get captureLevel;

  /// No description provided for @captureTilt.
  ///
  /// In en, this message translates to:
  /// **'Tilt {deg}°'**
  String captureTilt(String deg);

  /// No description provided for @captureSharp.
  ///
  /// In en, this message translates to:
  /// **'Sharp'**
  String get captureSharp;

  /// No description provided for @captureFocusing.
  ///
  /// In en, this message translates to:
  /// **'Focusing…'**
  String get captureFocusing;

  /// No description provided for @captureNoGlare.
  ///
  /// In en, this message translates to:
  /// **'No glare'**
  String get captureNoGlare;

  /// No description provided for @captureGlare.
  ///
  /// In en, this message translates to:
  /// **'Glare: remove lid / dim light'**
  String get captureGlare;

  /// No description provided for @captureUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock focus & exposure'**
  String get captureUnlock;

  /// No description provided for @captureLock.
  ///
  /// In en, this message translates to:
  /// **'Lock focus & exposure'**
  String get captureLock;

  /// No description provided for @multiRoundOnly.
  ///
  /// In en, this message translates to:
  /// **'Several plates in one photo works with round dishes only.'**
  String get multiRoundOnly;

  /// No description provided for @multiLayPlates.
  ///
  /// In en, this message translates to:
  /// **'Lay the plates side by side, lids off, on a dark surface, and photograph them from straight above.'**
  String get multiLayPlates;

  /// No description provided for @multiTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get multiTakePhoto;

  /// No description provided for @multiChoosePhoto.
  ///
  /// In en, this message translates to:
  /// **'Choose photo'**
  String get multiChoosePhoto;

  /// No description provided for @multiNoPlatesFound.
  ///
  /// In en, this message translates to:
  /// **'No plates found in this photo.'**
  String get multiNoPlatesFound;

  /// No description provided for @multiPlatesInPhoto.
  ///
  /// In en, this message translates to:
  /// **'Plates in photo'**
  String get multiPlatesInPhoto;

  /// No description provided for @multiPlatesFound.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 plate found} other{{n} plates found}}'**
  String multiPlatesFound(int n);

  /// No description provided for @multiDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get multiDone;

  /// No description provided for @multiAddRemove.
  ///
  /// In en, this message translates to:
  /// **'Add or remove plates'**
  String get multiAddRemove;

  /// No description provided for @multiEditHint.
  ///
  /// In en, this message translates to:
  /// **'Tap a circle to remove it, or tap the centre of a missed plate to add one.'**
  String get multiEditHint;

  /// No description provided for @multiUsePencil.
  ///
  /// In en, this message translates to:
  /// **'Use the pencil to mark the plates.'**
  String get multiUsePencil;

  /// No description provided for @multiAllSaved.
  ///
  /// In en, this message translates to:
  /// **'All plates are saved.'**
  String get multiAllSaved;

  /// No description provided for @multiTapToCount.
  ///
  /// In en, this message translates to:
  /// **'Tap a plate to count it. {n} still to save.'**
  String multiTapToCount(int n);

  /// No description provided for @reviewPhotoMissing.
  ///
  /// In en, this message translates to:
  /// **'The photo for this plate is missing.'**
  String get reviewPhotoMissing;

  /// No description provided for @reviewCouldNotCount.
  ///
  /// In en, this message translates to:
  /// **'Could not count this photo: {error}'**
  String reviewCouldNotCount(String error);

  /// No description provided for @reviewRecountTitle.
  ///
  /// In en, this message translates to:
  /// **'Recount plate?'**
  String get reviewRecountTitle;

  /// No description provided for @reviewRecountBody.
  ///
  /// In en, this message translates to:
  /// **'Your manual additions and removals will be discarded.'**
  String get reviewRecountBody;

  /// No description provided for @reviewCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get reviewCancel;

  /// No description provided for @reviewRecount.
  ///
  /// In en, this message translates to:
  /// **'Recount'**
  String get reviewRecount;

  /// No description provided for @reviewPlateType.
  ///
  /// In en, this message translates to:
  /// **'Plate type'**
  String get reviewPlateType;

  /// No description provided for @reviewShareSubject.
  ///
  /// In en, this message translates to:
  /// **'Colony count'**
  String get reviewShareSubject;

  /// No description provided for @reviewCouldNotShare.
  ///
  /// In en, this message translates to:
  /// **'Could not share the photo: {error}'**
  String reviewCouldNotShare(String error);

  /// No description provided for @reviewDiscardTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard this count?'**
  String get reviewDiscardTitle;

  /// No description provided for @reviewDiscardBody.
  ///
  /// In en, this message translates to:
  /// **'It has not been saved.'**
  String get reviewDiscardBody;

  /// No description provided for @reviewKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get reviewKeep;

  /// No description provided for @reviewDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get reviewDiscard;

  /// No description provided for @reviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review count'**
  String get reviewTitle;

  /// No description provided for @reviewUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get reviewUndo;

  /// No description provided for @reviewHideMarks.
  ///
  /// In en, this message translates to:
  /// **'Hide marks'**
  String get reviewHideMarks;

  /// No description provided for @reviewShowMarks.
  ///
  /// In en, this message translates to:
  /// **'Show marks'**
  String get reviewShowMarks;

  /// No description provided for @reviewHintMarksHidden.
  ///
  /// In en, this message translates to:
  /// **'Marks are hidden, so you can look over the plate. Tap the eye to show them again and edit.'**
  String get reviewHintMarksHidden;

  /// No description provided for @reviewSensitivity.
  ///
  /// In en, this message translates to:
  /// **'Detection sensitivity'**
  String get reviewSensitivity;

  /// No description provided for @reviewMenuTooltip.
  ///
  /// In en, this message translates to:
  /// **'Plate type and colours'**
  String get reviewMenuTooltip;

  /// No description provided for @reviewShareAnnotated.
  ///
  /// In en, this message translates to:
  /// **'Share annotated photo'**
  String get reviewShareAnnotated;

  /// No description provided for @reviewAddLaterPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add a later photo (time-lapse)'**
  String get reviewAddLaterPhoto;

  /// No description provided for @reviewTimelapse.
  ///
  /// In en, this message translates to:
  /// **'Time-lapse'**
  String get reviewTimelapse;

  /// No description provided for @reviewPlateTypeItem.
  ///
  /// In en, this message translates to:
  /// **'Plate type: {type}…'**
  String reviewPlateTypeItem(String type);

  /// No description provided for @reviewDropPlate.
  ///
  /// In en, this message translates to:
  /// **'Drop plate'**
  String get reviewDropPlate;

  /// No description provided for @reviewColoursItem.
  ///
  /// In en, this message translates to:
  /// **'Colours: {mode}'**
  String reviewColoursItem(String mode);

  /// No description provided for @reviewCounting.
  ///
  /// In en, this message translates to:
  /// **'Counting colonies…'**
  String get reviewCounting;

  /// No description provided for @reviewAdded.
  ///
  /// In en, this message translates to:
  /// **'+{n} added'**
  String reviewAdded(int n);

  /// No description provided for @reviewRemoved.
  ///
  /// In en, this message translates to:
  /// **'−{n} removed'**
  String reviewRemoved(int n);

  /// No description provided for @reviewInClusters.
  ///
  /// In en, this message translates to:
  /// **'+{n} in clusters'**
  String reviewInClusters(int n);

  /// No description provided for @reviewModeZoom.
  ///
  /// In en, this message translates to:
  /// **'Zoom'**
  String get reviewModeZoom;

  /// No description provided for @reviewModeEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get reviewModeEdit;

  /// No description provided for @reviewModePlate.
  ///
  /// In en, this message translates to:
  /// **'Plate'**
  String get reviewModePlate;

  /// No description provided for @reviewModeDrops.
  ///
  /// In en, this message translates to:
  /// **'Drops'**
  String get reviewModeDrops;

  /// No description provided for @reviewModeColour.
  ///
  /// In en, this message translates to:
  /// **'Colour'**
  String get reviewModeColour;

  /// No description provided for @reviewAutomatic.
  ///
  /// In en, this message translates to:
  /// **'automatic'**
  String get reviewAutomatic;

  /// No description provided for @reviewAutoEdits.
  ///
  /// In en, this message translates to:
  /// **'auto {auto} · {edits}'**
  String reviewAutoEdits(int auto, String edits);

  /// No description provided for @reviewHintZoom.
  ///
  /// In en, this message translates to:
  /// **'Pinch to zoom, drag to pan.'**
  String get reviewHintZoom;

  /// No description provided for @reviewHintEdit.
  ///
  /// In en, this message translates to:
  /// **'Tap a mark to remove it, tap empty agar to add one. Long-press a mark to set how many colonies it contains.'**
  String get reviewHintEdit;

  /// No description provided for @reviewHintSquare.
  ///
  /// In en, this message translates to:
  /// **'Drag to move the square, use the sliders to resize and turn it, then recount.'**
  String get reviewHintSquare;

  /// No description provided for @reviewHintCircle.
  ///
  /// In en, this message translates to:
  /// **'Drag to move the circle, use the slider to resize it, then recount.'**
  String get reviewHintCircle;

  /// No description provided for @reviewHintDrops.
  ///
  /// In en, this message translates to:
  /// **'Tap a drop to set its dilution and replicate, tap empty agar to add a drop, drag a drop to move it.'**
  String get reviewHintDrops;

  /// No description provided for @reviewHintColour.
  ///
  /// In en, this message translates to:
  /// **'Tap a colony to switch its colour class.'**
  String get reviewHintColour;

  /// No description provided for @reviewSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get reviewSize;

  /// No description provided for @reviewRecountSquare.
  ///
  /// In en, this message translates to:
  /// **'Recount with this square'**
  String get reviewRecountSquare;

  /// No description provided for @reviewRecountCircle.
  ///
  /// In en, this message translates to:
  /// **'Recount with this circle'**
  String get reviewRecountCircle;

  /// No description provided for @reviewSavePlate.
  ///
  /// In en, this message translates to:
  /// **'Save plate'**
  String get reviewSavePlate;

  /// No description provided for @reviewSaveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get reviewSaveChanges;

  /// No description provided for @reviewCheckCount.
  ///
  /// In en, this message translates to:
  /// **'Check this count ({warnings}). Zoom in and correct any missed or extra marks before saving.'**
  String reviewCheckCount(String warnings);

  /// No description provided for @reviewAccuracyCheck.
  ///
  /// In en, this message translates to:
  /// **'Accuracy check: please check every colony on this plate. It is saved as a reference count to track how well the automatic count works on your plates.'**
  String get reviewAccuracyCheck;

  /// No description provided for @reviewClassCount.
  ///
  /// In en, this message translates to:
  /// **'{name} {n}'**
  String reviewClassCount(String name, int n);

  /// No description provided for @reviewClassPercent.
  ///
  /// In en, this message translates to:
  /// **'{percent} % {name}'**
  String reviewClassPercent(String percent, String name);

  /// No description provided for @reviewNoDrops.
  ///
  /// In en, this message translates to:
  /// **'No drops marked yet: use Drops to add them.'**
  String get reviewNoDrops;

  /// No description provided for @reviewClusterTitle.
  ///
  /// In en, this message translates to:
  /// **'Colonies in this mark'**
  String get reviewClusterTitle;

  /// No description provided for @reviewSet.
  ///
  /// In en, this message translates to:
  /// **'Set'**
  String get reviewSet;

  /// No description provided for @reviewSensitivityHelp.
  ///
  /// In en, this message translates to:
  /// **'Higher finds fainter and smaller colonies but may count debris. Default: 6.5.'**
  String get reviewSensitivityHelp;

  /// No description provided for @reviewLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get reviewLow;

  /// No description provided for @reviewHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get reviewHigh;

  /// No description provided for @reviewDropTitle.
  ///
  /// In en, this message translates to:
  /// **'Drop {index} · {n, plural, =1{1 colony} other{{n} colonies}}'**
  String reviewDropTitle(int index, int n);

  /// No description provided for @reviewDilution.
  ///
  /// In en, this message translates to:
  /// **'Dilution'**
  String get reviewDilution;

  /// No description provided for @reviewReplicate.
  ///
  /// In en, this message translates to:
  /// **'Replicate'**
  String get reviewReplicate;

  /// No description provided for @reviewTntc.
  ///
  /// In en, this message translates to:
  /// **'Too numerous to count'**
  String get reviewTntc;

  /// No description provided for @reviewConfluent.
  ///
  /// In en, this message translates to:
  /// **'Confluent drop'**
  String get reviewConfluent;

  /// No description provided for @reviewDropSize.
  ///
  /// In en, this message translates to:
  /// **'Size {mm} mm'**
  String reviewDropSize(String mm);

  /// No description provided for @reviewDeleteDrop.
  ///
  /// In en, this message translates to:
  /// **'Delete drop'**
  String get reviewDeleteDrop;

  /// No description provided for @reviewOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get reviewOk;

  /// No description provided for @samplesNotFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'Sample “{id}” not found'**
  String samplesNotFoundTitle(Object id);

  /// No description provided for @samplesSetUpNow.
  ///
  /// In en, this message translates to:
  /// **'Set up this sample now?'**
  String get samplesSetUpNow;

  /// No description provided for @samplesCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get samplesCancel;

  /// No description provided for @samplesSetUp.
  ///
  /// In en, this message translates to:
  /// **'Set up'**
  String get samplesSetUp;

  /// No description provided for @samplesPhotographNow.
  ///
  /// In en, this message translates to:
  /// **'Photograph this plate now?'**
  String get samplesPhotographNow;

  /// No description provided for @samplesJustOpen.
  ///
  /// In en, this message translates to:
  /// **'Just open sample'**
  String get samplesJustOpen;

  /// No description provided for @samplesPhotograph.
  ///
  /// In en, this message translates to:
  /// **'Photograph'**
  String get samplesPhotograph;

  /// No description provided for @samplesAlreadyCounted.
  ///
  /// In en, this message translates to:
  /// **'{plate} is already counted.'**
  String samplesAlreadyCounted(Object plate);

  /// No description provided for @samplesNoResult.
  ///
  /// In en, this message translates to:
  /// **'No result yet'**
  String get samplesNoResult;

  /// No description provided for @samplesEstimated.
  ///
  /// In en, this message translates to:
  /// **'est.'**
  String get samplesEstimated;

  /// No description provided for @samplesHours.
  ///
  /// In en, this message translates to:
  /// **'{h} h'**
  String samplesHours(Object h);

  /// No description provided for @samplesEmpty.
  ///
  /// In en, this message translates to:
  /// **'Set up a sample to plan its dilution series and replicates. The app then tells you which plate to photograph next and reports mean ± SD and log₁₀ CFU/mL across replicates.'**
  String get samplesEmpty;

  /// No description provided for @samplesSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search sample, strain, operator, tag…'**
  String get samplesSearchHint;

  /// No description provided for @samplesNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No samples match.'**
  String get samplesNoMatch;

  /// No description provided for @samplesNoExperiment.
  ///
  /// In en, this message translates to:
  /// **'No experiment'**
  String get samplesNoExperiment;

  /// No description provided for @samplesPlatesDone.
  ///
  /// In en, this message translates to:
  /// **'{done}/{total} plates'**
  String samplesPlatesDone(int done, int total);

  /// No description provided for @samplesPlateCount.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 plate} other{{n} plates}}'**
  String samplesPlateCount(int n);

  /// No description provided for @samplesSlotPlate.
  ///
  /// In en, this message translates to:
  /// **'plate'**
  String get samplesSlotPlate;

  /// No description provided for @samplesLabelsSubject.
  ///
  /// In en, this message translates to:
  /// **'Plate labels for {id}'**
  String samplesLabelsSubject(Object id);

  /// No description provided for @samplesDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {id}?'**
  String samplesDeleteTitle(Object id);

  /// No description provided for @samplesDeletePlanOnly.
  ///
  /// In en, this message translates to:
  /// **'The sample plan will be removed.'**
  String get samplesDeletePlanOnly;

  /// No description provided for @samplesDeleteAsk.
  ///
  /// In en, this message translates to:
  /// **'Remove only the plan and keep its {n, plural, =1{1 plate} other{{n} plates}}, or delete the plates too?'**
  String samplesDeleteAsk(int n);

  /// No description provided for @samplesKeepPlates.
  ///
  /// In en, this message translates to:
  /// **'Keep plates'**
  String get samplesKeepPlates;

  /// No description provided for @samplesDeleteAll.
  ///
  /// In en, this message translates to:
  /// **'Delete all'**
  String get samplesDeleteAll;

  /// No description provided for @samplesDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get samplesDelete;

  /// No description provided for @samplesEditPlan.
  ///
  /// In en, this message translates to:
  /// **'Edit plan'**
  String get samplesEditPlan;

  /// No description provided for @samplesCreatePlan.
  ///
  /// In en, this message translates to:
  /// **'Create plan'**
  String get samplesCreatePlan;

  /// No description provided for @samplesNewLikeThis.
  ///
  /// In en, this message translates to:
  /// **'New sample like this'**
  String get samplesNewLikeThis;

  /// No description provided for @samplesMulti.
  ///
  /// In en, this message translates to:
  /// **'Photograph several plates at once'**
  String get samplesMulti;

  /// No description provided for @samplesPrintLabels.
  ///
  /// In en, this message translates to:
  /// **'Print plate labels (PDF)'**
  String get samplesPrintLabels;

  /// No description provided for @samplesDeleteSample.
  ///
  /// In en, this message translates to:
  /// **'Delete sample'**
  String get samplesDeleteSample;

  /// No description provided for @samplesPlates.
  ///
  /// In en, this message translates to:
  /// **'Plates'**
  String get samplesPlates;

  /// No description provided for @samplesDropsUl.
  ///
  /// In en, this message translates to:
  /// **'{v} µL drops'**
  String samplesDropsUl(Object v);

  /// No description provided for @samplesMlFiltered.
  ///
  /// In en, this message translates to:
  /// **'{v} mL filtered'**
  String samplesMlFiltered(Object v);

  /// No description provided for @samplesMlPerPlate.
  ///
  /// In en, this message translates to:
  /// **'{v} mL per plate'**
  String samplesMlPerPlate(Object v);

  /// No description provided for @samplesPhotographSlot.
  ///
  /// In en, this message translates to:
  /// **'Photograph {slot}'**
  String samplesPhotographSlot(Object slot);

  /// No description provided for @samplesImportFor.
  ///
  /// In en, this message translates to:
  /// **'Import photo for {slot}'**
  String samplesImportFor(Object slot);

  /// No description provided for @samplesAllDone.
  ///
  /// In en, this message translates to:
  /// **'All planned plates are done.'**
  String get samplesAllDone;

  /// No description provided for @samplesNoPlan.
  ///
  /// In en, this message translates to:
  /// **'This sample has no plan (its plates were saved one by one). Use “Create plan” in the menu for a guided plate list.'**
  String get samplesNoPlan;

  /// No description provided for @samplesNoCountable.
  ///
  /// In en, this message translates to:
  /// **'No countable plates yet'**
  String get samplesNoCountable;

  /// No description provided for @samplesReplicateCount.
  ///
  /// In en, this message translates to:
  /// **'n = {n, plural, =1{1 replicate} other{{n} replicates}}'**
  String samplesReplicateCount(int n);

  /// No description provided for @samplesPoolFilters.
  ///
  /// In en, this message translates to:
  /// **'Each replicate pools its countable filters ({range} colonies, {rule}) as ΣC / Σ(V × d); log₁₀ is the mean ± SD of the replicates\' log values.'**
  String samplesPoolFilters(Object range, Object rule);

  /// No description provided for @samplesPoolPlates.
  ///
  /// In en, this message translates to:
  /// **'Each replicate pools its countable plates ({range} colonies, {rule}) as ΣC / Σ(V × d); log₁₀ is the mean ± SD of the replicates\' log values.'**
  String samplesPoolPlates(Object range, Object rule);

  /// No description provided for @samplesStrain.
  ///
  /// In en, this message translates to:
  /// **'Strain'**
  String get samplesStrain;

  /// No description provided for @samplesMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get samplesMedium;

  /// No description provided for @samplesBatch.
  ///
  /// In en, this message translates to:
  /// **'batch {batch}'**
  String samplesBatch(Object batch);

  /// No description provided for @samplesIncubation.
  ///
  /// In en, this message translates to:
  /// **'Incubation'**
  String get samplesIncubation;

  /// No description provided for @samplesIncubationAt.
  ///
  /// In en, this message translates to:
  /// **'{hours} at {temp}'**
  String samplesIncubationAt(Object hours, Object temp);

  /// No description provided for @samplesOperator.
  ///
  /// In en, this message translates to:
  /// **'Operator'**
  String get samplesOperator;

  /// No description provided for @samplesTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get samplesTags;

  /// No description provided for @samplesNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get samplesNotes;

  /// No description provided for @samplesDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get samplesDetails;

  /// No description provided for @setupRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get setupRequired;

  /// No description provided for @setupIdTaken.
  ///
  /// In en, this message translates to:
  /// **'This sample ID already exists'**
  String get setupIdTaken;

  /// No description provided for @setupNewSample.
  ///
  /// In en, this message translates to:
  /// **'New sample'**
  String get setupNewSample;

  /// No description provided for @setupEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit {id}'**
  String setupEditTitle(Object id);

  /// No description provided for @setupSampleId.
  ///
  /// In en, this message translates to:
  /// **'Sample ID'**
  String get setupSampleId;

  /// No description provided for @setupExperiment.
  ///
  /// In en, this message translates to:
  /// **'Experiment (optional)'**
  String get setupExperiment;

  /// No description provided for @setupExperimentHelp.
  ///
  /// In en, this message translates to:
  /// **'Samples of one experiment can be compared'**
  String get setupExperimentHelp;

  /// No description provided for @setupCondition.
  ///
  /// In en, this message translates to:
  /// **'Condition'**
  String get setupCondition;

  /// No description provided for @setupConditionHelp.
  ///
  /// In en, this message translates to:
  /// **'e.g. Control, 1 % NaOCl'**
  String get setupConditionHelp;

  /// No description provided for @setupTimePoint.
  ///
  /// In en, this message translates to:
  /// **'Time point'**
  String get setupTimePoint;

  /// No description provided for @setupHoursUnit.
  ///
  /// In en, this message translates to:
  /// **'h'**
  String get setupHoursUnit;

  /// No description provided for @setupOptional.
  ///
  /// In en, this message translates to:
  /// **'optional'**
  String get setupOptional;

  /// No description provided for @setupPlating.
  ///
  /// In en, this message translates to:
  /// **'Plating'**
  String get setupPlating;

  /// No description provided for @setupSpread.
  ///
  /// In en, this message translates to:
  /// **'Spread'**
  String get setupSpread;

  /// No description provided for @setupDrop.
  ///
  /// In en, this message translates to:
  /// **'Drop'**
  String get setupDrop;

  /// No description provided for @setupMembrane.
  ///
  /// In en, this message translates to:
  /// **'Membrane'**
  String get setupMembrane;

  /// No description provided for @setupMembraneRange.
  ///
  /// In en, this message translates to:
  /// **'Countable range per filter'**
  String get setupMembraneRange;

  /// No description provided for @setupMembraneUnit.
  ///
  /// In en, this message translates to:
  /// **'Results are reported as CFU/100 mL'**
  String get setupMembraneUnit;

  /// No description provided for @setupPlateType.
  ///
  /// In en, this message translates to:
  /// **'Plate type'**
  String get setupPlateType;

  /// No description provided for @setupFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get setupFrom;

  /// No description provided for @setupTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get setupTo;

  /// No description provided for @setupReplicates.
  ///
  /// In en, this message translates to:
  /// **'Replicates'**
  String get setupReplicates;

  /// No description provided for @setupVolumeFiltered.
  ///
  /// In en, this message translates to:
  /// **'Volume filtered'**
  String get setupVolumeFiltered;

  /// No description provided for @setupVolumePerPlate.
  ///
  /// In en, this message translates to:
  /// **'Volume per plate'**
  String get setupVolumePerPlate;

  /// No description provided for @setupDropVolume.
  ///
  /// In en, this message translates to:
  /// **'Drop volume'**
  String get setupDropVolume;

  /// No description provided for @setupFilterCount.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 filter} other{{n} filters}}.'**
  String setupFilterCount(int n);

  /// No description provided for @setupPlateCount.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 plate} other{{n} plates}}.'**
  String setupPlateCount(int n);

  /// No description provided for @setupPlateCountDrops.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 plate} other{{n} plates}} with {drops} drops each.'**
  String setupPlateCountDrops(int n, int drops);

  /// No description provided for @setupColonyColours.
  ///
  /// In en, this message translates to:
  /// **'Colony colours'**
  String get setupColonyColours;

  /// No description provided for @setupColourNone.
  ///
  /// In en, this message translates to:
  /// **'All colonies are counted together.'**
  String get setupColourNone;

  /// No description provided for @setupColourBlueWhite.
  ///
  /// In en, this message translates to:
  /// **'Blue and white colonies are counted separately (X-gal screening).'**
  String get setupColourBlueWhite;

  /// No description provided for @setupColourTwo.
  ///
  /// In en, this message translates to:
  /// **'Colonies are split into two colour groups (e.g. chromogenic agar).'**
  String get setupColourTwo;

  /// No description provided for @setupNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get setupNotes;

  /// No description provided for @setupSave.
  ///
  /// In en, this message translates to:
  /// **'Save sample'**
  String get setupSave;

  /// No description provided for @setupDetails.
  ///
  /// In en, this message translates to:
  /// **'Experiment details'**
  String get setupDetails;

  /// No description provided for @setupDetailsSummary.
  ///
  /// In en, this message translates to:
  /// **'Strain, medium, incubation, operator, tags'**
  String get setupDetailsSummary;

  /// No description provided for @setupStrain.
  ///
  /// In en, this message translates to:
  /// **'Strain / organism'**
  String get setupStrain;

  /// No description provided for @setupMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get setupMedium;

  /// No description provided for @setupBatch.
  ///
  /// In en, this message translates to:
  /// **'Batch / lot'**
  String get setupBatch;

  /// No description provided for @setupIncubation.
  ///
  /// In en, this message translates to:
  /// **'Incubation'**
  String get setupIncubation;

  /// No description provided for @setupTemperature.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get setupTemperature;

  /// No description provided for @setupOperator.
  ///
  /// In en, this message translates to:
  /// **'Operator'**
  String get setupOperator;

  /// No description provided for @setupTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get setupTags;

  /// No description provided for @setupTagsHelp.
  ///
  /// In en, this message translates to:
  /// **'Comma-separated, e.g. thesis, batch 3'**
  String get setupTagsHelp;

  /// No description provided for @saveSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Plate details'**
  String get saveSheetTitle;

  /// No description provided for @saveSheetSampleId.
  ///
  /// In en, this message translates to:
  /// **'Sample ID'**
  String get saveSheetSampleId;

  /// No description provided for @saveSheetSampleHelp.
  ///
  /// In en, this message translates to:
  /// **'Plates with the same sample ID are pooled for CFU/mL'**
  String get saveSheetSampleHelp;

  /// No description provided for @saveSheetScan.
  ///
  /// In en, this message translates to:
  /// **'Scan plate label'**
  String get saveSheetScan;

  /// No description provided for @saveSheetDilution.
  ///
  /// In en, this message translates to:
  /// **'Plated dilution'**
  String get saveSheetDilution;

  /// No description provided for @saveSheetReplicate.
  ///
  /// In en, this message translates to:
  /// **'Replicate'**
  String get saveSheetReplicate;

  /// No description provided for @saveSheetDropVolume.
  ///
  /// In en, this message translates to:
  /// **'Drop volume'**
  String get saveSheetDropVolume;

  /// No description provided for @saveSheetVolumeFiltered.
  ///
  /// In en, this message translates to:
  /// **'Volume filtered'**
  String get saveSheetVolumeFiltered;

  /// No description provided for @saveSheetVolume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get saveSheetVolume;

  /// No description provided for @saveSheetEnterVolume.
  ///
  /// In en, this message translates to:
  /// **'Enter a volume'**
  String get saveSheetEnterVolume;

  /// No description provided for @saveSheetDropNote.
  ///
  /// In en, this message translates to:
  /// **'Drop plate: each drop has its own dilution and replicate (set them in Drops).'**
  String get saveSheetDropNote;

  /// No description provided for @saveSheetSpreader.
  ///
  /// In en, this message translates to:
  /// **'Spreader on plate'**
  String get saveSheetSpreader;

  /// No description provided for @saveSheetSpreaderHelp.
  ///
  /// In en, this message translates to:
  /// **'Excluded from CFU/mL'**
  String get saveSheetSpreaderHelp;

  /// No description provided for @saveSheetTntc.
  ///
  /// In en, this message translates to:
  /// **'Too numerous to count'**
  String get saveSheetTntc;

  /// No description provided for @saveSheetTntcHelp.
  ///
  /// In en, this message translates to:
  /// **'Count is a lower bound'**
  String get saveSheetTntcHelp;

  /// No description provided for @saveSheetIncubation.
  ///
  /// In en, this message translates to:
  /// **'Incubation time (optional)'**
  String get saveSheetIncubation;

  /// No description provided for @saveSheetHoursUnit.
  ///
  /// In en, this message translates to:
  /// **'h'**
  String get saveSheetHoursUnit;

  /// No description provided for @saveSheetIncubationHelp.
  ///
  /// In en, this message translates to:
  /// **'Hours since plating, for time-lapse photos'**
  String get saveSheetIncubationHelp;

  /// No description provided for @saveSheetVerified.
  ///
  /// In en, this message translates to:
  /// **'Checked every colony'**
  String get saveSheetVerified;

  /// No description provided for @saveSheetVerifiedHelp.
  ///
  /// In en, this message translates to:
  /// **'Use this plate as a reference count for accuracy tracking'**
  String get saveSheetVerifiedHelp;

  /// No description provided for @saveSheetNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get saveSheetNotes;

  /// No description provided for @saveSheetAlone.
  ///
  /// In en, this message translates to:
  /// **'This plate alone ({rule})'**
  String saveSheetAlone(Object rule);

  /// No description provided for @saveSheetSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveSheetSave;

  /// No description provided for @methodSpread.
  ///
  /// In en, this message translates to:
  /// **'Spread / pour plate'**
  String get methodSpread;

  /// No description provided for @methodDrop.
  ///
  /// In en, this message translates to:
  /// **'Drop plate (Miles–Misra)'**
  String get methodDrop;

  /// No description provided for @methodMembrane.
  ///
  /// In en, this message translates to:
  /// **'Membrane filtration'**
  String get methodMembrane;

  /// No description provided for @layoutReplicates.
  ///
  /// In en, this message translates to:
  /// **'One dilution per plate, drops = replicates'**
  String get layoutReplicates;

  /// No description provided for @layoutDilutions.
  ///
  /// In en, this message translates to:
  /// **'All dilutions on one plate, one drop each'**
  String get layoutDilutions;

  /// No description provided for @colourOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get colourOff;

  /// No description provided for @colourBlueWhite.
  ///
  /// In en, this message translates to:
  /// **'Blue / white'**
  String get colourBlueWhite;

  /// No description provided for @colourTwo.
  ///
  /// In en, this message translates to:
  /// **'Two colours'**
  String get colourTwo;

  /// No description provided for @classAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get classAll;

  /// No description provided for @classWhite.
  ///
  /// In en, this message translates to:
  /// **'White'**
  String get classWhite;

  /// No description provided for @classBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get classBlue;

  /// No description provided for @classColourA.
  ///
  /// In en, this message translates to:
  /// **'Colour A'**
  String get classColourA;

  /// No description provided for @classColourB.
  ///
  /// In en, this message translates to:
  /// **'Colour B'**
  String get classColourB;

  /// No description provided for @formatDish90.
  ///
  /// In en, this message translates to:
  /// **'90 mm dish'**
  String get formatDish90;

  /// No description provided for @formatDish60.
  ///
  /// In en, this message translates to:
  /// **'60 mm dish'**
  String get formatDish60;

  /// No description provided for @formatDish100.
  ///
  /// In en, this message translates to:
  /// **'100 mm dish'**
  String get formatDish100;

  /// No description provided for @formatDish150.
  ///
  /// In en, this message translates to:
  /// **'150 mm dish'**
  String get formatDish150;

  /// No description provided for @formatSquare100.
  ///
  /// In en, this message translates to:
  /// **'100 mm square plate'**
  String get formatSquare100;

  /// No description provided for @formatSquare120.
  ///
  /// In en, this message translates to:
  /// **'120 mm square plate'**
  String get formatSquare120;

  /// No description provided for @formatMembrane47.
  ///
  /// In en, this message translates to:
  /// **'47 mm membrane filter'**
  String get formatMembrane47;

  /// No description provided for @ruleDrop.
  ///
  /// In en, this message translates to:
  /// **'Drop 3–30'**
  String get ruleDrop;

  /// No description provided for @ruleMembrane80.
  ///
  /// In en, this message translates to:
  /// **'Membrane 20–80'**
  String get ruleMembrane80;

  /// No description provided for @ruleMembrane200.
  ///
  /// In en, this message translates to:
  /// **'Membrane 20–200'**
  String get ruleMembrane200;

  /// No description provided for @trainingChecked.
  ///
  /// In en, this message translates to:
  /// **'Checked plates only'**
  String get trainingChecked;

  /// No description provided for @trainingCorrected.
  ///
  /// In en, this message translates to:
  /// **'Checked and corrected plates'**
  String get trainingCorrected;

  /// No description provided for @trainingAll.
  ///
  /// In en, this message translates to:
  /// **'All plates'**
  String get trainingAll;

  /// No description provided for @flagSpreader.
  ///
  /// In en, this message translates to:
  /// **'Spreader'**
  String get flagSpreader;

  /// No description provided for @flagTntc.
  ///
  /// In en, this message translates to:
  /// **'Too many to count'**
  String get flagTntc;

  /// No description provided for @flagClusters.
  ///
  /// In en, this message translates to:
  /// **'Clusters estimated'**
  String get flagClusters;

  /// No description provided for @flagCrowded.
  ///
  /// In en, this message translates to:
  /// **'Crowded plate'**
  String get flagCrowded;

  /// No description provided for @flagManyClusters.
  ///
  /// In en, this message translates to:
  /// **'Many touching colonies'**
  String get flagManyClusters;

  /// No description provided for @flagLowContrast.
  ///
  /// In en, this message translates to:
  /// **'Faint colonies'**
  String get flagLowContrast;

  /// No description provided for @neat.
  ///
  /// In en, this message translates to:
  /// **'Neat'**
  String get neat;

  /// No description provided for @unlabelled.
  ///
  /// In en, this message translates to:
  /// **'Unlabelled'**
  String get unlabelled;

  /// No description provided for @dropPlateDrops.
  ///
  /// In en, this message translates to:
  /// **'drop plate ({n, plural, =1{1 drop} other{{n} drops}})'**
  String dropPlateDrops(int n);

  /// No description provided for @noteAllSpreaders.
  ///
  /// In en, this message translates to:
  /// **'all plates have spreaders'**
  String get noteAllSpreaders;

  /// No description provided for @noteNoColonies.
  ///
  /// In en, this message translates to:
  /// **'no colonies on least diluted plate'**
  String get noteNoColonies;

  /// No description provided for @noteBelowRange.
  ///
  /// In en, this message translates to:
  /// **'below countable range ({range})'**
  String noteBelowRange(Object range);

  /// No description provided for @noteAboveRange.
  ///
  /// In en, this message translates to:
  /// **'above countable range ({range})'**
  String noteAboveRange(Object range);

  /// No description provided for @noteTntc.
  ///
  /// In en, this message translates to:
  /// **'too numerous to count'**
  String get noteTntc;

  /// No description provided for @noteNoPlateInRange.
  ///
  /// In en, this message translates to:
  /// **'no plate in countable range'**
  String get noteNoPlateInRange;

  /// No description provided for @estimatePrefix.
  ///
  /// In en, this message translates to:
  /// **'est. '**
  String get estimatePrefix;

  /// No description provided for @noEstimate.
  ///
  /// In en, this message translates to:
  /// **'no estimate'**
  String get noEstimate;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'th'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'th':
      return AppLocalizationsTh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
