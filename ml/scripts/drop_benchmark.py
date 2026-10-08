"""Drop-plate reference on synthetic plates: layout found and labelled, per-drop counts,
confluent drops and CFU/mL against the truth.

    python scripts/drop_benchmark.py --n 10
"""

import argparse
import json

import numpy as np

from colonycounter.drop_stats import dilution_table, drop_counts, estimate_drops, DropCount, WINDOW
from colonycounter.drops import Layout, count_drop_plate, drop_diameter_mm
from colonycounter.synth_drops import make_drop_plate

CASES = {
    "sectors8": (Layout("sectors", n=8, ring_mm=25), list(range(3, 11))),
    "sectors6x2": (Layout("sectors", n=6, ring_mm=25, drops_per_dilution=2), [4, 5, 6]),
    "grid4x3": (Layout("grid", rows=4, cols=3, pitch_mm=12), [4, 5, 6, 7]),
    "grid5x5": (Layout("grid", rows=5, cols=5, pitch_mm=11), [3, 4, 5, 6, 7]),
}


def run(n: int, seed0: int) -> dict:
    out = {}
    for name, (layout, dils) in CASES.items():
        found = labelled = 0
        errs, conf_hit, conf_n, conf_false, cfu_err = [], 0, 0, 0, []
        for k in range(n):
            seed = seed0 + k
            rng = np.random.default_rng(seed)
            cfu = 10 ** rng.uniform(6.5, 8.5)
            over = 0.0 if k % 2 == 0 else 0.25
            s = make_drop_plate(layout, dils, cfu_per_ml=cfu, seed=seed, overdispersion=over)
            r = count_drop_plate(s.image, layout, dils)
            ok_pos = ok_lab = True
            for t in s.drops:
                d = min(r.drops, key=lambda q: np.hypot(q.x - t.x, q.y - t.y))
                if np.hypot(d.x - t.x, d.y - t.y) / s.px_per_mm > 0.4 * drop_diameter_mm(s.volume_ul):
                    ok_pos = False
                    continue
                # Which drop of a dilution is replicate 1 cannot be seen: dilution only.
                if d.dilution_exp != t.dilution_exp:
                    ok_lab = False
                if t.confluent:
                    conf_n += 1
                    conf_hit += d.confluent
                elif d.confluent:
                    # A drop with more than the window is uncountable anyway.
                    conf_false += t.count <= WINDOW[1]
                elif WINDOW[0] <= t.count <= WINDOW[1]:
                    errs.append(d.count - t.count)
            found += ok_pos and len(r.drops) == len(s.drops)
            labelled += ok_pos and ok_lab
            truth = estimate_drops(dilution_table(
                [DropCount(t.dilution_exp, t.replicate, t.count, t.confluent) for t in s.drops]), s.volume_ul)
            est = estimate_drops(dilution_table(drop_counts(r)), s.volume_ul)
            if truth.qualifier == "exact" and np.isfinite(est.cfu_per_ml):
                cfu_err.append(abs(est.cfu_per_ml / truth.cfu_per_ml - 1) * 100)
        e = np.abs(np.array(errs)) if errs else np.zeros(1)
        out[name] = {
            "plates": n,
            "layout_found": found / n,
            "labels_correct": labelled / n,
            "drops_in_window": len(errs),
            "count_within_2_or_10pct": float(np.mean([abs(x) <= 2 or abs(x) <= 0.1 * 30 for x in errs])) if errs else None,
            "count_mean_abs_err": float(e.mean()),
            "count_bias": float(np.mean(errs)) if errs else 0.0,
            "confluent_recall": conf_hit / conf_n if conf_n else None,
            "confluent_false": conf_false,
            "cfu_mean_abs_pct_vs_truth_counts": float(np.mean(cfu_err)) if cfu_err else None,
        }
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=10)
    ap.add_argument("--seed0", type=int, default=100)
    print(json.dumps(run(**vars(ap.parse_args())), indent=1))
