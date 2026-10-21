// Facebook launch images from raw app screens (the phone screens rendered by
// the manual harness, e.g. count-2-result.en.png):
//
//   node make_social.js <phoneRaw>   → store/social/facebook-*-{en,th}.png
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const raw = path.resolve(process.argv[2]);
const out = path.resolve(__dirname, '..', 'social');

const NOTE = {
  en: 'Petrifilm is a trademark of Neogen Corporation. Not made or endorsed by Neogen. For research and teaching, not a medical device.',
  th: 'Petrifilm เป็นเครื่องหมายการค้าของ Neogen Corporation แอปนี้ไม่ได้จัดทำหรือรับรองโดย Neogen · สำหรับงานวิจัยและการเรียนการสอน ไม่ใช่เครื่องมือทางการแพทย์',
};
const GET = {
  en: [['Android', 'Google Play'], ['iPhone / iPad', 'cc.amphur.in.th/ios.html']],
  th: [['Android', 'Google Play'], ['iPhone / iPad', 'cc.amphur.in.th/ios.html']],
};
const TEXT = {
  en: {
    badge: 'Now free on Google Play',
    h: 'Count colonies and CFU with your phone',
    hLink: 'Count colonies and CFU with your phone, free',
    chips: ['CFU/mL', 'Drop plates', 'Petrifilm®', 'Inhibition zones', 'Thai & English'],
    hFeatures: 'What it does',
    tiles: ['Count from a photo', 'CFU/mL from a dilution series', 'Compare conditions',
      'Drop plates (Miles\u2060–\u2060Misra)', 'Petrifilm® dry films', 'Inhibition zones (beta)'],
  },
  th: {
    badge: 'ดาวน์โหลดฟรีแล้ว',
    h: 'นับโคโลนีและคำนวณ CFU ด้วยมือถือ',
    hLink: 'นับโคโลนีและคำนวณ CFU ด้วยมือถือ ฟรี',
    chips: ['CFU/mL', 'ดรอปเพลต', 'Petrifilm®', 'โซนยับยั้ง', 'ไทย / อังกฤษ'],
    hFeatures: 'ทำอะไรได้บ้าง',
    tiles: ['นับโคโลนีจากภาพถ่าย', 'CFU/mL\nจากชุดการเจือจาง', 'เปรียบเทียบสภาวะ',
      'ดรอปเพลต (Miles\u2060–\u2060Misra)', 'แผ่นฟิล์ม Petrifilm®', 'โซนยับยั้ง (เบต้า)'],
  },
};
const IMAGES = [
  ['square', 1080, 1080, ['examples-3-result', 'count-2-result', 'petrifilm-8-gas']],
  ['link', 1200, 630, ['examples-3-result', 'count-2-result']],
  ['features', 1080, 1080, ['count-2-result', 'examples-3-result', 'examples-4-compare',
    'drops-22-table', 'petrifilm-8-gas', 'zones-10-review']],
];

(async () => {
  fs.mkdirSync(out, { recursive: true });
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  for (const lang of ['en', 'th']) {
    const t = TEXT[lang];
    for (const [kind, w, h, shots] of IMAGES) {
      const page = await b.newPage({ viewport: { width: w, height: h } });
      const text = { badge: t.badge, h: kind === 'link' ? t.hLink : kind === 'features' ? t.hFeatures : t.h,
        chips: t.chips, tiles: t.tiles, get: GET[lang], note: NOTE[lang] };
      const q = new URLSearchParams({ kind, lang, text: JSON.stringify(text) });
      shots.forEach((s, i) => {
        const img = path.join(raw, `${s}.${lang}.png`);
        if (!fs.existsSync(img)) throw new Error(`missing ${img}`);
        q.set('img' + (i + 1), 'file://' + img);
      });
      await page.goto('file://' + path.join(__dirname, 'social.html') + '?' + q);
      await page.waitForFunction(() => [...document.images].every(i => i.complete) && document.fonts.status === 'loaded');
      const file = path.join(out, `facebook-${kind}-${lang}.png`);
      await page.screenshot({ path: file });
      console.log(file);
      await page.close();
    }
  }
  await b.close();
})().catch(e => { console.error('FAILED', e.message); process.exit(1); });
