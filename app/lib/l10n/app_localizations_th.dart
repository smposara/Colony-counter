// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Thai (`th`).
class AppLocalizationsTh extends AppLocalizations {
  AppLocalizationsTh([String locale = 'th']) : super(locale);

  @override
  String get aboutTitle => 'เกี่ยวกับแอป';

  @override
  String get aboutTagline =>
      'นับโคโลนี (CFU) บนจานอาหารเลี้ยงเชื้อด้วยกล้องโทรศัพท์';

  @override
  String aboutVersion(String version, int build) {
    return 'เวอร์ชัน $version (บิลด์ $build)';
  }

  @override
  String get aboutDeveloper => 'ผู้พัฒนา';

  @override
  String get aboutEmail => 'อีเมล';

  @override
  String get aboutWebsite => 'เว็บไซต์';

  @override
  String get aboutSource => 'ซอร์สโค้ด';

  @override
  String get aboutLicense => 'สัญญาอนุญาต';

  @override
  String get aboutLicenseText =>
      'ซอฟต์แวร์เสรีและโอเพนซอร์ส ใช้งาน ศึกษา แจกจ่าย และแก้ไขได้ หากนำฉบับที่แก้ไขไปให้ผู้อื่นใช้ รวมถึงให้บริการเป็นเว็บไซต์ ต้องเปิดเผยซอร์สโค้ดภายใต้สัญญาอนุญาตเดียวกัน';

  @override
  String get aboutOpenSource => 'สัญญาอนุญาตโอเพนซอร์ส';

  @override
  String get aboutOpenSourceSub => 'ไลบรารีและฟอนต์ที่แอปใช้';

  @override
  String get aboutPrivacy => 'ความเป็นส่วนตัว';

  @override
  String get aboutPrivacyText =>
      'การนับทำงานบนอุปกรณ์นี้ ภาพถ่ายและผลการนับเก็บไว้ในอุปกรณ์นี้ (หรือในเบราว์เซอร์นี้) เว้นแต่คุณส่งออกหรือแชร์เอง';

  @override
  String get aboutIntendedUse => 'วัตถุประสงค์การใช้งาน';

  @override
  String get aboutIntendedUseText =>
      'สำหรับงานวิจัยและการเรียนการสอน ไม่ใช่เครื่องมือทางการแพทย์หรือการวินิจฉัย โปรดตรวจสอบผลการนับอัตโนมัติทุกครั้ง';

  @override
  String aboutCopyright(int year, String developer) {
    return '© $year $developer';
  }

  @override
  String aboutCannotOpen(String target) {
    return 'เปิด $target ไม่ได้';
  }

  @override
  String get aboutPrivacyPolicy => 'นโยบายความเป็นส่วนตัว';

  @override
  String get aboutStand => 'แท่นถ่ายภาพพิมพ์ 3 มิติ';

  @override
  String get sampleKind => 'ชนิดตัวอย่าง';

  @override
  String get sampleLiquid => 'ของเหลว (CFU/mL)';

  @override
  String get sampleSolid => 'ของแข็ง (CFU/g)';

  @override
  String get sampleWeight => 'น้ำหนักตัวอย่าง';

  @override
  String get diluentVolume => 'สารละลายเจือจาง';

  @override
  String get solidTenfold =>
      'สารแขวนลอยเริ่มต้นเป็น 1:10 จึงนับเป็นระดับการเจือจาง 10⁻¹ ให้ระบุระดับการเจือจางรวมของตัวอย่างบนเพลต (เช่น 10⁻² สำหรับหลอดถัดไป)';

  @override
  String solidOther(String ratio, String factor) {
    return 'สารแขวนลอยเริ่มต้นเป็น 1:$ratio ให้ระบุระดับการเจือจางบนเพลตเสมือนเป็น 10⁻¹ ผลลัพธ์จะถูกปรับด้วย ×$factor';
  }

  @override
  String get homeSamples => 'ตัวอย่าง';

  @override
  String get homeCompare => 'เปรียบเทียบ';

  @override
  String get homePlates => 'เพลต';

  @override
  String get homeSeveralPlates => 'หลายเพลตในภาพเดียว';

  @override
  String get homeImportPhoto => 'นำเข้าภาพ';

  @override
  String get homeScanLabel => 'สแกนฉลากเพลต';

  @override
  String get homeCountPlate => 'นับเพลต';

  @override
  String get homeNewSample => 'ตัวอย่างใหม่';

  @override
  String get homeShareCounts => 'จำนวนโคโลนี';

  @override
  String get homeShareTraining => 'ข้อมูลสำหรับฝึกโมเดลจาก Colony Counter';

  @override
  String get homeShareBackup => 'ข้อมูลสำรอง Colony Counter';

  @override
  String get homeExportTraining => 'ส่งออกข้อมูลสำหรับฝึกโมเดล';

  @override
  String get homeTrainingInfo =>
      'ภาพถ่ายพร้อมตำแหน่งทุกโคโลนีในรูปแบบ COCO และ YOLO สำหรับฝึกโมเดลตรวจจับโคโลนีด้วยเพลตของคุณเอง';

  @override
  String get homeNoPlatesToExport => 'ไม่มีเพลตให้ส่งออก';

  @override
  String get homePreparingExport => 'กำลังเตรียมส่งออก…';

  @override
  String get homePreparingBackup => 'กำลังเตรียมข้อมูลสำรอง…';

  @override
  String homeNPlates(int n) {
    return '$n เพลต';
  }

  @override
  String homeNSamples(int n) {
    return '$n ตัวอย่าง';
  }

  @override
  String homeRestored(String plates, String samples) {
    return 'กู้คืน $plates และ $samples แล้ว';
  }

  @override
  String homeRestoredKept(String plates, String samples, int skipped) {
    return 'กู้คืน $plates และ $samples แล้ว (มีอยู่แล้ว $skipped เพลต เก็บไว้)';
  }

  @override
  String get homeExportCsv => 'ส่งออก CSV';

