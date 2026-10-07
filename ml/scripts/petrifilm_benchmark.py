"""Accuracy of the Petrifilm counter on random synthetic films.

Per plate type: films at random angles (±15°), scales (9–15 px/mm), densities
within the counting range, lighting and noise; plus crowded Aerobic Count
films that need the square-based estimate. Run from ml/:

    python scripts/petrifilm_benchmark.py --n 10
"""

import argparse
import json
import warnings

import numpy as np

from colonycounter.petrifilm import TYPES, count_petrifilm
from colonycounter.synth_petrifilm import make_film

DENSITY = {"ac": (30, 200), "ec": (20, 110), "cc": (20, 110), "eb": (20, 90), "ym": (20, 80)}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=10)
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()
    warnings.filterwarnings("ignore")
    rng = np.random.default_rng(args.seed)
    report = {}
    for t in TYPES:
        errs, rows = [], []
        for i in range(args.n):
            s = make_film(t, n=int(rng.integers(*DENSITY[t])), seed=100 * i + len(t),
                          px_per_mm=float(rng.uniform(9, 15)), angle_deg=float(rng.uniform(-15, 15)),
                          gradient=float(rng.uniform(0, 0.25)))
            r = count_petrifilm(s.image, t)
            truth = s.truth()
            for k, v in truth.items():
                got = r.values[k]
                errs.append(abs(got - v) / max(v, 1))
                rows.append((k, v, round(got, 1)))
        e = np.array(errs)
        report[t] = {"results": len(e), "mean_abs_pct": round(100 * e.mean(), 1),
                     "within_10pct": round(float(np.mean(e <= 0.10)), 3),
                     "worst": sorted(rows, key=lambda r: -abs(r[2] - r[1]) / max(r[1], 1))[:3]}
    est = []
    for i in range(max(3, args.n // 2)):
        s = make_film("ac", n=int(rng.integers(500, 900)), seed=900 + i, px_per_mm=12.0,
                      angle_deg=float(rng.uniform(-10, 10)))
        r = count_petrifilm(s.image, "ac")
        true_total = s.truth()["aerobic"]
        est.append((true_total, round(r.values["aerobic"]), "estimated" in r.flags, r.squares_used))
    report["ac_crowded_estimate"] = {"true_vs_estimate": est,
                                     "mean_abs_pct": round(100 * float(np.mean([abs(b - a) / a for a, b, *_ in est])), 1)}
    print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
