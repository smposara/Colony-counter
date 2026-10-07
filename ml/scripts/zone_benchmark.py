"""Accuracy of the zone detector on random synthetic plates.

Mixes both lightings, disks and wells, sharp and hazy edges, colonies inside
zones, 1–6 disks on 90 mm dishes and 12 disks on 150 mm dishes. Prints the
summary and every zone off by more than 1 mm. Run from ml/:

    python scripts/zone_benchmark.py --n 60
"""

import argparse
import json
import warnings

import numpy as np

from colonycounter.metrics import match_zones, zone_metrics
from colonycounter.synth_zones import make_zone_plate
from colonycounter.zones import measure_plate


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=60)
    ap.add_argument("--seed", type=int, default=123)
    args = ap.parse_args()
    warnings.filterwarnings("ignore")
    rng = np.random.default_rng(args.seed)
    preds, trues, worst = [], [], []
    missed = extra = unmeasured = 0
    for i in range(args.n):
        big = i % 10 == 9
        kw = dict(seed=1000 + i,
                  n_disks=12 if big else int(rng.integers(1, 7)),
                  plate_mm=150.0 if big else 90.0,
                  lighting=str(rng.choice(["reflected", "backlit"])),
                  assay=str(rng.choice(["disk", "disk", "well"])),
                  edge_mm=(0.1, 0.3) if rng.random() < 0.6 else (0.5, 1.2),
                  colonies_in_zones=int(rng.integers(0, 6)),
                  gradient=float(rng.uniform(0, 0.4)))
        if kw["assay"] == "well":
            kw["disk_mm"] = float(rng.choice([6.0, 8.0]))
        s = make_zone_plate(**kw)
        r = measure_plate(s.image, plate_diameter_mm=s.plate.diameter_mm, assay=s.assay, disk_mm=s.disk_mm)
        pairs = match_zones([[z.x, z.y] for z in r.zones], [[t.x, t.y] for t in s.zones],
                            2 / s.plate.mm_per_px)
        missed += len(s.zones) - len(pairs)
        extra += len(r.zones) - len(pairs)
        for pi, ti in pairs:
            z, t = r.zones[pi], s.zones[ti]
            if z.diameter_rounded is None:
                unmeasured += 1
                continue
            preds.append(float(z.diameter_mm))
            trues.append(t.diameter_mm)
            if abs(preds[-1] - trues[-1]) > 1:
                worst.append({"plate": i, "true": round(t.diameter_mm, 1), "measured": round(preds[-1], 1),
                              "flags": z.flags, "lighting": kw["lighting"], "assay": kw["assay"],
                              "edge_mm": kw["edge_mm"]})
    summary = zone_metrics(preds, trues)
    summary.update({"plates": args.n, "missed_disks": missed, "extra_disks": extra, "unmeasured": unmeasured})
    print(json.dumps(summary, indent=2))
    for w in worst:
        print(w)


if __name__ == "__main__":
    main()
