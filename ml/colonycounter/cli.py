"""Command line: count plates, evaluate against labels, make synthetic test plates.

    colonycounter count photos/*.jpg --overlay out/
    colonycounter evaluate data/labelled/
    colonycounter synth out/ --n 20
    colonycounter zones photos/*.jpg --assay disk --overlay out/
    colonycounter evaluate-zones data/zones_labelled/
    colonycounter synth-zones out/ --n 20
    colonycounter petrifilm photos/*.jpg --type ec --overlay out/
    colonycounter evaluate-petrifilm data/petrifilm_labelled/
    colonycounter synth-petrifilm out/ --type ec --n 10
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import cv2
import numpy as np

from .metrics import count_metrics, match_points, match_zones, zone_metrics
from .pipeline import count_colonies, draw_overlay
from .synth import make_plate
from .petrifilm import TYPES as FILM_TYPES, count_petrifilm, draw_film
from .synth_petrifilm import make_film
from .synth_zones import make_zone_plate
from .zones import draw_zones, measure_plate

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".tif", ".tiff", ".bmp"}


def _read(path: Path) -> np.ndarray:
    img = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if img is None:
        raise SystemExit(f"Cannot read image: {path}")
    return img


def cmd_count(args) -> int:
    rows = []
    for path in map(Path, args.images):
        img = _read(path)
        res = count_colonies(img, plate_diameter_mm=args.plate_mm, rim_fraction=args.rim,
                             polarity=args.polarity)
        rows.append({"image": str(path), **res.to_dict()})
        if args.overlay:
            out = Path(args.overlay)
            out.mkdir(parents=True, exist_ok=True)
            cv2.imwrite(str(out / f"{path.stem}_overlay.jpg"), draw_overlay(img, res, args.rim))
        if not args.json:
            flags = f"  [{', '.join(res.flags)}]" if res.flags else ""
            print(f"{path.name}: {res.count} CFU{flags}")
    if args.json:
        json.dump(rows, sys.stdout, indent=2)
        print()
    return 0


def cmd_evaluate(args) -> int:
    """Each image needs a sidecar ``<stem>.json`` with {"count": N} and/or {"points": [[x, y], ...]}."""
    folder = Path(args.folder)
    preds, trues, pr = [], [], []
    for path in sorted(p for p in folder.iterdir() if p.suffix.lower() in IMAGE_EXTS):
        label_path = path.with_suffix(".json")
        if not label_path.exists():
            continue
        label = json.loads(label_path.read_text())
        res = count_colonies(_read(path), plate_diameter_mm=args.plate_mm, rim_fraction=args.rim,
                             polarity=args.polarity)
        true = label.get("count", len(label.get("points", [])))
        preds.append(res.count)
        trues.append(true)
        line = f"{path.name}: predicted {res.count}, true {true}"
        if "points" in label:
            radius = args.match_mm / res.plate.mm_per_px
            m = match_points([[c.x, c.y] for c in res.colonies], label["points"], radius)
            pr.append(m)
            line += f", P {m['precision']:.3f} R {m['recall']:.3f}"
        print(line)
    if not trues:
        raise SystemExit(f"No labelled images in {folder}")
    summary = count_metrics(preds, trues)
    if pr:
        tp = sum(m["tp"] for m in pr)
        summary["precision"] = tp / max(1, tp + sum(m["fp"] for m in pr))
        summary["recall"] = tp / max(1, tp + sum(m["fn"] for m in pr))
    print(json.dumps(summary, indent=2))
    return 0


def cmd_synth(args) -> int:
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(args.seed)
    for i in range(args.n):
        n = int(rng.integers(0, args.max_colonies + 1))
        s = make_plate(n, seed=args.seed + i, polarity=args.polarity)
        cv2.imwrite(str(out / f"synth_{i:03d}.png"), s.image)
        label = {"count": len(s.points), "points": s.points.round(1).tolist()}
        (out / f"synth_{i:03d}.json").write_text(json.dumps(label))
    print(f"Wrote {args.n} plates to {out}")
    return 0


def cmd_zones(args) -> int:
    rows = []
    for path in map(Path, args.images):
        img = _read(path)
        res = measure_plate(img, plate_diameter_mm=args.plate_mm, assay=args.assay, disk_mm=args.disk_mm)
        rows.append({"image": str(path), **res.to_dict()})
        if args.overlay:
            out = Path(args.overlay)
            out.mkdir(parents=True, exist_ok=True)
            cv2.imwrite(str(out / f"{path.stem}_zones.jpg"), draw_zones(img, res))
        if not args.json:
            flags = f"  [{', '.join(res.flags)}]" if res.flags else ""
            print(f"{path.name}: {len(res.zones)} {args.assay}s{flags}")
            for i, z in enumerate(res.zones, 1):
                d = "?" if z.diameter_rounded is None else f"{z.diameter_rounded} mm ({z.diameter_mm:.1f})"
                zf = f"  [{', '.join(z.flags)}]" if z.flags else ""
                print(f"  {i}: {d}  confidence {z.confidence:.2f}{zf}")
    if args.json:
        json.dump(rows, sys.stdout, indent=2)
        print()
    return 0


def cmd_evaluate_zones(args) -> int:
    """Each image needs a sidecar ``<stem>.json``:
    {"plate_mm": 90, "assay": "disk", "disk_mm": 6,
     "zones": [{"x": px, "y": px, "diameter_mm": 22.0}, ...]}
    x/y are the disk centres in image pixels (to pair readings with disks);
    plate_mm, assay and disk_mm fall back to the command-line options.
    """
    folder = Path(args.folder)
    preds, trues = [], []
    missed = extra = unmeasured = 0
    for path in sorted(p for p in folder.iterdir() if p.suffix.lower() in IMAGE_EXTS):
        label_path = path.with_suffix(".json")
        if not label_path.exists():
            continue
        label = json.loads(label_path.read_text())
        assay = label.get("assay", args.assay)
        disk_mm = float(label.get("disk_mm", args.disk_mm))
        res = measure_plate(_read(path), plate_diameter_mm=float(label.get("plate_mm", args.plate_mm)),
                            assay=assay, disk_mm=disk_mm)
        truth = label["zones"]
        radius = 3.0 / res.plate.mm_per_px
        pairs = match_zones([[z.x, z.y] for z in res.zones], [[t["x"], t["y"]] for t in truth], radius)
        missed += len(truth) - len(pairs)
        extra += len(res.zones) - len(pairs)
        errs = []
        for pi, ti in pairs:
            z = res.zones[pi]
            if z.diameter_rounded is None:
                unmeasured += 1
                continue
            preds.append(z.diameter_mm)
            trues.append(float(truth[ti]["diameter_mm"]))
            errs.append(z.diameter_mm - trues[-1])
        worst = f", worst {max(errs, key=abs):+.1f} mm" if errs else ""
        print(f"{path.name}: {len(pairs)}/{len(truth)} matched{worst}")
    if not trues:
        raise SystemExit(f"No labelled zone images in {folder}")
    summary = zone_metrics(preds, trues)
    summary.update({"missed_disks": missed, "extra_disks": extra, "unmeasured": unmeasured})
    print(json.dumps(summary, indent=2))
    return 0


def cmd_synth_zones(args) -> int:
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(args.seed)
    for i in range(args.n):
        kw = dict(n_disks=int(rng.integers(1, 7)),
                  lighting=str(rng.choice(["reflected", "backlit"])),
                  edge_mm=(0.1, 0.3) if rng.random() < 0.6 else (0.5, 1.2),
                  colonies_in_zones=int(rng.integers(0, 5)),
                  gradient=float(rng.uniform(0, 0.4)))
        s = make_zone_plate(seed=args.seed + i, assay=args.assay, disk_mm=args.disk_mm, **kw)
        cv2.imwrite(str(out / f"zones_{i:03d}.png"), s.image)
        label = {"plate_mm": s.plate.diameter_mm, "assay": s.assay, "disk_mm": s.disk_mm,
                 "zones": [{"x": round(z.x, 1), "y": round(z.y, 1), "diameter_mm": round(z.diameter_mm, 2)}
                           for z in s.zones]}
        (out / f"zones_{i:03d}.json").write_text(json.dumps(label))
    print(f"Wrote {args.n} zone plates to {out}")
    return 0


def cmd_petrifilm(args) -> int:
    rows = []
    for path in map(Path, args.images):
        img = _read(path)
        res = count_petrifilm(img, args.type)
        rows.append({"image": str(path), **res.to_dict()})
        if args.overlay:
            out = Path(args.overlay)
            out.mkdir(parents=True, exist_ok=True)
            cv2.imwrite(str(out / f"{path.stem}_film.jpg"), draw_film(img, res))
        if not args.json:
            est = res.estimates or {}
            vals = ", ".join(f"{k} {v:g}{' (est.)' if k in est else ''}" for k, v in res.values.items())
            flags = f"  [{', '.join(res.flags)}]" if res.flags else ""
            print(f"{path.name}: {vals}{flags}")
    if args.json:
        json.dump(rows, sys.stdout, indent=2)
        print()
    return 0


def cmd_evaluate_petrifilm(args) -> int:
    """Each image needs ``<stem>.json``: {"type": "ec", "counts": {"ecoli": 12, "coliform": 30}}."""
    folder = Path(args.folder)
    per: dict[str, tuple[list, list]] = {}
    for path in sorted(p for p in folder.iterdir() if p.suffix.lower() in IMAGE_EXTS):
        label_path = path.with_suffix(".json")
        if not label_path.exists():
            continue
        label = json.loads(label_path.read_text())
        res = count_petrifilm(_read(path), label.get("type", args.type))
        line = []
        for k, v in label["counts"].items():
            got = res.values.get(k)
            if got is None:
                continue
            pred, true = per.setdefault(k, ([], []))
            pred.append(got)
            true.append(v)
            line.append(f"{k} {got:g}/{v}")
        print(f"{path.name}: {', '.join(line)}")
    if not per:
        raise SystemExit(f"No labelled films in {folder}")
    print(json.dumps({k: count_metrics(p, t) for k, (p, t) in per.items()}, indent=2))
    return 0


def cmd_synth_petrifilm(args) -> int:
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(args.seed)
    for i in range(args.n):
        s = make_film(args.type, n=int(rng.integers(20, 120)), seed=args.seed + i,
                      angle_deg=float(rng.uniform(-12, 12)))
        cv2.imwrite(str(out / f"film_{args.type}_{i:03d}.jpg"), s.image, [cv2.IMWRITE_JPEG_QUALITY, 92])
        (out / f"film_{args.type}_{i:03d}.json").write_text(json.dumps({"type": args.type, "counts": s.truth()}))
    print(f"Wrote {args.n} {args.type} films to {out}")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="colonycounter")
    sub = ap.add_subparsers(dest="cmd", required=True)

    def common(p):
        p.add_argument("--plate-mm", type=float, default=90.0, help="dish diameter in mm")
        p.add_argument("--rim", type=float, default=0.95, help="fraction of radius counted")
        p.add_argument("--polarity", choices=["auto", "bright", "dark"], default="auto")

    p = sub.add_parser("count", help="count colonies in images")
    p.add_argument("images", nargs="+")
    p.add_argument("--overlay", help="folder for annotated images")
    p.add_argument("--json", action="store_true", help="print full results as JSON")
    common(p)
    p.set_defaults(func=cmd_count)

    p = sub.add_parser("evaluate", help="compare counts with labels in a folder")
    p.add_argument("folder")
    p.add_argument("--match-mm", type=float, default=0.5, help="point match radius in mm")
    common(p)
    p.set_defaults(func=cmd_evaluate)

    p = sub.add_parser("synth", help="write synthetic labelled plates")
    p.add_argument("out")
    p.add_argument("--n", type=int, default=20)
    p.add_argument("--max-colonies", type=int, default=300)
    p.add_argument("--seed", type=int, default=0)
    p.add_argument("--polarity", choices=["bright", "dark"], default="bright")
    p.set_defaults(func=cmd_synth)

    def zone_common(p):
        p.add_argument("--plate-mm", type=float, default=90.0, help="dish diameter in mm")
        p.add_argument("--assay", choices=["disk", "well"], default="disk")
        p.add_argument("--disk-mm", type=float, default=6.0, help="disk or well diameter in mm")

    p = sub.add_parser("zones", help="measure inhibition zones in images")
    p.add_argument("images", nargs="+")
    p.add_argument("--overlay", help="folder for annotated images")
    p.add_argument("--json", action="store_true", help="print full results as JSON")
    zone_common(p)
    p.set_defaults(func=cmd_zones)

    p = sub.add_parser("evaluate-zones", help="compare zone diameters with labels in a folder")
    p.add_argument("folder")
    zone_common(p)
    p.set_defaults(func=cmd_evaluate_zones)

    p = sub.add_parser("synth-zones", help="write synthetic labelled zone plates")
    p.add_argument("out")
    p.add_argument("--n", type=int, default=20)
    p.add_argument("--seed", type=int, default=0)
    zone_common(p)
    p.set_defaults(func=cmd_synth_zones)

    types = sorted(FILM_TYPES)
    p = sub.add_parser("petrifilm", help="count Petrifilm-style dry-film plates")
    p.add_argument("images", nargs="+")
    p.add_argument("--type", choices=types, required=True)
    p.add_argument("--overlay", help="folder for annotated images")
    p.add_argument("--json", action="store_true", help="print full results as JSON")
    p.set_defaults(func=cmd_petrifilm)

    p = sub.add_parser("evaluate-petrifilm", help="compare film counts with labels in a folder")
    p.add_argument("folder")
    p.add_argument("--type", choices=types, default="ac", help="when a label has no type")
    p.set_defaults(func=cmd_evaluate_petrifilm)

    p = sub.add_parser("synth-petrifilm", help="write synthetic labelled films")
    p.add_argument("out")
    p.add_argument("--type", choices=types, default="ac")
    p.add_argument("--n", type=int, default=10)
    p.add_argument("--seed", type=int, default=0)
    p.set_defaults(func=cmd_synth_petrifilm)

    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
