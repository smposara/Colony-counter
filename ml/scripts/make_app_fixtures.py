"""Write the golden plates used by the Flutter app's tests (app/test/fixtures).

Each fixture is a synthetic JPEG plus a JSON label with the true colony positions
and the Python pipeline's count on that same JPEG, so the Dart port can be checked
against both. Run from the repo root:  python ml/scripts/make_app_fixtures.py
"""

import json
from pathlib import Path

import cv2

from colonycounter import count_colonies
from colonycounter.synth import make_plate

OUT = Path(__file__).resolve().parents[2] / "app" / "test" / "fixtures"
CASES = [  # name, colonies, seed, polarity
    ("empty", 0, 11, "bright"),
    ("sparse", 40, 12, "bright"),
    ("medium", 120, 13, "bright"),
    ("dense", 250, 14, "bright"),
    ("backlit", 80, 15, "dark"),
]


def _plate(p) -> dict:
    return {"cx": float(p.cx), "cy": float(p.cy), "radius": float(p.radius)}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, n, seed, polarity in CASES:
        s = make_plate(n, size=1000, seed=seed, polarity=polarity, radius_mm=(0.5, 1.4))
        path = OUT / f"{name}.jpg"
        cv2.imwrite(str(path), s.image, [cv2.IMWRITE_JPEG_QUALITY, 92])
        res = count_colonies(cv2.imread(str(path)))
        label = {
            "true_count": len(s.points),
            "python_count": res.count,
            "polarity": res.polarity,
            "plate": _plate(s.plate),
            "python_plate": _plate(res.plate),
            "points": s.points.round(1).tolist(),
        }
        (OUT / f"{name}.json").write_text(json.dumps(label))
        print(f"{name}: true {len(s.points)}, python {res.count}")


if __name__ == "__main__":
    main()
