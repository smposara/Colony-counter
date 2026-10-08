"""Synthetic drop plates (Miles–Misra / spot plates) with known drops and counts.

A round dish photographed in the dark-field lightbox (as in synth.py), with drops of a
tenfold dilution series laid out as sectors (a ring) or as a grid (a row per dilution).
Colonies per drop are Poisson around the true density (optionally overdispersed); drops
above ``confluent_at`` expected colonies are drawn as a confluent lawn; crowded drops get
merged colonies; a few stray colonies grow between drops. Each drop also leaves a faint
dried-drop disc, as real drops do.

For testing the method, not for measuring accuracy on real photos.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from .drops import Layout, drop_diameter_mm, layout_positions_mm
from .synth import make_plate


@dataclass
class TrueDrop:
    x: float  # centre, image px
    y: float
    radius_px: float
    position: int  # index in the layout
    dilution_exp: int  # 5 means 10^-5
    replicate: int
    count: int  # colonies grown (0 for an empty drop); for a confluent drop, the expected number
    confluent: bool = False
    points: list[tuple[float, float]] = field(default_factory=list)


@dataclass
class SynthDropPlate:
    image: np.ndarray  # BGR uint8
    px_per_mm: float
    layout: Layout
    volume_ul: float
    dilutions: list[int]
    cfu_per_ml: float
    drops: list[TrueDrop]
    strays: list[tuple[float, float]]
    rotation_deg: float
    plate_centre: tuple[float, float]


def make_drop_plate(
    layout: Layout,
    dilutions: list[int],
    cfu_per_ml: float = 2e7,
    volume_ul: float = 10.0,
    seed: int = 0,
    rotation_deg: float | None = None,
    overdispersion: float = 0.0,
    confluent_at: float = 150.0,
    strays: int = 2,
    size: int = 1200,
    colony_radius_mm: tuple[float, float] = (0.28, 0.42),
    noise: float = 3.0,
) -> SynthDropPlate:
    """``layout`` positions in mm (relative to the plate centre) are turned by
    ``rotation_deg`` (random when None). ``overdispersion`` is the gamma-Poisson
    coefficient of variation of the per-drop density (0 = pure Poisson)."""
    rng = np.random.default_rng(seed)
    base = make_plate(0, size=size, seed=seed, noise=noise)
    img = base.image.astype(np.float32)
    px_per_mm = 1 / base.plate.mm_per_px
    cx0, cy0 = base.plate.cx, base.plate.cy
    rot = float(rng.uniform(0, 360)) if rotation_deg is None else rotation_deg
    th = np.deg2rad(rot)
    ca, sa = np.cos(th), np.sin(th)
    drop_r = drop_diameter_mm(volume_ul) / 2 * px_per_mm
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)

    def blend(x0, y0, x1, y1, layer, colour):
        sub = img[y0:y1, x0:x1]
        a = layer[..., None]
        img[y0:y1, x0:x1] = sub * (1 - a) + np.asarray(colour, np.float32) * a

    def box(x, y, r):
        return (max(0, int(x - r - 3)), max(0, int(y - r - 3)),
                min(size, int(x + r + 4)), min(size, int(y + r + 4)))

    drops: list[TrueDrop] = []
    all_points: list[tuple[float, float, float]] = []
    for pos, (px_mm, py_mm, dil, rep) in enumerate(layout_positions_mm(layout, dilutions)):
        x = cx0 + (ca * px_mm - sa * py_mm) * px_per_mm
        y = cy0 + (sa * px_mm + ca * py_mm) * px_per_mm
        # Faint dried-drop disc.
        x0, y0, x1, y1 = box(x, y, drop_r)
        d = np.hypot(xx[y0:y1, x0:x1] - x, yy[y0:y1, x0:x1] - y)
        img[y0:y1, x0:x1] += (4.0 / (1 + np.exp((d - drop_r) / 1.5)))[..., None]

        mean = cfu_per_ml * volume_ul / 1000 * 10.0 ** -dil
        if overdispersion > 0:
            k = 1 / overdispersion**2
            mean = rng.gamma(k, mean / k)
        if mean > confluent_at:
            # Confluent lawn: a textured bright disc, no separate colonies.
            tex = rng.normal(0, 6, d.shape)
            lawn = 1 / (1 + np.exp((d - drop_r * 0.95) / 2.0))
            blend(x0, y0, x1, y1, lawn * 0.85, (165, 195, 205))
            img[y0:y1, x0:x1] += (tex * lawn)[..., None]
            drops.append(TrueDrop(x, y, drop_r, pos, dil, rep, int(round(mean)), True))
            continue
        n = int(rng.poisson(mean))
        pts = _place(rng, n, x, y, drop_r * 0.85, colony_radius_mm, px_per_mm, all_points)
        for qx, qy, qr in pts:
            _draw_colony(img, xx, yy, qx, qy, qr, rng, size)
        drops.append(TrueDrop(x, y, drop_r, pos, dil, rep, n, False, [(p[0], p[1]) for p in pts]))
        all_points += pts

    stray_pts: list[tuple[float, float]] = []
    R = base.plate.radius * 0.85
    for _ in range(strays):
        for _attempt in range(200):
            ang, rad = rng.uniform(0, 2 * np.pi), R * np.sqrt(rng.random())
            sx, sy = cx0 + rad * np.cos(ang), cy0 + rad * np.sin(ang)
            if all(np.hypot(sx - t.x, sy - t.y) > t.radius_px * 1.8 for t in drops):
                r = rng.uniform(*colony_radius_mm) * px_per_mm
                _draw_colony(img, xx, yy, sx, sy, r, rng, size)
                stray_pts.append((sx, sy))
                break

    img += rng.normal(0, 1.5, img.shape)
    return SynthDropPlate(np.clip(img, 0, 255).astype(np.uint8), px_per_mm, layout, volume_ul,
                          list(dilutions), cfu_per_ml, drops, stray_pts, rot, (cx0, cy0))


def _place(rng, n, x, y, max_r, radius_mm, px_per_mm, existing):
    """``n`` colonies inside a drop; when the drop is too full to keep them apart,
    later ones touch or overlap (merged colonies, as in real crowded drops)."""
    pts: list[tuple[float, float, float]] = []
    for i in range(n):
        r = rng.uniform(*radius_mm) * px_per_mm
        for attempt in range(300):
            ang, rad = rng.uniform(0, 2 * np.pi), (max_r - r) * np.sqrt(rng.random())
            qx, qy = x + rad * np.cos(ang), y + rad * np.sin(ang)
            gap = 1.15 if attempt < 250 else 0.75  # crowded: allow touching
            if all(np.hypot(qx - a, qy - b) > (r + c) * gap for a, b, c in pts):
                break
        pts.append((qx, qy, r))
    return pts


def _draw_colony(img, xx, yy, x, y, r, rng, size):
    x0, x1 = int(max(0, x - 2 * r)), int(min(size, x + 2 * r + 1))
    y0, y1 = int(max(0, y - 2 * r)), int(min(size, y + 2 * r + 1))
    d = np.hypot(xx[y0:y1, x0:x1] - x, yy[y0:y1, x0:x1] - y)
    edge = 1 / (1 + np.exp((d - r) / max(0.6, r * 0.12)))
    dome = np.clip(1 - (d / r) ** 2, 0, 1) ** 0.5
    amp = rng.uniform(70, 110)
    img[y0:y1, x0:x1] += (amp * edge * (0.75 + 0.25 * dome))[..., None] * np.array([0.8, 0.95, 1.1])
