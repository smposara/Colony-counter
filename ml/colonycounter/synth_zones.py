"""Synthetic disk / agar-well diffusion plates with known zone diameters.

Lighting follows the EUCAST reading set-up: plate over a dark background with
reflected light ("reflected": cream lawn, dark clear zones, white paper disks), or
lit from behind ("backlit": dark turbid lawn, bright clear zones, dark disks).

The lawn's growth around each disk is a sigmoid of distance whose 50 % point is
the true zone edge, so a detector reading the edge at half contrast should agree.
Not a substitute for real photos when measuring accuracy.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import cv2
import numpy as np

from .plate import Plate

LEVELS = {
    #            surround, clear agar, lawn, disk, well floor, rim
    "reflected": (10.0, 40.0, 150.0, 235.0, 25.0, 160.0),
    "backlit": (30.0, 205.0, 110.0, 70.0, 220.0, 240.0),
}


def _sigmoid(t):
    return 1 / (1 + np.exp(-np.clip(t, -60, 60)))


@dataclass
class TrueZone:
    x: float
    y: float
    disk_radius_px: float
    diameter_mm: float  # zone diameter; equals the disk/well diameter when there is no zone


@dataclass
class SynthZonePlate:
    image: np.ndarray  # BGR uint8
    plate: Plate
    zones: list[TrueZone]
    assay: str
    disk_mm: float
    meta: dict = field(default_factory=dict)


def disk_positions(n: int, plate: Plate, rng, ring_fraction: float = 0.58, jitter_mm: float = 1.0):
    """EUCAST-style layout: up to 6 disks evenly on a ring, more on two rings."""
    px_per_mm = 1 / plate.mm_per_px
    R_mm = plate.diameter_mm / 2
    if n == 1:
        rings = [(0.0, 1)]
    elif n <= 6:
        rings = [(ring_fraction, n)]
    else:
        outer = (n + 2) // 2 + 1
        rings = [(0.66, outer), (0.28, n - outer)]
    pts = []
    for frac, k in rings:
        rot = rng.uniform(0, 2 * np.pi)
        for i in range(k):
            a = rot + 2 * np.pi * i / k
            rad = frac * R_mm
            x = plate.cx + (rad * np.cos(a) + rng.normal(0, jitter_mm)) * px_per_mm
            y = plate.cy + (rad * np.sin(a) + rng.normal(0, jitter_mm)) * px_per_mm
            pts.append((x, y))
    return pts


def make_zone_plate(
    n_disks: int = 6,
    zone_mm=(6.0, 32.0),
    size: int = 1600,
    seed: int = 0,
    plate_mm: float = 90.0,
    assay: str = "disk",
    disk_mm: float = 6.0,
    edge_mm=(0.1, 0.3),
    lighting: str = "reflected",
    gradient: float = 0.25,
    grain: float = 8.0,
    noise: float = 3.0,
    colonies_in_zones: int = 0,
    printed_codes: bool = True,
    positions=None,
) -> SynthZonePlate:
    """``zone_mm``: a (lo, hi) range drawn per disk, or a list with one diameter per disk.
    ``edge_mm``: (lo, hi) range of the edge's sigmoid width in mm; larger is hazier.
    ``assay``: "disk" (paper disks) or "well" (holes cut in the agar, ``disk_mm`` wide).
    """
    rng = np.random.default_rng(seed)
    surround, clear, lawn, disk_lvl, well_lvl, rim_lvl = LEVELS[lighting]
    cx = cy = size / 2
    R = size * 0.42
    plate = Plate(cx, cy, R, plate_mm)
    px_mm = 1 / plate.mm_per_px

    pts = positions if positions is not None else disk_positions(n_disks, plate, rng)
    n = len(pts)
    if isinstance(zone_mm, tuple):
        diam = [float(rng.uniform(*zone_mm)) for _ in range(n)]
    else:
        diam = [float(d) for d in zone_mm]
    diam = [max(d, disk_mm) for d in diam]
    widths = [float(rng.uniform(*edge_mm)) for _ in range(n)]

    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    rr = np.hypot(xx - cx, yy - cy)

    growth = np.ones((size, size), np.float32)
    for (x, y), d, w in zip(pts, diam, widths):
        dist = np.hypot(xx - x, yy - y)
        rz = d / 2 * px_mm
        if d <= disk_mm:
            continue  # no zone: lawn grows right up to the disk
        growth *= _sigmoid((dist - rz) / (w * px_mm))

    # Colonies growing inside zones (resistant subpopulation): lawn-like dots.
    for _ in range(colonies_in_zones):
        cand = [i for i, d in enumerate(diam) if d - disk_mm > 6]
        if not cand:
            break
        i = int(rng.choice(cand))
        (x, y), d = pts[i], diam[i]
        a = rng.uniform(0, 2 * np.pi)
        rad = rng.uniform(disk_mm / 2 + 1.0, d / 2 - 1.5) * px_mm
        r = rng.uniform(0.3, 0.6) * px_mm
        dist = np.hypot(xx - (x + rad * np.cos(a)), yy - (y + rad * np.sin(a)))
        growth = np.maximum(growth, _sigmoid((r - dist) / 0.8))

    light = 1 + gradient * ((xx - cx) / R) * 0.5 + gradient * 0.5 * ((yy - cy) / R) ** 2
    texture = cv2.GaussianBlur(rng.normal(0, 1, (size, size)).astype(np.float32), (0, 0), 1.5)
    texture *= grain / max(float(texture.std()), 1e-6)
    agar = (clear + (lawn - clear) * growth + texture * growth) * light
    img = np.where(rr <= R, agar, surround)
    img += (rim_lvl - clear) * np.exp(-((rr - R * 1.01) / (R * 0.008)) ** 2)

    rd = disk_mm / 2 * px_mm
    for x, y in pts:
        dist = np.hypot(xx - x, yy - y)
        inside = _sigmoid((rd - dist) / 0.7)
        if assay == "disk":
            img = img * (1 - inside) + disk_lvl * inside
            if printed_codes:
                code = np.zeros_like(img)
                tw, th = 2.4 * px_mm, 0.9 * px_mm
                code[(np.abs(xx - x) < tw / 2) & (np.abs(yy - y) < th / 2)] = 1
                code = cv2.GaussianBlur(code, (0, 0), 1.2)
                img -= 0.35 * (disk_lvl - surround) * code * (1 if lighting == "reflected" else -0.3)
        elif assay == "well":
            img = img * (1 - inside) + well_lvl * light * inside
            img += (rim_lvl - clear) * 0.5 * np.exp(-((dist - rd) / 1.2) ** 2)
        else:
            raise ValueError(f"Unknown assay: {assay!r}")

    img += rng.normal(0, noise, img.shape)
    gray = np.clip(img, 0, 255).astype(np.uint8)
    tint = np.array([0.85, 0.97, 1.05], np.float32)
    bgr = np.clip(gray[..., None] * tint, 0, 255).astype(np.uint8)
    zones = [TrueZone(float(x), float(y), rd, d) for (x, y), d in zip(pts, diam)]
    return SynthZonePlate(bgr, plate, zones, assay, disk_mm,
                          {"edge_mm": widths, "lighting": lighting})
