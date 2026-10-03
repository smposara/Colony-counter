"""Command line: count plates, evaluate against labels, make synthetic test plates.

    colonycounter count photos/*.jpg --overlay out/
    colonycounter evaluate data/labelled/
    colonycounter synth out/ --n 20
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import cv2
import numpy as np

from .metrics import count_metrics, match_points
from .pipeline import count_colonies, draw_overlay
from .synth import make_plate

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

    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
