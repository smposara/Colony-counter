"""Accuracy metrics for comparing automatic counts with manual ground truth."""

from __future__ import annotations

import numpy as np
from scipy.optimize import linear_sum_assignment


def count_metrics(pred, true, tol_frac: float = 0.10, tol_abs: int = 5) -> dict:
    """Per-plate count agreement. ``pred`` and ``true`` are equal-length sequences."""
    p = np.asarray(pred, float)
    t = np.asarray(true, float)
    err = p - t
    nz = t > 0
    ape = np.abs(err[nz]) / t[nz]
    ba = bland_altman(p, t)
    return {
        "n_plates": int(len(t)),
        "mae": float(np.mean(np.abs(err))),
        "bias": ba["bias"],
        "loa_low": ba["loa_low"],
        "loa_high": ba["loa_high"],
        "median_ape": float(np.median(ape)) if ape.size else float("nan"),
        "mape": float(np.mean(ape)) if ape.size else float("nan"),
        f"within_{int(tol_frac * 100)}pct": float(np.mean(np.abs(err) <= tol_frac * t)),
        f"within_{tol_abs}": float(np.mean(np.abs(err) <= tol_abs)),
        "lins_ccc": lins_ccc(p, t),
    }


def bland_altman(a, b) -> dict:
    d = np.asarray(a, float) - np.asarray(b, float)
    bias = float(d.mean())
    sd = float(d.std(ddof=1)) if d.size > 1 else 0.0
    return {"bias": bias, "loa_low": bias - 1.96 * sd, "loa_high": bias + 1.96 * sd}


def lins_ccc(a, b) -> float:
    """Lin's concordance correlation coefficient."""
    x = np.asarray(a, float)
    y = np.asarray(b, float)
    if x.size < 2:
        return float("nan")
    sxy = np.mean((x - x.mean()) * (y - y.mean()))
    denom = x.var() + y.var() + (x.mean() - y.mean()) ** 2
    return float(2 * sxy / denom) if denom > 0 else 1.0


def match_points(pred, gt, radius: float) -> dict:
    """One-to-one match of predicted and true colony centres within ``radius`` px."""
    pred = np.asarray(pred, float).reshape(-1, 2)
    gt = np.asarray(gt, float).reshape(-1, 2)
    if len(pred) == 0 or len(gt) == 0:
        tp = 0
    else:
        d = np.linalg.norm(pred[:, None, :] - gt[None, :, :], axis=2)
        cost = np.where(d <= radius, d, 1e9)
        rows, cols = linear_sum_assignment(cost)
        tp = int(np.sum(cost[rows, cols] <= radius))
    fp = len(pred) - tp
    fn = len(gt) - tp
    precision = tp / (tp + fp) if tp + fp else 1.0
    recall = tp / (tp + fn) if tp + fn else 1.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    return {"tp": tp, "fp": fp, "fn": fn, "precision": precision, "recall": recall, "f1": f1}


def match_zones(pred_xy, true_xy, radius: float) -> list[tuple[int, int]]:
    """One-to-one (pred, true) index pairs of disks within ``radius`` px of each other."""
    pred = np.asarray(pred_xy, float).reshape(-1, 2)
    true = np.asarray(true_xy, float).reshape(-1, 2)
    if len(pred) == 0 or len(true) == 0:
        return []
    d = np.linalg.norm(pred[:, None, :] - true[None, :, :], axis=2)
    cost = np.where(d <= radius, d, 1e9)
    rows, cols = linear_sum_assignment(cost)
    return [(int(r), int(c)) for r, c in zip(rows, cols) if cost[r, c] <= radius]


def zone_metrics(pred_mm, true_mm) -> dict:
    """Zone diameter agreement in mm, and the AST go/no-go gate
    (mean error ≤ 1 mm and ≥ 95 % within ±2 mm; see docs/AST.md)."""
    p = np.asarray(pred_mm, float)
    t = np.asarray(true_mm, float)
    if p.size == 0:
        return {"n_zones": 0}
    err = p - t
    a = np.abs(err)
    ba = bland_altman(p, t)
    mae = float(a.mean())
    within_2 = float(np.mean(a <= 2.0))
    return {
        "n_zones": int(p.size),
        "mae_mm": mae,
        "bias_mm": ba["bias"],
        "loa_low_mm": ba["loa_low"],
        "loa_high_mm": ba["loa_high"],
        "max_abs_error_mm": float(a.max()),
        "within_0_5mm": float(np.mean(a <= 0.5)),
        "within_1mm": float(np.mean(a <= 1.0)),
        "within_2mm": within_2,
        "rounded_exact": float(np.mean(np.floor(p + 0.5) == np.floor(t + 0.5))),
        "gate_pass": bool(mae <= 1.0 and within_2 >= 0.95),
    }
