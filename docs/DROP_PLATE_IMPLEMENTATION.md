# Drop plates (Options A + B): implementation plan

Status: **M1–M2 done in Python, M3 core port done in Dart** (October 2026; see Progress below). Study and options: [DROP_PLATE.md](DROP_PLATE.md). Same
approach as Petrifilm and AST: Python reference first, Dart port checked against golden
fixtures, then data, UI and export.

## Scope

**Option A, reliable drops:**
- Layout templates, fitted to the found drops, that fill in empty drops.
- Labels taken from layout positions.
- Drop size computed from drop volume.
- Detection of confluent drops.
- A per-drop crowding flag.
- Fixes for the smaller gaps.

**Option B, drop statistics:**
- A per-dilution drop table.
- Poisson dispersion and outlier flags.
- A check that neighbouring dilutions differ by about tenfold.
- A confidence interval and detection limit.
- A choice of calculation, plus report and CSV output.

**Out of scope (Option C):** single-plate dilution zones, 96-spot grids, phage spot titration
and tilt/track dilution.

## Architecture overview

```
photo → plate → colonies (existing detector)
      → drop candidates: colony groups (existing) + confluent-drop blobs (new)
      → layout fit: template (rows × columns, sectors, free) placed on the candidates
        by a similarity transform → every planned position, empty ones included
      → per drop: count, crowding, confluent / TNTC, excluded by the user
      → per dilution: drops in the window → mean, SD, VMR, χ² dispersion, outliers
      → sample: chosen rule (first countable dilution or pooled) → CFU/mL, Poisson CI,
        "<" detection limit over all drops of the least diluted dilution
```

What is reused:
- The colony detector, `suggestSpots` (as the candidate finder), `Spot`, `countInSpot`, the
  Drops review mode and `_SpotDialog`.
- The calculator's `estimate()` and replicate statistics, plus exports and backup.

## 1. Python reference (`ml/colonycounter/`)

There is no drop code in Python today. Add:

- **`synth_drops.py`:** `make_drop_plate(layout, volume_ul, dilutions, drops_per_dilution,
  true_cfu_per_ml, seed, …)` builds round or square plates.
  - Layouts: `sectors(n)` (one ring), `grid(rows, cols)` (rows = dilutions) and
    `free(points)`.
  - Colonies are Poisson per drop, with optional overdispersion (a gamma-Poisson factor) to
    test the flags.
  - Drops that should be empty or confluent (a lawn disc), merged colonies in crowded drops,
    stray colonies between drops, and a faint dried-drop ring.
  - Returns the truth: positions, dilution and replicate of each drop, counts and confluent
    flags.
- **`drops.py`:**
  - `drop_diameter_mm(volume_ul)`: 7 mm × (V / 10 µL)^(1/3), so 5 µL → 5.6 mm and
    20 µL → 8.8 mm. Overridable per sample.
  - `drop_candidates(colonies, image, plate, mm)`: colony groups, as `suggestSpots` does
    (link 0.35 × drop diameter instead of a fixed 2.5 mm), plus confluent blobs. A confluent
    blob is a disc about one drop across whose foreground covers ≥ 60 % of it, with few
    separable colonies.
  - `fit_layout(candidates, template, mm)`: finds the template's scale, rotation and
    translation that best match the candidate centres.
    - Try each pair of candidates against each pair of template positions, then refine by
      least squares on the matched pairs.
    - Score: matched candidates minus a penalty for distance and for unmatched colonies.
    - Positions with no candidate become empty drops (count 0).
    - Candidates far from every position are reported as "outside the layout"; they are not
      counted.
  - `label_drops(positions, plan)`: assigns dilution and replicate from the template's row
    and column (or sector index plus the starting sector, see the UI). This replaces the
    reading-order index.
  - `drop_flags(drop)`: `crowded` when the colony coverage in the drop is > 25 % or any
    cluster has n ≥ 3; `confluent` when the drop is a blob; `outside_layout`.
