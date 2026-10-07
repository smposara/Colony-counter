"""Counting Petrifilm-style dry-film plates (Neogen® Petrifilm® and similar).

    photo → printed 1 cm grid (angle, pitch → mm/px, line positions)
          → grid lines erased and filled from the gel around them
          → round growth area (the tinted gel) → background per Lab channel
          → colonies where the gel is darker / changes colour (classical detector)
          → per colony: colour (blue / red), gas bubble within one colony
            diameter, yellow zone, yeast vs mold by size
          → results per the interpretation guide; above the counting range an
            estimate from complete 1 cm squares × growth area

Plate-type values marked ``confirmed=False`` must be checked against the
current Neogen interpretation guide before release (see docs/PETRIFILM.md).
Petrifilm and Neogen are trademarks of Neogen Corporation.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field

import cv2
import numpy as np

from .classical import DetectParams, detect
from .normalize import estimate_background
from .plate import Plate
from .zones import RING_SECTORS, _all_round, ring_taps


@dataclass(frozen=True)
class FilmType:
    key: str
    label: str
    results: tuple[str, ...]  # what is reported, in order
    count_min: int
    count_max: int
    area_cm2: float  # growth area used for square-based estimates
    foam: bool  # growth area bounded by a foam ring
    confirmed: bool  # range and area checked against the current guide
    source: str


TYPES: dict[str, FilmType] = {
    "ac": FilmType("ac", "Aerobic Count (AC)", ("aerobic",), 25, 250, 20.0, False, True,
                   "AC interpretation guide: 25-250 preferred, ~20 cm², square × 20"),
    "ec": FilmType("ec", "E. coli/Coliform (EC)", ("ecoli", "coliform"), 15, 150, 20.0, True, False,
                   "EC interpretation guide: counting limit 150 (lower limit and area to confirm)"),
    "cc": FilmType("cc", "Coliform Count (CC)", ("coliform",), 15, 150, 20.0, True, False,
                   "CC interpretation guide (to confirm)"),
    "eb": FilmType("eb", "Enterobacteriaceae (EB)", ("enterobacteriaceae",), 15, 100, 20.0, True, False,
                   "EB interpretation guide (to confirm)"),
    "ym": FilmType("ym", "Yeast & Mold (YM)", ("yeast", "mold"), 15, 150, 20.0, True, False,
                   "YM / Rapid YM interpretation guides (to confirm)"),
}

NOMINAL_AREA_DIAMETER_MM = 50.5  # 20 cm²
GRID_PITCH_MM = 10.0


@dataclass
class Grid:
    pitch_px: float
    angle_deg: float  # rotate the image by this to make the grid axis-aligned
    ox: float  # line positions in the rotated frame: ox + k * pitch
    oy: float
    centre: tuple[float, float]  # rotation centre

    @property
    def mm_per_px(self) -> float:
        return GRID_PITCH_MM / self.pitch_px

    def matrix(self) -> np.ndarray:
        return cv2.getRotationMatrix2D(self.centre, self.angle_deg, 1.0)

    def to_grid(self, x, y):
        m = self.matrix()
        return m[0, 0] * x + m[0, 1] * y + m[0, 2], m[1, 0] * x + m[1, 1] * y + m[1, 2]

    def to_image(self, gx, gy):
        m = np.vstack([self.matrix(), [0, 0, 1]])
        inv = np.linalg.inv(m)
        return inv[0, 0] * gx + inv[0, 1] * gy + inv[0, 2], inv[1, 0] * gx + inv[1, 1] * gy + inv[1, 2]


@dataclass
class FilmColony:
    x: float
    y: float
    radius_px: float
    kind: str  # "colony" (AC), "blue", "red", "yeast", "mold"
    n: int = 1
    gas: bool = False
    yellow: bool = False


@dataclass
class FilmResult:
    type: str
    plate: Plate
    grid: Grid
    colonies: list[FilmColony]
    bubbles: list[tuple[float, float, float]]  # x, y, radius_px
    counts: dict[str, int]  # counted per result
    estimates: dict[str, float] | None  # from squares, when above the range
    squares_used: int
    flags: list[str] = field(default_factory=list)

    @property
    def values(self) -> dict[str, float]:
        """Per-plate result: the estimate when there is one, else the count."""
        return dict(self.estimates) if self.estimates else {k: float(v) for k, v in self.counts.items()}

    def to_dict(self) -> dict:
        return {
            "type": self.type,
            "counts": self.counts,
            "estimates": self.estimates,
            "squares_used": self.squares_used,
            "flags": self.flags,
            "mm_per_px": self.plate.mm_per_px,
            "plate": asdict(self.plate),
            "grid": {"pitch_px": self.grid.pitch_px, "angle_deg": self.grid.angle_deg},
            "colonies": [asdict(c) for c in self.colonies],
            "bubbles": [list(b) for b in self.bubbles],
        }


# ---------------------------------------------------------------------------
# Grid

def _line_map(gray: np.ndarray, k: int) -> np.ndarray:
    """Thin dark lines (and other thin dark detail): black top-hat."""
    kern = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k))
    return cv2.morphologyEx(gray, cv2.MORPH_BLACKHAT, kern).astype(np.float32)


def _periodicity(profile: np.ndarray, min_period: float, max_period: float) -> tuple[float, float]:
    """(strength, period) of the strongest repeat in a 1-D profile."""
    p = profile - profile.mean()
    n = len(p)
    spec = np.abs(np.fft.rfft(p * np.hanning(n))) ** 2
    f = np.arange(len(spec))
    ok = (f >= n / max_period) & (f <= n / min_period)
    if not ok.any():
        return 0.0, 0.0
    i = int(np.argmax(np.where(ok, spec, 0)))
    return float(spec[i] / (spec[1:].sum() + 1e-9)), n / max(i, 1)


def _rotate(img: np.ndarray, centre, angle: float) -> np.ndarray:
    m = cv2.getRotationMatrix2D(centre, angle, 1.0)
    return cv2.warpAffine(img, m, (img.shape[1], img.shape[0]), flags=cv2.INTER_LINEAR)


def find_grid(gray: np.ndarray) -> Grid:
    """Angle, pitch and line positions of the printed grid.

    Angle: the rotation that makes the row and column sums of the line map most
    peaked (largest variance), as in document skew detection. Pitch: the
    autocorrelation peak of those sums.
    """
    h, w = gray.shape
    s = min(1.0, 700 / max(h, w))
    small = cv2.resize(gray, (round(w * s), round(h * s)), interpolation=cv2.INTER_AREA)
    lines_s = _line_map(small, 5)
    lines_s -= lines_s.mean()
    cs = (small.shape[1] / 2, small.shape[0] / 2)

    def score(a):
        r = _rotate(lines_s, cs, a)
        return float(r.sum(axis=0).var() + r.sum(axis=1).var())

    best = max(np.arange(-45, 45, 0.5), key=score)
    angle = float(max(np.arange(best - 0.6, best + 0.6001, 0.05), key=score))

    k = max(5, int(round(5 / s)) | 1)
    lines = _line_map(gray, min(k, 15))
    centre = (w / 2, h / 2)
    rot = _rotate(lines, centre, angle)
    px, py = rot.sum(axis=0), rot.sum(axis=1)
    lo, hi = 12 / s, min(h, w) / 3
    pitch = float(np.mean([_refine_period(px, _first_period(px, lo, hi)),
                           _refine_period(py, _first_period(py, lo, hi))]))
    return Grid(pitch, angle, _phase(px, pitch), _phase(py, pitch), centre)


def _first_period(profile: np.ndarray, lo: float, hi: float) -> float:
    """Shortest lag with a strong autocorrelation peak (not a multiple of it)."""
    p = profile - profile.mean()
    ac = np.correlate(p, p, mode="full")[len(p) - 1:]
    ac = ac / (ac[0] + 1e-9)
    lo_i, hi_i = int(lo), min(int(hi), len(ac) - 2)
    seg = ac[lo_i:hi_i]
    if seg.size == 0:
        return lo
    top = float(seg.max())
    for i in range(lo_i + 1, hi_i):
        if ac[i] >= 0.6 * top and ac[i] >= ac[i - 1] and ac[i] >= ac[i + 1]:
            return float(i)
    return float(lo_i + int(np.argmax(seg)))


def _refine_period(profile: np.ndarray, guess: float) -> float:
    """Sub-pixel period from the autocorrelation peak near ``guess``."""
    p = profile - profile.mean()
    ac = np.correlate(p, p, mode="full")[len(p) - 1:]
    lo, hi = int(guess * 0.85), int(guess * 1.15) + 2
    i = lo + int(np.argmax(ac[lo:hi]))
    if 0 < i < len(ac) - 1:
        a, b, c = ac[i - 1], ac[i], ac[i + 1]
        den = a - 2 * b + c
        if den < 0:
            return i + 0.5 * (a - c) / den
    return float(i)


def _phase(profile: np.ndarray, pitch: float) -> float:
    """Offset of the lines: argmax over φ of the profile summed at φ + k·pitch."""
    n = len(profile)
    best, best_v = 0.0, -np.inf
    for phi in np.arange(0, pitch, 0.25):
        pos = np.arange(phi, n - 1, pitch)
        v = np.interp(pos, np.arange(n), profile).mean()
        if v > best_v:
            best, best_v = float(phi), v
    return best


def grid_line_mask(shape, grid: Grid, half_width_px: float) -> np.ndarray:
    h, w = shape[:2]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    gx, gy = grid.to_grid(xx, yy)
    dx = np.abs((gx - grid.ox + grid.pitch_px / 2) % grid.pitch_px - grid.pitch_px / 2)
    dy = np.abs((gy - grid.oy + grid.pitch_px / 2) % grid.pitch_px - grid.pitch_px / 2)
    return ((dx < half_width_px) | (dy < half_width_px)).astype(np.uint8) * 255


# ---------------------------------------------------------------------------
# Growth area

def find_growth_area(lab: np.ndarray, mm_per_px: float) -> Plate:
    """The round gel: the circle of about the nominal size whose inside is most
    tinted (chroma) relative to a ring just outside it. Colonies only add
    chroma inside, so crowded plates do not upset it."""
    a = lab[..., 1].astype(np.float32) - 128
    b = lab[..., 2].astype(np.float32) - 128
    chroma = np.hypot(a, b)
    r_nom = NOMINAL_AREA_DIAMETER_MM / 2 / mm_per_px
    s = min(1.0, 60.0 / r_nom)
    h, w = chroma.shape
    small = cv2.resize(chroma, (max(1, round(w * s)), max(1, round(h * s))), interpolation=cv2.INTER_AREA)
    best = (-np.inf, 0.0, 0.0, 0.0)
    for f in np.arange(0.85, 1.151, 0.025):
        r = r_nom * s * f
        k = int(np.ceil(r * 1.25)) + 1
        yy, xx = np.mgrid[-k:k + 1, -k:k + 1]
        d = np.hypot(xx, yy)
        inside = (d <= r).astype(np.float32)
        ring = ((d > r) & (d <= r * 1.2)).astype(np.float32)
        kern = inside / inside.sum() - ring / ring.sum()
        resp = cv2.filter2D(small, cv2.CV_32F, kern, borderType=cv2.BORDER_CONSTANT)
        y, x = np.unravel_index(int(np.argmax(resp)), resp.shape)
        if resp[y, x] > best[0]:
            best = (float(resp[y, x]), x / s, y / s, r / s)
    if not np.isfinite(best[0]) or best[0] <= 0:
        raise ValueError("No growth area found")
    _, cx, cy, r = best
    cx, cy, r = _refine_edge(chroma, cx, cy, r)
    return Plate(float(cx), float(cy), float(r), 2 * r * mm_per_px)


def _refine_edge(chroma, cx, cy, r):
    """Sub-pixel circle from the strongest chroma drop on 90 rays near r."""
    sm = cv2.GaussianBlur(chroma, (0, 0), 1.5)
    a = np.linspace(0, 2 * np.pi, 90, endpoint=False)
    t = np.arange(r * 0.9, r * 1.1, 0.5, dtype=np.float32)
    mx = (cx + np.cos(a)[:, None] * t[None, :]).astype(np.float32)
    my = (cy + np.sin(a)[:, None] * t[None, :]).astype(np.float32)
    prof = cv2.remap(sm, mx, my, cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
    k = np.argmin(np.diff(prof, axis=1), axis=1)  # steepest drop going outwards
    rho = t[k] + 0.25
    ex, ey = cx + np.cos(a) * rho, cy + np.sin(a) * rho
    keep = np.abs(rho - np.median(rho)) < max(3.0, 0.02 * r)
    if keep.sum() < 20:
        return cx, cy, r
    fx, fy, fr = _fit_circle(ex[keep], ey[keep])
    if np.hypot(fx - cx, fy - cy) > 0.1 * r or abs(fr / r - 1) > 0.1:
        return cx, cy, r
    return fx, fy, fr


def _fit_circle(x, y):
    A = np.column_stack([x, y, np.ones_like(x)])
    (p, q, c), *_ = np.linalg.lstsq(A, x * x + y * y, rcond=None)
    cx, cy = p / 2, q / 2
    return cx, cy, float(np.sqrt(max(c + cx * cx + cy * cy, 0)))


# ---------------------------------------------------------------------------
# Gas bubbles

BUBBLE_RADIUS_MM = (0.28, 0.9)  # searched every BUBBLE_RADIUS_STEP_PX
BUBBLE_RADIUS_STEP_PX = 0.75  # the rim is thin: radii must be about a pixel apart
BUBBLE_MIN_SCORE = 8.0  # Lab L (8-bit) brighter rim than inside and outside
# Sorted sector index that must still pass: 2 lets two of the 8 sectors fail,
# e.g. where the bubble touches its colony (synthetic: recall 0.87, precision 1.0).
BUBBLE_SECTOR_INDEX = 2


def find_bubbles(L: np.ndarray, plate: Plate, mm_per_px: float) -> list[tuple[float, float, float]]:
    """Gas bubbles: a thin rim brighter than both its inside and outside, all round."""
    x0 = max(0, int(plate.cx - plate.radius)); x1 = min(L.shape[1], int(plate.cx + plate.radius) + 1)
    y0 = max(0, int(plate.cy - plate.radius)); y1 = min(L.shape[0], int(plate.cy + plate.radius) + 1)
    roi = cv2.GaussianBlur(L[y0:y1, x0:x1].astype(np.float32), (0, 0), 0.8)
    best = np.zeros_like(roi)
    best_r = np.zeros_like(roi)
    for r in np.arange(BUBBLE_RADIUS_MM[0] / mm_per_px, BUBBLE_RADIUS_MM[1] / mm_per_px,
                       BUBBLE_RADIUS_STEP_PX):
        _, ridge = ring_taps(r)
        k = int(np.max(np.abs(ridge[:, :2]))) + 1
        per = []
        for sec in range(RING_SECTORS):
            kern = np.zeros((2 * k + 1, 2 * k + 1), np.float32)
            for dx, dy, sc, wgt in ridge[ridge[:, 2] == sec]:
                kern[int(dy) + k, int(dx) + k] += wgt
            per.append(cv2.filter2D(roi, cv2.CV_32F, kern, borderType=cv2.BORDER_REPLICATE))
        srt = np.sort(np.stack(per), axis=0)
        score = np.maximum(srt[BUBBLE_SECTOR_INDEX], 0)  # bright rim only
        upd = score > best
        best[upd] = score[upd]
        best_r[upd] = r
    yy, xx = np.mgrid[y0:y1, x0:x1]
    inside = np.hypot(xx - plate.cx, yy - plate.cy) < plate.radius * 0.97
    best[~inside] = 0
    ys, xs = np.nonzero(best >= BUBBLE_MIN_SCORE)
    order = np.argsort(-best[ys, xs], kind="stable")
    out: list[tuple[float, float, float]] = []
    for i in order:
        x, y, r = xs[i] + x0, ys[i] + y0, best_r[ys[i], xs[i]]
        if any(np.hypot(x - bx, y - by) < max(r, br) * 1.5 for bx, by, br in out):
            continue
        out.append((float(x), float(y), float(r)))
    return out


# ---------------------------------------------------------------------------
# Whole plate

MOLD_MIN_RADIUS_MM = 1.0
BLUE_MAX_B = -8.0  # Lab b* (blue colonies are clearly negative)
YELLOW_MIN_DB = 10.0  # Lab b* rise in the zone around a colony


def count_petrifilm(image: np.ndarray, type: str, plate: Plate | None = None,
                    grid: Grid | None = None) -> FilmResult:
    ft = TYPES[type]
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    grid = grid or find_grid(gray)
    mm = grid.mm_per_px
    lines = grid_line_mask(gray.shape, grid, max(1.5, 0.22 / mm))
    clean = cv2.inpaint(image, lines, 3, cv2.INPAINT_TELEA)
    lab = cv2.cvtColor(clean, cv2.COLOR_BGR2LAB).astype(np.float32)
    flags: list[str] = []
    if plate is None:
        plate = find_growth_area(lab, mm)
    plate = Plate(plate.cx, plate.cy, plate.radius, 2 * plate.radius * mm)
    if abs(plate.diameter_mm / NOMINAL_AREA_DIAMETER_MM - 1) > 0.1:
        flags.append("area_size_unexpected")

    # Wide background where large features (molds, yellow zones) would lift it.
    kernel = 12.0 if type in ("ym", "eb") else 6.0
    bg = [estimate_background(lab[..., i], plate, kernel_mm=kernel) for i in range(3)]
    dL = lab[..., 0] - bg[0]
    dc = np.hypot(lab[..., 1] - bg[1], lab[..., 2] - bg[2])
    darker = dL < 0
    fg = np.where(darker, -dL + 0.5 * dc, 0).astype(np.float32)
    mask = plate.mask(gray.shape, 0.95)
    # Molds are large and touch: much higher limits before a blob is a
    # "spreader" or the plate is too crowded.
    params = DetectParams(min_diameter_mm=0.25, k_sigma=4.0, min_contrast=8.0,
                          spreader_fraction=0.25 if type == "ym" else 0.04)
    det = detect(fg, mask, mm, params)

    bubbles: list[tuple[float, float, float]] = []
    if type in ("ec", "cc", "eb"):
        # A bright ring centred on a colony is its yellow zone or edge, not gas.
        bubbles = [b for b in find_bubbles(lab[..., 0], plate, mm)
                   if not any(np.hypot(b[0] - c.x, b[1] - c.y) < c.radius_px + 0.5 * b[2]
                              for c in det.colonies)]
    marks = _clean_marks(det.colonies, bubbles, mm)
    if type == "ym":
        marks = _merge_split_molds(_own_radius(marks, fg, mask, det.threshold), mm)
        marks += _yeasts_in_molds(fg, marks, mm, params)
    colonies: list[FilmColony] = []
    for c in marks:
        r_in = max(1.0, 0.6 * c.radius_px)
        a, b = _disc_mean(lab, c.x, c.y, r_in)[1:]
        if type == "ac":
            kind = "colony"
        elif type == "ym":
            kind = "mold" if c.radius_px * mm >= MOLD_MIN_RADIUS_MM else "yeast"
        else:
            kind = "blue" if (b - 128) < BLUE_MAX_B else "red"
        gas = any(np.hypot(c.x - bx, c.y - by) - c.radius_px - br <= 2 * c.radius_px
                  for bx, by, br in bubbles)
        yellow = False
        if type == "eb":
            ring_b = _ring_mean(lab[..., 2], c.x, c.y, c.radius_px + 0.3 / mm, c.radius_px + 1.5 / mm)
            yellow = ring_b - _disc_mean_ch(bg[2], c.x, c.y, c.radius_px) >= YELLOW_MIN_DB
        colonies.append(FilmColony(c.x, c.y, c.radius_px, kind, c.n, bool(gas), bool(yellow)))

    def tally(sel) -> int:
        return int(sum(c.n for c in colonies if sel(c)))

    rules = {
        "aerobic": lambda c: True,
        "ecoli": lambda c: c.kind == "blue",
        "coliform": (lambda c: c.kind == "blue" or (c.kind == "red" and c.gas)) if type == "ec"
        else (lambda c: c.gas),
        "enterobacteriaceae": lambda c: c.kind == "red" and (c.gas or c.yellow),
        "yeast": lambda c: c.kind == "yeast",
        "mold": lambda c: c.kind == "mold",
    }
    counts = {k: tally(rules[k]) for k in ft.results}

    estimates, used = None, 0
    if max(counts.values()) > ft.count_max:
        squares = _complete_squares(grid, plate)
        used = len(squares)
        if used >= 3:
            estimates = {}
            for k in ft.results:
                per = [sum(c.n for c in colonies if rules[k](c) and _in_square(grid, sq, c.x, c.y))
                       for sq in squares]
                estimates[k] = float(np.mean(per) * ft.area_cm2)
            flags.append("estimated")
    if det.coverage > (0.6 if type == "ym" else 0.3):
        flags.append("tntc")
    if det.spreaders:
        flags.append("spreader")
    return FilmResult(type, plate, grid, colonies, bubbles, counts, estimates, used, flags)


def _own_radius(marks, fg, mask, threshold):
    """Each mark's own size: the distance-transform value at its centre. The
    detector gives the marks it splits out of one blob a shared radius, which
    would make a yeast touching a mold look as large as the mold."""
    from .classical import Colony
    binary = ((fg > threshold) & (mask > 0)).astype(np.uint8)
    dt = cv2.distanceTransform(binary, cv2.DIST_L2, 5)
    h, w = dt.shape
    out = []
    for c in marks:
        x, y = int(round(c.x)), int(round(c.y))
        r = float(dt[max(0, y - 1):min(h, y + 2), max(0, x - 1):min(w, x + 2)].max())
        out.append(Colony(c.x, c.y, max(1.0, min(c.radius_px, r)) if r > 0 else c.radius_px, c.n, c.score))
    return out


def _merge_split_molds(marks, mm):
    """A mold's diffuse body can give two marks inside its own radius: keep one."""
    out = []
    for c in sorted(marks, key=lambda c: -c.radius_px):
        big = c.radius_px * mm >= MOLD_MIN_RADIUS_MM
        if big and any(o.radius_px * mm >= MOLD_MIN_RADIUS_MM
                       and np.hypot(c.x - o.x, c.y - o.y) < 0.9 * o.radius_px for o in out):
            continue
        out.append(c)
    return out


