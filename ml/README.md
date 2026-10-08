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
| `petrifilm.py` | Petrifilm-style dry films: grid scale, grid removal, colonies, gas, yellow zones, yeast/mold (`count_petrifilm`) |
| `synth_petrifilm.py` | Synthetic AC / EC / CC / EB / YM films with known colonies, gas and halos |
| `drops.py` | Drop plates (Miles–Misra, spot plates): layout fit, empty and confluent drops, per-drop counts (`count_drop_plate`) |
| `drop_stats.py` | Per-dilution drop table (mean, SD, VMR, χ² dispersion, outliers, tenfold check) and CFU/mL (`estimate_drops`) |
| `synth_drops.py` | Synthetic drop plates (sectors or grid) with known drops, counts, confluent drops and strays |
| `cli.py` | `colonycounter count / evaluate / synth / zones / evaluate-zones / synth-zones / petrifilm / evaluate-petrifilm / synth-petrifilm / drops / synth-drops` |

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

## Petrifilm-style dry films (in development, see `docs/PETRIFILM_IMPLEMENTATION.md`)

Counts Neogen® Petrifilm® plates (Petrifilm and Neogen are trademarks of Neogen
Corporation; this project is not made or endorsed by Neogen). Types: `ac` Aerobic Count,
`ec` E. coli/Coliform, `cc` Coliform Count, `eb` Enterobacteriaceae, `ym` Yeast & Mold.

```
photo (short side ≤ 1800 px) → printed 1 cm grid: line map (square-kernel black
        top-hat, blobs removed); angle = rotation that makes its row/column sums most
        peaked (coarse to fine); pitch (autocorrelation), phase and line width → mm/px
      → grid lines replaced by the colour from across the line (no inpainting)
      → growth area: chroma edges vote for a centre one radius (0.85–1.15 × 25 mm) in,
        then the edge is refined along 90 rays
      → background per Lab channel; colonies where the gel gets darker / changes colour
      → per colony: blue (b* < −8) or red; gas = a bubble (thin rim brighter than inside
        and outside, all round, radii 0.28–0.9 mm) within one colony diameter;
        yellow zone = b* rise around the colony; mold = own radius ≥ 1 mm
      → results per the interpretation guide; above the counting range,
        mean per complete 1 cm square × growth area (flag `estimated`)
```

Results: `ac` aerobic · `ec` ecoli (blue, with or without gas), coliform (blue + red with
gas) · `cc` coliform (with gas) · `eb` enterobacteriaceae (red with yellow zone and/or gas)
· `ym` yeast, mold. Plate-type values live in `TYPES`; those with `confirmed=False` must be
checked against the current interpretation guide.

```
colonycounter petrifilm photos/*.jpg --type ec --overlay out/
colonycounter synth-petrifilm synth/ --type ec --n 10 && colonycounter evaluate-petrifilm synth/
python scripts/petrifilm_benchmark.py --n 8
```

**Labels for `evaluate-petrifilm`:** `<stem>.json` with `{"type": "ec", "counts":
{"ecoli": 12, "coliform": 30}}`.

**Synthetic benchmark** (`scripts/petrifilm_benchmark.py --n 8`, ±15° turns, 9–15 px/mm):
mean error AC 0.3 %, EC 0.8 %, CC 2.1 %, EB 0.8 %, YM 1.0 %; within 10 %: 100 % for every
type. Crowded AC (≈600 colonies) estimated from 8 squares at +10 %:
the synthetic films keep colonies 1.5 mm from the edge, so the inner squares are denser
than the plate average.

**Flags:** `grid_not_found` when the printed grid does not repeat clearly (`Grid.strength` <
0.3: not a film, glare or out of focus), `area_size_unexpected`, `estimated`, `tntc`, `spreader`.

Synthetic colours are approximations of the guides: they test the method, not the
thresholds. Blue/red, yellow-zone, bubble and mold thresholds must be set from real photos.

## Drop plates (in development, see `docs/DROP_PLATE_IMPLEMENTATION.md`)

Miles–Misra and spot plates: drops of a tenfold dilution series laid out as **sectors**
(a ring of drops, clockwise from the top) or a **grid** (a row per dilution, a column per
replicate), or **free** (drops found from their colonies only, as the app does today).

```
photo → dish → background (15 mm kernel) → colonies (classical detector)
      → drop candidates: colony groups (single linkage, 0.35 × drop diameter) and
        confluent blobs (one component ≥ 60 % of a drop disc)
      → layout fit: rotation over the layout's symmetry, translations from candidate
        pairs, Procrustes refinement (scale 0.8–1.25); positions off the plate and far
        from the centre are penalised; empty drops come from the layout
      → labels: among near-best placements and the layout's symmetric orientations, the
        one whose counts best follow the dilution series (Poisson likelihood)
      → per drop: colonies within 1.1 radii; confluent → TNTC; crowded (cover > 35 % or a
        merged cluster) → also counted by area, the larger count kept
      → drop table (mean, SD, VMR, χ² test, outlier drops, tenfold check) and CFU/mL:
        pooled ΣC / Σ(V·d) over drops in 3–30, or the first countable dilution;
        Garwood 95 % interval; "<" 1 / (N·V·d) when nothing grew; ">" when all TNTC
```

Drop diameter scales with volume: 7 mm × (V / 10 µL)^⅓.

```
colonycounter drops photos/*.jpg --layout sectors --n-drops 8 --dilutions 3-10 --overlay out/
colonycounter drops photos/*.jpg --layout grid --rows 4 --cols 3 --pitch-mm 12 --dilutions 4-7 --mode first
colonycounter synth-drops synth/ --layout grid --rows 4 --cols 3 --pitch-mm 12 --dilutions 4-7
python scripts/drop_benchmark.py --n 12 --seed0 200
```

**Synthetic benchmark** (`scripts/drop_benchmark.py`, 80 plates over two seed sets; random
rotation, CFU 10^6.5–10^8.5, half the plates overdispersed, 2 stray colonies each):

| Layout | Layout found and labelled | In-window drops within ±2 / 10 % | Confluent recall | CFU/mL error vs true counts |
|---|---|---|---|---|
| 8 sectors, 1 per dilution | 100 % | 100 % | 100 % | 3–5 % |
| 6 sectors, 2 per dilution | 100 % | 93–100 % | 100 % | 2–7 % |
| 4 × 3 grid | 100 % | 93–96 % | 100 % | 6–7 % |
| 5 × 5 grid | 100 % | 95 % | 100 % | 4–5 % |

"Found" means every planned drop placed within 0.4 drop diameters (2.8 mm for 10 µL).
Which drop of a dilution is replicate 1 cannot be seen on the plate, so replicates are
numbered in reading order and only the dilution is checked. The remaining count errors are
crowded drops near 30 colonies, where merged colonies are counted by area.

Synthetic drops test the geometry and statistics, not the thresholds: confluent and
crowded limits must be set from real photos (Step 0 of `docs/DROP_PLATE.md`).