- **`drop_stats.py`:**
  - `dilution_table(drops, rule)`: for each dilution, the number of drops, counts, mean, SD,
    VMR = s²/x̄ and χ² = Σ(x − x̄)² / x̄ with N − 1 degrees of freedom, with p-value.
    Flag `overdispersed` when p < 0.01 and N ≥ 3.
  - **Outlier drop:** |x − x̄| / √x̄ > 3 with the others consistent. This is only flagged;
    nothing is excluded automatically.
  - **Tenfold check:** the ratio of means of neighbouring countable dilutions is outside
    3–30 (expected 10). Flag `dilution_inconsistent`.
  - `estimate_drops(table, rule, mode)`:
    - `mode="first"` (first countable dilution): the mean of its drops ÷ (V·d).
    - `mode="pooled"`: ΣC / Σ(V·d) over in-range drops, as the app does today.
    - Poisson 95 % CI from the total count (Garwood), scaled the same way.
    - Below range: "<" uses all drops of the least diluted dilution,
      1 / (N·V·d) for zero colonies.
- **CLI and benchmark:** a `drops` command, and `scripts/drop_benchmark.py` measuring
  layout found/labelled, per-drop count error, confluent recall and CFU error.

**Gate** (synthetic, then real photos from Step 0): all positions found and labelled on
≥ 95 % of plates; per-drop count within ±2 (or ±10 %) on ≥ 90 % of in-window drops;
confluent drops ≥ 90 % recall with ≤ 5 % false flags.

## 2. Dart port (`app/lib/core/`)

- **`drop_layout.dart`:** `DropTemplate` (sealed: `Sectors(n, startAngle)`,
  `Grid(rows, cols, pitchMm)`, `Free`), plus `dropDiameterMm`, `fitLayout`, `labelDrops`
  and confluent-blob detection. It mirrors Python, with golden fixtures from
  `make_app_fixtures.py --drops` and agreement checks as for zones and Petrifilm.
- **`drop_stats.dart`:** `DilutionRow` (counts, mean, SD, VMR, χ², p, flags),
  `dilutionTable` and `estimateDrops(mode)`. The χ² p-value comes from the regularised
  gamma function (a small series and continued fraction; no dependency needed).
- **`spots.dart`:**
  - `Spot` gains `position` (the template index, or null for free drops), `excluded` with a
    `reason` (the user left the drop out: splash, merged, bubble), and `flags`.
  - `suggestSpots` keeps working for the free layout.
- **`calculator.dart`:** a `CountingRule.drop` window, configurable per sample. 3–30 per
  10 µL stays the default; for other volumes the window is shown as given, not rescaled.

## 3. Data (`app/lib/data/`)

- **`SampleInfo`** (JSON with defaults, so older samples load unchanged):
  - `dropTemplate` (sectors, grid or free, plus size).
  - `dropsPerDilution`.
  - `dropMode` (`first` or `pooled`; default `pooled`, as today).
  - `dropWindow` (min and max; default 3–30).
  - `dropDiameterMm` (null means computed from the volume).
- **`PlateRecord`:** spots with `position`, `excluded`, `reason` and `flags`. The plate-level
  `spreader` flag applies to every drop on the plate (fixes gap 7).
- **Fixes:**
  - Replicate labels no longer wrap: extra drops are flagged instead.
  - `SampleInfo.inferred` infers the layout from the spots.
  - Drop plates join the accuracy check: per-drop counts are scored against the user's
    corrected counts.

## 4. User interface (`app/lib/ui/`)

- **Sample setup:**
  - A layout picker with a small diagram: sectors on a round plate (4, 6 or 8 drops), rows
    × columns (dilutions × drops, e.g. 6 × 3 on a square plate), or free.
  - Drops per dilution, the counting window and the calculation (first countable dilution
    or pooled), with a one-line explanation of each.