def _yeasts_in_molds(fg, marks, mm, params):
    """Yeasts touching a mold merge into its diffuse edge. Find compact dots in
    a high-pass of the contrast inside each mold, away from its centre."""
    from .classical import Colony
    molds = [m for m in marks if m.radius_px * mm >= MOLD_MIN_RADIUS_MM]
    if not molds:
        return []
    hp = np.maximum(fg - cv2.GaussianBlur(fg, (0, 0), 0.5 / mm), 0).astype(np.float32)
    region = np.zeros(fg.shape, np.uint8)
    for m in molds:
        cv2.circle(region, (round(m.x), round(m.y)), round(m.radius_px * 1.3), 255, -1)
    found = detect(hp, region, mm, params).colonies
    out = []
    for c in found:
        if c.radius_px * mm >= MOLD_MIN_RADIUS_MM:
            continue
        if any(np.hypot(c.x - m.x, c.y - m.y) < 0.5 * m.radius_px for m in molds):
            continue
        if any(np.hypot(c.x - o.x, c.y - o.y) < max(o.radius_px, c.radius_px)
               for o in marks if o.radius_px * mm < MOLD_MIN_RADIUS_MM):
            continue
        out.append(Colony(c.x, c.y, c.radius_px, 1, c.score))
    return out


def _clean_marks(colonies, bubbles, mm):
    """Drop specks on a bubble's dark outline, and merge marks that coincide."""
    out = []
    for c in sorted(colonies, key=lambda c: -c.radius_px):
        if c.radius_px * mm < 0.3 and any(abs(np.hypot(c.x - bx, c.y - by) - br) < 0.25 / mm
                                          for bx, by, br in bubbles):
            continue
        if any(np.hypot(c.x - o.x, c.y - o.y) < 0.5 * o.radius_px for o in out):
            continue
        out.append(c)
    return out