  @override
  String get homeBackUpAll => 'สำรองข้อมูลทั้งหมด';

  @override
  String get homeRestore => 'กู้คืนจากข้อมูลสำรอง';

  @override
  String get homeSettings => 'การตั้งค่า';

  @override
  String get homeCountingRule => 'เกณฑ์การนับ';

  @override
  String homeCountableRange(int min, int max) {
    return 'ช่วงที่นับได้: $min–$max โคโลนีต่อเพลต';
  }

  @override
  String get homeDefaultVolume => 'ปริมาตรที่เพาะเริ่มต้น';

  @override
  String get homeDefaultPlateType => 'ชนิดจานเริ่มต้น';

  @override
  String get homeDefaultPlateTypeHelp => 'ใช้กับการนับด่วนและตัวอย่างใหม่';

  @override
  String get homeNoPlates => 'ยังไม่มีเพลต';

  @override
  String get homeEmptyHint =>
      'วางเพลต Nutrient Agar ขนาด 90 มม. แบบเปิดฝาในกล่องไฟ แล้วแตะ “นับเพลต”';

  @override
  String get homeDeletePlate => 'ลบเพลตนี้หรือไม่';

  @override
  String get homeDeletePlateBody =>
      'ภาพถ่ายและจำนวนนับจะถูกลบออกจากโทรศัพท์เครื่องนี้';

  @override
  String get homeCancel => 'ยกเลิก';

  @override
  String get homeDelete => 'ลบ';

  @override
  String get homeFlagged => 'ถูกแจ้งให้ตรวจ';

  @override
  String get homeChecked => 'ตรวจทุกโคโลนีแล้ว';

  @override
  String get homeTimelapse => 'ไทม์แลปส์';

  @override
  String get accuracyTitle => 'ความแม่นยำการนับ';

  @override
  String get accuracyNoChecked => 'ยังไม่มีเพลตที่ตรวจแล้ว';

  @override
  String get accuracyHowTo =>
      'ตรวจทุกโคโลนีบนเพลตเป็นครั้งคราว: ซูมเข้า ลบเครื่องหมายที่ผิด เพิ่มโคโลนีที่พลาด และกำหนดกลุ่มโคโลนี แล้วเปิด \"ตรวจทุกโคโลนีแล้ว\" ตอนบันทึก แอปจะเทียบจำนวนนับของแอปกับของคุณ และแสดงความแม่นยำบนเพลตของคุณที่นี่';

  @override
  String accuracyCheckedPlates(int n) {
    return 'ตรวจแล้ว $n เพลต';
  }

  @override
  String accuracyWithin10(String pct) {
    return '$pct % ของเพลตคลาดเคลื่อนไม่เกิน ±10 %';
  }

  @override
  String accuracyOfChecked(String plates) {
    return 'จากจำนวนที่ตรวจแล้ว · $plates';
  }

  @override
  String get accuracyMeanError => 'ความคลาดเคลื่อนเฉลี่ย';

  @override
  String get accuracyBias => 'ความเอนเอียง';

  @override
  String get accuracyColoniesOff => 'โคโลนีที่คลาดโดยเฉลี่ย';

  @override
  String get accuracyPrecision => 'ของเครื่องหมายเป็นโคโลนีจริง';

  @override
  String get accuracyRecall => 'ของโคโลนีที่พบ';

  @override
  String get accuracyFootnote =>
      'ร้อยละคิดจากเพลตที่มี 10 โคโลนีขึ้นไป ความเอนเอียงติดลบหมายถึงแอปนับได้น้อยเกินไป';

  @override
  String get accuracyScatterTitle => 'จำนวนนับอัตโนมัติเทียบกับที่ตรวจแล้ว';

  @override
  String get accuracyNotFlagged => 'ไม่ถูกแจ้ง';

  @override
  String get accuracyScatterHint =>
      'แตะจุดเพื่อดูรายละเอียด จุดใต้เส้น: แอปนับได้น้อยเกินไป แถบแรเงา: คลาดเคลื่อนไม่เกิน ±10 %';

  @override
  String accuracyPointDetail(String plate, String date, int auto, int checked) {
    return '$plate · $date: แอป $auto, ตรวจแล้ว $checked';
  }

  @override
  String get accuracyAxisChecked => 'จำนวนที่ตรวจ →';

  @override
  String accuracyRangeColonies(String range) {
    return '$range โคโลนี';
  }

  @override
  String get accuracyErrorsTitle => 'ความคลาดเคลื่อนเกิดที่ไหน';

  @override
  String get accuracyColPlates => 'เพลต';

  @override
  String get accuracyWarningsUseful =>
      'ถ้าคำเตือนมีประโยชน์ เพลตที่ถูกแจ้งจะมีความคลาดเคลื่อนมากกว่า';

  @override
  String get accuracyCheckedPlatesTitle => 'เพลตที่ตรวจแล้ว';

  @override
  String accuracyAppVsChecked(int auto, int checked) {
    return 'แอป $auto · ตรวจแล้ว $checked';
  }

  @override
  String get accuracyAskCheck => 'ขอให้ฉันตรวจเพลต';

  @override
  String get accuracyNever => 'ไม่ต้อง';

  @override
  String accuracyEvery(int n) {
    return 'ทุก $n เพลต';
  }

  @override
  String get accuracyAskCheckHelp =>
      'หน้าตรวจทานจะขอให้คุณตรวจทุกโคโลนีบนเพลตนั้นก่อนบันทึก';

  @override
  String timelapseHours(String h) {
    return '$h ชม.';
  }

  @override
  String get timelapseNoPhotos => 'ไม่มีภาพถ่ายในชุดนี้';

  @override
  String get timelapseShareCsv => 'แชร์ตารางโคโลนี (CSV)';

  @override
  String get timelapseAddLater => 'เพิ่มภาพถ่ายภายหลัง';

  @override
  String timelapsePhotos(int n) {
    return '$n ภาพ';
  }

  @override
  String get timelapseSincePlating => 'ชม. นับจากเพาะเชื้อ';

