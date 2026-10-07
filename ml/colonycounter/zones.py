"""Inhibition zone measurement for disk diffusion and agar well diffusion plates.

    photo → find_plate (mm/px scale) → find disks or wells (ring of strong edges
    at the known disk size) → for each disk: brightness along 180 rays from the
    disk edge → edge on each ray at ``edge_level`` between the zone and lawn
    levels, held for ``persist_mm`` → robust circle fit → diameter, confidence,
    flags

Measurement only: no S/I/R interpretation.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field

import cv2
import numpy as np

from .normalize import to_gray
from .plate import Plate, find_plate

WORK_SHORT_SIDE = 1800
N_RAYS = 180
MIN_AGREEING = 0.15  # below this fraction of rays agreeing, leave the zone to the user


@dataclass
class ZoneParams:
    edge_level: float = 0.5  # fraction of zone→lawn contrast where the edge is read
    persist_mm: float = 1.5  # growth must hold this long to count as the edge
    start_gap_mm: float = 0.4  # rays start this far outside the disk edge
    min_contrast: float = 10.0  # grey levels between zone and lawn for a zone to count
    max_zone_mm: float = 50.0
    hazy_width_mm: float = 1.0  # 20→80 % edge width above this is "hazy"
    scale_tolerance: float = 0.05


@dataclass
class Disk:
    x: float
    y: float
    radius_px: float
    score: float = 0.0
    measured: bool = True  # radius fitted to the edge, not assumed from the plate scale


@dataclass
class Zone:
    x: float
    y: float
    disk_radius_px: float
    radius_px: float
    diameter_mm: float
    confidence: float
    edge_width_mm: float
    flags: list[str] = field(default_factory=list)

    @property
    def diameter_rounded(self) -> int | None:
        """Whole mm as shown on screen (EUCAST reads to the nearest mm); None if unmeasured."""
        if not np.isfinite(self.diameter_mm):
            return None
        return int(np.floor(self.diameter_mm + 0.5))


@dataclass
class ZoneResult:
    plate: Plate
    assay: str
    zones: list[Zone]
    polarity: str  # "dark_zone" (reflected light) or "bright_zone" (back-lit)
    disk_scale_ratio: float  # measured disk diameter / nominal; 1.0 is perfect
    flags: list[str]

    def to_dict(self) -> dict:
        return {
            "assay": self.assay,
            "polarity": self.polarity,
            "disk_scale_ratio": round(self.disk_scale_ratio, 4),
            "flags": self.flags,
            "plate": {"cx": self.plate.cx, "cy": self.plate.cy, "radius": self.plate.radius,
                      "diameter_mm": self.plate.diameter_mm},
            "zones": [{**asdict(z), "diameter_rounded": z.diameter_rounded} for z in self.zones],
        }


def measure_plate(
    image: np.ndarray,
    plate_diameter_mm: float = 90.0,
    assay: str = "disk",
    disk_mm: float = 6.0,
    plate: Plate | None = None,
    disks: list[Disk] | None = None,
    params: ZoneParams = ZoneParams(),
) -> ZoneResult:
    """Measure every zone on a plate photo. ``disk_mm`` is the well diameter for wells.

    ``plate`` and ``disks`` (in image pixels) skip detection, e.g. after manual fixes.
    """
    if assay not in ("disk", "well"):
        raise ValueError(f"Unknown assay: {assay!r}")
    gray_full = to_gray(image)
    if plate is None:
        plate = find_plate(image, diameter_mm=plate_diameter_mm)
    h, w = gray_full.shape
    s = min(1.0, WORK_SHORT_SIDE / min(h, w))
    gray = cv2.resize(gray_full, (round(w * s), round(h * s)), interpolation=cv2.INTER_AREA) \
        if s < 1 else gray_full
    wplate = Plate(plate.cx * s, plate.cy * s, plate.radius * s, plate.diameter_mm)

    if disks is None:
        wdisks = find_disks(gray, wplate, disk_mm)
    else:
        wdisks = [Disk(d.x * s, d.y * s, d.radius_px * s, d.score, d.measured) for d in disks]

    flags: list[str] = []
    ratio = 1.0
    scale_plate = wplate
    measured = [d.radius_px for d in wdisks if d.measured]
    if measured:
        disk_px = 2 * float(np.median(measured))
        ratio = disk_px * wplate.mm_per_px / disk_mm
        if abs(ratio - 1) > params.scale_tolerance:
            flags.append("scale_mismatch")
        elif assay == "disk":
            # Paper disks are made to 6.0 mm, a better ruler than the dish edge
            # (the plate finder tends to lock onto the dish wall, outside the agar).
            scale_plate = Plate(wplate.cx, wplate.cy, wplate.radius,
                                disk_mm / disk_px * 2 * wplate.radius)
    elif wdisks:
        flags.append("scale_unchecked")
    else:
        flags.append("no_disks")

    zones, polarity = measure_zones(gray, scale_plate, wdisks, disk_mm, params)
    for z in zones:
        z.x /= s
        z.y /= s
        z.disk_radius_px /= s
        z.radius_px /= s
    return ZoneResult(plate, assay, zones, polarity, ratio, flags)


def find_disks(gray: np.ndarray, plate: Plate, disk_mm: float = 6.0,
               min_relative_score: float = 0.2) -> list[Disk]:
    """Disks and wells: circles of the known size, darker or lighter all round.

    Two signed ring averages, so lawn grain (random direction) cancels out while a
    real edge adds up all the way round:
    - the brightness step across the ring, measured along the radius (a paper
      disk or the floor of a well against the agar);
    - a thin line on the ring (the cut edge of a well).
    Straight or large curved edges (zones, the dish rim) touch the ring in only
    a few places and score low.
    """
    r0 = disk_mm / 2 / plate.mm_per_px
    g = cv2.GaussianBlur(gray, (0, 0), 1.0)
    gx = cv2.Sobel(g, cv2.CV_32F, 1, 0, ksize=3) / 8
    gy = cv2.Sobel(g, cv2.CV_32F, 0, 1, ksize=3) / 8

    k = int(np.ceil(r0 + 6))
    yy, xx = np.mgrid[-k:k + 1, -k:k + 1].astype(np.float32)
    d = np.hypot(xx, yy)
    theta = np.arctan2(yy, xx)

    def ring(r):
        m = (np.abs(d - r) <= 1.0).astype(np.float32)
        return m / m.sum()

    rk = ring(r0)
    step = (cv2.filter2D(gx, cv2.CV_32F, rk * np.cos(theta), borderType=cv2.BORDER_REPLICATE)
            + cv2.filter2D(gy, cv2.CV_32F, rk * np.sin(theta), borderType=cv2.BORDER_REPLICATE))
    ridge = cv2.filter2D(g, cv2.CV_32F, rk - 0.5 * ring(r0 - 3) - 0.5 * ring(r0 + 3),
                         borderType=cv2.BORDER_REPLICATE)
    score = 3 * np.abs(step) + np.abs(ridge)

    hh, ww = gray.shape
    py, px = np.mgrid[0:hh, 0:ww]
    allowed = np.hypot(px - plate.cx, py - plate.cy) < plate.radius * 0.97 - r0 * 1.5
    score[~allowed] = 0
    best = float(score.max())
    if best <= 0:
        return []
    sep = int(r0 * 3) | 1
    peaks = (score == cv2.dilate(score, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (sep, sep))))
    vals = score[allowed]
    floor = float(np.median(vals) + 15 * np.median(np.abs(vals - np.median(vals))) + 1e-6)
    ys, xs = np.nonzero(peaks & (score >= max(min_relative_score * best, floor)))
    order = np.argsort(-score[ys, xs])
    disks: list[Disk] = []
    for i in order:
        x, y = float(xs[i]), float(ys[i])
        if any(np.hypot(x - o.x, y - o.y) < r0 * 3 for o in disks):
            continue
        x, y = _subpixel(score, int(xs[i]), int(ys[i]))
        x, y, r, ok = _refine_disk(g, x, y, r0)
        disks.append(Disk(x, y, r, float(score[ys[i], xs[i]]), ok))
    return disks


def _subpixel(score: np.ndarray, x: int, y: int) -> tuple[float, float]:
    def off(a, b, c):
        den = a - 2 * b + c
        return 0.0 if den >= 0 else float(np.clip(0.5 * (a - c) / den, -0.5, 0.5))
    h, w = score.shape
    dx = off(score[y, x - 1], score[y, x], score[y, x + 1]) if 0 < x < w - 1 else 0.0
    dy = off(score[y - 1, x], score[y, x], score[y + 1, x]) if 0 < y < h - 1 else 0.0
    return x + dx, y + dy


def _refine_disk(g: np.ndarray, x: float, y: float, r0: float) -> tuple[float, float, float, bool]:
    """Centre and radius of the disk edge near (x, y): the steepest brightness
    change on 72 short rays, fitted with a circle (twice, from the new centre)."""
    a = np.linspace(0, 2 * np.pi, 72, endpoint=False)
    t = np.arange(r0 * 0.7, r0 * 1.4, 0.25, dtype=np.float32)
    cx, cy, r, ok = x, y, r0, False
    for _ in range(2):
        mx = (cx + np.cos(a)[:, None] * t[None, :]).astype(np.float32)
        my = (cy + np.sin(a)[:, None] * t[None, :]).astype(np.float32)
        prof = cv2.remap(g, mx, my, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
        k = np.argmax(np.abs(np.diff(prof, axis=1)), axis=1)
        rho = t[k] + 0.125
        ex, ey = cx + np.cos(a) * rho, cy + np.sin(a) * rho
        keep = np.ones(len(a), bool)
        for _ in range(3):
            fx, fy, fr = _fit_circle(ex[keep], ey[keep])
            res = np.abs(np.hypot(ex - fx, ey - fy) - fr)
            keep = res < max(2.0, 2.5 * float(np.median(res[keep])))
            if keep.sum() < 24:
                break
        if keep.sum() < 24:
            break
        fx, fy, fr = _fit_circle(ex[keep], ey[keep])
        if not (np.isfinite(fr) and 0.7 * r0 <= fr <= 1.4 * r0 and np.hypot(fx - x, fy - y) < 0.3 * r0):
            break
        cx, cy, r, ok = fx, fy, fr, True
    return float(cx), float(cy), float(r), ok


def measure_zones(gray: np.ndarray, plate: Plate, disks: list[Disk], disk_mm: float,
                  params: ZoneParams = ZoneParams()) -> tuple[list[Zone], str]:
    if not disks:
        return [], "unknown"
    mm = plate.mm_per_px
    sm = cv2.GaussianBlur(gray, (0, 0), max(1.0, 0.1 / mm))
    angles = np.linspace(0, 2 * np.pi, N_RAYS, endpoint=False)
    step = 0.5
    rays = [_cast(sm, plate, d, disks, angles, step, params) for d in disks]

    # Lawn level: far ends of rays that reached open lawn (not stopped early).
    far = np.concatenate([r["far"] for r in rays if r["far"].size] or [np.zeros(0)])
    near = np.array([r["near_level"] for r in rays])
    if far.size == 0:
        far = near
    lawn = float(np.median(far))
    diffs = lawn - near
    sign = 1.0 if np.median(diffs[np.abs(diffs) >= params.min_contrast]
                            if np.any(np.abs(diffs) >= params.min_contrast) else diffs) >= 0 else -1.0
    polarity = "dark_zone" if sign > 0 else "bright_zone"

    # Clear-agar level as a fraction of the local lawn, from the clearest zone on
    # the plate. Small or hazy zones never reach full clearing next to the disk,
    # so their own near level would put the half-way edge too far out. A ratio
    # still holds under uneven lighting, which scales both levels.
    # Local lawn: only ray ends that really are lawn (on crowded plates many
    # rays end inside a neighbour's zone).
    clearest = float(np.min(near) if sign > 0 else np.max(near))
    mid = 0.5 * (lawn + clearest)
    local_lawn = []
    for r in rays:
        f = r["far"][sign * (r["far"] - mid) > 0]
        local_lawn.append(float(np.median(f)) if f.size >= 20 else lawn)
    ratios = [r["near_level"] / max(l, 1e-6) for r, l in zip(rays, local_lawn)]
    clear_ratio = min(ratios) if sign > 0 else max(ratios)

    zones = []
    for d, r, l in zip(disks, rays, local_lawn):
        clear = clear_ratio * l
        if sign > 0:
            lo = min(r["near_level"], max(clear, clearest - 0.1 * abs(lawn - clearest)))
        else:
            lo = max(r["near_level"], min(clear, clearest + 0.1 * abs(lawn - clearest)))
        zones.append(_measure_one(d, r, lawn, lo, sign, disk_mm, mm, step, params))

    # Zones whose circles cross each other: the reading on the shared side is lost.
    for i, a in enumerate(zones):
        for b in zones[i + 1:]:
            if not (np.isfinite(a.radius_px) and np.isfinite(b.radius_px)):
                continue
            if "no_zone" in a.flags or "no_zone" in b.flags:
                continue
            if np.hypot(a.x - b.x, a.y - b.y) < a.radius_px + b.radius_px - 0.5 / mm:
                for z in (a, b):
                    if "overlap" not in z.flags:
                        z.flags.append("overlap")
    return zones, polarity


def _cast(sm, plate, disk, disks, angles, step, params):
    mm = plate.mm_per_px
    start = disk.radius_px + params.start_gap_mm / mm
    max_len = params.max_zone_mm / 2 / mm
    ux, uy = np.cos(angles), np.sin(angles)

    # Ray ends: plate rim, or the nearest other disk in the way.
    ox, oy = disk.x - plate.cx, disk.y - plate.cy
    b = ox * ux + oy * uy
    c = ox * ox + oy * oy - (plate.radius * 0.97) ** 2
    rim_t = -b + np.sqrt(np.maximum(b * b - c, 0))
    end = np.minimum(rim_t - 0.3 / mm, max_len)
    reason = np.where(rim_t - 0.3 / mm < max_len, "rim", "max").astype(object)
    for o in disks:
        if o is disk:
            continue
        vx, vy = o.x - disk.x, o.y - disk.y
        t = vx * ux + vy * uy
        perp2 = vx * vx + vy * vy - t * t
        rr = (o.radius_px + params.start_gap_mm / mm) ** 2
        hit = (t > 0) & (perp2 < rr)
        t_in = t - np.sqrt(np.maximum(rr - perp2, 0))
        closer = hit & (t_in < end)
        end = np.where(closer, t_in, end)
        reason = np.where(closer, "neighbour", reason)

    n = int(np.ceil((max_len - start) / step)) + 1
    t = start + step * np.arange(n, dtype=np.float32)
    mx = (disk.x + ux[:, None] * t[None, :]).astype(np.float32)
    my = (disk.y + uy[:, None] * t[None, :]).astype(np.float32)
    prof = cv2.remap(sm, mx, my, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
    valid = t[None, :] <= end[:, None]
    prof = np.where(valid, prof, np.nan)

    n_near = max(2, int(0.5 / mm / step))
    near_level = float(np.nanmedian(prof[:, :n_near]))
    n_far = max(2, int(1.0 / mm / step))
    lengths = valid.sum(axis=1)
    far_vals = []
    for i in range(len(angles)):
        L = lengths[i]
        if reason[i] != "neighbour" and L > n_far + n_near:
            far_vals.append(prof[i, L - n_far:L])
    far = np.concatenate(far_vals) if far_vals else np.zeros(0)
    return {"prof": prof, "t": t, "lengths": lengths, "reason": reason, "ux": ux, "uy": uy,
            "near_level": near_level, "far": far, "n_near": n_near, "n_far": n_far}


def _measure_one(disk, ray, lawn, zone_level, sign, disk_mm, mm, step, params) -> Zone:
    prof, t, lengths, reason = ray["prof"], ray["t"], ray["lengths"], ray["reason"]
    no_zone = Zone(disk.x, disk.y, disk.radius_px, disk.radius_px, disk_mm, 1.0, 0.0, ["no_zone"])
    if sign * (lawn - ray["near_level"]) < params.min_contrast:
        return no_zone
    contrast = sign * (lawn - zone_level)

    persist = max(2, int(params.persist_mm / mm / step))
    n_far = ray["n_far"]
    edges = np.full(len(prof), np.nan)
    widths = []
    spikes = 0
    blocked = {"rim": 0, "neighbour": 0}
    for i in range(len(prof)):
        L = int(lengths[i])
        p = sign * prof[i, :L]
        if L < 3:
            blocked[reason[i] if reason[i] in blocked else "rim"] += 1
            continue
        hi = sign * lawn
        if reason[i] != "neighbour" and L > n_far + 2:
            tail = float(np.median(p[L - n_far:]))
            if tail - sign * zone_level > 0.5 * contrast:
                hi = tail
        lo = sign * zone_level
        g = (p - lo) / max(hi - lo, 1e-6)
        above = g >= params.edge_level
        j = _first_persistent(above, persist)
        if j is None:
            if reason[i] in blocked:
                blocked[reason[i]] += 1
            continue
        if np.any(above[:j]):
            spikes += 1
        if j == 0:
            edges[i] = t[0]
        else:
            g0, g1 = g[j - 1], g[j]
            f = (params.edge_level - g0) / (g1 - g0) if g1 != g0 else 0.0
            edges[i] = t[j - 1] + f * step
        lo_i = _crossing(g, 0.2, j)
        hi_i = _crossing_after(g, 0.8, j)
        if lo_i is not None and hi_i is not None:
            widths.append((hi_i - lo_i) * step * mm)

    def unmeasured():
        flags = ["unmeasured", "low_confidence"]
        if blocked["neighbour"] > 0.1 * N_RAYS:
            flags.append("overlap")
        if blocked["rim"] > 0.1 * N_RAYS:
            flags.append("hits_rim")
        return Zone(disk.x, disk.y, disk.radius_px, float("nan"), float("nan"), 0.0, 0.0, flags)

    ok = ~np.isnan(edges)
    if ok.sum() < N_RAYS * MIN_AGREEING:
        return unmeasured()

    ux, uy = ray["ux"], ray["uy"]
    ex = disk.x + ux[ok] * edges[ok]
    ey = disk.y + uy[ok] * edges[ok]
    rho = edges[ok]
    med = float(np.median(rho))
    tol = max(0.4 / mm, 3.0)
    inl = np.abs(rho - med) < tol
    cx, cy, rad = disk.x, disk.y, float(np.mean(rho[inl]))
    if inl.sum() >= 12:
        fx, fy, fr = _fit_circle(ex[inl], ey[inl])
        if np.hypot(fx - disk.x, fy - disk.y) < 1.0 / mm:
            d2 = np.abs(np.hypot(ex - fx, ey - fy) - fr)
            inl = d2 < tol
            if inl.sum() >= 12:
                fx, fy, fr = _fit_circle(ex[inl], ey[inl])
                if np.hypot(fx - disk.x, fy - disk.y) < 1.0 / mm:
                    cx, cy, rad = fx, fy, fr

    confidence = float(inl.sum()) / N_RAYS
    if confidence < MIN_AGREEING:
        return unmeasured()
    width = float(np.median(widths)) if widths else 0.0
    diameter = 2 * rad * mm
    flags = []
    if diameter - disk_mm < 2 * params.start_gap_mm + 0.3:
        return no_zone
    if blocked["neighbour"] > 0.1 * N_RAYS:
        flags.append("overlap")
    if blocked["rim"] > 0.1 * N_RAYS:
        flags.append("hits_rim")
    if width > params.hazy_width_mm:
        flags.append("hazy")
    if spikes > 0.05 * N_RAYS:
        flags.append("colonies_in_zone")
    if confidence < 0.6:
        flags.append("low_confidence")
    return Zone(cx, cy, disk.radius_px, rad, diameter, confidence, width, flags)


def _first_persistent(above: np.ndarray, persist: int):
    n = len(above)
    if n == 0:
        return None
    run = 0
    for j in range(n):
        run = run + 1 if above[j] else 0
        if run >= persist:
            return j - persist + 1
    # Edge too close to the end of the ray to confirm the full persistence.
    if run >= 3:
        return n - run
    return None


def _crossing(g, level, j):
    for k in range(j, 0, -1):
        if g[k - 1] < level <= g[k]:
            return k - 1 + (level - g[k - 1]) / (g[k] - g[k - 1])
    return None


def _crossing_after(g, level, j):
    for k in range(max(j, 1), len(g)):
        if g[k - 1] < level <= g[k]:
            return k - 1 + (level - g[k - 1]) / (g[k] - g[k - 1])
    return None


def _fit_circle(x: np.ndarray, y: np.ndarray) -> tuple[float, float, float]:
    """Algebraic least-squares circle (Kåsa)."""
    A = np.column_stack([x, y, np.ones_like(x)])
    b = x * x + y * y
    (a, bb, c), *_ = np.linalg.lstsq(A, b, rcond=None)
    cx, cy = a / 2, bb / 2
    return float(cx), float(cy), float(np.sqrt(max(c + cx * cx + cy * cy, 0)))


def draw_zones(image: np.ndarray, result: ZoneResult) -> np.ndarray:
    out = image.copy() if image.ndim == 3 else cv2.cvtColor(image, cv2.COLOR_GRAY2BGR)
    p = result.plate
    th = max(2, round(p.radius / 300))
    cv2.circle(out, (round(p.cx), round(p.cy)), round(p.radius), (255, 200, 0), th)
    for z in result.zones:
        c = (round(z.x), round(z.y))
        cv2.circle(out, c, round(z.disk_radius_px), (255, 120, 0), th)
        colour = (0, 200, 0) if z.confidence >= 0.6 and not z.flags else (0, 165, 255)
        if "unmeasured" in z.flags:
            label = "?"
            cv2.putText(out, label, (c[0] - round(z.disk_radius_px * 1.6), c[1] - round(z.disk_radius_px * 1.4)),
                        cv2.FONT_HERSHEY_SIMPLEX, p.radius / 700, (0, 0, 255), th, cv2.LINE_AA)
            continue
        if "no_zone" not in z.flags:
            cv2.circle(out, c, round(z.radius_px), colour, th)
        label = f"{z.diameter_rounded} mm"
        cv2.putText(out, label, (c[0] - round(z.disk_radius_px * 1.6), c[1] - round(z.disk_radius_px * 1.4)),
                    cv2.FONT_HERSHEY_SIMPLEX, p.radius / 700, colour, th, cv2.LINE_AA)
    return out
