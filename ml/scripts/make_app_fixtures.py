"""Write the golden plates used by the Flutter app's tests (app/test/fixtures).

Each fixture is a synthetic JPEG plus a JSON label with the true colony positions
and the Python pipeline's count on that same JPEG, so the Dart port can be checked
against both. Run from the repo root:  python ml/scripts/make_app_fixtures.py
(add --zones or --petrifilm for the zone plates or dry films only).
"""

import json
from pathlib import Path

import cv2
import numpy as np

from colonycounter import count_colonies
from colonycounter.petrifilm import count_petrifilm
from colonycounter.synth import make_plate
from colonycounter.synth_petrifilm import make_film
from colonycounter.synth_zones import make_zone_plate
from colonycounter.zones import measure_plate

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


    make_zone_fixtures()


def _zone_cases():
    """Inhibition zone plates: name, make_zone_plate arguments."""
    base = make_zone_plate(n_disks=1, size=1200)
    c, mm = base.plate.cx, base.plate.mm_per_px
    return [
        ("zones_reflected", dict(seed=31, colonies_in_zones=4)),
        ("zones_backlit_hazy", dict(seed=32, lighting="backlit", edge_mm=(0.6, 1.0))),
        ("zones_wells", dict(seed=33, assay="well", disk_mm=8.0, zone_mm=(12.0, 24.0))),
        ("zones_nozone", dict(seed=34, zone_mm=[6, 20, 6, 24, 6, 18])),
        ("zones_overlap", dict(seed=35, positions=[(c - 11 / mm, c), (c + 11 / mm, c), (c, c + 26 / mm)],
                               zone_mm=[28.0, 26.0, 14.0])),
    ]


def make_zone_fixtures() -> None:
    """Zone plates for the Dart port: true diameters plus the Python result on the same JPEG."""
    OUT.mkdir(parents=True, exist_ok=True)
    for name, kw in _zone_cases():
        s = make_zone_plate(size=1200, **kw)
        path = OUT / f"{name}.jpg"
        cv2.imwrite(str(path), s.image, [cv2.IMWRITE_JPEG_QUALITY, 92])
        res = measure_plate(cv2.imread(str(path)), plate_diameter_mm=s.plate.diameter_mm,
                            assay=s.assay, disk_mm=s.disk_mm)
        label = {
            "assay": s.assay,
            "disk_mm": s.disk_mm,
            "plate_mm": s.plate.diameter_mm,
            "plate": _plate(s.plate),
            "true": [{"x": round(z.x, 2), "y": round(z.y, 2), "diameter_mm": round(z.diameter_mm, 3)}
                     for z in s.zones],
            "python": {
                "polarity": res.polarity,
                "flags": res.flags,
                "disk_scale_ratio": round(float(res.disk_scale_ratio), 4),
                "plate": _plate(res.plate),
                "zones": [{"x": round(float(z.x), 2), "y": round(float(z.y), 2),
                           "diameter_mm": None if z.diameter_rounded is None else round(float(z.diameter_mm), 3),
                           "flags": z.flags} for z in res.zones],
            },
        }
        (OUT / f"{name}.json").write_text(json.dumps(label, indent=1))
        print(name, [round(z.diameter_mm, 1) for z in s.zones], "python",
              [None if z.diameter_rounded is None else round(float(z.diameter_mm), 1) for z in res.zones],
              res.flags)


PETRIFILM_CASES = [  # name, make_film arguments
    ("film_ac", dict(type="ac", n=60, seed=41, angle_deg=4)),
    ("film_ec", dict(type="ec", n=40, seed=42, angle_deg=-5)),
    ("film_cc", dict(type="cc", n=30, seed=43, angle_deg=2)),
    ("film_eb", dict(type="eb", n=40, seed=44, angle_deg=-3)),
    ("film_ym", dict(type="ym", n=40, seed=45, angle_deg=6)),
    ("film_ac_crowded", dict(type="ac", n=700, seed=46, angle_deg=3)),
]


def make_petrifilm_fixtures() -> None:
    """Dry films for the Dart port: true counts plus the Python result on the same JPEG."""
    OUT.mkdir(parents=True, exist_ok=True)
    for name, kw in PETRIFILM_CASES:
        s = make_film(**kw)
        path = OUT / f"{name}.jpg"
        cv2.imwrite(str(path), s.image, [cv2.IMWRITE_JPEG_QUALITY, 90])
        res = count_petrifilm(cv2.imread(str(path)), s.type)
        label = {
            "type": s.type,
            "px_per_mm": s.px_per_mm,
            "angle_deg": s.angle_deg,
            "area": {"cx": round(float(s.centre[0]), 2), "cy": round(float(s.centre[1]), 2),
                     "radius": round(float(s.radius_px), 2)},
            "true": s.truth(),
            "python": {
                "counts": res.counts,
                "estimates": None if res.estimates is None
                else {k: round(v, 1) for k, v in res.estimates.items()},
                "squares_used": res.squares_used,
                "flags": res.flags,
                "pitch_px": round(res.grid.pitch_px, 3),
                "angle_deg": round(res.grid.angle_deg, 3),
                "line_half_px": round(res.grid.line_half_px, 2),
                "grid_strength": round(res.grid.strength, 3),
                "area": _plate(res.plate),
                "bubbles": len(res.bubbles),
                "colonies": [{"x": round(c.x, 1), "y": round(c.y, 1), "r": round(c.radius_px, 2),
                              "kind": c.kind, "n": c.n, "gas": c.gas, "yellow": c.yellow}
                             for c in res.colonies],
            },
        }
        (OUT / f"{name}.json").write_text(json.dumps(label, indent=1))
        print(name, s.image.shape[:2], "true", s.truth(), "python", res.counts, res.estimates, res.flags)


if __name__ == "__main__":
    import sys
    if sys.argv[1:] == ["--zones"]:
        make_zone_fixtures()
    elif sys.argv[1:] == ["--petrifilm"]:
        make_petrifilm_fixtures()
    else:
        main()
