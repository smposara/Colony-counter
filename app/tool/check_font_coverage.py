"""Fail if the app's text uses a character the bundled fonts cannot draw.

The web build bundles Roboto plus a small symbol font (ColonySymbols) instead of
downloading fallback fonts, so any new symbol in a string literal must be in one
of them. Run from app/: python tool/check_font_coverage.py
"""

import pathlib
import sys

from fontTools.ttLib import TTFont

FONTS = ["assets/fonts/Roboto-Regular.ttf", "assets/fonts/ColonySymbols-Regular.ttf"]

covered = set()
for path in FONTS:
    covered |= set(TTFont(path).getBestCmap())

missing = {}
for f in pathlib.Path("lib").rglob("*.dart"):
    for ch in f.read_text(encoding="utf-8"):
        if ord(ch) > 126 and ord(ch) not in covered:
            missing.setdefault(ch, set()).add(str(f))

if missing:
    for ch, files in sorted(missing.items()):
        print(f"U+{ord(ch):04X} {ch!r} not in bundled fonts: {', '.join(sorted(files))}")
    sys.exit(1)
print("All characters used in lib/ are covered by the bundled fonts.")