- **Camera:** an outline of the chosen layout in the guide (the sectors or the grid).
- **Review, Drops mode:**
  - The fitted layout is drawn. Empty positions show "0" and are labelled like the others.
    Confluent drops are red and marked TNTC; drops outside the layout are grey.
  - Drag the whole layout (two-finger to rotate and scale) or a single drop.
  - Tap a drop to change its label, set TNTC or **leave it out** (with a reason). Excluded
    drops are crossed through.
  - For sectors, a "first sector" control picks which drop is the first dilution.
- **Drop table** in the review panel, the sample card and the save sheet:
  - Each dilution as a row of drop counts, then mean ± SD, VMR and a flag icon:
    "10⁻⁵ · 12 15 9 14 11 · 12.2 ± 2.4".
  - The CFU/mL line names the dilution used (first-countable mode) or the pooled dilutions.
  - It shows the Poisson CI and any "<" detection limit.
- **Warnings:**
  - Overdispersed drops ("drops disagree more than chance: check mixing and pipetting").
  - Outlier drop, dilutions not tenfold, crowded drops ("read earlier or use a higher
    dilution").
  - A drop count that doesn't match the plan.
- **Shared photo:** the drop table and CFU/mL in the banner.

## 5. Export

- **`plates.csv`:** `drop_layout`, `drop_mode`, `drop_window`, `drops_planned`,
  `drops_found`, `drops_excluded`, `drop_flags`.
- **New `drops.csv`**, one row per drop: plate, sample, position, dilution, replicate, count,
  TNTC, excluded and reason, flags, x/y in mm.
- **`samples.csv`:** `drop_dilution_used`, `drop_mean`, `drop_sd`, `drop_vmr`,
  `drop_chi2_p`, `cfu_ci_low`, `cfu_ci_high`.
- **Backup:** carries all new fields; older backups load unchanged.

## 6. Translation and text

`app/lib/l10n/parts/drops.json` (English and Thai) covers layout names, the calculation modes,
table headings, warnings and reasons for excluding a drop. Ask a Thai microbiologist to check
the terms for drop plate (ดรอปเพลต), dispersion (การกระจาย) and detection limit (ขีดจำกัดการตรวจพบ).

## 7. Tests

- **Python:**
  - Layout fit on sectors and grids at any rotation, with 0–3 empty positions and stray
    colonies.
  - Confluent recall.
  - χ² and VMR against hand-computed values.
  - First-countable and pooled estimates.
  - Detection limit over N drops.
  - Garwood CI values against tables.
- **Dart:**
  - Golden fixtures (sectors with empty drops, a 6 × 3 grid with confluent and crowded
    drops, overdispersed drops, free layout), checked against Python and the truth.
  - Unit tests for the statistics.
  - Widget tests: setup layout picker; review labels with an empty drop first (the current
    bug); excluding a drop; the drop table; the first-countable switch.
- **Regression:** the existing drop-plate test and data tests still pass; older records and
  backups load.

## 8. Docs and store

- Update the app README, and the store listing line "Drop plates (Miles–Misra)" to mention
  layouts and the drop table.
- Add screenshots and release notes in both languages.

## Milestones

| # | Milestone | Effort |
|---|---|---|
| M1 | Python synthetic plates, layout fit, labels, confluent drops, benchmark | 1.5 weeks |
| M2 | Python drop statistics and estimates | 0.5 week |
| M3 | Dart port of layout and statistics, golden fixtures | 1 week |
| M4 | Data model, setup screen, Drops mode with layout, exclusions, fixes | 1.5 weeks |
| M5 | Drop table, warnings, exports, shared photo, translations | 1 week |
| M6 | Tests, docs, screenshots, release | 0.5 week |

**Total: about 6 weeks** (A ≈ 4, B ≈ 2).

## Progress

**M1 + M2 (Python reference), done:** `ml/colonycounter/drops.py`, `drop_stats.py`,
`synth_drops.py`, `scripts/drop_benchmark.py`, `tests/test_drops.py`, CLI `drops` and
`synth-drops`. Synthetic benchmark on 80 plates (sectors 8 × 1 and 6 × 2, grids 4 × 3 and
5 × 5): every layout found and labelled (100 %), in-window drop counts within ±2 / 10 % on
93–100 % of drops, confluent recall 100 % with no false TNTC on countable drops, CFU/mL
within 2–7 % of the estimate from the true counts. That passes the study's gate on synthetic
plates; the real-photo gate (Step 0) is still open.

What M1 needed beyond the plan:
- Labels by **dilution-series likelihood** over near-best placements and the layout's
  symmetric orientations (including transposes of square grids): geometry alone cannot tell
  a grid shifted by one row, or a sector ring turned by one sector.
- An off-plate penalty and a plate-centre prior in the layout score.
- Replicates numbered in reading order within a dilution.
- **Crowded drops also counted by area** (colony pixels ÷ the pixels of an isolated colony),
  keeping the larger count: merged colonies in a ~30-colony drop were undercounted by up to
  half, and such a drop fell inside the window and pulled the pooled estimate down by up to
  60 % on overdispersed plates.

**M3 (Dart port of layout and statistics), core done:** `app/lib/core/drop_layout.dart`
(`DropTemplate` = `SectorTemplate` / `GridTemplate` / `FreeTemplate`, `dropDiameterMm`,
`templatePositionsMm`, `countDropPlate`, `countDropPlateInPhoto` for a background isolate,
`countDropPlateInBackground` in `background.dart`, `FoundDrop.toSpot()` for the review screen) and `app/lib/core/drop_stats.dart`
(`dilutionTable`, `estimateDrops(mode)`, `poissonInterval`, `chi2Sf`; the χ² p-value and the
Garwood limits come from a regularised incomplete gamma, no dependency). Golden fixtures
from `make_app_fixtures.py --drops` (8 sectors, 6 sectors × 2, 4 × 3 grid with crowded
drops, 5 × 5 grid, a mostly empty ring) in `app/test/drop_layout_test.dart`:

- Every drop where Python puts it (< 1 mm), same dilution and confluent flag; per-drop
  counts within one colony of Python (46 of 50 countable drops exact).
- Same flags; rotation and scale equal up to the layout's symmetry.
- CFU/mL within 3 % of Python and within 15 % of the estimate from the true counts.
- On Python's counts the drop table (mean, VMR, χ², p, flags) and both estimates (value,
  interval, dilutions and drops used) agree with Python to rounding.
