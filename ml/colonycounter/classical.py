"""Classical colony detection: threshold, then split touching colonies.

This is the training-free baseline and fallback. It expects a background-corrected
contrast map where colonies are positive (see ``normalize.foreground``).
"""

from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np
from scipy import ndimage as ndi


@dataclass(frozen=True)
class DetectParams:
    min_diameter_mm: float = 0.15
    k_sigma: float = 4.0
    min_contrast: float = 6.0
    # Colonies closer than this fraction of a typical radius are treated as one.
    peak_separation: float = 0.5
    # A blob covering more than this fraction of the plate is a spreader.
    spreader_fraction: float = 0.04


@dataclass(frozen=True)
class Colony:
    x: float
    y: float
    radius_px: float
    n: int = 1  # how many colonies this mark stands for (merged clusters)
    score: float = 0.0  # peak contrast in noise sigmas


@dataclass(frozen=True)
class Detection:
    colonies: list[Colony]
    threshold: float
    noise_sigma: float
    coverage: float  # fraction of the counted area covered by colonies
    spreaders: int


def robust_sigma(values: np.ndarray) -> float:
    med = np.median(values)
    return float(1.4826 * np.median(np.abs(values - med))) or 1.0


def detect(
    fg: np.ndarray,
    mask: np.ndarray,
    mm_per_px: float,
    params: DetectParams = DetectParams(),
) -> Detection:
    inside = mask > 0
    sigma = robust_sigma(fg[inside])
    thr = max(params.k_sigma * sigma, params.min_contrast)
    binary = ((fg > thr) & inside).astype(np.uint8)
    binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    binary = ndi.binary_fill_holes(binary).astype(np.uint8)

    min_r_px = params.min_diameter_mm / mm_per_px / 2
    min_area = max(4.0, np.pi * min_r_px**2)
    n_lab, labels, stats, _ = cv2.connectedComponentsWithStats(binary, connectivity=8)

    areas = stats[1:, cv2.CC_STAT_AREA].astype(float)
    keep = np.flatnonzero(areas >= min_area) + 1
    if keep.size == 0:
        return Detection([], thr, sigma, 0.0, 0)

    dist = cv2.distanceTransform(binary, cv2.DIST_L2, 5)
    plate_area = float(inside.sum())
    typical_r = _typical_radius(labels, stats, keep, binary)
    typical_area = np.pi * typical_r**2
    footprint = max(2, int(round(params.peak_separation * typical_r)))
    peaks = _peaks(dist, footprint, min_height=max(1.0, 0.35 * typical_r))
    peak_lab, _ = ndi.label(peaks)
    peak_pts = ndi.center_of_mass(peaks, peak_lab, range(1, peak_lab.max() + 1))
    peaks_by_comp: dict[int, list[tuple[float, float]]] = {}
    for py, px in peak_pts:
        comp = labels[int(round(py)), int(round(px))]
        if comp:
            peaks_by_comp.setdefault(comp, []).append((px, py))

    colonies: list[Colony] = []
    spreaders = 0
    covered = 0.0
    slices = ndi.find_objects(labels)
    for comp in keep:
        area = stats[comp, cv2.CC_STAT_AREA]
        covered += area
        sl = slices[comp - 1]
        comp_mask = labels[sl] == comp
        score = float(fg[sl][comp_mask].max() / sigma)
        if area > params.spreader_fraction * plate_area:
            spreaders += 1
            continue
        pts = peaks_by_comp.get(comp, [])
        if len(pts) <= 1:
            ys, xs = np.nonzero(comp_mask)
            cx, cy = xs.mean() + sl[1].start, ys.mean() + sl[0].start
            n = 1
            if area > 2.5 * typical_area and _solidity(comp_mask) < 0.85:
                n = int(round(area / typical_area))
            colonies.append(Colony(float(cx), float(cy), float(np.sqrt(area / np.pi)), n, score))
        else:
            r = float(np.sqrt(area / np.pi / len(pts)))
            for px, py in pts:
                colonies.append(Colony(float(px), float(py), r, 1, score))

    return Detection(colonies, thr, sigma, covered / plate_area, spreaders)


def _peaks(dist: np.ndarray, footprint: int, min_height: float) -> np.ndarray:
    size = 2 * footprint + 1
    yy, xx = np.ogrid[-footprint:footprint + 1, -footprint:footprint + 1]
    disk = (xx * xx + yy * yy) <= footprint * footprint
    local_max = ndi.maximum_filter(dist, footprint=disk, mode="constant") if size > 1 else dist
    return (dist == local_max) & (dist >= min_height)


def _typical_radius(labels, stats, keep, binary) -> float:
    """Median radius of blobs that look like single, round colonies."""
    radii = []
    slices = ndi.find_objects(labels)
    for comp in keep:
        sl = slices[comp - 1]
        m = labels[sl] == comp
        if _solidity(m) > 0.9:
            radii.append(np.sqrt(stats[comp, cv2.CC_STAT_AREA] / np.pi))
    if not radii:
        radii = list(np.sqrt(stats[keep, cv2.CC_STAT_AREA] / np.pi))
    return float(max(1.5, np.median(radii)))


def _solidity(m: np.ndarray) -> float:
    contours, _ = cv2.findContours(m.astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return 1.0
    c = max(contours, key=cv2.contourArea)
    hull = cv2.contourArea(cv2.convexHull(c))
    return float(m.sum() / hull) if hull > 0 else 1.0
