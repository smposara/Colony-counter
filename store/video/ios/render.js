// Renders the Play Store promo video from howto.html, frame by frame.
//   node render.js en|th video out.mp4    -> 1920x1080, 30 fps, H.264 (silent audio track)
//   node render.js en|th stills 1.5,6,12  -> still-<lang>-<t>.png for a quick look
// Needs Playwright (Chromium) and ffmpeg. Set CHROMIUM to the browser path if it
// is not the one below.
const { chromium } = require('playwright');
const http = require('http'), fs = require('fs'), path = require('path'), { spawn } = require('child_process');
// Files come from this folder, the app's fonts and icon, and the store screenshots.
const repo = path.join(__dirname, '..', '..', '..');
const roots = [__dirname, path.join(repo, 'app/assets/fonts'), path.join(repo, 'app/assets/icon'), path.join(repo, 'app/web/app-icons')];
const find = (p) => roots.map(r => path.join(r, p)).find(f => fs.existsSync(f) && fs.statSync(f).isFile());
const types = { '.html': 'text/html', '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml', '.ttf': 'font/ttf' };
const server = http.createServer((req, res) => {
  const f = find(decodeURIComponent(req.url.split('?')[0]));
  if (!f) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'Content-Type': types[path.extname(f)] || 'application/octet-stream' });
  fs.createReadStream(f).pipe(res);
}).listen(0, '127.0.0.1');
const [lang, mode, arg] = process.argv.slice(2);
const FPS = 30;
(async () => {
  const b = await chromium.launch({ executablePath: process.env.CHROMIUM || '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const p = await b.newPage({ viewport: { width: 1920, height: 1080 } });
  p.on('pageerror', e => console.log('pageerror', e.message));
  await p.goto(`http://127.0.0.1:${server.address().port}/howto.html?lang=${lang}`);
  const dur = await p.evaluate(() => window.ready);
  console.log('duration', dur.toFixed(2), 's');
  if (mode === 'stills') {
    for (const t of arg.split(',').map(Number)) {
      await p.evaluate(t => render(t), t);
      await p.screenshot({ path: `still-${lang}-${t}.png` });
    }
  } else {
    const ff = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'mjpeg', '-i', '-',
      '-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo', '-shortest',
      '-c:v', 'libx264', '-preset', 'slow', '-crf', '17', '-pix_fmt', 'yuv420p', '-r', String(FPS),
      '-c:a', 'aac', '-b:a', '128k', '-movflags', '+faststart', arg], { stdio: ['pipe', 'inherit', 'inherit'] });
    const n = Math.round(dur * FPS);
    for (let i = 0; i < n; i++) {
      await p.evaluate(t => render(t), i / FPS);
      const buf = await p.screenshot({ type: 'jpeg', quality: 95 });
      if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
      if (i % 150 === 0) console.log('frame', i, '/', n);
    }
    ff.stdin.end();
    await new Promise(r => ff.on('close', r));
  }
  await b.close(); server.close();
})().catch(e => { console.log('FAILED', e.message); process.exit(1); });
