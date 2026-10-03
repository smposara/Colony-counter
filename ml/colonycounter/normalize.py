"""Background correction: remove uneven lighting so colonies stand out evenly."""

from __future__ import annotations

import cv2
import numpy as np

from .plate import Plate


def to_gray(image: np.ndarray) -> np.ndarray:
    if image.ndim == 2:
        return image.astype(np.float32)
    return cv2.cvtColor(image, cv2.COLOR_BGR2GRAY).astype(np.float32)


def estimate_background(
    gray: np.ndarray,
    plate: Plate,
    kernel_mm: float = 6.0,
    work_px_per_mm: float = 4.0,
) -> np.ndarray:
    """Smooth background of the agar, ignoring colonies.

    A median filter much wider than a colony follows lighting gradients but not the
    colonies themselves. It runs on a downscaled copy (``work_px_per_mm``) for speed.
    Pixels outside the plate are filled with the agar median first so the dark
    surround does not bleed into the rim.
    """
    inside = plate.mask(gray.shape, rim_fraction=0.97) > 0
    filled = gray.copy()
    filled[~inside] = float(np.median(gray[inside]))

    scale = min(1.0, work_px_per_mm * plate.mm_per_px)
    h, w = gray.shape
    small = cv2.resize(filled, (max(1, round(w * scale)), max(1, round(h * scale))),
                       interpolation=cv2.INTER_AREA)
    k = int(round(kernel_mm / plate.mm_per_px * scale)) | 1
    k = max(3, min(k, 255))
    # cv2.medianBlur only accepts kernels > 5 for 8-bit input.
    lo, hi = float(small.min()), float(small.max())
    span = max(hi - lo, 1e-6)
    small8 = np.clip((small - lo) / span * 255.0, 0, 255).astype(np.uint8)
    bg8 = cv2.medianBlur(small8, k)
    bg = bg8.astype(np.float32) / 255.0 * span + lo
    bg = cv2.GaussianBlur(bg, (0, 0), max(1.0, k / 6))
    return cv2.resize(bg, (w, h), interpolation=cv2.INTER_LINEAR)


def foreground(
    gray: np.ndarray,
    background: np.ndarray,
    mask: np.ndarray,
    polarity: str = "auto",
) -> tuple[np.ndarray, str]:
    """Signed contrast map where colonies are positive.

    ``polarity`` is "bright" (dark-field / dark background: colonies lighter than
    agar), "dark" (back-lit: colonies darker) or "auto".
    """
    diff = gray - background
    if polarity == "auto":
        vals = diff[mask > 0]
        hi = np.percentile(vals, 99.7)
        lo = -np.percentile(vals, 0.3)
        polarity = "bright" if hi >= lo else "dark"
    if polarity == "dark":
        diff = -diff
    elif polarity != "bright":
        raise ValueError(f"Unknown polarity: {polarity!r}")
    diff[mask == 0] = 0
    return diff, polarity
