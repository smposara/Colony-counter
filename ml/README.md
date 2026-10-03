# colonycounter: reference pipeline

The Python version of the counting pipeline. The mobile app must reproduce its
results on a fixed set of reference images.

```
photo → find_plate (Hough circle, 90 mm gives the mm/px scale)
      → rim mask (95 % of radius)
      → background correction (wide median) → contrast map (auto bright/dark)
      → threshold at max(4σ noise, 6 grey levels)
      → split touching colonies (distance-transform peaks), estimate clusters
      → flags: spreader, tntc, clusters_estimated
```

| Module | Purpose |
|---|---|
| `plate.py` | Find the dish, build the counting mask |
| `normalize.py` | Background / lighting correction, colony polarity |
| `classical.py` | Training-free colony detector (baseline and fallback) |
| `pipeline.py` | `count_colonies(image)` → `CountResult`; `draw_overlay` |
| `calculator.py` | CFU/mL with FDA BAM / ISO 7218 / 30–300 rules, pooled weighted mean |
| `metrics.py` | Count agreement (MAE, Bland–Altman, Lin's CCC) and point matching (P/R/F1) |
| `synth.py` | Synthetic labelled plates for tests and demos |
| `cli.py` | `colonycounter count / evaluate / synth` |

```python
import cv2
from colonycounter import count_colonies
from colonycounter.calculator import PlateCount, estimate

res = count_colonies(cv2.imread("P0042_pixel8_box.jpg"))
print(res.count, res.flags)

print(estimate([PlateCount(res.count, dilution=1e-5, volume_ml=0.1)], rule="FDA_BAM"))
```

**Labels for `evaluate`:** next to each image put `<stem>.json` containing
`{"count": N}` or `{"points": [[x, y], ...]}`, in pixel coordinates of the original image.

**Tuning:** `DetectParams` in `classical.py`: `k_sigma` (sensitivity),
`min_diameter_mm` (smallest colony counted), `peak_separation` (how readily touching
colonies are split).