  @override
  String get timelapseSinceFirst => 'ชม. นับจากภาพแรก';

  @override
  String timelapseColoniesAt(int n, String time) {
    return '$n โคโลนีที่ $time';
  }

  @override
  String timelapseAppeared(int n, String time) {
    return '$n โคโลนีปรากฏหลังภาพแรก · ครึ่งหนึ่งปรากฏภายใน $time';
  }

  @override
  String timelapseGrowth(String rate) {
    return 'อัตราการโตของเส้นผ่านศูนย์กลาง (มัธยฐาน) $rate mm/h';
  }

  @override
  String get timelapseAddLaterHint =>
      'เพิ่มภาพถ่ายภายหลังของเพลตเดิม เพื่อดูว่าโคโลนีปรากฏเมื่อใดและโตเร็วเพียงใด';

  @override
  String get timelapseMatching =>
      'โคโลนีถูกจับคู่ระหว่างภาพตามตำแหน่ง หลังจากหมุนและกลับด้านภาพก่อนหน้าให้ตรงกับภาพถัดไป หากช่วงแรกเห็นโคโลนีน้อย ให้วางเพลตในทิศเดิมทุกครั้ง';

  @override
  String get timelapseChartTitle => 'จำนวนโคโลนีตามเวลา';

  @override
  String get timelapsePhotosTitle => 'ภาพถ่าย';

  @override
  String timelapsePhotoRow(String time, int n) {
    return '$time · $n โคโลนี';
  }

  @override
  String timelapseFirstSeen(int n) {
    return 'พบครั้งแรก $n';
  }

  @override
  String timelapseTurned(int deg) {
    return 'หมุน $deg° ให้ตรงกับภาพถัดไป';
  }

  @override
  String timelapseTurnedMirrored(int deg) {
    return 'หมุน $deg° และกลับด้านให้ตรงกับภาพถัดไป';
  }

  @override
  String get timelapseAppearanceTitle => 'เวลาที่แต่ละโคโลนีปรากฏ';

  @override
  String timelapseBy(String time) {
    return 'ภายใน $time';
  }

  @override
  String get compareEmpty =>
      'ตั้งชื่อการทดลองเดียวกันให้ตัวอย่างและระบุสภาวะ (เช่น ชุดควบคุม / ทดสอบ) และจุดเวลาหากต้องการ เพื่อเปรียบเทียบที่นี่: log reduction, อัตราการฆ่า (%) และกราฟ time-kill หรือกราฟการเจริญ';

  @override
  String get compareExperiment => 'การทดลอง';

  @override
  String get compareControl => 'ชุดควบคุม';

  @override
  String compareOverTime(String unit) {
    return 'log₁₀ $unit ตามเวลา';
  }

  @override
  String get compareChartHint => 'ค่าเฉลี่ย ± SD ของซ้ำ แตะจุดเพื่อดูค่า';

  @override
  String get compareResults => 'ผลลัพธ์';

  @override
  String get compareCondition => 'สภาวะ';

  @override
  String compareReductionVs(String control) {
    return 'การลดลงเทียบกับ $control';
  }

  @override
  String get compareReductionHelp =>
      'log reduction = ค่าเฉลี่ย log₁₀(ชุดควบคุม) − ค่าเฉลี่ย log₁₀(ชุดทดสอบ) SD รวมจากทั้งสองกลุ่ม อัตราการฆ่า (%) คำนวณจากค่าเฉลี่ยเรขาคณิต';

  @override
  String get compareTime => 'เวลา';

  @override
  String get compareLogReduction => 'log reduction';

  @override
  String get compareKill => 'อัตราการฆ่า (%)';

  @override
  String get compareSamples => 'ตัวอย่าง';

  @override
  String get appTitle => 'Colony Counter';

  @override
  String get settingsLanguage => 'ภาษา';

  @override
  String get languageSystem => 'ตามเครื่อง';

  @override
  String get settingsTheme => 'รูปแบบการแสดงผล';

  @override
  String get themeSystem => 'อัตโนมัติ';

  @override
  String get themeLight => 'สว่าง';

  @override
  String get themeDark => 'มืด';

  @override
  String get restoreNotZip =>
      'ไฟล์นี้ไม่ใช่ไฟล์สำรองข้อมูลของ Colony Counter (ไม่ใช่ไฟล์ zip)';

  @override
  String get restoreNotBackup =>
      'ไฟล์ zip นี้ไม่ใช่ไฟล์สำรองข้อมูลของ Colony Counter';

  @override
  String get methodFilm => 'Petrifilm (ฟิล์มแห้ง)';

  @override
  String get formatFilmAc => 'Petrifilm AC (จุลินทรีย์ทั้งหมด)';

  @override
  String get formatFilmEc => 'Petrifilm EC (อี. โคไล/โคลิฟอร์ม)';

  @override
  String get formatFilmCc => 'Petrifilm CC (โคลิฟอร์ม)';

  @override
  String get formatFilmEb => 'Petrifilm EB (เอนเทอโรแบคทีเรียซีอี)';

  @override
  String get formatFilmYm => 'Petrifilm YM (ยีสต์และรา)';

  @override
  String get setupFilm => 'ฟิล์ม';

  @override
  String get filmType => 'ชนิดฟิล์ม';

  @override
  String filmRangeFromType(int min, int max) {
    return 'ช่วงที่นับได้ $min–$max ต่อแผ่น ตามชนิดฟิล์ม ปริมาตรปกติ 1 mL';
  }

  @override
  String get resultAerobic => 'จุลินทรีย์ทั้งหมด';

  @override
  String get resultEcoli => 'อี. โคไล';

  @override
  String get resultColiform => 'โคลิฟอร์ม';

  @override
  String get resultEnterobacteriaceae => 'เอนเทอโรแบคทีเรียซีอี';

  @override
  String get resultYeast => 'ยีสต์';

  @override
  String get resultMold => 'รา';

  @override
  String get kindColony => 'โคโลนี';

  @override
  String get kindRed => 'สีแดง';

