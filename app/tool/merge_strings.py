"""Merge translation parts into the ARB files used by `flutter gen-l10n`.

Each lib/l10n/parts/*.json maps a key to its English and Thai text, e.g.
  {"savePlate": {"en": "Save plate", "th": "บันทึกเพลต"},
   "nPlates": {"en": "{n, plural, =1{1 plate} other{{n} plates}}",
               "th": "{n} เพลต", "placeholders": {"n": {"type": "int"}}}}
Run from app/: python tool/merge_strings.py
"""

import json
import pathlib
import re
import sys

parts = sorted(pathlib.Path("lib/l10n/parts").glob("*.json"))
en, th = {"@@locale": "en"}, {"@@locale": "th"}
seen = {}
ok = True
for part in parts:
    for key, v in json.loads(part.read_text(encoding="utf-8")).items():
        if key in seen:
            print(f"duplicate key {key} in {part.name} and {seen[key]}")
            ok = False
        seen[key] = part.name
        en[key] = v["en"]
        th[key] = v["th"]
        ph = v.get("placeholders")
        if ph is None:
            # Infer simple {name} placeholders as Object.
            names = set(re.findall(r"\{(\w+)[},]", v["en"]))
            ph = {n: {} for n in sorted(names)}
        if ph:
            en["@" + key] = {"placeholders": ph}
if not ok:
    sys.exit(1)
for name, data in [("app_en.arb", en), ("app_th.arb", th)]:
    pathlib.Path("lib/l10n", name).write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
print(f"{len(seen)} strings from {len(parts)} parts")
