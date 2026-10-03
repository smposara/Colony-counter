"""Turn plate counts into CFU/mL (or CFU/g) following common counting rules.

Pooled (weighted-mean) estimate over the countable plates:

    N = ΣC / Σ(V_i × d_i)

where C is the colonies on each retained plate, V_i the plated volume in mL and
d_i the dilution of that plate (e.g. 1e-4). For two successive tenfold dilutions
this equals the ISO 7218 form N = ΣC / (V × (n1 + 0.1·n2) × d).
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

# Countable range per plate (inclusive). Check against your lab SOP.
PRESETS: dict[str, tuple[int, int]] = {
    "FDA_BAM": (25, 250),
    "ISO_7218": (10, 300),
    "30_300": (30, 300),
}


@dataclass(frozen=True)
class PlateCount:
    count: int
    dilution: float  # e.g. 1e-4 for the 10^-4 tube
    volume_ml: float = 0.1
    spreader: bool = False
    tntc: bool = False  # too numerous to count; ``count`` is a lower bound


@dataclass
class Estimate:
    value: float  # CFU per mL of the original sample (before the sample-prep factor)
    qualifier: str  # "", "<", ">" or "~" (estimated)
    rule: str
    plates_used: list[PlateCount] = field(default_factory=list)
    note: str = ""

    @property
    def estimated(self) -> bool:
        return self.qualifier != ""

    def __str__(self) -> str:
        q = {"": "", "~": "est. ", "<": "< ", ">": "> "}[self.qualifier]
        return f"{q}{format_sci(self.value)} CFU/mL"


def cfu_per_ml(count: float, dilution: float, volume_ml: float) -> float:
    if dilution <= 0 or volume_ml <= 0:
        raise ValueError("dilution and volume_ml must be positive")
    return count / (volume_ml * dilution)


def round_sig(x: float, sig: int = 2) -> float:
    if x == 0 or not math.isfinite(x):
        return x
    return round(x, sig - 1 - int(math.floor(math.log10(abs(x)))))


def format_sci(x: float, sig: int = 2) -> str:
    if x == 0:
        return "0"
    exp = int(math.floor(math.log10(abs(x))))
    mant = round_sig(x, sig) / 10**exp
    if abs(mant) >= 10:  # rounding carried over, e.g. 9.96 -> 10
        mant /= 10
        exp += 1
    return f"{mant:.{sig - 1}f} × 10^{exp}"


def estimate(
    plates: list[PlateCount],
    rule: str = "FDA_BAM",
    countable: tuple[int, int] | None = None,
    sample_factor: float = 1.0,
) -> Estimate:
    """CFU/mL from one or more plates of a dilution series.

    ``sample_factor`` converts to the original sample, e.g. 10 if 10 g were
    homogenised in 90 mL and you want CFU/g (only if not already in ``dilution``).
    """
    lo, hi = countable or PRESETS[rule]
    usable = [p for p in plates if not p.spreader]
    if not usable:
        return Estimate(float("nan"), "~", rule, [], "all plates have spreaders")

    in_range = [p for p in usable if lo <= p.count <= hi and not p.tntc]
    if in_range:
        total = sum(p.count for p in in_range)
        denom = sum(p.volume_ml * p.dilution for p in in_range)
        return Estimate(round_sig(total / denom * sample_factor), "", rule, in_range)

    above = [p for p in usable if p.count > hi or p.tntc]
    below = [p for p in usable if p.count < lo and not p.tntc]

    if below and not above:
        # Use the least diluted plate (largest expected count).
        p = max(below, key=lambda p: p.volume_ml * p.dilution)
        if p.count == 0:
            v = cfu_per_ml(1, p.dilution, p.volume_ml) * sample_factor
            return Estimate(round_sig(v), "<", rule, [p], "no colonies on least diluted plate")
        v = cfu_per_ml(p.count, p.dilution, p.volume_ml) * sample_factor
        return Estimate(round_sig(v), "~", rule, [p], f"below countable range ({lo}-{hi})")

    if above and not below:
        # Use the most diluted plate (smallest expected count).
        p = min(above, key=lambda p: p.volume_ml * p.dilution)
        v = cfu_per_ml(p.count, p.dilution, p.volume_ml) * sample_factor
        if p.tntc:
            return Estimate(round_sig(v), ">", rule, [p], "too numerous to count")
        return Estimate(round_sig(v), "~", rule, [p], f"above countable range ({lo}-{hi})")

    # Neighbouring dilutions straddle the range: take the count closest to it.
    def gap(p: PlateCount) -> float:
        return lo - p.count if p.count < lo else p.count - hi

    p = min(usable, key=gap)
    v = cfu_per_ml(p.count, p.dilution, p.volume_ml) * sample_factor
    return Estimate(round_sig(v), "~", rule, [p], "no plate in countable range")
