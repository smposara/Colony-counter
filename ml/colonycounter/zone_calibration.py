"""Calibration of zone measurement against the user's own calliper (or ruler).

The user photographs a used zone plate, measures one long span (outer edge of one disk
to the outer edge of the disk farthest from it) and each zone. This module compares
those readings with the app's measurement: bias, Bland-Altman limits of agreement, the
scale error from the span, and a hint at the cause (scale, lens, edge reading or
spread). Check only: nothing here changes a measurement.

Mirrored by app/lib/core/zone_calibration.dart; keep the two in step (the shared cases
in app/test/fixtures/calibration_cases.json check agreement). See
docs/ZONE_CALIBRATION_IMPLEMENTATION.md.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

# Zones at or beyond this fraction of the plate radius count as "near the edge".
OUTER_FRACTION = 0.6

# The slope of difference against size is only judged when the zones differ in size by
# at least this much (mm).
MIN_SIZE_SPREAD = 5.0


@dataclass(frozen=True)
class Limits:
    min_zones: int
    good_bias: float
    good_loa: float
    good_scale: float  # fraction, e.g. 0.01
    usable_bias: float
    usable_loa: float


LIMITS = {
    "calliper": Limits(6, 0.5, 1.0, 0.01, 1.0, 2.0),
    "ruler": Limits(8, 0.5, 1.5, 0.015, 1.0, 2.5),
}


@dataclass
class CalZone:
    """One zone: the app's diameter on each photo and the user's reading(s), in mm."""

    app_mm: list[float]
    user_mm: list[float]
    radial_fraction: float = 0.0  # distance from the plate centre / plate radius
    included: bool = True


@dataclass
class CalSummary:
    n: int
    bias: float
    sd: float
    loa_low: float
    loa_high: float
    max_abs: float
    within_1mm: float
    slope: float | None
    slope_significant: bool
    edge_minus_centre: float | None
    repeatability_sd: float | None
    scale_error: float | None
    verdict: str  # good, usable, poor, too_few
    hint: str  # none, scale, lens, edge, spread
    differences: list[float] = field(default_factory=list)


def _mean(v):
    return sum(v) / len(v)


def _sd(v):
    if len(v) < 2:
        return float("nan")
    m = _mean(v)
    return math.sqrt(sum((x - m) ** 2 for x in v) / (len(v) - 1))


def farthest_pair(disks) -> tuple[int, int]:
    """Indices of the two disks (x, y, r in px) whose outer edges are farthest apart."""
    best, pair = -1.0, (0, 1)
    for i in range(len(disks)):
        for j in range(i + 1, len(disks)):
            (xa, ya, ra), (xb, yb, rb) = disks[i], disks[j]
            span = math.hypot(xa - xb, ya - yb) + ra + rb
            if span > best:
                best, pair = span, (i, j)
    return pair


def app_span_mm(a, b, mm_per_px: float) -> float:
    """Outer edge to outer edge of disks a and b (x, y, r in px), in mm."""
    return (math.hypot(a[0] - b[0], a[1] - b[1]) + a[2] + b[2]) * mm_per_px


def calibration_summary(zones: list[CalZone], app_span: float | None = None,
                        user_span: float | None = None, tool: str = "calliper") -> CalSummary:
    lim = LIMITS[tool]
    use = [z for z in zones if z.included and z.app_mm and z.user_mm
           and all(math.isfinite(v) for v in z.app_mm + z.user_mm)]
    app = [_mean(z.app_mm) for z in use]
    user = [_mean(z.user_mm) for z in use]
    d = [a - u for a, u in zip(app, user)]
    m = [(a + u) / 2 for a, u in zip(app, user)]
    n = len(d)
    nan = float("nan")
    bias = _mean(d) if n else nan
    sd = _sd(d) if n >= 2 else (0.0 if n == 1 else nan)
    loa_low, loa_high = bias - 1.96 * sd, bias + 1.96 * sd
    max_abs = max((abs(x) for x in d), default=nan)
    within = sum(1 for x in d if abs(x) <= 1.0 + 1e-9) / n if n else nan

    # Difference against size: a slope means the scale is off.
    slope, significant = None, False
    if n >= 3:
        mm = _mean(m)
        sxx = sum((x - mm) ** 2 for x in m)
        if sxx > 1e-12:
            slope = sum((x - mm) * (y - bias) for x, y in zip(m, d)) / sxx
            resid = [y - (bias + slope * (x - mm)) for x, y in zip(m, d)]
            s2 = sum(r * r for r in resid) / (n - 2) if n > 2 else 0.0
            se = math.sqrt(s2 / sxx)
            spread = max(m) - min(m)
            big = abs(slope) * spread > 0.5
            # Zones of similar size can't show a scale error: the mean of the two
            # readings then varies mostly with the difference itself.
            significant = (n >= 4 and spread >= MIN_SIZE_SPREAD and big
                           and (se == 0 or abs(slope) > 2 * se))

    # Near the plate edge against the centre: lens distortion or tilt.
    outer = [x for x, z in zip(d, use) if z.radial_fraction >= OUTER_FRACTION]
    inner = [x for x, z in zip(d, use) if z.radial_fraction < OUTER_FRACTION]
    edge = _mean(outer) - _mean(inner) if len(outer) >= 2 and len(inner) >= 2 else None

    # Repeatability: pooled SD of the app's diameter across photos.
    multi = [z.app_mm for z in use if len(z.app_mm) >= 2]
    rep = math.sqrt(_mean([_sd(v) ** 2 for v in multi])) if multi else None

    scale = (app_span / user_span - 1) if app_span and user_span else None

    if n < lim.min_zones:
        verdict = "too_few"
    elif (abs(bias) <= lim.good_bias and loa_low >= -lim.good_loa and loa_high <= lim.good_loa
          and (scale is None or abs(scale) <= lim.good_scale)):
        verdict = "good"
    elif abs(bias) <= lim.usable_bias and loa_low >= -lim.usable_loa and loa_high <= lim.usable_loa:
        verdict = "usable"
    else:
        verdict = "poor"

    if verdict in ("good", "too_few"):
        hint = "none"
    elif (scale is not None and abs(scale) > lim.good_scale) or significant:
        hint = "scale"
    elif edge is not None and abs(edge) > 0.5:
        hint = "lens"
    elif abs(bias) > 0.5:
        hint = "edge"
    else:
        hint = "spread"

    return CalSummary(n=n, bias=bias, sd=sd, loa_low=loa_low, loa_high=loa_high, max_abs=max_abs,
                      within_1mm=within, slope=slope, slope_significant=significant,
                      edge_minus_centre=edge, repeatability_sd=rep, scale_error=scale,
                      verdict=verdict, hint=hint, differences=d)
