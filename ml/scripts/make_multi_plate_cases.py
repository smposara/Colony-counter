"""Synthetic photos with several plates, for the app's multi-plate finder.

Cuts the dish out of the app's fixture plates (app/test/fixtures/{medium,sparse,
dense,backlit}.jpg) and the store photo (store/video/plate.jpg) and lays copies
out on a dark, grey or light surround: 1–6 plates, different sizes, gaps,
brightness, colony densities and rim contrast (``faint`` removes the rim
highlight and brings the agar close to the surround's brightness).

Run from the repo root:

    python ml/scripts/make_multi_plate_cases.py OUT_DIR      # whole set + cases.json
    python ml/scripts/make_multi_plate_cases.py --fixtures   # the few kept as app fixtures

Each case's ground truth is the true centre and radius of every plate in the
photo's pixels, in reading order (top row first, left to right).
"""

import argparse
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "app" / "test" / "fixtures"

# Source plates: file, centre x, centre y, radius (the dish's outer edge).
SOURCES = {
    "medium": (FIXTURES / "medium.jpg", 500, 500, 420),
    "sparse": (FIXTURES / "sparse.jpg", 500, 500, 420),
    "dense": (FIXTURES / "dense.jpg", 500, 500, 420),
    "backlit": (FIXTURES / "backlit.jpg", 500, 500, 420),
    "store": (ROOT / "store" / "video" / "plate.jpg", 600, 500, 420),
}

_cache: dict = {}


def _source(name: str) -> tuple[np.ndarray, float]:
    """RGB float crop of a source plate centred on the dish, and its radius."""
    if name not in _cache:
        path, cx, cy, r = SOURCES[name]
        a = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
        h = r + 4
        _cache[name] = (a[cy - h : cy + h, cx - h : cx + h].copy(), float(r))
    return _cache[name]


def _plate_patch(name, radius, brightness=1.0, faint=None, bg=None):
    """(rgb, alpha) of one plate scaled to ``radius``, on a square patch."""
    src, r0 = _source(name)
    s = radius / r0
    size = int(math.ceil(src.shape[0] * s))
    rgb = np.asarray(
        Image.fromarray(src.clip(0, 255).astype(np.uint8)).resize((size, size), Image.LANCZOS)
    ).astype(np.float32)
    c = (size - 1) / 2
    yy, xx = np.mgrid[0:size, 0:size]
    d = np.hypot(xx - c, yy - c)
    inside = d < radius * 0.9
    agar = np.median(rgb[inside], axis=0)
    rgb *= brightness
    agar = agar * brightness
    if faint is not None:
        # No rim highlight, and agar only ``faint`` grey levels from the surround.
        t = np.clip((d / radius - 0.88) / 0.06, 0, 1)[..., None]
        rgb = rgb * (1 - t) + agar * t
        shift = (np.asarray(bg, np.float32).mean() + faint) - agar.mean()
        rgb += shift
    alpha = np.clip(radius + 0.5 - d, 0, 1)  # anti-aliased disc edge
    return rgb, alpha


def _layout(n, cols, radius, gap, margin, rng, jitter=0.04):
    rows = math.ceil(n / cols)
    rmax = radius * (1 + jitter)
    cell = 2 * rmax + gap
    w = int(cols * cell - gap + 2 * margin)
    h = int(rows * cell - gap + 2 * margin)
    plates = []
    for i in range(n):
        row, col = divmod(i, cols)
        r = radius * (1 + rng.uniform(-jitter, jitter))
        slack = rmax - r
        cx = margin + col * cell + rmax + rng.uniform(-slack, slack)
        cy = margin + row * cell + rmax + rng.uniform(-slack, slack)
        plates.append([float(cx), float(cy), float(r)])
    return w, h, plates


