"""Drop-plate statistics: the per-dilution drop table and CFU/mL.

For each dilution: the drop counts, mean, SD and the index of dispersion (VMR). Drops of a
well-mixed suspension are Poisson, so χ² = Σ(x − x̄)²/x̄ with N − 1 degrees of freedom tests
whether they agree (Miles & Misra 1938). Then CFU/mL:

- ``pooled``: ΣC / Σ(V·d) over the drops inside the counting window (the app's rule today);
- ``first``: the mean of the first (least diluted) countable dilution ÷ (V·d), as most
  protocols do.

Both give a Poisson 95 % interval from the total count (Garwood) and a "<" detection limit
of 1 / (N·V·d) over all drops of the least diluted dilution when nothing grew.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np
from scipy import stats

WINDOW = (3, 30)  # colonies per drop (10 µL drops; Naghili et al. 2013)
OVERDISPERSED_P = 0.01
OUTLIER_Z = 3.0
TENFOLD = (3.0, 30.0)  # acceptable ratio of means of neighbouring dilutions


@dataclass(frozen=True)
class DropCount:
    dilution_exp: int
    replicate: int
    count: int
    tntc: bool = False  # confluent or marked too numerous
    excluded: bool = False  # left out by the user


@dataclass
class DilutionRow:
    dilution_exp: int
    counts: list[int]  # usable drops (not excluded, not TNTC)
    tntc: int  # drops too numerous to count
    excluded: int
    mean: float
    sd: float
    vmr: float  # variance / mean (index of dispersion)
    chi2: float
    p: float  # dispersion test p-value (1.0 when it cannot be computed)
    outliers: list[int] = field(default_factory=list)  # indices into ``counts``
    flags: list[str] = field(default_factory=list)

    @property
    def total(self) -> int:
        return int(sum(self.counts))


def dilution_table(drops: list[DropCount]) -> list[DilutionRow]:
    rows = []
    for d in sorted({x.dilution_exp for x in drops}):
        mine = [x for x in drops if x.dilution_exp == d]
        cs = [x.count for x in mine if not x.excluded and not x.tntc]
        n_t = sum(1 for x in mine if x.tntc and not x.excluded)
        n_e = sum(1 for x in mine if x.excluded)
        a = np.array(cs, float)
        mean = float(a.mean()) if a.size else 0.0
        sd = float(a.std(ddof=1)) if a.size > 1 else 0.0
        vmr = sd**2 / mean if mean > 0 and a.size > 1 else 1.0
        chi2 = float(((a - mean) ** 2).sum() / mean) if mean > 0 and a.size > 1 else 0.0
        p = float(stats.chi2.sf(chi2, a.size - 1)) if mean > 0 and a.size > 1 else 1.0
        row = DilutionRow(d, cs, n_t, n_e, mean, sd, vmr, chi2, p)
        if a.size >= 3 and p < OVERDISPERSED_P:
            row.flags.append("overdispersed")
        if mean > 0 and a.size >= 3:
            for i, x in enumerate(cs):
                rest = np.delete(a, i)
                m = rest.mean()
                if m > 0 and abs(x - m) / np.sqrt(m) > OUTLIER_Z:
                    row.outliers.append(i)
            if row.outliers:
                row.flags.append("outlier_drop")
        rows.append(row)
    # Neighbouring dilutions should differ about tenfold.
    for a_row, b_row in zip(rows, rows[1:]):
        if a_row.tntc or b_row.tntc or a_row.total < 5 or b_row.total < 5:
            continue
        step = 10.0 ** (b_row.dilution_exp - a_row.dilution_exp)
        ratio = a_row.mean / b_row.mean / step * 10
        if not TENFOLD[0] <= ratio <= TENFOLD[1]:
            a_row.flags.append("not_tenfold")
    return rows


@dataclass
class DropEstimate:
    cfu_per_ml: float
    qualifier: str  # "exact", "estimated", "<" or ">"
    low: float  # 95 % interval
    high: float
    dilutions_used: list[int]
    drops_used: int
    note: str = ""


def estimate_drops(rows: list[DilutionRow], volume_ul: float, mode: str = "pooled",
                   window: tuple[int, int] = WINDOW) -> DropEstimate:
    lo, hi = window
    v = volume_ul / 1000

    def make(total, vd, dils, n, qual, note=""):
        lo_c = stats.chi2.ppf(0.025, 2 * total) / 2 if total > 0 else 0.0
        hi_c = stats.chi2.ppf(0.975, 2 * total + 2) / 2
        return DropEstimate(total / vd, qual, lo_c / vd, hi_c / vd, dils, n, note)

    usable = [r for r in rows if r.counts or r.tntc]
    if not usable:
        return DropEstimate(float("nan"), "estimated", float("nan"), float("nan"), [], 0, "no drops")
    if mode == "first":
        for r in usable:
            if not r.tntc and r.counts and lo <= r.mean <= hi:
                n = len(r.counts)
                return make(r.total, n * v * 10.0 ** -r.dilution_exp, [r.dilution_exp], n, "exact")
    else:
        total, vd, dils, n = 0, 0.0, [], 0
        for r in usable:
            inside = [c for c in r.counts if lo <= c <= hi]
            if inside:
                total += sum(inside)
                vd += len(inside) * v * 10.0 ** -r.dilution_exp
                dils.append(r.dilution_exp)
                n += len(inside)
        if n:
            return make(total, vd, dils, n, "exact")
    # Nothing in the window.
    below = all(not r.tntc and all(c < lo for c in r.counts) for r in usable)
    if below:
        r = usable[0]  # least diluted
        n = len(r.counts)
        vd = n * v * 10.0 ** -r.dilution_exp
        if r.total == 0:
            e = make(0, vd, [r.dilution_exp], n, "<", "no colonies in any drop")
            e.cfu_per_ml = 1 / vd
            return e
        return make(r.total, vd, [r.dilution_exp], n, "estimated", f"below the counting window ({lo}–{hi})")
    # The series straddles the window (a dilution above it, the next below):
    # the dilution whose mean is closest to it on a ratio scale (36 per drop is
    # nearer 30 than 0.7 is to 3, and far more precise).
    rows_below = [r for r in usable if not r.tntc and r.counts and r.mean < lo]
    if rows_below and len(rows_below) < len(usable):
        def gap(r):
            if r.mean <= 0:
                return float("inf")
            return np.log(lo / r.mean) if r.mean < lo else (np.log(r.mean / hi) if r.mean > hi else 0.0)
        r = min((r for r in usable if r.counts and not r.tntc), key=gap)
        n = len(r.counts)
        return make(r.total, n * v * 10.0 ** -r.dilution_exp, [r.dilution_exp], n, "estimated",
                    f"no dilution in the counting window ({lo}–{hi})")
    r = usable[-1]  # most diluted
    if r.tntc or not r.counts:
        n = r.tntc + len(r.counts)
        e = make(hi * n, n * v * 10.0 ** -r.dilution_exp, [r.dilution_exp], n, ">", "too numerous to count")
        return e
    n = len(r.counts)
    return make(r.total, n * v * 10.0 ** -r.dilution_exp, [r.dilution_exp], n, "estimated",
                f"above the counting window ({lo}–{hi})")


def drop_counts(result) -> list[DropCount]:
    """The drops of a ``drops.DropResult`` as counts."""
    return [DropCount(d.dilution_exp, d.replicate, d.count, d.tntc) for d in result.drops]