  @override
  String get kindBlue => 'สีน้ำเงิน';

  @override
  String get kindYeast => 'ยีสต์';

  @override
  String get kindMold => 'รา';

  @override
  String get reviewModeKind => 'ชนิด';

  @override
  String get reviewModeGas => 'แก๊ส';

  @override
  String get reviewModeSquares => 'ช่อง';

  @override
  String get reviewHintSquares =>
      'แตะช่องตารางเพื่อไม่นำมาประมาณ (มีฟอง รอยพับ หรือการแผ่กระจาย) หรือแตะอีกครั้งเพื่อนำกลับมา';

  @override
  String reviewFilmSquaresLeftOut(int n) {
    return 'ไม่นับ $n ช่อง';
  }

  @override
  String reviewFilmGasSplit(String kind, int withGas, int without) {
    return '$kind: มีแก๊ส $withGas ไม่มีแก๊ส $without';
  }

  @override
  String get reviewModeYellow => 'โซน';

  @override
  String reviewHintKind(Object a, Object b) {
    return 'แตะโคโลนีเพื่อสลับระหว่าง$aและ$b';
  }

  @override
  String get reviewHintGas =>
      'แตะโคโลนีเพื่อทำเครื่องหมายหรือยกเลิกฟองแก๊สข้างโคโลนี (วงสีขาว)';

  @override
  String get reviewHintYellow =>
      'แตะโคโลนีเพื่อทำเครื่องหมายหรือยกเลิกโซนสีเหลืองรอบโคโลนี (วงสีเหลือง)';

  @override
  String reviewFilmMarks(int n) {
    return 'จุดที่ทำเครื่องหมาย';
  }

  @override
  String reviewFilmRedNoGas(int n) {
    return 'สีแดงไม่มีแก๊ส $n (ไม่นับ)';
  }

  @override
  String reviewFilmNotCounted(int n) {
    return 'ไม่นับ $n (ไม่มีแก๊สหรือโซน)';
  }

  @override
  String reviewFilmEstimate(int n) {
    return 'เกินช่วงที่นับได้: ประมาณจากช่องตารางที่สมบูรณ์ $n ช่อง × 20 cm²';
  }

  @override
  String get reviewFilmFewSquares =>
      'เกินช่วงที่นับได้ แต่พบช่องตารางที่สมบูรณ์น้อยกว่า 3 ช่อง จึงแสดงจำนวนที่นับได้';

  @override
  String get reviewFilmNoGrid =>
      'ไม่พบตารางที่พิมพ์บนฟิล์ม มาตราส่วนและผลการนับนี้อาจผิด ภาพนี้เป็นแผ่น Petrifilm ที่วางเรียบ ชัด และไม่มีแสงสะท้อนหรือไม่? ถ่ายภาพใหม่หรือตรวจทุกโคโลนี';

  @override
  String get reviewFilmAid =>
      'การนับฟิล์มอัตโนมัติเป็นตัวช่วย: ตรวจสอบกับคู่มือการอ่านผล';

  @override
  String get flagEstimated => 'ประมาณจากช่องตาราง';

  @override
  String get flagGridNotFound => 'ไม่พบตาราง';

  @override
  String get flagAreaSize => 'ขนาดพื้นที่เพาะเชื้อผิดปกติ';

  @override
  String get captureFilmTip =>
      'วางฟิล์มให้เรียบบนพื้นสีเรียบ ถ่ายตรงลงด้านล่าง และหลีกเลี่ยงแสงสะท้อนบนฟิล์มใสด้านบน';

  @override
  String get aboutPetrifilmTitle => 'ฟิล์มแห้ง';

  @override
  String get aboutPetrifilm =>
      'อ่านแผ่น Neogen® Petrifilm® ชนิด AC, EC, CC, EB และ YM โดย Petrifilm และ Neogen เป็นเครื่องหมายการค้าของ Neogen Corporation แอปนี้ไม่ได้จัดทำหรือรับรองโดย Neogen ผลการนับเป็นตัวช่วยที่ต้องตรวจสอบ ไม่ใช่ผลที่ผ่านการรับรองตาม AOAC';

  @override
  String get photoReadingLabel => 'กำลังอ่านฉลากเพลต…';

  @override
  String get photoNoLabelFound =>
      'ไม่พบฉลากเพลต ให้ QR code เต็มกรอบภาพแล้วลองอีกครั้ง';

  @override
  String captureLockNotSupported(String error) {
    return 'ล็อกไม่ได้: $error';
  }

  @override
  String captureFailed(String error) {
    return 'ถ่ายภาพไม่สำเร็จ: $error';
  }

  @override
  String get capturePhotographPlate => 'ถ่ายภาพเพลต';

  @override
  String captureCameraUnavailable(String error) {
    return 'ใช้กล้องไม่ได้: $error';
  }

  @override
  String get captureLevel => 'ได้ระดับ';

  @override
  String captureTilt(String deg) {
    return 'เอียง $deg°';
  }

  @override
  String get captureSharp => 'คมชัด';

  @override
  String get captureFocusing => 'กำลังโฟกัส…';

  @override
  String get captureNoGlare => 'ไม่มีแสงสะท้อน';

  @override
  String get captureGlare => 'แสงสะท้อน: เปิดฝา / ลดแสง';

  @override
  String get captureUnlock => 'ปลดล็อกโฟกัสและการรับแสง';

  @override
  String get captureLock => 'ล็อกโฟกัสและการรับแสง';

  @override
  String get multiRoundOnly =>
      'การนับหลายเพลตในภาพเดียวใช้ได้กับจานกลมเท่านั้น';

  @override
  String get multiLayPlates =>
      'วางเพลตเรียงกันบนพื้นสีเข้ม เปิดฝาออก แล้วถ่ายภาพจากด้านบนตรง ๆ';

  @override
  String get multiTakePhoto => 'ถ่ายภาพ';

  @override
  String get multiChoosePhoto => 'เลือกภาพ';

  @override
  String get multiNoPlatesFound => 'ไม่พบเพลตในภาพนี้';