def _disc_mean(lab, x, y, r):
    h, w = lab.shape[:2]
    x0, x1 = max(0, int(x - r)), min(w, int(x + r) + 1)
    y0, y1 = max(0, int(y - r)), min(h, int(y + r) + 1)
    yy, xx = np.mgrid[y0:y1, x0:x1]
    m = np.hypot(xx - x, yy - y) <= r
    if not m.any():
        return lab[int(y), int(x)]
    return lab[y0:y1, x0:x1][m].mean(axis=0)


def _disc_mean_ch(ch, x, y, r):
    return float(_disc_mean(ch[..., None], x, y, max(r, 1.0))[0])


def _ring_mean(ch, x, y, r0, r1):
    h, w = ch.shape
    x0, x1 = max(0, int(x - r1)), min(w, int(x + r1) + 1)
    y0, y1 = max(0, int(y - r1)), min(h, int(y + r1) + 1)
    yy, xx = np.mgrid[y0:y1, x0:x1]
    d = np.hypot(xx - x, yy - y)
    m = (d >= r0) & (d <= r1)
    return float(ch[y0:y1, x0:x1][m].mean()) if m.any() else 0.0


def _complete_squares(grid: Grid, plate: Plate) -> list[tuple[int, int]]:
    """Grid squares (i, j) lying wholly inside the counted area."""
    gx, gy = grid.to_grid(plate.cx, plate.cy)
    n = int(plate.radius / grid.pitch_px) + 2
    i0 = int(np.floor((gx - grid.ox) / grid.pitch_px))
    j0 = int(np.floor((gy - grid.oy) / grid.pitch_px))
    out = []
    for i in range(i0 - n, i0 + n + 1):
        for j in range(j0 - n, j0 + n + 1):
            corners = [(grid.ox + (i + a) * grid.pitch_px, grid.oy + (j + b) * grid.pitch_px)
                       for a in (0, 1) for b in (0, 1)]
            if all(np.hypot(*(np.array(grid.to_image(cx, cy)) - [plate.cx, plate.cy]))
                   < plate.radius * 0.95 for cx, cy in corners):
                out.append((i, j))
    return out


