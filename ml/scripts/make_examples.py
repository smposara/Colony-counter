"""Write the photos for the app's built-in example data (app/assets/examples).

Synthetic plates for a lake-water dilution series, a small disinfectant
time-kill set and one inhibition-zone plate. The app then counts and measures
them with its own pipeline and packs them into a backup zip:

    python ml/scripts/make_examples.py              # → app/build/examples/
    cd app && flutter test test/examples/make_examples_gen.dart

Photos are kept small (800 px, JPEG quality 82) so the asset stays near 1 MB.
"""

import argparse
import json
from pathlib import Path

import cv2

from colonycounter.synth import make_plate
from colonycounter.synth_zones import make_zone_plate

OUT = Path(__file__).resolve().parents[2] / "app" / "build" / "examples"
SIZE = 800
QUALITY = 82

# name, colonies, seed. Lake water: 10⁻⁴ and 10⁻⁵, two replicates each (about
# 2.3 × 10⁷ CFU/mL); disinfectant: control and treated at 0 h and 2 h, the
# treated 2 h sample plated two dilutions lower (about 2 log reduction).
PLATES = [
    ("lake_e4_r1", 236, 101),
    ("lake_e4_r2", 212, 102),
    ("lake_e5_r1", 26, 103),
    ("lake_e5_r2", 23, 104),
    ("control_0h", 128, 111),
    ("control_2h", 141, 112),
    ("treated_0h", 119, 113),
    ("treated_2h", 133, 114),
]

# Six disks with these zones; the 6 mm one has none (the negative control).
ZONE_MM = [6.0, 14.0, 22.0, 11.0, 17.0, 9.0]


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", type=Path, default=OUT)
    out = ap.parse_args().out
    out.mkdir(parents=True, exist_ok=True)
    truth = {}
    for name, n, seed in PLATES:
        s = make_plate(n, size=SIZE, seed=seed, radius_mm=(0.5, 1.3))
        cv2.imwrite(str(out / f"{name}.jpg"), s.image, [cv2.IMWRITE_JPEG_QUALITY, QUALITY])
        truth[name] = len(s.points)
    z = make_zone_plate(n_disks=6, zone_mm=ZONE_MM, size=SIZE, seed=121, colonies_in_zones=3)
    cv2.imwrite(str(out / "zones.jpg"), z.image, [cv2.IMWRITE_JPEG_QUALITY, QUALITY])
    truth["zones"] = [round(q.diameter_mm, 1) for q in z.zones]
    (out / "truth.json").write_text(json.dumps(truth, indent=1))
    size = sum(p.stat().st_size for p in out.glob("*.jpg"))
    print(json.dumps(truth), f"\n{size / 1024:.0f} KB of photos in {out}")


if __name__ == "__main__":
    main()
