// Makes the Play Store phone screenshots (1080 × 1920) and feature graphics
// (1024 × 500) in English and Thai from real app screens.
//   node make_graphics.js <raw screens folder>
// The raw screens are the manual's unannotated PNGs (<name>.<lang>.png, made by
// app/test/manual: MANUAL_OUT=<folder> flutter test test/manual/<chapter>_manual.dart).
const { chromium } = require('playwright');
const path = require('path'), fs = require('fs');

const raw = path.resolve(process.argv[2]);
// Optional: the same chapters rendered with MANUAL_SIZE=1280x800 (tablet) and
// MANUAL_SIZE=1440x900 (desktop / Chromebook).
const rawTablet = process.argv[3] && path.resolve(process.argv[3]);
const rawDesktop = process.argv[4] && path.resolve(process.argv[4]);
const store = path.resolve(__dirname, '..');
// Order = order in the listing. h: headline, s: subline, n: footnote.
const SHOTS = [
  ['count-2-result', {
    en: { h: 'Count colonies from a photo', s: 'Automatic count, then check it on the photo' },
    th: { h: 'นับโคโลนีจากภาพถ่าย', s: 'นับอัตโนมัติ แล้วตรวจผลบนภาพได้ทันที' } }],
  ['examples-3-result', {
    en: { h: 'CFU/mL from a dilution series', s: 'Replicates, mean ± SD and log₁₀ CFU/mL' },
    th: { h: 'CFU/mL จากชุดการเจือจาง', s: 'ค่าซ้ำ ค่าเฉลี่ย ± SD และ log₁₀ CFU/mL' } }],
  ['examples-4-compare', {
    en: { h: 'Compare conditions', s: 'Log reduction, % kill and time-kill curves' },
    th: { h: 'เปรียบเทียบสภาวะการทดลอง', s: 'log reduction อัตราการฆ่า และกราฟ time-kill' } }],
  ['multi-3-found', {
    en: { h: 'Several plates in one photo', s: 'Each plate is found, counted and saved' },
    th: { h: 'หลายเพลตในภาพเดียว', s: 'หา นับ และบันทึกทีละเพลต' } }],
  ['drops-22-table', {
    en: { h: 'Drop plates (Miles–Misra)', s: 'Every drop found, with a drop table and 95 % interval' },
    th: { h: 'ดรอปเพลต (Miles–Misra)', s: 'หาทุกหยด พร้อมตารางหยดและช่วงความเชื่อมั่น 95 %' } }],
  ['petrifilm-8-gas', {
    en: { h: 'Petrifilm® dry films', s: 'E. coli, coliforms, gas bubbles and more',
          n: 'Petrifilm is a trademark of Neogen Corporation. Not made or endorsed by Neogen.' },
    th: { h: 'แผ่นฟิล์มแห้ง Petrifilm®', s: 'อี. โคไล โคลิฟอร์ม ฟองแก๊ส และอื่น ๆ',
          n: 'Petrifilm เป็นเครื่องหมายการค้าของ Neogen Corporation แอปนี้ไม่ได้จัดทำหรือรับรองโดย Neogen' } }],
  ['zones-10-review', {
    en: { h: 'Inhibition zones (beta)', s: 'Zone diameters in mm, checked against your calliper' },
    th: { h: 'โซนยับยั้ง (เบต้า)', s: 'วัดเส้นผ่านศูนย์กลางโซนเป็นมิลลิเมตร เทียบกับเวอร์เนียร์ของคุณ' } }],
  ['examples-1-plates', {
    en: { h: 'Try it now with examples', s: 'Built-in example data and a picture manual' },
    th: { h: 'ลองใช้ได้ทันทีด้วยข้อมูลสาธิต', s: 'มีข้อมูลสาธิตในตัว พร้อมคู่มือภาพทุกฟีเจอร์' } }],
];
// Screens shown on tablets and Chromebooks (their headlines come from SHOTS).
const WIDE = SHOTS.map(([shot]) => shot);
const FEATURE = {
  en: { t: 'Count CFU on agar plates with your phone', s: 'Dilution series · drop plates · Petrifilm® · inhibition zones' },
  th: { t: 'นับโคโลนี (CFU) บนจานเพาะเชื้อด้วยโทรศัพท์', s: 'ชุดการเจือจาง · ดรอปเพลต · Petrifilm® · โซนยับยั้ง' },
};

(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  for (const lang of ['en', 'th']) {
    const tag = lang === 'en' ? 'en-US' : 'th-TH';
    const outDir = path.join(store, 'screenshots', tag);
    fs.mkdirSync(outDir, { recursive: true });
    for (const f of fs.readdirSync(outDir)) if (f.endsWith('.png')) fs.unlinkSync(path.join(outDir, f));
    const page = await b.newPage({ viewport: { width: 1080, height: 1920 } });
    for (const [i, [shot, text]] of SHOTS.entries()) {
      const img = path.join(raw, `${shot}.${lang}.png`);
      if (!fs.existsSync(img)) throw new Error(`missing ${img}`);
      const q = new URLSearchParams({ lang, img: 'file://' + img, ...text[lang] });
      await page.goto('file://' + path.join(__dirname, 'frame.html') + '?' + q);
      await page.waitForFunction(() => document.getElementById('img').complete && document.fonts.status === 'loaded');
      const out = path.join(outDir, `${i + 1}-${shot.split('-')[0]}.png`);
      await page.screenshot({ path: out });
      console.log(out);
    }
    await page.close();
    const fp = await b.newPage({ viewport: { width: 1024, height: 500 } });
    const q = new URLSearchParams({ lang, ...FEATURE[lang],
      a: 'file://' + path.join(raw, `examples-3-result.${lang}.png`),
      b: 'file://' + path.join(raw, `count-2-result.${lang}.png`) });
    await fp.goto('file://' + path.join(__dirname, 'feature.html') + '?' + q);
    await fp.waitForFunction(() => [...document.images].every(i => i.complete) && document.fonts.status === 'loaded');
    const out = path.join(store, 'graphics', `feature-graphic-${lang}.png`);
    await fp.screenshot({ path: out });
    console.log(out);
    await fp.close();
    for (const [kind, dir, folder] of [['tablet', rawTablet, 'tablet'], ['desktop', rawDesktop, 'chromebook']]) {
      if (!dir) continue;
      const wideDir = path.join(store, 'screenshots', folder, tag);
      fs.mkdirSync(wideDir, { recursive: true });
      for (const f of fs.readdirSync(wideDir)) if (f.endsWith('.png')) fs.unlinkSync(path.join(wideDir, f));
      const wp = await b.newPage({ viewport: { width: 2560, height: 1440 } });
      for (const [i, shot] of WIDE.entries()) {
        const img = path.join(dir, `${shot}.${lang}.png`);
        if (!fs.existsSync(img)) throw new Error(`missing ${img}`);
        const text = SHOTS.find(([s]) => s === shot)[1][lang];
        const q = new URLSearchParams({ lang, kind, img: 'file://' + img, ...text });
        await wp.goto('file://' + path.join(__dirname, 'wide.html') + '?' + q);
        await wp.waitForFunction(() => document.getElementById('img').complete && document.fonts.status === 'loaded');
        const out = path.join(wideDir, `${i + 1}-${shot.split('-')[0]}.png`);
        await wp.screenshot({ path: out });
        console.log(out);
      }
      await wp.close();
    }
  }
  await b.close();
})().catch(e => { console.error('FAILED', e.message); process.exit(1); });
