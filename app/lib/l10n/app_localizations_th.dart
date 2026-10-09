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
  String get aboutZonesTitle => 'โซนยับยั้ง (เบต้า)';

  @override
  String get aboutZones =>
      'วัดเฉพาะเส้นผ่านศูนย์กลางของโซน ไม่แปลผลเป็นไว ปานกลาง หรือดื้อ ยังไม่ได้เทียบกับการวัดด้วยเวอร์เนียร์บนเพลตจริง ควรตรวจทุกโซน';

  @override
  String get calSuggestTitle => 'ปรับเทียบกับเวอร์เนียร์ของคุณก่อนไหม';

  @override
  String get calSuggestBody =>
      'แนะนำอย่างยิ่งก่อนใช้ขนาดโซนจริง ถ่ายภาพเพลตวัดโซนที่ใช้แล้ว วัดด้วยเวอร์เนียร์หรือไม้บรรทัด แล้วดูว่าแอปวัดได้ใกล้เคียงกับคุณเพียงใด ใช้เวลาประมาณ 5–10 นาที และทำภายหลังได้จากเมนูของแท็บโซนยับยั้ง';

  @override
  String get calLater => 'ภายหลัง';

  @override
  String get calNow => 'ปรับเทียบตอนนี้';

  @override
  String get calTitle => 'การปรับเทียบการวัดโซน';

  @override
  String get calNew => 'ปรับเทียบใหม่';

  @override
  String get calNone =>
      'ยังไม่มีการปรับเทียบ แตะ ปรับเทียบใหม่ แล้วเตรียมเวอร์เนียร์ (หรือไม้บรรทัด) และเพลตวัดโซนที่ใช้แล้ว';

  @override
  String get calOld => 'เกิน 90 วันแล้ว: ควรปรับเทียบใหม่';

  @override
  String calStats(String bias, String low, String high, int n) {
    return 'ค่าเบี่ยงเบน $bias มม. · ช่วงความสอดคล้อง $low ถึง $high มม. · $n โซน';
  }

  @override
  String calPlatesTool(int n, String tool) {
    return '$n เพลต · $tool';
  }

  @override
  String get calToolCalliper => 'เวอร์เนียร์';

  @override
  String get calToolRuler => 'ไม้บรรทัด';

  @override
  String get calAddPlate => 'เพิ่มเพลตอีกแผ่น';

  @override
  String get calDeleteTitle => 'ลบการปรับเทียบ?';

  @override
  String get calDeleteBody =>
      'ค่าที่วัดจะถูกลบ เพลตยังอยู่เป็นเพลตวัดโซนตามปกติ';

  @override
  String get calVerdictGood =>
      'ดี: แอปวัดได้ใกล้เคียงกับค่าที่คุณวัดภายในประมาณ 1 มม.';

  @override
  String get calVerdictUsable =>
      'ใช้ได้: ต่างกันภายในประมาณ 2 มม. ควรวัดโซนที่ก้ำกึ่งด้วยมือ';

  @override
  String get calVerdictPoor => 'ยังไม่ดีพอ';

  @override
  String get calVerdictTooFew => 'วัดโซนน้อยเกินไป';

  @override
  String get calSetupStand => 'บนขาตั้ง';

  @override
  String get calSetupHandheld => 'ถือด้วยมือ';

  @override
  String get calOtherSetup =>
      'เพลตนี้ถ่ายด้วยกล้องอื่นหรือที่ความสูงอื่น ควรใช้การตั้งค่าเดียวกันสำหรับทุกเพลตในการปรับเทียบหนึ่งครั้ง';

  @override
  String get calNoRecent => 'ไม่มีเพลตวัดโซนในวันที่ผ่านมา';

  @override
  String get calUseRecent => 'ใช้เพลตที่เพิ่งวัด';

  @override
  String get calLeaveTitle => 'ออกจากการปรับเทียบ?';

  @override
  String get calLeaveBody => 'ค่าที่วัดไว้ยังไม่ได้บันทึก';

  @override
  String get calIntroTitle => 'ตรวจแอปเทียบกับเวอร์เนียร์ของคุณ';

  @override
  String get calAddPlateTitle => 'เพิ่มเพลตในการปรับเทียบนี้';

  @override
  String get calIntro =>
      'แอปวัดเพลตวัดโซนที่ใช้แล้วจากภาพ คุณวัดเพลตเดียวกัน แล้วแอปแสดงว่าทั้งสองสอดคล้องกันเพียงใด ไม่มีการแก้ค่าใด ๆ เพลตที่วัดหลังจากนี้จะแสดงผลการปรับเทียบ';

  @override
  String get calNeedTool => 'เวอร์เนียร์ (หรือไม้บรรทัด)';

  @override
  String get calNeedPlate =>
      'เพลตวัดโซนที่บ่มแล้ว มีโซนชัดอย่างน้อย 6 โซน ควรมีหลายขนาดและมีบางโซนอยู่ใกล้ขอบ';

  @override
  String get calNeedSetup => 'ขาตั้ง ระยะ และแสงแบบเดียวกับที่ใช้กับเพลตจริง';

  @override
  String get calBiosafety =>
      'เพลตมีเชื้อมีชีวิต: วัดโดยปิดฝาจากด้านนอก และปฏิบัติตามข้อกำหนดของห้องปฏิบัติการ';

  @override
  String get calToolQuestion => 'คุณจะวัดด้วยอะไร';

  @override
  String calMinZones(int n) {
    return 'ต้องวัดอย่างน้อย $n โซน';
  }

  @override
  String get calSetupQuestion => 'คุณถ่ายภาพเพลตอย่างไร';

  @override
  String get calPhotograph => 'ถ่ายภาพเพลตที่ใช้แล้ว';

  @override
  String get calBackToResult => 'กลับไปที่ผลลัพธ์';

  @override
  String get calReadingsHelp =>
      'วัดแบบที่คุณอ่านโซนตามปกติ เช่น วัดจากด้านหลังเพลตโดยปิดฝา ขนาดที่แอปวัดได้จะถูกซ่อนไว้ เพื่อให้ค่าที่วัดเป็นของคุณเอง';

  @override
  String get calSpanTitle => 'ตรวจมาตราส่วน';

  @override
  String calSpanHelp(int a, int b) {
    return 'วัดจากขอบนอกของแผ่นที่ $a ถึงขอบนอกของแผ่นที่ $b (เส้นสีเหลือง)';
  }

  @override
  String get calSpanLabel => 'ระยะ';

  @override
  String get calSpanInvalid => 'ใส่ระยะ 20 ถึง 90 มม.';

  @override
  String calReadingInvalid(int n) {
    return 'โซน $n: ใส่ 2 ถึง 90 มม.';
  }

  @override
  String calNeedZones(int need, int have) {
    return 'วัดอย่างน้อย $need โซน (ตอนนี้ $have)';
  }

  @override
  String get calZonesTitle => 'เส้นผ่านศูนย์กลางโซน';

  @override
  String calZoneN(int n) {
    return 'โซน $n';
  }

  @override
  String get calDoubtful =>
      'ขอบไม่ชัด ซ้อนกัน หรือไม่มีโซน: ไม่นำมาคิดหากไม่เลือก';

  @override
  String get calSecondReading => 'วัดอีกแนวตั้งฉาก';

  @override
  String get calNotRound => 'ไม่กลม: เพิ่มการวัดอีกแนว';

  @override
  String get calOneReading => 'วัดแนวเดียว';

  @override
  String get calSeeResult => 'ดูผลลัพธ์';

  @override
  String get calCheckTitle => 'ตรวจโซนเหล่านี้';

  @override
  String calCheckBody(String list) {
    return 'โซน $list ต่างจากแอปมากกว่า 3 มม. ใส่ค่าถูกโซนหรือไม่';
  }

  @override
  String get calCheckFix => 'ตรวจอีกครั้ง';

  @override
  String get calCheckOk => 'ถูกต้องแล้ว';

  @override
  String get calHintScale =>
      'มาตราส่วนขนาดดูคลาดเคลื่อน ตรวจขนาดแผ่นและชนิดจาน ตั้งขาตั้งที่ความสูงเดิม และใช้เลนส์หลักแทนการซูม';

  @override
  String get calHintLens =>
      'โซนที่อยู่ใกล้ขอบเพลตต่างมากกว่าโซนตรงกลาง ให้ถอยกล้องออกห่างขึ้นและวางเพลตไว้กลางภาพ';

  @override
  String calHintEdgeLarger(String mm) {
    return 'แอปวัดโซนใหญ่กว่าที่คุณวัดประมาณ $mm มม. คือวางขอบโซนออกไปด้านนอกมากกว่า ตรวจแสง และวัดโซนที่ก้ำกึ่งด้วยมือ แอปจะไม่เลื่อนขอบโซนเอง';
  }

  @override
  String calHintEdgeSmaller(String mm) {
    return 'แอปวัดโซนเล็กกว่าที่คุณวัดประมาณ $mm มม. คือวางขอบโซนเข้ามาด้านในมากกว่า ตรวจแสง และวัดโซนที่ก้ำกึ่งด้วยมือ แอปจะไม่เลื่อนขอบโซนเอง';
  }

  @override
  String get calHintSpread =>
      'ค่าความต่างกระจายมาก วัดใหม่อย่างระมัดระวัง ใช้ขาตั้ง และล็อกโฟกัส';

  @override
  String calWithin1(int pct) {
    return '$pct % ของโซนต่างกันไม่เกิน 1 มม.';
  }

  @override
  String calScaleCheck(String pct) {
    return 'ตรวจมาตราส่วน: ระยะที่แอปวัดต่างจากของคุณ $pct %';
  }

  @override
  String calRepeatability(String mm) {
    return 'ความซ้ำได้ระหว่างภาพ: SD $mm มม.';
  }

  @override
  String get calPlotCaption =>
      'แต่ละจุดคือหนึ่งโซน: ค่าของแอปลบค่าของคุณ เทียบกับค่าเฉลี่ยของทั้งสอง เส้นทึบคือค่าเบี่ยงเบน เส้นประคือช่วงความสอดคล้อง 95 % แถบสีจางคือ ±1 มม.';

  @override
  String get calColZone => 'โซน';

  @override
  String get calColYours => 'ของคุณ';

  @override
  String get calColApp => 'แอป';

  @override
  String get calColDiff => 'แอป − ของคุณ';

  @override
  String get calLeftOut => 'ไม่นำมาคิด';

  @override
  String get calWhatChecked =>
      'ผลนี้เทียบแอปกับค่าที่คุณวัดเอง บนกล้องและการตั้งค่านี้ ไม่ได้รับรองวิธีการ เพราะค่าที่วัดด้วยเวอร์เนียร์ก็ต่างกันระหว่างผู้วัดประมาณ 0.5 มม.';

  @override
  String get calSave => 'บันทึกการปรับเทียบ';

  @override
  String get calTryAgain => 'ลองใหม่โดยไม่ใช้เพลตนี้';

  @override
  String get calMenu => 'ปรับเทียบกับเวอร์เนียร์';

  @override
  String get calShortGood => 'ดี';

  @override
  String get calShortUsable => 'ใช้ได้';

  @override
  String get calShortPoor => 'ยังไม่ดีพอ';

  @override
  String get calShortTooFew => 'โซนน้อยเกินไป';

  @override
  String calChipCalibrated(String verdict, String bias) {
    return 'ปรับเทียบแล้ว: $verdict · เบี่ยงเบน $bias มม.';
  }

  @override
  String get calChipNone => 'ยังไม่ได้ปรับเทียบ';

  @override
  String get calChipAgain => 'ควรปรับเทียบใหม่';

  @override
  String get calChipPlate => 'เพลตสำหรับปรับเทียบ';

  @override
  String get calReasonOld =>
      'ควรปรับเทียบใหม่: การปรับเทียบเก่ากว่าภาพนี้เกิน 90 วัน';

  @override
  String get calReasonCamera =>
      'ควรปรับเทียบใหม่: ภาพนี้ถ่ายด้วยกล้องหรือขนาดภาพต่างจากตอนปรับเทียบ';

  @override
  String get calReasonSetup =>
      'ควรปรับเทียบใหม่: เพลตในภาพมีขนาดต่างไป ความสูงของขาตั้งน่าจะเปลี่ยน';

  @override
  String calScaleSmall(String pct) {
    return 'โซนอาจวัดได้เล็กไปประมาณ $pct %: มาตราส่วนของเพลตนี้ต่างจากที่ปรับเทียบไว้';
  }

  @override
  String calScaleLarge(String pct) {
    return 'โซนอาจวัดได้ใหญ่ไปประมาณ $pct %: มาตราส่วนของเพลตนี้ต่างจากที่ปรับเทียบไว้';
  }

  @override
  String get calScaleDisksHint => 'ตรวจขนาดแผ่นและชนิดจาน';

  @override
  String get calScaleWellsHint =>
      'เพลตแบบหลุมใช้มาตราส่วนจากขอบจาน ซึ่งอยู่สูงกว่าผิววุ้น ควรวัดโซนที่ก้ำกึ่งด้วยมือ';

  @override
  String get calBannerNone =>
      'ยังไม่ได้ปรับเทียบ: ตรวจแอปเทียบกับเวอร์เนียร์ของคุณ';

  @override
  String get calBannerOld =>
      'การปรับเทียบเก่าเกิน 90 วันแล้ว: ควรปรับเทียบใหม่';

  @override
  String calBannerOk(String verdict, String date) {
    return 'ปรับเทียบแล้ว: $verdict · $date';
  }

  @override
  String get calCalibrate => 'ปรับเทียบ';

  @override
  String get calAgainTitle => 'ปรับเทียบใหม่ไหม';

  @override
  String get calAgainBody =>
      'การปรับเทียบครั้งล่าสุดเก่าเกิน 90 วันแล้ว การตรวจสั้น ๆ ด้วยเพลตที่ใช้แล้วและเวอร์เนียร์ช่วยให้ขนาดโซนน่าเชื่อถือ';

  @override
  String get calShareData => 'แชร์เป็นข้อมูลทดสอบ';

  @override
  String get calShareSubject => 'ข้อมูลทดสอบการปรับเทียบการวัดโซน';

  @override
  String get calShareInfo =>
      'ภาพเพลตที่ใช้ปรับเทียบและค่าที่คุณวัด รวมในไฟล์ zip เดียว ข้อมูลอยู่ในเครื่องนี้จนกว่าคุณจะแชร์';

  @override
  String calGate(int plates, int need, String mean, int pct) {
    return 'ข้อมูลทดสอบ: $plates จาก $need เพลตที่วัดด้วยเวอร์เนียร์ · ความคลาดเคลื่อนเฉลี่ย $mean มม. · $pct % ต่างกันไม่เกิน 2 มม.';
  }

  @override
  String get calGateMet =>
      'มีข้อมูลจากเวอร์เนียร์มากพอสำหรับพิจารณายกเลิกสถานะเบต้าแล้ว: แชร์ให้ผู้พัฒนา';

  @override
  String get calGateHelp =>
      'เพลตที่วัดด้วยเวอร์เนียร์ยังช่วยให้ฟีเจอร์วัดโซนพ้นจากสถานะเบต้าได้';

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
  String get setupDropArrangement => 'ตำแหน่งของหยดบนจาน';

  @override
  String get dropArrangementFree => 'อิสระ';

  @override
  String get dropArrangementSectors => 'วงรอบจาน';

  @override
  String get dropArrangementGrid => 'เป็นแถว';

  @override
  String get setupDropFreeHelp =>
      'หาหยดจากโคโลนีที่อยู่ในหยด และเรียงลำดับจากบนลงล่าง ซ้ายไปขวา หยดที่ว่างหรือเจริญเต็มหยดต้องเพิ่มเอง';

  @override
  String get setupDropSectorsHelp =>
      'หยดเรียงเป็นวงรอบจานตามเข็มนาฬิกา เริ่มจากด้านบน (ตำแหน่ง 12 นาฬิกา) คือระดับการเจือจางแรก หยดที่ว่างหรือเจริญเต็มหยดจะหาได้จากตำแหน่งในวง';

  @override
  String get setupDropGridHelp =>
      'หนึ่งแถวต่อหนึ่งระดับการเจือจาง เรียงจากบนลงล่าง หยดของแต่ละระดับวางเรียงกันในแถว หยดที่ว่างหรือเจริญเต็มหยดจะหาได้จากตำแหน่งในแถว';

  @override
  String get setupDropGridRowHelp =>
      'หยดเรียงเป็นแถวเดียวจากซ้ายไปขวา หยดที่ว่างหรือเจริญเต็มหยดจะหาได้จากตำแหน่งในแถว';

  @override
  String get setupDropsPerDilution => 'จำนวนหยดต่อระดับการเจือจาง';

  @override
  String get setupDropPitch => 'ระยะห่างระหว่างหยด';

  @override
  String get setupDropLayoutPreview => 'ตำแหน่งของหยดบนแต่ละจาน';

  @override
  String get reviewFindDrops => 'หาหยดใหม่';

  @override
  String get reviewTurnLabels => 'เลื่อนป้ายกำกับไปหนึ่งหยด';

  @override
  String get reviewHintDropsLayout =>
      'แตะหยดเพื่อเปลี่ยนป้ายกำกับ ทำเครื่องหมาย TNTC หรือไม่นำมาคำนวณ แตะบนอาหารเลี้ยงเชื้อที่ว่างเพื่อเพิ่มหยด ลากหยดเพื่อย้าย หรือลากบนอาหารเลี้ยงเชื้อเพื่อย้ายทุกหยด';

  @override
  String get reviewLeaveOut => 'ไม่นำหยดนี้มาคำนวณ';

  @override
  String get reviewLeaveOutHelp =>
      'หยดยังแสดงบนภาพโดยมีกากบาท และไม่นำมาคำนวณ CFU/mL';

  @override
  String get reviewLeaveOutWhy => 'เหตุผล';

  @override
  String get dropExclusionSplash => 'หยดกระเด็นหรือเลอะ';

  @override
  String get dropExclusionMerged => 'ไหลรวมกับหยดข้างเคียง';

  @override
  String get dropExclusionBubble => 'มีฟองอากาศหรือรอยขีดข่วน';

  @override
  String get dropExclusionContaminated => 'มีการปนเปื้อน';

  @override
  String get dropExclusionOther => 'อื่น ๆ';

  @override
  String get reviewDropLeftOut => 'ไม่นำมาคำนวณ';

  @override
  String get reviewDropCrowded =>
      'หยดแน่น: โคโลนีที่รวมกันนับบางส่วนจากพื้นที่ ควรตรวจสอบจำนวน หรืออ่านผลเร็วขึ้นในครั้งต่อไป';

  @override
  String get reviewDropUnplanned =>
      'จำนวนหยดมากกว่าแผน: ตรวจสอบป้ายกำกับของหยดนี้';

  @override
  String get flagOutsideDrops => 'มีโคโลนีอยู่นอกหยด (ไม่นับ)';

  @override
  String get flagLayoutUncertain => 'ไม่แน่ใจตำแหน่งของหยด: ตรวจสอบหยด';

  @override
  String get setupDropWindow => 'ช่วงที่นับได้ (โคโลนีต่อหยด)';

  @override
  String get setupDropWindowFrom => 'ตั้งแต่';

  @override
  String get setupDropWindowTo => 'ถึง';

  @override
  String get setupDropWindowHelp =>
      'ช่วงที่ใช้ทั่วไปคือ 3–30 โคโลนีต่อหยด 10 µL หากใช้หยดปริมาตรอื่น ให้ใช้ช่วงตามวิธีปฏิบัติของห้องปฏิบัติการ';

  @override
  String get setupDropMode => 'วิธีคำนวณ';

  @override
  String get dropModePooled => 'รวมทุกหยด';

  @override
  String get dropModeFirst => 'ระดับแรกที่นับได้';

  @override
  String get setupDropPooledHelp =>
      'รวมทุกหยดที่อยู่ในช่วงที่นับได้จากทุกระดับการเจือจาง: ΣC ÷ Σ(V × d)';

  @override
  String get setupDropFirstHelp =>
      'ใช้ค่าเฉลี่ยของระดับการเจือจางที่น้อยที่สุดซึ่งหยดอยู่ในช่วงที่นับได้ ตามวิธีปฏิบัติส่วนใหญ่';

  @override
  String get dropTableTitle => 'หยดในแต่ละระดับการเจือจาง';

  @override
  String dropRowMean(String mean) {
    return 'เฉลี่ย $mean';
  }

  @override
  String dropRowLeftOut(int n) {
    return 'ไม่นำมาคำนวณ $n';
  }

  @override
  String dropUsedPooled(String dilutions, int n) {
    return 'รวมจาก $dilutions ($n หยด)';
  }

  @override
  String dropUsedFirst(String dilution, int n) {
    return 'จาก $dilution ระดับการเจือจางแรกที่นับได้ ($n หยด)';
  }

  @override
  String dropCi(String low, String high) {
    return 'ช่วงความเชื่อมั่น 95 % $low–$high';
  }

  @override
  String dropRuleLine(String mode, String range) {
    return '$mode · $range โคโลนีต่อหยด แต่ละซ้ำคำนวณจากตารางหยดของตนเอง log₁₀ คือค่าเฉลี่ย ± SD ของค่า log ของทุกซ้ำ';
  }

  @override
  String get dropWarnOverdispersed =>
      'หยดในระดับการเจือจางเดียวกันต่างกันมากเกินกว่าความบังเอิญ: ตรวจสอบการผสมและการปิเปต';

  @override
  String get dropWarnOutlier =>
      'มีหยดที่ต่างจากหยดอื่นในระดับเดียวกันมาก: ตรวจสอบ หรือไม่นำมาคำนวณ';

  @override
  String get dropWarnNotTenfold =>
      'ระดับการเจือจางที่ติดกันไม่ต่างกันประมาณ 10 เท่า: ตรวจสอบชุดการเจือจาง';

  @override
  String get dropWarnCrowded =>
      'หยดแน่นเกินไป: อ่านผลเร็วขึ้น หรือนับระดับการเจือจางที่สูงขึ้น';

  @override
  String dropWarnNotAsPlanned(int found, int planned) {
    return 'จำนวนหยดไม่ตรงกับแผน (พบ $found หยด แผน $planned หยด): ตรวจสอบป้ายกำกับ';
  }

  @override
  String get noteNoDropColonies => 'ไม่มีโคโลนีในหยดใดเลย';

  @override
  String noteNoDilutionInWindow(Object range) {
    return 'ไม่มีระดับการเจือจางใดอยู่ในช่วงที่นับได้ ($range): ใช้ระดับที่ใกล้ที่สุด';
  }

  @override
  String get noteNoDrops => 'ไม่มีหยด';

  @override
  String dropUsedFrom(String dilutions, int n) {
    return 'จาก $dilutions ($n หยด)';
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

  @override
  String get homeZones => 'โซนยับยั้ง';

  @override
  String get zonesMeasure => 'วัดโซนยับยั้ง';

  @override
  String get zonesNone => 'ยังไม่มีเพลตวัดโซนยับยั้ง';

  @override
  String get zonesEmptyHint =>
      'วัดโซนยับยั้งรอบแผ่นกระดาษหรือหลุมวุ้น: แตะ วัดโซนยับยั้ง แล้วถ่ายภาพเพลตโดยเปิดฝา';

  @override
  String get zoneSetupTitle => 'เพลตวัดโซนยับยั้ง';

  @override
  String get zoneAssay => 'วิธี';

  @override
  String get zoneAssayDisk => 'แผ่นกระดาษ';

  @override
  String get zoneAssayWell => 'หลุมวุ้น';

  @override
  String get zoneDiskSize => 'เส้นผ่านศูนย์กลางแผ่นกระดาษ (มม.)';

  @override
  String get zoneWellSize => 'เส้นผ่านศูนย์กลางหลุม (มม.)';

  @override
  String get zoneSizeInvalid => 'ใส่ 3 ถึง 15 มม.';

  @override
  String get zoneOrganism => 'เชื้อทดสอบ';

  @override
  String get zoneOrganismHint => 'เช่น S. aureus ATCC 25923';

  @override
  String get zoneExperiment => 'การทดลอง';

  @override
  String get zoneReplicate => 'ซ้ำที่';

  @override
  String get zonePanel => 'ชื่อสารทดสอบ';

  @override
  String get zonePanelNone => 'ไม่ใช้: ใส่ชื่อทีหลัง';

  @override
  String get zonePanelNew => 'สร้างรายการชื่อใหม่';

  @override
  String get zonePanelHelp =>
      'ชื่อเรียงตามเข็มนาฬิกาเริ่มจากตำแหน่ง 12 นาฬิกา แผ่นที่อยู่ตรงกลางเป็นลำดับสุดท้าย';

  @override
  String get zonePanelName => 'ชื่อรายการ';

  @override
  String get zonePanelLabels => 'ชื่อสารทดสอบ บรรทัดละหนึ่งชื่อ';

  @override
  String get zoneTakePhoto => 'ถ่ายภาพ';

  @override
  String get zoneFromGallery => 'จากคลังภาพ';

  @override
  String get zoneCaptureTip =>
      'เปิดฝา วางเพลตบนพื้นสีเข้ม ถือกล้องตรงเหนือเพลต';

  @override
  String get zoneMeasuring => 'กำลังวัดโซนยับยั้ง…';

  @override
  String zoneNZones(int n) {
    return '$n โซน';
  }

  @override
  String zoneNToCheck(int n) {
    return 'ต้องตรวจ $n';
  }

  @override
  String get zoneAllChecked => 'ตรวจครบแล้ว';

  @override
  String zoneRep(int n) {
    return 'ซ้ำที่ $n';
  }

  @override
  String get zoneHint =>
      'แตะแผ่นเพื่อตรวจ ลากขอบโซนเพื่อปรับขนาด กดค้างเพื่อเพิ่มแผ่นที่แอปหาไม่พบ';

  @override
  String get zoneHintWell =>
      'แตะหลุมเพื่อตรวจ ลากขอบโซนเพื่อปรับขนาด กดค้างเพื่อเพิ่มหลุมที่แอปหาไม่พบ';

  @override
  String get zoneHintPlate =>
      'ลากวงกลมให้ตรงขอบเพลต ใช้แถบเลื่อนปรับขนาด แล้ววัดใหม่';

  @override
  String get zoneFixPlate => 'แก้วงขอบเพลต';

  @override
  String get zoneMeasureAgain => 'วัดใหม่';

  @override
  String get zoneRemeasureTitle => 'วัดใหม่?';

  @override
  String get zoneRemeasureBody =>
      'การแก้ไขโซนทั้งหมดจะถูกแทนที่ด้วยผลการวัดใหม่';

  @override
  String get zoneNoDisks =>
      'ไม่พบแผ่นกระดาษ กดค้างที่แต่ละแผ่นเพื่อเพิ่ม หรือแก้วงขอบเพลต';

  @override
  String get zoneNoWells =>
      'ไม่พบหลุม กดค้างที่แต่ละหลุมเพื่อเพิ่ม หรือแก้วงขอบเพลต';

  @override
  String zoneDiskN(int n) {
    return 'แผ่นที่ $n';
  }

  @override
  String zoneWellN(int n) {
    return 'หลุมที่ $n';
  }

  @override
  String get zoneLabel => 'ชื่อสารทดสอบ';

  @override
  String get zoneDiameter => 'เส้นผ่านศูนย์กลางโซน';

  @override
  String zoneMm(Object mm) {
    return '$mm มม.';
  }

  @override
  String get zoneNotMeasured => 'วัดไม่ได้';

  @override
  String get zoneSmaller => 'เล็กลง 1 มม.';

  @override
  String get zoneLarger => 'ใหญ่ขึ้น 1 มม.';

  @override
  String get zoneNoZone => 'ไม่มีโซนยับยั้ง';

  @override
  String zoneNoZoneHelp(Object mm) {
    return 'รายงานเป็นขนาดของแผ่น $mm มม.';
  }

  @override
  String zoneNoZoneHelpWell(Object mm) {
    return 'รายงานเป็นขนาดของหลุม $mm มม.';
  }

  @override
  String zoneAutoWas(Object mm) {
    return 'แอปวัดได้ $mm มม.';
  }

  @override
  String get zoneAdded => 'เพิ่มเอง';

  @override
  String get zoneDeletePlate => 'ลบเพลตวัดโซนยับยั้ง?';

  @override
  String get zoneDeletePlateBody => 'ภาพและโซนทั้งหมดจะถูกลบ';

  @override
  String get zoneDetails => 'รายละเอียด';

  @override
  String get zoneFlagNoZone => 'ไม่พบโซนยับยั้งที่ชัดเจน';

  @override
  String get zoneFlagOverlap => 'ซ้อนกับโซนข้างเคียง';

  @override
  String get zoneFlagHitsRim => 'ถึงขอบเพลต';

  @override
  String get zoneFlagHazy => 'ขอบโซนไม่คม: ตรวจว่าเชื้อเริ่มขึ้นตรงไหน';

  @override
  String get zoneFlagColonies => 'มีโคโลนีในโซน';

  @override
  String get zoneFlagLowConfidence => 'ขอบโซนไม่ชัด';

  @override
  String get zoneFlagUnmeasured => 'วัดไม่ได้: ตั้งขนาดเอง';

  @override
  String get zoneScaleMismatch =>
      'ขนาดของแผ่นกับเพลตไม่สอดคล้องกัน: ตรวจชนิดจานและวงขอบเพลต';

  @override
  String get zoneScaleUnchecked =>
      'ขนาดคำนวณจากขอบเพลตอย่างเดียว เพราะวัดแผ่นไม่ได้';

  @override
  String get zoneShareSubject => 'โซนยับยั้ง';

  @override
  String get zoneResults => 'ผลการวัด';

  @override
  String get zoneNoExperiment => 'ไม่ได้ตั้งชื่อการทดลอง';

  @override
  String get zoneNoOrganism => 'ไม่ได้ระบุเชื้อทดสอบ';

  @override
  String get zoneColItem => 'สารทดสอบ';

  @override
  String get zoneColMean => 'ค่าเฉลี่ย ± SD (มม.)';

  @override
  String zoneResultsPlates(int n) {
    return '$n เพลต';
  }

  @override
  String get zoneResultsNone =>
      'ยังไม่มีโซนที่ตั้งชื่อ ใส่ชื่อสารทดสอบให้แผ่นเพื่อเปรียบเทียบ';

  @override
  String get zoneResultsNote =>
      'ค่าเฉลี่ย ± SD ของเส้นผ่านศูนย์กลางโซนจากเพลตซ้ำ แผ่นที่ไม่มีโซนนับเป็นขนาดของแผ่น (เส้นสีเทา) แอปรายงานเฉพาะขนาด ไม่แปลผลเป็นไว ปานกลาง หรือดื้อ';

  @override
  String get zoneExportCsv => 'ส่งออก CSV ของโซนยับยั้ง';

  @override
  String get zonesTitleBeta => 'โซนยับยั้ง (เบต้า)';

  @override
  String get zoneDisclaimerTitle => 'การวัดโซนยับยั้งยังเป็นรุ่นเบต้า';

  @override
  String get zoneDisclaimer =>
      'แอปวัดเส้นผ่านศูนย์กลางของโซนยับยั้งรอบแผ่นกระดาษและหลุมวุ้น ขณะนี้ทดสอบกับเพลตจำลองเท่านั้น ยังไม่ได้เทียบกับการวัดด้วยเวอร์เนียร์บนเพลตจริง จึงควรตรวจทุกโซนบนภาพ\n\nแอปรายงานเฉพาะขนาด ไม่แปลผลเป็นไว ปานกลาง หรือดื้อ และไม่ใช่การทดสอบความไวต่อยาที่ผ่านการรับรอง หรือเครื่องมือวินิจฉัยโรค';

  @override
  String get zoneDisclaimerOk => 'เข้าใจแล้ว';

  @override
  String zoneCouldNotMeasure(String error) {
    return 'วัดภาพนี้ไม่ได้: $error';
  }
}