  @override
  String get multiPlatesInPhoto => 'เพลตในภาพ';

  @override
  String multiPlatesFound(int n) {
    return 'พบ $n เพลต';
  }

  @override
  String get multiDone => 'เสร็จ';

  @override
  String get multiAddRemove => 'เพิ่มหรือลบเพลต';

  @override
  String get multiEditHint =>
      'แตะวงกลมเพื่อลบ หรือแตะกลางเพลตที่ตกหล่นเพื่อเพิ่ม';

  @override
  String get multiUsePencil => 'ใช้ปุ่มดินสอเพื่อระบุตำแหน่งเพลต';

  @override
  String get multiAllSaved => 'บันทึกครบทุกเพลตแล้ว';

  @override
  String multiTapToCount(int n) {
    return 'แตะเพลตเพื่อนับ เหลืออีก $n เพลตที่ยังไม่บันทึก';
  }

  @override
  String get reviewPhotoMissing => 'ไม่พบภาพถ่ายของเพลตนี้';

  @override
  String reviewCouldNotCount(String error) {
    return 'นับภาพนี้ไม่ได้: $error';
  }

  @override
  String get reviewRecountTitle => 'นับเพลตใหม่?';

  @override
  String get reviewRecountBody => 'การเพิ่มและลบที่แก้ไขเองจะถูกทิ้งทั้งหมด';

  @override
  String get reviewCancel => 'ยกเลิก';

  @override
  String get reviewRecount => 'นับใหม่';

  @override
  String get reviewPlateType => 'ชนิดจาน';

  @override
  String get reviewShareSubject => 'จำนวนโคโลนี';

  @override
  String reviewCouldNotShare(String error) {
    return 'แชร์ภาพไม่ได้: $error';
  }

  @override
  String get reviewDiscardTitle => 'ทิ้งการนับนี้?';

  @override
  String get reviewDiscardBody => 'ยังไม่ได้บันทึก';

  @override
  String get reviewKeep => 'เก็บไว้';

  @override
  String get reviewDiscard => 'ทิ้ง';

  @override
  String get reviewTitle => 'ตรวจผลการนับ';

  @override
  String get reviewUndo => 'เลิกทำ';

  @override
  String get reviewHideMarks => 'ซ่อนเครื่องหมาย';

  @override
  String get reviewShowMarks => 'แสดงเครื่องหมาย';

  @override
  String get reviewHintMarksHidden =>
      'ซ่อนเครื่องหมายอยู่ เพื่อดูภาพรวมของเพลต แตะรูปตาเพื่อแสดงอีกครั้งและแก้ไข';

  @override
  String get reviewSensitivity => 'ความไวในการตรวจจับ';

  @override
  String get reviewMenuTooltip => 'ชนิดจานและสี';

  @override
  String get reviewShareAnnotated => 'แชร์ภาพที่มีเครื่องหมาย';

  @override
  String get reviewAddLaterPhoto => 'เพิ่มภาพถ่ายภายหลัง (ไทม์แลปส์)';

  @override
  String get reviewTimelapse => 'ไทม์แลปส์';

  @override
  String reviewPlateTypeItem(String type) {
    return 'ชนิดจาน: $type…';
  }

  @override
  String get reviewDropPlate => 'ดรอปเพลต';

  @override
  String reviewColoursItem(String mode) {
    return 'สี: $mode';
  }

  @override
  String get reviewCounting => 'กำลังนับโคโลนี…';

  @override
  String reviewAdded(int n) {
    return '+$n เพิ่ม';
  }

  @override
  String reviewRemoved(int n) {
    return '−$n ลบออก';
  }

  @override
  String reviewInClusters(int n) {
    return '+$n ในกลุ่มโคโลนี';
  }

  @override
  String get reviewModeZoom => 'ซูม';

  @override
  String get reviewModeEdit => 'แก้ไข';

  @override
  String get reviewModePlate => 'เพลต';

  @override
  String get reviewModeDrops => 'หยด';

  @override
  String get reviewModeColour => 'สี';

  @override
  String get reviewAutomatic => 'อัตโนมัติ';

  @override
  String reviewAutoEdits(int auto, String edits) {
    return 'อัตโนมัติ $auto · $edits';
  }

  @override
  String get reviewHintZoom => 'ใช้สองนิ้วเพื่อซูม ลากเพื่อเลื่อนภาพ';

  @override
  String get reviewHintEdit =>
      'แตะเครื่องหมายเพื่อลบ แตะบนอาหารเลี้ยงเชื้อที่ว่างเพื่อเพิ่ม กดค้างที่เครื่องหมายเพื่อกำหนดจำนวนโคโลนีในจุดนั้น';

  @override
  String get reviewHintSquare =>
      'ลากเพื่อย้ายกรอบสี่เหลี่ยม ใช้แถบเลื่อนเพื่อปรับขนาดและหมุน แล้วนับใหม่';

  @override
  String get reviewHintCircle =>
      'ลากเพื่อย้ายวงกลม ใช้แถบเลื่อนเพื่อปรับขนาด แล้วนับใหม่';

  @override
  String get reviewHintDrops =>
      'แตะหยดเพื่อกำหนดระดับการเจือจางและซ้ำ แตะบนอาหารเลี้ยงเชื้อที่ว่างเพื่อเพิ่มหยด ลากหยดเพื่อย้าย';

  @override
  String get reviewHintColour => 'แตะโคโลนีเพื่อสลับกลุ่มสี';

  @override
  String get reviewSize => 'ขนาด';

  @override
  String get reviewRecountSquare => 'นับใหม่ด้วยกรอบนี้';

  @override
  String get reviewRecountCircle => 'นับใหม่ด้วยวงกลมนี้';

  @override
  String get reviewSavePlate => 'บันทึกเพลต';

  @override
  String get reviewSaveChanges => 'บันทึกการแก้ไข';