def make_case(
    names,
    cols,
    radius,
    gap,
    bg=(14, 14, 16),
    margin=60,
    seed=0,
    brightness=None,
    faint=None,
    light_grad=0.0,
    jitter=0.04,
):
    """One photo. Returns (PIL image, [{cx, cy, radius}, ...])."""
    rng = np.random.default_rng(seed)
    w, h, plates = _layout(len(names), cols, radius, gap, margin, rng, jitter)
    img = np.empty((h, w, 3), np.float32)
    img[:] = bg
    if light_grad:
        ramp = np.linspace(-light_grad, light_grad, w, dtype=np.float32)[None, :, None]
        img += ramp
    for k, (name, (cx, cy, r)) in enumerate(zip(names, plates)):
        b = brightness[k] if brightness else 1.0
        f = faint[k] if isinstance(faint, list) else faint
        rgb, alpha = _plate_patch(name, r, b, f, bg)
        size = rgb.shape[0]
        c = (size - 1) / 2
        x0, y0 = int(round(cx - c)), int(round(cy - c))
        # Sub-pixel: the patch's centre lands at x0 + c.
        plates[k][0], plates[k][1] = x0 + c, y0 + c
        xs0, ys0 = max(0, x0), max(0, y0)
        xs1, ys1 = min(w, x0 + size), min(h, y0 + size)
        a = alpha[ys0 - y0 : ys1 - y0, xs0 - x0 : xs1 - x0, None]
        p = rgb[ys0 - y0 : ys1 - y0, xs0 - x0 : xs1 - x0]
        img[ys0:ys1, xs0:xs1] = img[ys0:ys1, xs0:xs1] * (1 - a) + p * a
    img += rng.normal(0, 2.0, img.shape).astype(np.float32)
    out = Image.fromarray(img.clip(0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6))
    truth = [{"cx": round(cx, 1), "cy": round(cy, 1), "radius": round(r, 1)} for cx, cy, r in plates]
    return out, truth


FIX4 = ["medium", "sparse", "dense", "backlit"]
DARK, GREY, LIGHT = (14, 14, 16), (95, 95, 100), (215, 215, 210)


def cases():
    """name -> kwargs for make_case. Covers 1–6 plates, gaps 10–150 px, radius
    140–330 px, dark / grey / light surrounds, mixed densities and faint rims."""
    c = {}
    # Exactly 10 px between neighbours (no size jitter).
    c["store4_gap10"] = dict(names=["store"] * 4, cols=2, radius=300, gap=10, bg=(24, 24, 28), jitter=0)
    c["store4_gap10_density"] = dict(
        names=["store", "sparse", "dense", "store"], cols=2, radius=300, gap=10, bg=(24, 24, 28)
    )
    c["store4_faint"] = dict(names=["store"] * 4, cols=2, radius=280, gap=40, bg=(24, 24, 28), faint=12)
    c["fix4_gap10"] = dict(names=FIX4, cols=2, radius=300, gap=10, jitter=0)
    c["fix4_gap40"] = dict(names=FIX4, cols=2, radius=260, gap=40, seed=1)
    c["fix4_gap150"] = dict(names=FIX4, cols=2, radius=220, gap=150, seed=2)
    c["fix4_row"] = dict(names=FIX4, cols=4, radius=180, gap=25, seed=3)
    c["fix4_light"] = dict(names=FIX4, cols=2, radius=260, gap=30, bg=LIGHT, seed=4)
    c["fix4_grey"] = dict(names=FIX4, cols=2, radius=260, gap=20, bg=GREY, seed=5)
    c["fix4_faint"] = dict(names=FIX4, cols=2, radius=260, gap=30, faint=10, seed=6)
    c["fix4_faint_light"] = dict(names=FIX4, cols=2, radius=260, gap=30, bg=LIGHT, faint=-12, seed=7)
    c["fix4_bright_mix"] = dict(
        names=FIX4, cols=2, radius=260, gap=15, brightness=[0.6, 1.4, 1.0, 0.8], seed=8
    )
    c["mixed_faint_strong"] = dict(
        names=["dense", "store", "sparse", "medium"], cols=2, radius=260, gap=20, faint=[None, 14, None, 10], seed=9
    )
    c["two_gap10"] = dict(names=["dense", "sparse"], cols=2, radius=330, gap=10, seed=10)
    c["three_row"] = dict(names=["medium", "store", "backlit"], cols=3, radius=240, gap=30, seed=11)
    c["three_light"] = dict(names=["store", "dense", "sparse"], cols=3, radius=240, gap=12, bg=LIGHT, seed=12)
    c["five"] = dict(names=FIX4 + ["store"], cols=3, radius=200, gap=20, seed=13)
    c["six_gap10"] = dict(names=FIX4 + ["store", "dense"], cols=3, radius=200, gap=10, seed=14)
    c["six_grey_faint"] = dict(names=FIX4 + ["store", "sparse"], cols=3, radius=190, gap=30, bg=GREY, faint=12, seed=15)
    c["six_light"] = dict(names=["store"] * 3 + FIX4[:3], cols=3, radius=170, gap=15, bg=LIGHT, seed=16)
    c["one_dense_small"] = dict(names=["dense"], cols=1, radius=250, gap=0, margin=200, seed=17)
    c["one_store_light"] = dict(names=["store"], cols=1, radius=320, gap=0, margin=80, bg=LIGHT, seed=18)
    c["one_faint"] = dict(names=["medium"], cols=1, radius=300, gap=0, margin=120, faint=10, seed=19)
    c["four_shaded"] = dict(names=FIX4, cols=2, radius=250, gap=20, bg=(40, 40, 44), light_grad=25, seed=20)
    return c