def _in_square(grid: Grid, sq, x, y) -> bool:
    gx, gy = grid.to_grid(x, y)
    i = np.floor((gx - grid.ox) / grid.pitch_px)
    j = np.floor((gy - grid.oy) / grid.pitch_px)
    return (int(i), int(j)) == tuple(sq)


def draw_film(image: np.ndarray, res: FilmResult) -> np.ndarray:
    out = image.copy()
    p = res.plate
    th = max(1, round(p.radius / 250))
    cv2.circle(out, (round(p.cx), round(p.cy)), round(p.radius), (255, 200, 0), th)
    colours = {"colony": (0, 220, 0), "red": (0, 220, 255), "blue": (255, 120, 0),
               "yeast": (0, 220, 0), "mold": (255, 0, 255)}
    for c in res.colonies:
        col = colours[c.kind]
        cv2.circle(out, (round(c.x), round(c.y)), round(c.radius_px * 1.4) + 2, col, th)
        if c.gas:
            cv2.circle(out, (round(c.x), round(c.y)), round(c.radius_px * 1.4) + 5, (255, 255, 255), th)
        if c.yellow:
            cv2.circle(out, (round(c.x), round(c.y)), round(c.radius_px * 1.4) + 8, (0, 255, 255), th)
    for x, y, r in res.bubbles:
        cv2.circle(out, (round(x), round(y)), max(2, round(r)), (200, 200, 200), 1)
    return out