  @override
  String reviewCheckCount(String warnings) {
    return 'โปรดตรวจผลการนับนี้ ($warnings) ซูมเข้าไปแก้เครื่องหมายที่ขาดหรือเกินก่อนบันทึก';
  }

  @override
  String get reviewAccuracyCheck =>
      'ตรวจความแม่นยำ: โปรดตรวจทุกโคโลนีบนเพลตนี้ ผลจะถูกบันทึกเป็นจำนวนอ้างอิงเพื่อติดตามความแม่นยำของการนับอัตโนมัติกับเพลตของคุณ';

  @override
  String reviewClassCount(String name, int n) {
    return '$name $n';
  }

  @override
  String reviewClassPercent(String percent, String name) {
    return '$name $percent %';
  }

  @override
  String get reviewNoDrops => 'ยังไม่ได้ระบุหยด ใช้โหมด หยด เพื่อเพิ่ม';

  @override
  String get reviewClusterTitle => 'จำนวนโคโลนีในจุดนี้';

  @override
  String get reviewSet => 'ตั้งค่า';

  @override
  String get reviewSensitivityHelp =>
      'ค่าสูงจะพบโคโลนีที่จางและเล็กกว่า แต่อาจนับเศษสิ่งปนเปื้อนด้วย ค่าเริ่มต้น: 6.5';

  @override
  String get reviewLow => 'ต่ำ';

  @override
  String get reviewHigh => 'สูง';

  @override
  String reviewDropTitle(int index, int n) {
    return 'หยดที่ $index · $n โคโลนี';
  }

  @override
  String get reviewDilution => 'ระดับการเจือจาง';

  @override
  String get reviewReplicate => 'ซ้ำที่';

  @override
  String get reviewTntc => 'มากเกินนับ (TNTC)';

  @override
  String get reviewConfluent => 'หยดที่โคโลนีเจริญรวมกันเป็นแผ่น';

  @override
  String reviewDropSize(String mm) {
    return 'ขนาด $mm มม.';
  }

  @override
  String get reviewDeleteDrop => 'ลบหยด';

  @override
  String get reviewOk => 'ตกลง';

  @override
  String samplesNotFoundTitle(Object id) {
    return 'ไม่พบตัวอย่าง “$id”';
  }

  @override
  String get samplesSetUpNow => 'ตั้งค่าตัวอย่างนี้ตอนนี้หรือไม่';

  @override
  String get samplesCancel => 'ยกเลิก';

  @override
  String get samplesSetUp => 'ตั้งค่า';

  @override
  String get samplesPhotographNow => 'ถ่ายภาพเพลตนี้ตอนนี้หรือไม่';

  @override
  String get samplesJustOpen => 'เปิดตัวอย่างเท่านั้น';

  @override
  String get samplesPhotograph => 'ถ่ายภาพ';

  @override
  String samplesAlreadyCounted(Object plate) {
    return '$plate นับแล้ว';
  }

  @override
  String get samplesNoResult => 'ยังไม่มีผล';

  @override
  String get samplesEstimated => 'ประมาณ';

  @override
  String samplesHours(Object h) {
    return '$h ชม.';
  }

  @override
  String get samplesEmpty =>
      'ตั้งค่าตัวอย่างเพื่อวางแผนระดับการเจือจางและจำนวนซ้ำ แอปจะบอกว่าต้องถ่ายภาพเพลตใดต่อไป และรายงานค่าเฉลี่ย ± SD และ log₁₀ CFU/mL ของทุกซ้ำ';

  @override
  String get samplesSearchHint => 'ค้นหาตัวอย่าง สายพันธุ์ ผู้ปฏิบัติงาน แท็ก…';

  @override
  String get samplesNoMatch => 'ไม่พบตัวอย่างที่ตรงกัน';

  @override
  String get samplesNoExperiment => 'ไม่ระบุการทดลอง';

  @override
  String samplesPlatesDone(int done, int total) {
    return '$done/$total เพลต';
  }

  @override
  String samplesPlateCount(int n) {
    return '$n เพลต';
  }

  @override
  String get samplesSlotPlate => 'เพลต';

  @override
  String samplesLabelsSubject(Object id) {
    return 'ฉลากเพลตของ $id';
  }

  @override
  String samplesDeleteTitle(Object id) {
    return 'ลบ $id หรือไม่';
  }

  @override
  String get samplesDeletePlanOnly => 'แผนการเพาะของตัวอย่างนี้จะถูกลบ';

  @override
  String samplesDeleteAsk(int n) {
    return 'ลบเฉพาะแผนการเพาะและเก็บ $n เพลตไว้ หรือลบเพลตด้วย';
  }

  @override
  String get samplesKeepPlates => 'เก็บเพลตไว้';

  @override
  String get samplesDeleteAll => 'ลบทั้งหมด';

  @override
  String get samplesDelete => 'ลบ';

  @override
  String get samplesEditPlan => 'แก้ไขแผนการเพาะ';

  @override
  String get samplesCreatePlan => 'สร้างแผนการเพาะ';

  @override
  String get samplesNewLikeThis => 'สร้างตัวอย่างใหม่แบบนี้';

  @override
  String get samplesMulti => 'ถ่ายภาพหลายเพลตพร้อมกัน';

  @override
  String get samplesPrintLabels => 'พิมพ์ฉลากเพลต (PDF)';

  @override
  String get samplesDeleteSample => 'ลบตัวอย่าง';

  @override
  String get samplesPlates => 'เพลต';

  @override
  String samplesDropsUl(Object v) {
    return 'หยดละ $v µL';
  }

  @override
  String samplesMlFiltered(Object v) {
    return 'กรอง $v mL';
  }

  @override
  String samplesMlPerPlate(Object v) {
    return '$v mL ต่อเพลต';
  }

  @override
  String samplesPhotographSlot(Object slot) {
    return 'ถ่ายภาพ $slot';
  }

  @override
  String samplesImportFor(Object slot) {
    return 'นำเข้าภาพสำหรับ $slot';
  }

  @override
  String get samplesAllDone => 'เพลตตามแผนเสร็จครบแล้ว';