def random_cases(n, seed=100):
    """n random layouts: 1–6 plates, any source, gap 6–150 px, radius 150–330 px,
    random surround, brightness, faint rims and uneven light."""
    rng = np.random.default_rng(seed)
    out = {}
    for k in range(n):
        count = int(rng.integers(1, 7))
        cols = {1: 1, 2: 2, 3: 3, 4: int(rng.choice([2, 4])), 5: 3, 6: int(rng.choice([2, 3]))}[count]
        radius = float(rng.uniform(150, 330)) if count <= 2 else float(rng.uniform(150, 260))
        level = float(rng.choice([10, 30, 90, 150, 215]))
        bg = tuple(float(level + d) for d in rng.uniform(-6, 6, 3))
        faint = [
            (float(rng.choice([-1, 1]) * rng.uniform(8, 16)) if rng.random() < 0.3 else None) for _ in range(count)
        ]
        out[f"rand{k:02d}"] = dict(
            names=[str(rng.choice(list(SOURCES))) for _ in range(count)],
            cols=cols,
            radius=radius,
            gap=float(rng.choice([6, 10, 20, 40, 80, 150])),
            bg=bg,
            margin=int(rng.uniform(20, 150)),
            seed=1000 + k,
            brightness=[float(rng.uniform(0.6, 1.4)) for _ in range(count)],
            faint=faint,
            light_grad=float(rng.choice([0, 0, 15, 30])),
        )
    return out


# Kept in app/test/fixtures (as multi_<name>.jpg) with truth in multi_plates.json.
FIXTURE_CASES = [
    "store4_gap10",
    "fix4_gap10",
    "fix4_faint",
    "mixed_faint_strong",
    "fix4_light",
    "six_gap10",
]


def _write(out_dir: Path, names, prefix="", all_cases=None):
    out_dir.mkdir(parents=True, exist_ok=True)
    all_cases = all_cases or cases()
    truth = {}
    for name in names:
        img, plates = make_case(**all_cases[name])
        file = f"{prefix}{name}.jpg"
        img.save(out_dir / file, quality=88)
        truth[file] = {"width": img.width, "height": img.height, "plates": plates}
    return truth


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("out", nargs="?", help="directory for the whole set")
    ap.add_argument("--random", type=int, default=0, help="add this many random layouts to OUT")
    ap.add_argument("--fixtures", action="store_true", help="write the app fixtures")
    args = ap.parse_args()
    if args.fixtures:
        truth = _write(FIXTURES, FIXTURE_CASES, prefix="multi_")
        # Single plates whose truth is known from how they were made.
        truth["medium.jpg"] = {"width": 1000, "height": 1000, "plates": [{"cx": 500.0, "cy": 500.0, "radius": 420.0}]}
        (FIXTURES / "multi_plates.json").write_text(json.dumps(truth, indent=1) + "\n")
    if args.out:
        all_cases = {**cases(), **random_cases(args.random)}
        truth = _write(Path(args.out), list(all_cases), all_cases=all_cases)
        (Path(args.out) / "cases.json").write_text(json.dumps(truth, indent=1) + "\n")


if __name__ == "__main__":
    main()
