"""End-to-end counting on one plate photo."""

from __future__ import annotations

from dataclasses import asdict, dataclass, field

import cv2
import numpy as np

from .classical import Colony, DetectParams, detect
from .normalize import estimate_background, foreground, to_gray
from .plate import DEFAULT_PLATE_DIAMETER_MM, Plate, find_plate

# Above this many colonies a plate is "too numerous to count" for any preset.
TNTC_COUNT = 300
TNTC_COVERAGE = 0.30


@dataclass
class CountResult:
    count: int
    colonies: list[Colony]
    plate: Plate
    polarity: str
    flags: list[str] = field(default_factory=list)
    coverage: float = 0.0

    def to_dict(self) -> dict:
        return {
            "count": self.count,
            "flags": self.flags,
            "polarity": self.polarity,
            "coverage": round(self.coverage, 4),
            "plate": asdict(self.plate),
            "mm_per_px": self.plate.mm_per_px,
            "colonies": [asdict(c) for c in self.colonies],
        }


def count_colonies(
    image: np.ndarray,
    plate: Plate | None = None,
    plate_diameter_mm: float = DEFAULT_PLATE_DIAMETER_MM,
    rim_fraction: float = 0.95,
    polarity: str = "auto",
    params: DetectParams = DetectParams(),
) -> CountResult:
    """Count colonies in a BGR or grayscale image of one plate."""
    if plate is None:
        plate = find_plate(image, diameter_mm=plate_diameter_mm)
    gray = to_gray(image)
    mask = plate.mask(gray.shape, rim_fraction)
    bg = estimate_background(gray, plate)
    fg, polarity = foreground(gray, bg, mask, polarity)
    det = detect(fg, mask, plate.mm_per_px, params)

    count = sum(c.n for c in det.colonies)
    flags = []
    if det.spreaders:
        flags.append("spreader")
    if count > TNTC_COUNT or det.coverage > TNTC_COVERAGE:
        flags.append("tntc")
    if any(c.n > 1 for c in det.colonies):
        flags.append("clusters_estimated")
    return CountResult(count, det.colonies, plate, polarity, flags, det.coverage)


def draw_overlay(image: np.ndarray, result: CountResult, rim_fraction: float = 0.95) -> np.ndarray:
    """Copy of the image with the counted area and each colony marked."""
    out = image.copy() if image.ndim == 3 else cv2.cvtColor(image, cv2.COLOR_GRAY2BGR)
    p = result.plate
    thick = max(1, int(round(p.radius / 300)))
    cv2.circle(out, (round(p.cx), round(p.cy)), round(p.radius * rim_fraction), (255, 200, 0), thick)
    for c in result.colonies:
        color = (0, 0, 255) if c.n > 1 else (0, 255, 0)
        cv2.circle(out, (round(c.x), round(c.y)), max(3, round(c.radius_px * 1.3)), color, thick)
        if c.n > 1:
            cv2.putText(out, f"x{c.n}", (round(c.x + c.radius_px), round(c.y)),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.4 * thick + 0.2, color, thick)
    label = f"{result.count} CFU" + (f"  [{', '.join(result.flags)}]" if result.flags else "")
    cv2.putText(out, label, (10, 30 * thick), cv2.FONT_HERSHEY_SIMPLEX, 0.8 * thick, (0, 255, 255), 2 * thick)
    return out
