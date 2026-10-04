"""Write the golden plates used by the Flutter app's tests (app/test/fixtures).

Each fixture is a synthetic JPEG plus a JSON label with the true colony positions
and the Python pipeline's count on that same JPEG, so the Dart port can be checked
against both. Run from the repo root:  python ml/scripts/make_app_fixtures.py
"""

import json
from pathlib import Path

import cv2
import numpy as np

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


# Drop plate: four 10 µL drops (dilution, colonies, of which blue), left to right,
# top to bottom. Blue = X-gal positive.
DROPS = [(4, 26, 6), (5, 12, 3), (6, 4, 1), (7, 0, 0)]


def make_drop_plate(seed: int = 21):
    """Synthetic drop plate with blue and white colonies, plus its labels."""
    rng = np.random.default_rng(seed)
    base = make_plate(0, size=1200, seed=seed)
    img = base.image.astype(np.float32)
    px_per_mm = 1 / base.plate.mm_per_px
    cx0, cy0 = base.plate.cx, base.plate.cy
    centres = [(cx0 - 15 * px_per_mm, cy0 - 15 * px_per_mm), (cx0 + 15 * px_per_mm, cy0 - 15 * px_per_mm),
               (cx0 - 15 * px_per_mm, cy0 + 15 * px_per_mm), (cx0 + 15 * px_per_mm, cy0 + 15 * px_per_mm)]
    yy, xx = np.mgrid[0:img.shape[0], 0:img.shape[1]].astype(np.float32)
    drops = []
    for (dx, dy), (dil, n, n_blue) in zip(centres, DROPS):
        pts = []
        for _ in range(20000):
            if len(pts) == n:
                break
            ang, rad = rng.uniform(0, 2 * np.pi), 3.6 * px_per_mm * np.sqrt(rng.random())
            x, y = dx + rad * np.cos(ang), dy + rad * np.sin(ang)
            if all(np.hypot(x - a, y - b) > 1.0 * px_per_mm for a, b in pts):
                pts.append((x, y))
        assert len(pts) == n, "could not place colonies"
        for k, (x, y) in enumerate(pts):
            r = rng.uniform(0.35, 0.45) * px_per_mm
            d = np.hypot(xx - x, yy - y)
            edge = (1 / (1 + np.exp(np.clip((d - r) / max(0.6, r * 0.12), -50, 50))))[..., None]
            # BGR: white-cream colonies vs blue colonies.
            colour = np.array([200, 120, 60] if k < n_blue else [150, 190, 210], np.float32)
            img = img * (1 - edge) + colour * edge
        drops.append({"cx": float(dx), "cy": float(dy), "dilution_exp": dil, "count": n, "blue": n_blue})
    img += rng.normal(0, 2.5, img.shape)
    return np.clip(img, 0, 255).astype(np.uint8), drops


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

    image, drops = make_drop_plate()
    cv2.imwrite(str(OUT / "drops.jpg"), image, [cv2.IMWRITE_JPEG_QUALITY, 92])
    res = count_colonies(cv2.imread(str(OUT / "drops.jpg")))
    (OUT / "drops.json").write_text(json.dumps({"drops": drops, "python_count": res.count}))
    print(f"drops: true {sum(d['count'] for d in drops)}, python {res.count}")


if __name__ == "__main__":
    main()
