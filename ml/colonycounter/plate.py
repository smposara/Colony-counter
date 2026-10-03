"""Find the Petri dish in a photo and build the counting mask."""

from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np

# Inner diameter of the agar area in a standard 90 mm dish.
DEFAULT_PLATE_DIAMETER_MM = 90.0


@dataclass(frozen=True)
class Plate:
    """A circular plate in image pixel coordinates."""

    cx: float
    cy: float
    radius: float
    diameter_mm: float = DEFAULT_PLATE_DIAMETER_MM

    @property
    def mm_per_px(self) -> float:
        return self.diameter_mm / (2.0 * self.radius)

    def mask(self, shape: tuple[int, int], rim_fraction: float = 0.95) -> np.ndarray:
        """uint8 mask (255 inside) of the counted area, excluding the rim band."""
        mask = np.zeros(shape[:2], np.uint8)
        r = max(1, int(round(self.radius * rim_fraction)))
        cv2.circle(mask, (int(round(self.cx)), int(round(self.cy))), r, 255, -1)
        return mask


def _to_gray(image: np.ndarray) -> np.ndarray:
    if image.ndim == 2:
        return image
    return cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)


def find_plate(
    image: np.ndarray,
    diameter_mm: float = DEFAULT_PLATE_DIAMETER_MM,
    min_fill: float = 0.4,
    work_size: int = 800,
) -> Plate:
    """Locate the dish as the largest plausible circle in the image.

    Runs a Hough circle search on a downscaled copy and falls back to the largest
    roughly circular contour. ``min_fill`` is the smallest dish diameter allowed,
    as a fraction of the image's shorter side.
    """
    gray = _to_gray(image)
    h, w = gray.shape
    scale = work_size / max(h, w)
    small = cv2.resize(gray, (round(w * scale), round(h * scale)), interpolation=cv2.INTER_AREA)
    small = cv2.GaussianBlur(small, (5, 5), 0)
    short = min(small.shape)
    min_r = int(short * min_fill / 2)
    max_r = int(short * 0.55)

    circles = cv2.HoughCircles(
        small,
        cv2.HOUGH_GRADIENT,
        dp=1.5,
        minDist=short,
        param1=80,
        param2=40,
        minRadius=min_r,
        maxRadius=max_r,
    )
    if circles is not None:
        x, y, r = max(circles[0], key=lambda c: c[2])
        return Plate(x / scale, y / scale, r / scale, diameter_mm)

    plate = _largest_circular_contour(small, min_r)
    if plate is None:
        raise ValueError("No plate found in image")
    x, y, r = plate
    return Plate(x / scale, y / scale, r / scale, diameter_mm)


def _largest_circular_contour(gray: np.ndarray, min_r: int):
    edges = cv2.Canny(gray, 30, 90)
    edges = cv2.dilate(edges, np.ones((3, 3), np.uint8))
    contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    best = None
    for c in contours:
        if len(c) < 5:
            continue
        (x, y), r = cv2.minEnclosingCircle(c)
        if r < min_r:
            continue
        circularity = cv2.contourArea(cv2.convexHull(c)) / (np.pi * r * r)
        if circularity > 0.7 and (best is None or r > best[2]):
            best = (x, y, r)
    return best