  @override
  String get samplesNoPlan =>
      'ตัวอย่างนี้ไม่มีแผนการเพาะ (บันทึกเพลตทีละเพลต) ใช้ “สร้างแผนการเพาะ” ในเมนูเพื่อรับรายการเพลตแบบมีขั้นตอน';

  @override
  String get samplesNoCountable => 'ยังไม่มีเพลตที่นับได้';

  @override
  String samplesReplicateCount(int n) {
    return 'n = $n ซ้ำ';
  }

  @override
  String samplesPoolDrops(Object range, Object rule) {
    return 'แต่ละซ้ำรวมหยดที่นับได้ ($range โคโลนี, $rule) เป็น ΣC / Σ(V × d); log₁₀ คือค่าเฉลี่ย ± SD ของค่า log ของทุกซ้ำ';
  }

  @override
  String samplesPoolFilters(Object range, Object rule) {
    return 'แต่ละซ้ำรวมแผ่นกรองที่นับได้ ($range โคโลนี, $rule) เป็น ΣC / Σ(V × d); log₁₀ คือค่าเฉลี่ย ± SD ของค่า log ของทุกซ้ำ';
  }

  @override
  String samplesPoolPlates(Object range, Object rule) {
    return 'แต่ละซ้ำรวมเพลตที่นับได้ ($range โคโลนี, $rule) เป็น ΣC / Σ(V × d); log₁₀ คือค่าเฉลี่ย ± SD ของค่า log ของทุกซ้ำ';
  }

  @override
  String get samplesStrain => 'สายพันธุ์';

  @override
  String get samplesMedium => 'อาหารเลี้ยงเชื้อ';

  @override
  String samplesBatch(Object batch) {
    return 'ล็อต $batch';
  }

  @override
  String get samplesIncubation => 'การบ่ม';

  @override
  String samplesIncubationAt(Object hours, Object temp) {
    return '$hours ที่ $temp';
  }

  @override
  String get samplesOperator => 'ผู้ปฏิบัติงาน';

  @override
  String get samplesTags => 'แท็ก';

  @override
  String get samplesNotes => 'หมายเหตุ';

  @override
  String get samplesDetails => 'รายละเอียด';

  @override
  String get setupRequired => 'จำเป็นต้องกรอก';

  @override
  String get setupIdTaken => 'มีรหัสตัวอย่างนี้อยู่แล้ว';

  @override
  String get setupNewSample => 'ตัวอย่างใหม่';

  @override
  String setupEditTitle(Object id) {
    return 'แก้ไข $id';
  }

  @override
  String get setupSampleId => 'รหัสตัวอย่าง';

  @override
  String get setupExperiment => 'การทดลอง (ไม่บังคับ)';

  @override
  String get setupExperimentHelp => 'เปรียบเทียบตัวอย่างในการทดลองเดียวกันได้';

  @override
  String get setupCondition => 'สภาวะ';

  @override
  String get setupConditionHelp => 'เช่น ชุดควบคุม, 1 % NaOCl';

  @override
  String get setupTimePoint => 'จุดเวลา';

  @override
  String get setupHoursUnit => 'ชม.';

  @override
  String get setupOptional => 'ไม่บังคับ';

  @override
  String get setupPlating => 'การเพาะเชื้อ';

  @override
  String get setupSpread => 'สเปรด';

  @override
  String get setupDrop => 'ดรอป';

  @override
  String get setupMembrane => 'เมมเบรน';

  @override
  String get setupMembraneRange => 'ช่วงที่นับได้ต่อแผ่นกรอง';

  @override
  String get setupMembraneUnit => 'รายงานผลเป็น CFU/100 mL';

  @override
  String get setupPlateType => 'ชนิดจาน';

  @override
  String get setupFrom => 'จาก';

  @override
  String get setupTo => 'ถึง';

  @override
  String get setupReplicates => 'จำนวนซ้ำ';

  @override
  String get setupVolumeFiltered => 'ปริมาตรที่กรอง';

  @override
  String get setupVolumePerPlate => 'ปริมาตรต่อเพลต';

  @override
  String get setupDropVolume => 'ปริมาตรต่อหยด';

  @override
  String setupFilterCount(int n) {
    return '$n แผ่นกรอง';
  }

  @override
  String setupPlateCount(int n) {
    return '$n เพลต';
  }

  @override
  String setupPlateCountDrops(int n, int drops) {
    return '$n เพลต เพลตละ $drops หยด';
  }

  @override
  String get setupColonyColours => 'สีโคโลนี';

  @override
  String get setupColourNone => 'นับทุกโคโลนีรวมกัน';

  @override
  String get setupColourBlueWhite =>
      'นับโคโลนีสีน้ำเงินและสีขาวแยกกัน (คัดกรองด้วย X-gal)';

  @override
  String get setupColourTwo =>
      'แบ่งโคโลนีเป็นสองกลุ่มสี (เช่น chromogenic agar)';

  @override
  String get setupNotes => 'หมายเหตุ';

  @override
  String get setupSave => 'บันทึกตัวอย่าง';

  @override
  String get setupDetails => 'รายละเอียดการทดลอง';

  @override
  String get setupDetailsSummary =>
      'สายพันธุ์ อาหารเลี้ยงเชื้อ การบ่ม ผู้ปฏิบัติงาน แท็ก';

  @override
  String get setupStrain => 'สายพันธุ์ / สิ่งมีชีวิต';

  @override
  String get setupMedium => 'อาหารเลี้ยงเชื้อ';

  @override
  String get setupBatch => 'ล็อต';

  @override
  String get setupIncubation => 'การบ่ม';

  @override
  String get setupTemperature => 'อุณหภูมิ';

  @override
  String get setupOperator => 'ผู้ปฏิบัติงาน';

  @override
  String get setupTags => 'แท็ก';

  @override
  String get setupTagsHelp => 'คั่นด้วยจุลภาค เช่น thesis, ล็อต 3';

  @override
  String get saveSheetTitle => 'รายละเอียดเพลต';

