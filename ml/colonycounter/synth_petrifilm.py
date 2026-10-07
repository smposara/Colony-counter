"""Synthetic Petrifilm-style dry-film plates with known colonies, gas and halos.

A rectangular clear film on a table, a printed 1 cm grid, a round growth area
(with a foam ring on all types except Aerobic Count), coloured colonies, gas
bubbles next to some colonies plus loose background bubbles, yellow zones on
Enterobacteriaceae plates, and yeast and mold on Yeast & Mold plates.

Colours approximate Neogen's interpretation guides; they are for testing the
method, not for tuning thresholds to real plates.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import cv2
import numpy as np

# RGB colours per plate type.
GEL = {
    "ac": (232, 214, 198),   # pale pink-beige
    "ec": (196, 92, 104),    # red
    "cc": (196, 92, 104),
    "eb": (140, 84, 132),    # purple
    "ym": (214, 204, 182),   # beige
}
RED = (150, 30, 45)
BLUE = (55, 70, 150)
YELLOW = (226, 206, 92)
YEAST = (70, 128, 132)
MOLD = (60, 110, 105)
FILM = (226, 230, 230)
TABLE = (58, 60, 64)
GRID = (70, 96, 86)
FOAM = (240, 240, 236)

FILM_W_MM, FILM_H_MM = 75.0, 100.0
AREA_DIAMETER_MM = 50.5  # ~20 cm²
AREA_TOP_MM = 12.0


@dataclass
class TrueColony:
    x: float
    y: float
    radius_px: float
    kind: str  # "red", "blue", "yeast", "mold"
    gas: bool = False
    yellow: bool = False


@dataclass
class SynthFilm:
    image: np.ndarray  # BGR
    type: str
    px_per_mm: float
    centre: tuple[float, float]
    radius_px: float
    angle_deg: float
    colonies: list[TrueColony]
    loose_bubbles: list[tuple[float, float, float]] = field(default_factory=list)
    bubbles: list[tuple[float, float, float]] = field(default_factory=list)  # all, image px

    def truth(self) -> dict[str, int]:
        """Counts per result as the interpretation guide defines them."""
        c = self.colonies
        if self.type == "ac":
            return {"aerobic": len(c)}
        if self.type == "ec":
            blue = sum(k.kind == "blue" for k in c)
            red_gas = sum(k.kind == "red" and k.gas for k in c)
            return {"ecoli": blue, "coliform": blue + red_gas}
        if self.type == "cc":
            return {"coliform": sum(k.kind == "red" and k.gas for k in c)}
        if self.type == "eb":
            return {"enterobacteriaceae": sum(k.kind == "red" and (k.gas or k.yellow) for k in c)}
        if self.type == "ym":
            return {"yeast": sum(k.kind == "yeast" for k in c), "mold": sum(k.kind == "mold" for k in c)}
        raise ValueError(self.type)


def _window(xy, r_mm, px_per_mm, H, W):
    """Image slice around a point, r_mm in each direction."""
    x, y = xy
    r = r_mm * px_per_mm + 2
    return (slice(max(0, int(y - r)), min(H, int(y + r) + 1)),
            slice(max(0, int(x - r)), min(W, int(x + r) + 1)))


def _sig(t):
    return 1 / (1 + np.exp(-np.clip(t, -60, 60)))


def make_film(
    type: str = "ac",
    n: int = 60,
    seed: int = 0,
    px_per_mm: float = 12.0,
    angle_deg: float = 0.0,
    gas_fraction: float = 0.6,
    loose_bubbles: int = 6,
    yellow_fraction: float = 0.5,
    blue_fraction: float = 0.4,
    mold_fraction: float = 0.25,
    gradient: float = 0.15,
    noise: float = 2.5,
) -> SynthFilm:
    rng = np.random.default_rng(seed)
    margin = 12.0
    W = int((FILM_W_MM + 2 * margin) * px_per_mm)
    H = int((FILM_H_MM + 2 * margin) * px_per_mm)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    # Film coordinates (mm) of each pixel, with the film turned by angle_deg.
    cx_img, cy_img = W / 2, H / 2
    th = np.deg2rad(angle_deg)
    dx, dy = (xx - cx_img) / px_per_mm, (yy - cy_img) / px_per_mm
    u = np.cos(th) * dx + np.sin(th) * dy + FILM_W_MM / 2
    v = -np.sin(th) * dx + np.cos(th) * dy + FILM_H_MM / 2
    on_film = (u >= 0) & (u <= FILM_W_MM) & (v >= 0) & (v <= FILM_H_MM)

    acx, acy = FILM_W_MM / 2, AREA_TOP_MM + AREA_DIAMETER_MM / 2
    rr_mm = np.hypot(u - acx, v - acy)
    R_mm = AREA_DIAMETER_MM / 2
    gel_w = _sig((R_mm - rr_mm) * px_per_mm / 1.0)

    def to_img(um, vm):
        x = np.cos(th) * (um - FILM_W_MM / 2) - np.sin(th) * (vm - FILM_H_MM / 2)
        y = np.sin(th) * (um - FILM_W_MM / 2) + np.cos(th) * (vm - FILM_H_MM / 2)
        return cx_img + x * px_per_mm, cy_img + y * px_per_mm

    img = np.empty((H, W, 3), np.float32)
    img[:] = TABLE
    film = np.array(FILM, np.float32)
    gel = np.array(GEL[type], np.float32)
    base = film * (1 - gel_w[..., None]) + gel * gel_w[..., None]
    img[on_film] = base[on_film]
    if type != "ac":
        ring = np.exp(-((rr_mm - R_mm - 1.6) / 1.1) ** 2)
        img = img * (1 - ring[..., None] * on_film[..., None]) + np.array(FOAM, np.float32) * (
            ring[..., None] * on_film[..., None])

    colonies: list[TrueColony] = []
    pts: list[tuple[float, float, float]] = []  # (u, v, r_mm)

    def free(u0, v0, r0, gap=0.5):
        if np.hypot(u0 - acx, v0 - acy) > R_mm - r0 - 1.0:
            return False
        return all(np.hypot(u0 - a, v0 - b) > r0 + rb + gap for a, b, rb in pts)

    def place(r0):
        for _ in range(2000):
            ang, rad = rng.uniform(0, 2 * np.pi), (R_mm - 1.5) * np.sqrt(rng.random())
            u0, v0 = acx + rad * np.cos(ang), acy + rad * np.sin(ang)
            if free(u0, v0, r0):
                pts.append((u0, v0, r0))
                return u0, v0
        return None

    halos = np.zeros((H, W), np.float32)
    paint = []  # (u, v, r_mm, colour, edge_mm, dark_centre)
    bubbles: list[tuple[float, float, float]] = []
    for _ in range(n):
        if type == "ym":
            kind = "mold" if rng.random() < mold_fraction else "yeast"
        elif type == "ec":
            kind = "blue" if rng.random() < blue_fraction else "red"
        else:
            kind = "red"
        r0 = rng.uniform(1.4, 3.0) if kind == "mold" else rng.uniform(0.3, 0.75)
        at = place(r0 + (1.6 if kind == "red" and type in ("ec", "cc", "eb") else 0))
        if at is None:
            continue
        u0, v0 = at
        gas = yellow = False
        if kind == "red" and type in ("ec", "cc", "eb") and rng.random() < gas_fraction:
            gas = True
            br = rng.uniform(0.3, 0.7)
            a = rng.uniform(0, 2 * np.pi)
            d = r0 + br + rng.uniform(0.0, 0.8) * r0
            bubbles.append((u0 + d * np.cos(a), v0 + d * np.sin(a), br))
        if kind == "blue" and rng.random() < 0.3:
            gas = True  # E. coli counts with or without gas
            br = rng.uniform(0.3, 0.6)
            a = rng.uniform(0, 2 * np.pi)
            bubbles.append((u0 + (r0 + br + 0.2) * np.cos(a), v0 + (r0 + br + 0.2) * np.sin(a), br))
        if type == "eb" and rng.random() < yellow_fraction:
            yellow = True
            sl = _window(to_img(u0, v0), r0 * 3.0 + 2.0, px_per_mm, H, W)
            halos[sl] = np.maximum(halos[sl], _sig((r0 * 3.0 - np.hypot(u[sl] - u0, v[sl] - v0)) * px_per_mm / 4.0))
        colour = {"red": RED, "blue": BLUE, "yeast": YEAST, "mold": MOLD}[kind]
        edge = 0.6 if kind == "mold" else 0.06
        paint.append((u0, v0, r0, colour, edge, kind == "mold"))
        x, y = to_img(u0, v0)
        colonies.append(TrueColony(float(x), float(y), r0 * px_per_mm, kind, gas, yellow))

    loose = []
    for _ in range(loose_bubbles if type in ("ec", "cc", "eb") else 0):
        br = rng.uniform(0.3, 0.8)
        at = place(br + 2.5)
        if at:
            bubbles.append((at[0], at[1], br))
            x, y = to_img(*at)
            loose.append((float(x), float(y), br * px_per_mm))

    if type == "eb":
        img = img * (1 - 0.75 * halos[..., None]) + np.array(YELLOW, np.float32) * (0.75 * halos[..., None])
    for u0, v0, r0, colour, edge, dark in paint:
        sl = _window(to_img(u0, v0), r0 + 6 * edge + 0.5, px_per_mm, H, W)
        d = np.hypot(u[sl] - u0, v[sl] - v0)
        w = _sig((r0 - d) / edge)
        if dark:
            centre = np.clip(1 - d / r0, 0, 1)
            col = np.array(colour, np.float32)[None, None, :] * (1 - 0.45 * centre[..., None])
        else:
            col = np.array(colour, np.float32)
        img[sl] = img[sl] * (1 - 0.92 * w[..., None]) + col * (0.92 * w[..., None])
    for u0, v0, br in bubbles:
        sl = _window(to_img(u0, v0), br + 0.6, px_per_mm, H, W)
        d = np.hypot(u[sl] - u0, v[sl] - v0)
        rim = np.exp(-((d - br) / 0.07) ** 2)
        outer = np.exp(-((d - br - 0.12) / 0.06) ** 2)
        img[sl] += 70 * rim[..., None] - 25 * outer[..., None]

    # Printed grid (over the whole film, like the real plates).
    gu = np.abs(((u + 0.0) % 10.0) - 5.0)
    gv = np.abs(((v + 0.0) % 10.0) - 5.0)
    line = np.maximum(np.exp(-((5.0 - gu) / 0.09) ** 2), np.exp(-((5.0 - gv) / 0.09) ** 2))
    line *= on_film
    img = img * (1 - 0.55 * line[..., None]) + np.array(GRID, np.float32) * (0.55 * line[..., None])

    light = 1 + gradient * (xx - W / 2) / W
    img *= light[..., None]
    img += rng.normal(0, noise, img.shape)
    bgr = np.clip(img[..., ::-1], 0, 255).astype(np.uint8)
    centre = to_img(acx, acy)
    allb = [(*map(float, to_img(bu, bv)), br * px_per_mm) for bu, bv, br in bubbles]
    return SynthFilm(bgr, type, px_per_mm, (float(centre[0]), float(centre[1])),
                     R_mm * px_per_mm, angle_deg, colonies, loose, allb)
