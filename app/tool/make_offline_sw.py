"""Write build/web/offline_sw.js: the service worker that lets the web app open
and count with no internet connection.

Run by tool/package_web.sh after `flutter build web`. The worker saves the
app's files when it is installed (on the first visit, online) and serves them
from the browser's cache afterwards. Its version is a hash of the files, so
every release that changes a file is a new version: it installs in the
background and is switched to at the next launch (see web/index.html).

Usage: python3 tool/make_offline_sw.py build/web
"""

import hashlib
import json
import pathlib
import sys

# Not needed to run the app: the 3D-printed phone stand's files and page,
# and Flutter's own (self-removing) service worker.
SKIP_PREFIXES = ("stand/", "stand.html", "offline_sw.js", "flutter_service_worker.js", "install-check.html")
# The two CanvasKit builds; a browser loads only one of them.
CHROMIUM = ("canvaskit/chromium/",)
STANDARD = ("canvaskit/canvaskit.js", "canvaskit/canvaskit.wasm")

TEMPLATE = r"""'use strict';
// Made by tool/make_offline_sw.py; do not edit by hand.
// Saves the app's files so it opens and counts with no internet connection.
const VERSION = '__VERSION__';
const CACHE = 'colony-counter-' + VERSION;
const CORE = __CORE__;
const CHROMIUM = __CHROMIUM__;
const STANDARD = __STANDARD__;

// The CanvasKit build this browser will load (as flutter.js decides).
function engineFiles() {
  const chromium = typeof Intl !== 'undefined' &&
    typeof Intl.v8BreakIterator !== 'undefined' &&
    typeof ImageDecoder !== 'undefined';
  return chromium ? CHROMIUM : STANDARD;
}

const scope = () => self.registration.scope;
const url = (path) => new URL(path, scope()).href;

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    // index.html is also what the bare folder address ("./") shows.
    await cache.addAll([...CORE, ...engineFiles()].map((p) => new Request(url(p), { cache: 'reload' })));
  })());
  // The first install has no earlier version to wait for.
  if (!self.registration.active) self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) {
      if (key.startsWith('colony-counter-') && key !== CACHE) await caches.delete(key);
    }
  })());
});

// index.html asks the waiting new version to take over at the next launch.
self.addEventListener('message', (event) => {
  if (event.data === 'skipWaiting') self.skipWaiting();
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET' || !req.url.startsWith(scope())) return; // e.g. analytics
  // The install check always looks at the server, never the saved copy.
  const path = new URL(req.url).pathname;
  if (/(offline_sw\.js|install-check\.html)$/.test(path)) return;
  if (new URL(req.referrer || req.url).pathname.endsWith('install-check.html')) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    // Page loads (any address in the app's folder) get the saved index.html.
    const key = req.mode === 'navigate' && !/\.html$/.test(new URL(req.url).pathname)
      ? url('index.html') : req;
    const hit = await cache.match(key, { ignoreSearch: true });
    if (hit) return hit;
    try {
      const res = await fetch(req);
      // Anything else the app loads is saved the first time, as a safety net.
      if (res.ok && res.type === 'basic') cache.put(req, res.clone());
      return res;
    } catch (e) {
      if (req.mode === 'navigate') {
        const page = await cache.match(url('index.html'));
        if (page) return page;
      }
      throw e;
    }
  })());
});
"""


def main(out: pathlib.Path) -> None:
    files = sorted(
        p.relative_to(out).as_posix()
        for p in out.rglob("*")
        if p.is_file() and not p.relative_to(out).as_posix().startswith(SKIP_PREFIXES)
    )
    chromium = [f for f in files if f.startswith(CHROMIUM)]
    standard = [f for f in files if f in STANDARD]
    core = [f for f in files if f not in chromium and f not in standard]
    if "index.html" not in core or "main.dart.js" not in core:
        sys.exit(f"{out} does not look like a Flutter web build")
    h = hashlib.sha256()
    for f in files:
        h.update(f.encode())
        h.update(hashlib.sha256((out / f).read_bytes()).digest())
    sw = (TEMPLATE
          .replace("__VERSION__", h.hexdigest()[:16])
          .replace("__CORE__", json.dumps(core))
          .replace("__CHROMIUM__", json.dumps(chromium))
          .replace("__STANDARD__", json.dumps(standard)))
    (out / "offline_sw.js").write_text(sw, encoding="utf-8")
    size = sum((out / f).stat().st_size for f in core) / 1e6
    print(f"offline_sw.js: version {h.hexdigest()[:16]}, {len(core)} files ({size:.1f} MB) "
          f"+ CanvasKit ({len(chromium)} Chromium / {len(standard)} standard files)")


if __name__ == "__main__":
    main(pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "build/web"))
