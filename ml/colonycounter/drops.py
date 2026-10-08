"""Drop plates (Miles–Misra / spot plates): finding, labelling and counting drops.

    photo → plate → colonies (classical detector) and the foreground
          → drop candidates: groups of nearby colonies, plus confluent lawns
          → layout fit: the planned template (sectors or a grid), turned, moved and
            scaled onto the candidates, gives every planned drop, empty ones included
          → labels: which way round the layout lies is chosen by how well the
            counts follow the tenfold dilution series (Poisson likelihood)
          → per drop: colonies inside, confluent / crowded flags; colonies outside
            every drop are reported as strays and not counted

See docs/DROP_PLATE_IMPLEMENTATION.md. Statistics and CFU/mL: drop_stats.py.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import cv2
import numpy as np

from .classical import Colony, DetectParams, detect
from .normalize import estimate_background, foreground, to_gray
from .plate import DEFAULT_PLATE_DIAMETER_MM, Plate, find_plate

REFERENCE_DROP_MM = 7.0  # a 10 µL drop on dried agar
CONFLUENT_COVER = 0.6  # foreground over this fraction of the drop: confluent
CROWDED_COVER = 0.35  # colonies over this fraction of the drop: crowded
MAX_ANCHORS = 40  # candidates that propose layout translations


@dataclass(frozen=True)
class Layout:
    """How drops were placed. ``sectors``: ``n`` drops on a ring of ``ring_mm``,
    clockwise from the top, ``drops_per_dilution`` consecutive drops per dilution.
    ``grid``: ``rows`` × ``cols`` drops ``pitch_mm`` apart, a row per dilution and a
    column per replicate. ``free``: no template (drops are the colony groups)."""

    kind: str = "sectors"
    n: int = 8
    ring_mm: float = 25.0
    drops_per_dilution: int = 1
    rows: int = 4
    cols: int = 3
    pitch_mm: float = 11.0


def drop_diameter_mm(volume_ul: float) -> float:
    """Expected drop footprint: 7 mm for 10 µL, scaling with the cube root of the
    volume (5 µL → 5.6 mm, 20 µL → 8.8 mm)."""
    return REFERENCE_DROP_MM * (volume_ul / 10.0) ** (1 / 3)


def layout_positions_mm(layout: Layout, dilutions: list[int]):
    """Planned drops as (x_mm, y_mm, dilution_exp, replicate), relative to the
    layout centre, image axes (y down)."""
    out = []
    if layout.kind == "sectors":
        for k in range(layout.n):
            a = np.deg2rad(-90 + 360 * k / layout.n)
            dil = dilutions[min(k // max(1, layout.drops_per_dilution), len(dilutions) - 1)]
            out.append((layout.ring_mm * np.cos(a), layout.ring_mm * np.sin(a), dil,
                        k % max(1, layout.drops_per_dilution) + 1))
    elif layout.kind == "grid":
        for r in range(layout.rows):
            for c in range(layout.cols):
                out.append(((c - (layout.cols - 1) / 2) * layout.pitch_mm,
                            (r - (layout.rows - 1) / 2) * layout.pitch_mm,
                            dilutions[min(r, len(dilutions) - 1)], c + 1))
    return out


@dataclass
class Candidate:
    x: float
    y: float
    radius_px: float
    n: int  # colonies in the group
    confluent: bool = False


@dataclass
class Drop:
    x: float
    y: float
    radius_px: float
    position: int | None  # index in the layout (None for a free drop)
    dilution_exp: int
    replicate: int
    count: int  # colonies inside (meaningless when confluent)
    confluent: bool = False
    crowded: bool = False
    colonies: list[int] = field(default_factory=list)  # indices into DropResult.colonies

    @property
    def tntc(self) -> bool:
        return self.confluent


@dataclass
class LayoutFit:
    rotation_deg: float
    scale: float  # fitted size / nominal size
    centre: tuple[float, float]  # image px
    matched: int  # candidates on a planned position
    outside: int  # candidates on no planned position


@dataclass
class DropResult:
    plate: Plate
    mm_per_px: float
    drops: list[Drop]
    colonies: list[Colony]
    strays: list[int]  # colonies in no drop
    fit: LayoutFit | None
    flags: list[str]


# ---------------------------------------------------------------------------
# Candidates


def _foreground(image, plate: Plate):
    gray = to_gray(image)
    mask = plate.mask(gray.shape, 0.95)
    # A wide background window, so a confluent drop is not absorbed into it.
    bg = estimate_background(gray, plate, kernel_mm=15.0)
    fg, polarity = foreground(gray, bg, mask, "auto")
    return fg, mask


def group_colonies(colonies: list[Colony], mm: float, diameter_mm: float) -> list[list[int]]:
    """Single-linkage groups: colonies whose gap is under 0.35 drop diameters."""
    link = 0.35 * diameter_mm / mm
    n = len(colonies)
    parent = list(range(n))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for i in range(n):
        ci = colonies[i]
        for j in range(i + 1, n):
            cj = colonies[j]
            if np.hypot(ci.x - cj.x, ci.y - cj.y) - ci.radius_px - cj.radius_px <= link:
                parent[find(i)] = find(j)
    groups: dict[int, list[int]] = {}
    for i in range(n):
        groups.setdefault(find(i), []).append(i)
    return list(groups.values())


def drop_candidates(colonies, binary, mm: float, diameter_mm: float) -> list[Candidate]:
    """Colony groups and confluent lawns, each as a circle about one drop across."""
    r_drop = diameter_mm / 2 / mm
    out: list[Candidate] = []
    for g in group_colonies(colonies, mm, diameter_mm):
        xs = np.array([colonies[i].x for i in g])
        ys = np.array([colonies[i].y for i in g])
        w = np.array([colonies[i].n for i in g], float)
        cx, cy = float(np.average(xs, weights=w)), float(np.average(ys, weights=w))
        out.append(Candidate(cx, cy, r_drop, int(w.sum())))
    # Confluent lawns: foreground filling most of a drop-sized disc.
    n_lab, labels, stats, cents = cv2.connectedComponentsWithStats(binary, connectivity=8)
    disc = np.pi * r_drop**2
    for k in range(1, n_lab):
        area = stats[k, cv2.CC_STAT_AREA]
        if area < CONFLUENT_COVER * disc * 0.8 or area > disc * 2.5:
            continue
        cx, cy = cents[k]
        if _cover(binary, cx, cy, r_drop) >= CONFLUENT_COVER:
            out = [c for c in out if np.hypot(c.x - cx, c.y - cy) > r_drop]
            out.append(Candidate(float(cx), float(cy), r_drop, 0, True))
    return out


def _single_colony_area(binary, colonies, min_n: int = 5) -> float | None:
    """Median pixel area of foreground blobs that hold exactly one single colony."""
    _, lab, st, _ = cv2.connectedComponentsWithStats(binary, connectivity=8)
    h, w = binary.shape
    per: dict[int, list] = {}
    for c in colonies:
        k = int(lab[min(h - 1, int(round(c.y))), min(w - 1, int(round(c.x)))])
        if k:
            per.setdefault(k, []).append(c)
    areas = [st[k, cv2.CC_STAT_AREA] for k, cs in per.items() if len(cs) == 1 and cs[0].n == 1]
    return float(np.median(areas)) if len(areas) >= min_n else None


def _cover(binary, x, y, r) -> float:
    h, w = binary.shape
    x0, x1 = max(0, int(x - r)), min(w, int(x + r) + 1)
    y0, y1 = max(0, int(y - r)), min(h, int(y + r) + 1)
    yy, xx = np.mgrid[y0:y1, x0:x1]
    m = np.hypot(xx - x, yy - y) <= r
    return float(binary[y0:y1, x0:x1][m].mean()) if m.any() else 0.0


# ---------------------------------------------------------------------------
# Layout fit


def fit_layout(cands: list[Candidate], layout: Layout, dilutions, plate: Plate, mm: float,
               diameter_mm: float, keep: float = 3.0) -> list[tuple[np.ndarray, LayoutFit, float]]:
    """Place the template on the candidates: rotation, translation and scale that put
    the most candidates on planned positions, inside the plate and near its centre.

    Returns every distinct refined placement scoring within ``keep`` of the best, as
    (positions P × 2 px, fit, score), best first: a layout shifted by one row can match
    nearly as many drops, and the caller chooses between them by the dilution series."""
    P = np.array([(p[0], p[1]) for p in layout_positions_mm(layout, dilutions)]) / mm
    C = np.array([(c.x, c.y) for c in cands]) if cands else np.zeros((0, 2))
    wts = np.array([1.0 if c.confluent else min(1.0, 0.3 + 0.25 * c.n) for c in cands])
    tol = 0.5 * diameter_mm / mm
    centre = np.array([plate.cx, plate.cy])
    r_ok = plate.radius * 0.92

    # Symmetry: a ring repeats every 360/n; a grid every 180° (90° when square).
    if layout.kind == "sectors":
        span, anchors = 360.0 / layout.n, [0]
    else:
        span = 90.0 if layout.rows == layout.cols else 180.0
        anchors = list(range(len(P)))

    def score(T):
        off = np.hypot(T[:, 0] - centre[0], T[:, 1] - centre[1])
        s = -2.0 * float((off > r_ok).sum())  # drops off the plate
        s -= 0.3 * float((np.linalg.norm(T.mean(axis=0) - centre) / (0.25 * plate.radius)) ** 2)
        if len(C):
            d = np.linalg.norm(T[:, None, :] - C[None, :, :], axis=2)
            near = d.min(axis=0)
            s += float((wts * (near < tol)).sum() - 0.2 * (np.minimum(near, tol) / tol * wts).sum())
        return s

    def rot(th):
        r = np.deg2rad(th)
        return np.array([[np.cos(r), -np.sin(r)], [np.sin(r), np.cos(r)]])

    # Translations come from the strongest candidates only, so a photo with
    # many specks does not blow up the search (candidates x positions x angles).
    strong = sorted(range(len(C)), key=lambda i: (-wts[i], -cands[i].n, i))[:MAX_ANCHORS]
    hyps = []
    for th in np.arange(0, span, 3.0):
        RP = P @ rot(th).T
        for t in [centre] + [C[i] - RP[j] for i in strong for j in anchors]:
            hyps.append((score(RP + t), th, t))
    hyps.sort(key=lambda h: -h[0])
    top = hyps[0][0]

    out: list[tuple[np.ndarray, LayoutFit, float]] = []
    for sc, th, t in hyps:
        if sc < top - keep - 1.0 or len(out) >= 8:
            break
        Rm, scale = rot(th), 1.0
        T = P @ Rm.T + t
        # Refine: similarity transform (Procrustes) on matched pairs, twice.
        for _ in range(2):
            pairs = _match(T, C, tol)
            if len(pairs) < 2:
                break
            s_, Rm2, t2 = _procrustes(P[[p for p, _ in pairs]], C[[c for _, c in pairs]])
            if not 0.8 < s_ < 1.25:
                break
            T, scale, Rm = (P @ Rm2.T) * s_ + t2, s_, Rm2
        sc = score(T)
        if any(np.abs(T - o[0]).max() < tol for o in out):
            continue  # the same placement again
        pairs = _match(T, C, tol)
        r_deg = float(np.rad2deg(np.arctan2(Rm[1, 0], Rm[0, 0])))
        out.append((T, LayoutFit(r_deg, float(scale), tuple(T.mean(axis=0)), len(pairs),
                                 len(C) - len(pairs)), sc))
    out.sort(key=lambda o: -o[2])
    best = out[0][2]
    return [o for o in out if o[2] >= best - keep]


def _match(T, C, tol):
    """Greedy one-to-one pairs (position, candidate) closer than ``tol``."""
    if len(C) == 0:
        return []
    d = np.linalg.norm(T[:, None, :] - C[None, :, :], axis=2)
    pairs, used_p, used_c = [], set(), set()
    for k in np.argsort(d, axis=None):
        p, c = divmod(int(k), d.shape[1])
        if d[p, c] >= tol:
            break
        if p in used_p or c in used_c:
            continue
        pairs.append((p, c))
        used_p.add(p)
        used_c.add(c)
    return pairs


def _procrustes(src, dst):
    """Scale, rotation and translation with dst ≈ s·R·src + t (least squares)."""
    ms, md = src.mean(axis=0), dst.mean(axis=0)
    a, b = src - ms, dst - md
    u, sig, vt = np.linalg.svd(b.T @ a)
    d = np.sign(np.linalg.det(u @ vt))
    D = np.diag([1, d])
    R = u @ D @ vt
    s = float((sig * np.diag(D)).sum() / max((a**2).sum(), 1e-9))
    return s, R, md - s * (R @ ms)


# ---------------------------------------------------------------------------
# Labels


def _orientations(layout: Layout) -> list[list[int]]:
    """Ways the planned positions can be relabelled without moving them: a ring can
    start at any drop and run either way; a grid can be the other way up."""
    if layout.kind == "sectors":
        n = layout.n
        return [[(s + k) % n for k in range(n)] for s in range(n)] + \
               [[(s - k) % n for k in range(n)] for s in range(n)]
    rows, cols = layout.rows, layout.cols
    idx = lambda r, c: r * cols + c  # noqa: E731
    out = [[idx(r, c) for r in range(rows) for c in range(cols)],
           [idx(rows - 1 - r, c) for r in range(rows) for c in range(cols)],
           [idx(r, cols - 1 - c) for r in range(rows) for c in range(cols)],
           [idx(rows - 1 - r, cols - 1 - c) for r in range(rows) for c in range(cols)]]
    if rows == cols:
        # A square grid can also lie a quarter turn round: rows become columns.
        out += [[idx(c, r) for r in range(rows) for c in range(cols)],
                [idx(cols - 1 - c, r) for r in range(rows) for c in range(cols)],
                [idx(c, rows - 1 - r) for r in range(rows) for c in range(cols)],
                [idx(cols - 1 - c, rows - 1 - r) for r in range(rows) for c in range(cols)]]
    return out


def _dilution_loglik(counts, dils, volume_ml, confluent, cap=200):
    """Poisson log-likelihood of the counts for one density (its best value), with
    confluent drops taken as ``cap`` colonies."""
    x = np.array([cap if f else c for c, f in zip(counts, confluent)], float)
    v = volume_ml * 10.0 ** -np.array(dils, float)
    lam = x.sum() / v.sum() if x.sum() > 0 else 0.0
    mu = np.maximum(lam * v, 1e-12)
    return float((x * np.log(mu) - mu).sum())


# ---------------------------------------------------------------------------
# Whole plate


def count_drop_plate(image: np.ndarray, layout: Layout, dilutions: list[int], volume_ul: float = 10.0,
                     plate: Plate | None = None, plate_diameter_mm: float = DEFAULT_PLATE_DIAMETER_MM,
                     diameter_mm: float | None = None) -> DropResult:
    if plate is None:
        plate = find_plate(image, diameter_mm=plate_diameter_mm)
    mm = plate.mm_per_px
    diameter_mm = diameter_mm or drop_diameter_mm(volume_ul)
    fg, mask = _foreground(image, plate)
    det = detect(fg, mask, mm, DetectParams(min_diameter_mm=0.2))
    binary = ((fg > det.threshold) & (mask > 0)).astype(np.uint8)
    colonies = det.colonies
    cands = drop_candidates(colonies, binary, mm, diameter_mm)
    r_drop = diameter_mm / 2 / mm
    flags: list[str] = []

    def assign(T):
        """Colonies to their nearest drop (within 1.1 drop radii); the rest are strays."""
        owner = np.full(len(colonies), -1)
        if len(T):
            for i, c in enumerate(colonies):
                d = np.hypot(T[:, 0] - c.x, T[:, 1] - c.y)
                k = int(np.argmin(d))
                if d[k] <= r_drop * 1.1:
                    owner[i] = k
        conf = [any(c.confluent and np.hypot(c.x - x, c.y - y) < r_drop for c in cands) for x, y in T]
        counts = [int(sum(colonies[i].n for i in np.flatnonzero(owner == k))) for k in range(len(T))]
        return owner, conf, counts

    if layout.kind == "free":
        cands.sort(key=lambda c: (round(c.y / (2 * r_drop)), c.x))
        T = np.array([(c.x, c.y) for c in cands]).reshape(-1, 2)
        plan = [(0.0, 0.0, dilutions[min(k, len(dilutions) - 1)], 1) for k in range(len(T))]
        fit = None
        owner, conf, counts = assign(T)
        order = list(range(len(T)))
    else:
        plan = layout_positions_mm(layout, dilutions)
        # Among placements that fit about equally well, the one (and the way round)
        # whose counts best follow the dilution series.
        best = None
        for T_, fit_, sc in fit_layout(cands, layout, dilutions, plate, mm, diameter_mm):
            owner_, conf_, counts_ = assign(T_)
            for o in _orientations(layout):
                ll = _dilution_loglik([counts_[k] for k in o], [plan[p][2] for p in range(len(o))],
                                      volume_ul / 1000, [conf_[k] for k in o])
                if best is None or ll > best[0] + 1e-9:
                    best = (ll, T_, fit_, owner_, conf_, counts_, o)
        _, T, fit, owner, conf, counts, order = best
        if fit.outside > 0:
            flags.append("colonies_outside_drops")
        # Few strong groups on planned positions, or more colonies between the
        # drops than there are drops (specks or contamination can pull the
        # layout off by a row): check the drops by eye.
        if (fit.matched < max(1, len([c for c in cands if c.n >= 3 or c.confluent]) // 2)
                or int((owner < 0).sum()) > len(T)):
            flags.append("layout_uncertain")

    # Merged colonies in a crowded drop are undercounted by the detector: also count
    # them by area (colony pixels ÷ the pixels of a typical isolated colony) and keep the larger.
    unit = _single_colony_area(binary, colonies)
    disc = np.pi * r_drop**2
    drops: list[Drop] = []
    for slot, k in enumerate(order):
        x, y = T[k]
        members = [int(i) for i in np.flatnonzero(owner == k)]
        cover = _cover(binary, x, y, r_drop)
        crowded = (not conf[k]) and (cover > CROWDED_COVER or any(colonies[i].n >= 3 for i in members))
        count = counts[k]
        if crowded and unit:
            count = max(count, int(round(cover * disc / unit)))
        _, _, dil, rep = plan[slot]
        drops.append(Drop(float(x), float(y), r_drop, slot if fit else None, dil, rep, count,
                          conf[k], crowded, members))
    # Which drop of a dilution is "replicate 1" cannot be seen on the plate: number
    # them in reading order (rows of one drop diameter, then left to right).
    for dil in {d.dilution_exp for d in drops}:
        same = sorted((d for d in drops if d.dilution_exp == dil),
                      key=lambda d: (round(d.y / (2 * r_drop)), d.x))
        for i, d in enumerate(same):
            d.replicate = i + 1
    drops.sort(key=lambda d: (d.position if d.position is not None else 0, d.y, d.x))
    strays = [int(i) for i in np.flatnonzero(owner < 0)]
    return DropResult(plate, mm, drops, colonies, strays, fit, flags)
