"""Draws numbered callouts on the manual's screenshots.

Reads <in>/<chapter>.<lang>.json (written by test/manual/harness.dart) and the
PNGs next to it, and writes docs/manual/img/<chapter>-<step>.<lang>.webp with
a red-pink outline and a numbered badge on every marked control.

    python3 test/manual/annotate.py build/manual ../docs/manual/img
"""

import json
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFont

# A red-pink that stands out on the app's blue, orange and on plate photos.
ACCENT = (233, 30, 99)
WHITE = (255, 255, 255)
FONT = pathlib.Path(__file__).resolve().parents[2] / 'assets/fonts/Roboto-Bold.ttf'


def _badge(draw, cx, cy, r, n, font):
    draw.ellipse((cx - r - 3, cy - r - 3, cx + r + 3, cy + r + 3), fill=WHITE)
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=ACCENT)
    draw.text((cx, cy + 1), str(n), fill=WHITE, font=font, anchor='mm')


def annotate(png, marks, scale, out):
    im = Image.open(png).convert('RGB')
    draw = ImageDraw.Draw(im)
    W, H = im.size
    r = int(17 * scale)
    font = ImageFont.truetype(str(FONT), int(20 * scale))
    for n, m in enumerate(marks, 1):
        x0, y0 = m['x'] * scale, m['y'] * scale
        x1, y1 = x0 + m['w'] * scale, y0 + m['h'] * scale
        pad = 3 * scale
        box = (max(2, x0 - pad), max(2, y0 - pad), min(W - 3, x1 + pad),
               min(H - 3, y1 + pad))
        rad = int(min(14 * scale, (box[3] - box[1]) / 2))
        if m['kind'] != 'look' or m['w'] * m['h'] < 240 * 240:
            draw.rounded_rectangle(box, radius=rad, outline=WHITE,
                                   width=int(6 * scale))
            draw.rounded_rectangle(box, radius=rad, outline=ACCENT,
                                   width=int(3 * scale))
        # Badge at the top-left corner, kept on the screen.
        cx = min(max(box[0], r + 4), W - r - 4)
        cy = min(max(box[1], r + 4), H - r - 4)
        _badge(draw, cx, cy, r, n, font)
    im.save(out, 'WEBP', quality=82, method=6)


def main(src, dst):
    src, dst = pathlib.Path(src), pathlib.Path(dst)
    dst.mkdir(parents=True, exist_ok=True)
    index = {}
    for j in sorted(src.glob('*.json')):
        chapter, lang = j.stem.rsplit('.', 1)
        for name, shot in json.loads(j.read_text()).items():
            png = src / f'{name}.{lang}.png'
            annotate(png, shot['marks'], shot['scale'],
                     dst / f'{name}.{lang}.webp')
            index.setdefault(name, [m['kind'] for m in shot['marks']])
    (dst / 'marks.json').write_text(json.dumps(index, indent=1, sort_keys=True))
    print(f'{len(index)} screens')


if __name__ == '__main__':
    main(*sys.argv[1:3])
