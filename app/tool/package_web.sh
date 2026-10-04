#!/usr/bin/env bash
# Build the web version and zip it for self-hosting.
#   app/tool/package_web.sh            -> dist/colony-counter-web.zip (repo root)
# Upload the zip's contents to any static web host (any folder, HTTPS required
# for the camera). Fonts and the rendering engine are bundled: no CDN needed.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter build web --release --no-web-resources-cdn --no-wasm-dry-run

out=build/web
# The JS build uses CanvasKit: canvaskit/chromium/* on Chrome-based browsers,
# canvaskit/canvaskit.* elsewhere (Safari, Firefox). The rest is for --wasm
# builds or debugging and is never downloaded.
rm -rf "$out"/canvaskit/skwasm* "$out"/canvaskit/wimp* "$out"/canvaskit/webparagraph
find "$out" -name '*.symbols' -delete

dist=../dist
mkdir -p "$dist"
zip_path="$(cd "$dist" && pwd)/colony-counter-web.zip"
rm -f "$zip_path"
(cd "$out" && zip -qr -9 "$zip_path" .)
echo "Wrote $zip_path ($(du -h "$zip_path" | cut -f1))"