- 1.2–2.2 s per 1200 px plate in the test VM.

Differences from Python: the 2-D Procrustes rotation is solved in closed form (no SVD), and
sorts break ties by order found (Dart's sort is not stable). The `Spot` changes
(`position`, `excluded`, `reason`, `flags`) are left for the data model in M4.

The decisions below were built with the plan's defaults (pooled by default with `first` as
an option; 3–30 for every volume; sectors and grids; confluent detection on).

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Labs' layouts differ from the templates | The free layout keeps today's behaviour; the grid size is free (rows × columns) |
| Too few drops with colonies to fit a layout (mostly empty plate) | Fall back to the template centred on the plate with the user dragging it; ask for confirmation |
| Confluent detection fooled by shadows or medium colour | Only suggest TNTC (shown in red, one tap to undo); tune on Step 0 photos |
| Overdispersion flagged too often on real data | p < 0.01 with N ≥ 3, wording as advice, never an automatic exclusion |
| Changing the default calculation surprises existing users | Keep "pooled" as the default; "first countable dilution" is opt-in per sample |
| Merged colonies in small drops undercount | Crowding flag and cluster estimate; advise reading earlier |

## Decisions to make before M1

1. **Default calculation:** keep pooled (today), or switch new samples to first countable
   dilution (the convention in most protocols)?
2. **Default window:** 3–30 per drop for every volume, or rescale for 20 µL drops (e.g. 5–50)?
3. **Templates in the first release:** sectors and rows × columns only, or also a 96-spot
   8 × 12 grid (Option C)?
4. **Confluent detection:** build it now, or start with "tap to mark TNTC" plus the
   empty-drop fix?
