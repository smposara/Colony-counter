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
| `zones.py` | Inhibition zone diameters on disk / agar-well diffusion plates (`measure_plate`) |
| `synth_zones.py` | Synthetic disk and well diffusion plates with known zone diameters |
| `cli.py` | `colonycounter count / evaluate / synth / zones / evaluate-zones / synth-zones` |

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

## Inhibition zones (in development, see `docs/AST_IMPLEMENTATION.md`)

Measures zone diameters in mm; it does **not** interpret S/I/R.

```
photo → find_plate → find disks / wells: signed ring score at the known size,
        split into 8 sectors (the second-weakest counts, so only edges all
        round score); candidates on a downscaled copy at 0.8/1/1.25× the
        expected size, re-scored at full resolution, then a circle fitted to
        the disk edge
      → scale from the 6 mm paper disks (wells: from the plate), checked against the plate
      → 180 rays per disk: edge where brightness passes half-way from clear agar
        to lawn and stays there for 1.5 mm (ignores colonies inside the zone)
      → circle fit with outlier rejection → diameter, confidence, flags
```

```python
from colonycounter.zones import measure_plate
res = measure_plate(cv2.imread("plate.jpg"), plate_diameter_mm=90, assay="disk", disk_mm=6.0)
for z in res.zones:
    print(z.diameter_rounded, round(z.diameter_mm, 1), z.confidence, z.flags)
```

```
colonycounter zones photos/*.jpg --assay disk --overlay out/
colonycounter zones photos/*.jpg --assay well --disk-mm 8
colonycounter synth-zones synth/ --n 20 && colonycounter evaluate-zones synth/
python scripts/zone_benchmark.py --n 60
```

**Flags per zone:** `no_zone` (lawn grows up to the disk; reported as the disk
diameter), `overlap` (circles of two zones cross), `hits_rim`, `hazy` (20→80 % edge
wider than 1 mm), `colonies_in_zone`, `low_confidence` (< 60 % of rays agree),
`unmeasured` (< 15 % agree: no number, the user must set it).
**Per plate:** `scale_mismatch` (disk size differs from 6 mm by > 5 % at the chosen
plate size: wrong plate format or a tilted photo), `scale_unchecked`, `no_disks`.

**Labels for `evaluate-zones`:** `<stem>.json` with `{"plate_mm": 90, "assay": "disk",
"disk_mm": 6, "zones": [{"x": px, "y": px, "diameter_mm": 22.0}, ...]}`; x/y are disk
centres in the original image, used to pair readings with disks. The summary includes
`gate_pass`: mean error ≤ 1 mm and ≥ 95 % within ±2 mm (the go/no-go gate in `docs/AST.md`).

**Synthetic benchmark** (`scripts/zone_benchmark.py --n 60`, 271 zones): mean error
0.13 mm, 98.5 % within 1 mm, 100 % within 2 mm; 2 of 271 disks/wells missed and 2
invented (all wells). The only misses over 1 mm are zones reaching < 0.6 mm past the
disk, read as "no zone". Synthetic wells are a guess at how real wells look: their
detection (`COARSE_RADIUS_PX["well"]`, `MIN_DISK_SCORE`) must be checked on real photos.

**App port:** `app/lib/core/zones.dart` mirrors this module step for step. Golden
plates for it come from `python scripts/make_app_fixtures.py --zones`
(`app/test/fixtures/zones_*`, checked by `app/test/zones_core_test.dart`). Change
both sides together and regenerate the fixtures.
Synthetic edges are defined at half growth, so this checks the method, not the
reading convention: real plates (EUCAST reads at complete inhibition) will set
`ZoneParams.edge_level`.

**Tuning:** `ZoneParams` in `zones.py`: `edge_level`, `persist_mm`, `min_contrast`,
`hazy_width_mm`, `scale_tolerance`.