  @override
  String get saveSheetSampleId => 'รหัสตัวอย่าง';

  @override
  String get saveSheetSampleHelp =>
      'เพลตที่มีรหัสตัวอย่างเดียวกันจะรวมกันเพื่อคำนวณ CFU/mL';

  @override
  String get saveSheetScan => 'สแกนฉลากเพลต';

  @override
  String get saveSheetDilution => 'ระดับการเจือจางที่เพาะ';

  @override
  String get saveSheetReplicate => 'ซ้ำที่';

  @override
  String get saveSheetDropVolume => 'ปริมาตรต่อหยด';

  @override
  String get saveSheetVolumeFiltered => 'ปริมาตรที่กรอง';

  @override
  String get saveSheetVolume => 'ปริมาตร';

  @override
  String get saveSheetEnterVolume => 'กรอกปริมาตร';

  @override
  String get saveSheetDropNote =>
      'ดรอปเพลต: แต่ละหยดมีระดับการเจือจางและซ้ำของตัวเอง (ตั้งค่าในหน้าหยด)';

  @override
  String get saveSheetSpreader => 'มีโคโลนีแผ่กระจายบนเพลต';

  @override
  String get saveSheetSpreaderHelp => 'ไม่นำมาคำนวณ CFU/mL';

  @override
  String get saveSheetTntc => 'มากเกินนับ (TNTC)';

  @override
  String get saveSheetTntcHelp => 'จำนวนนับเป็นค่าต่ำสุด';

  @override
  String get saveSheetIncubation => 'เวลาบ่ม (ไม่บังคับ)';

  @override
  String get saveSheetHoursUnit => 'ชม.';

  @override
  String get saveSheetIncubationHelp =>
      'จำนวนชั่วโมงหลังเพาะ สำหรับภาพไทม์แลปส์';

  @override
  String get saveSheetVerified => 'ตรวจทุกโคโลนีแล้ว';

  @override
  String get saveSheetVerifiedHelp =>
      'ใช้เพลตนี้เป็นจำนวนอ้างอิงเพื่อติดตามความแม่นยำ';

  @override
  String get saveSheetNotes => 'หมายเหตุ';

  @override
  String saveSheetAlone(Object rule) {
    return 'เฉพาะเพลตนี้ ($rule)';
  }

  @override
  String get saveSheetSave => 'บันทึก';

  @override
  String get methodSpread => 'สเปรดเพลต / พอร์เพลต';

  @override
  String get methodDrop => 'ดรอปเพลต (Miles–Misra)';

  @override
  String get methodMembrane => 'การกรองผ่านเมมเบรน';

  @override
  String get layoutReplicates =>
      'หนึ่งระดับการเจือจางต่อเพลต หยดแต่ละหยดคือซ้ำ';

  @override
  String get layoutDilutions => 'ทุกระดับการเจือจางบนเพลตเดียว ระดับละหนึ่งหยด';

  @override
  String get colourOff => 'ปิด';

  @override
  String get colourBlueWhite => 'สีน้ำเงิน / ขาว';

  @override
  String get colourTwo => 'สองสี';

  @override
  String get classAll => 'ทั้งหมด';

  @override
  String get classWhite => 'ขาว';

  @override
  String get classBlue => 'น้ำเงิน';

  @override
  String get classColourA => 'สี A';

  @override
  String get classColourB => 'สี B';

  @override
  String get formatDish90 => 'จานขนาด 90 มม.';

  @override
  String get formatDish60 => 'จานขนาด 60 มม.';

  @override
  String get formatDish100 => 'จานขนาด 100 มม.';

  @override
  String get formatDish150 => 'จานขนาด 150 มม.';

  @override
  String get formatSquare100 => 'จานสี่เหลี่ยม 100 มม.';

  @override
  String get formatSquare120 => 'จานสี่เหลี่ยม 120 มม.';

  @override
  String get formatMembrane47 => 'แผ่นกรองเมมเบรน 47 มม.';

  @override
  String get ruleDrop => 'ดรอป 3–30';

  @override
  String get ruleMembrane80 => 'เมมเบรน 20–80';

  @override
  String get ruleMembrane200 => 'เมมเบรน 20–200';

  @override
  String get trainingChecked => 'เฉพาะเพลตที่ตรวจทุกโคโลนีแล้ว';

  @override
  String get trainingCorrected => 'เพลตที่ตรวจแล้วและที่แก้ไขแล้ว';

  @override
  String get trainingAll => 'ทุกเพลต';

  @override
  String get flagSpreader => 'มีโคโลนีแผ่กระจาย';

  @override
  String get flagTntc => 'มากเกินนับ (TNTC)';

  @override
  String get flagClusters => 'ประมาณจำนวนในกลุ่มโคโลนี';

  @override
  String get flagCrowded => 'เพลตหนาแน่น';

  @override
  String get flagManyClusters => 'โคโลนีติดกันมาก';

  @override
  String get flagLowContrast => 'โคโลนีจาง';

  @override
  String get neat => 'ไม่เจือจาง';

  @override
  String get unlabelled => 'ไม่มีรหัส';

  @override
  String dropPlateDrops(int n) {
    return 'ดรอปเพลต ($n หยด)';
  }

  @override
  String get noteAllSpreaders => 'ทุกเพลตมีโคโลนีแผ่กระจาย';

  @override
  String get noteNoColonies => 'ไม่พบโคโลนีบนเพลตที่เจือจางน้อยที่สุด';

  @override
  String noteBelowRange(Object range) {
    return 'ต่ำกว่าช่วงที่นับได้ ($range)';
  }

  @override
  String noteAboveRange(Object range) {
    return 'สูงกว่าช่วงที่นับได้ ($range)';
  }

  @override
  String get noteTntc => 'มากเกินนับ';

  @override
  String get noteNoPlateInRange => 'ไม่มีเพลตในช่วงที่นับได้';

  @override
  String get estimatePrefix => 'ประมาณ ';

  @override
  String get noEstimate => 'คำนวณไม่ได้';
}
