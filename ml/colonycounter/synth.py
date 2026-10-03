"""Synthetic plate photos with known colony positions, for tests and demos.

Imitates a nutrient-agar plate photographed in the dark-field lightbox: black
surround, dim translucent agar with a lighting gradient, a bright dish rim, and
cream-white colonies. Not a substitute for real photos when measuring accuracy.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .plate import Plate


@dataclass
class SynthPlate:
    image: np.ndarray  # BGR uint8
    points: np.ndarray  # (N, 2) true colony centres, x/y in pixels
    plate: Plate


def make_plate(
    n_colonies: int = 100,
    size: int = 1600,
    seed: int = 0,
    radius_mm: tuple[float, float] = (0.4, 1.4),
    touching_fraction: float = 0.15,
    gradient: float = 0.35,
    noise: float = 3.0,
    polarity: str = "bright",
) -> SynthPlate:
    rng = np.random.default_rng(seed)
    cx = cy = size / 2
    R = size * 0.42
    plate = Plate(cx, cy, R)
    px_per_mm = 1 / plate.mm_per_px

    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    rr = np.hypot(xx - cx, yy - cy)

    # Agar: dim amber, lit unevenly from one side.
    light = 1 + gradient * ((xx - cx) / R) * 0.5 + gradient * 0.5 * ((yy - cy) / R) ** 2
    agar = np.full((size, size), 55.0, np.float32) * light
    img = np.where(rr <= R, agar, 8.0)
    # Bright dish wall ring just outside/at the agar edge.
    img += 120 * np.exp(-((rr - R * 1.01) / (R * 0.008)) ** 2)

    centres, radii = _place(rng, n_colonies, (cx, cy), R * 0.9, radius_mm, px_per_mm, touching_fraction)
    for (x, y), r in zip(centres, radii):
        x0, x1 = int(max(0, x - 2 * r)), int(min(size, x + 2 * r + 1))
        y0, y1 = int(max(0, y - 2 * r)), int(min(size, y + 2 * r + 1))
        d = np.hypot(xx[y0:y1, x0:x1] - x, yy[y0:y1, x0:x1] - y)
        edge = 1 / (1 + np.exp((d - r) / max(0.6, r * 0.12)))
        dome = np.clip(1 - (d / r) ** 2, 0, 1) ** 0.5
        amp = rng.uniform(60, 110)
        sign = 1 if polarity == "bright" else -0.6
        img[y0:y1, x0:x1] += sign * amp * edge * (0.75 + 0.25 * dome)

    img += rng.normal(0, noise, img.shape)
    gray = np.clip(img, 0, 255).astype(np.uint8)
    tint = np.array([0.80, 0.95, 1.10], np.float32)  # amber-ish in BGR
    bgr = np.clip(gray[..., None] * tint, 0, 255).astype(np.uint8)
    return SynthPlate(bgr, np.asarray(centres, float).reshape(-1, 2), plate)


def _place(rng, n, centre, max_r, radius_mm, px_per_mm, touching_fraction):
    centres: list[tuple[float, float]] = []
    radii: list[float] = []
    cx, cy = centre
    attempts = 0
    while len(centres) < n and attempts < n * 500:
        attempts += 1
        r = rng.uniform(*radius_mm) * px_per_mm
        if centres and rng.random() < touching_fraction:
            # Touch an existing colony: overlap slightly but keep two visible domes.
            i = rng.integers(len(centres))
            ang = rng.uniform(0, 2 * np.pi)
            dist = (radii[i] + r) * rng.uniform(0.85, 0.95)
            x, y = centres[i][0] + dist * np.cos(ang), centres[i][1] + dist * np.sin(ang)
            ok_with = {i}
        else:
            ang = rng.uniform(0, 2 * np.pi)
            rad = max_r * np.sqrt(rng.random())
            x, y = cx + rad * np.cos(ang), cy + rad * np.sin(ang)
            ok_with = set()
        if np.hypot(x - cx, y - cy) + r > max_r:
            continue
        if all(j in ok_with or np.hypot(x - px, y - py) > (radii[j] + r) * 1.15
               for j, (px, py) in enumerate(centres)):
            centres.append((x, y))
            radii.append(r)
    return centres, radii
