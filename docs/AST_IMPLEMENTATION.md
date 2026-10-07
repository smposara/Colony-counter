# Inhibition zone measurement (AST Option A): implementation plan

Status: **parked**, not scheduled; design decisions made (see the end). Context and the
go/no-go gate are in [AST.md](AST.md).
Target release: 0.6.0 (or later), only after the gate in AST.md passes.

## Scope

**In:**
- Disk diffusion (6 mm disks) and agar well diffusion (well diameter set by the user).
- Zone diameter in mm for each disk or well, edited by hand where needed.
- Replicates: mean ± SD per test item.
- CSV export, annotated image, backup.
- Thai and English.
- "For research and education only, not for clinical diagnosis" disclaimer.

**Out:** S/I/R interpretation, breakpoint tables, reading disk codes automatically (OCR),
WHONET export, MIC strips. These are candidates for later.

**Rule:** colony counting must not change. All 93 existing tests pass unchanged, and zone
plates live in their own records, screens and export files.

## Architecture overview

```
photo ─► find plate (existing) ─► mm/px scale
      ─► find disks / wells (new) ─► check scale against 6 mm disks
      ─► for each disk: radial profiles on 180 rays ─► edge point per ray
      ─► robust circle fit (drops rays blocked by neighbours, rim, colonies)
      ─► diameter (mm) + confidence + flags
      ─► review screen (drag / ± adjust) ─► ZoneRecord ─► stats, CSV, backup
```

Same pattern as the colony pipeline: write and validate in Python (`ml/`), port to Dart
(`app/lib/core/`), and check the port against the Python results on shared test images.

## 1. Python reference (`ml/colonycounter/`)

**`zones.py`** (new):
- `find_disks(gray, plate, disk_mm=6.0)`: disks are small, bright, uniform circles of known
  size. Use template matching or a Hough search limited to radius `disk_mm / 2 / mm_per_px` ± 15 %,
  then non-maximum suppression. Return centres and the measured disk radius.
- `find_wells(gray, plate, well_mm)`: same, for the well diameter the user enters. Wells
  contrast less than disks, so tune this separately.
- `scale_check(plate, disks)`: compare the median disk diameter with 6.0 mm. If it's off by
  more than 5 %, flag `scale_mismatch`, which usually means tilt or the wrong plate format.
  A 1 % scale error is 0.3 mm on a 30 mm zone.
- `measure_zone(gray, plate, disk)`:
  1. Correct the background with the existing wide median (`normalize.estimate_background`).
  2. Take the lawn level from an outer ring and the zone level just outside the disk. The sign
     gives the polarity (a clear zone looks darker on a dark background, brighter when back-lit).
  3. Sample 180 rays from the disk edge to the maximum radius (the plate rim, or halfway to a
     neighbouring disk, whichever is nearer).
  4. Edge on each ray = first lasting crossing of the midpoint between the zone and lawn levels,
     after light smoothing. Mark a ray as blocked when it reaches the rim, meets a neighbouring
     zone first, or hits an isolated colony inside the zone.
  5. Fit a circle to the unblocked edge points with RANSAC (centre kept close to the disk
     centre). Report diameter = 2r × mm/px, the inlier fraction, and edge sharpness (gradient at
     the edge).
  6. Flags: `no_zone` (edge at the disk, reported as the disk diameter), `overlap`, `hits_rim`,
     `hazy` (low sharpness), `colonies_in_zone`, `low_confidence` (inlier fraction < 0.6).
- `measure_plate(image, format, assay, well_mm=None) -> ZoneResult`: the full pipeline.

**`synth_zones.py`** (new): synthetic lawns with grain, disks, zones with soft or sharp edges,
overlapping zones, colonies inside zones, and both polarities. Ground truth comes with each image.

**`metrics.py`:** add `zone_metrics(pred_mm, true_mm)` returning MAE, % within ±1 mm, % within
±2 mm, and a Bland–Altman bias.

**`cli.py`:** add `colonycounter zones <images> [--well-mm 6] [--overlay out/]` and
`colonycounter evaluate-zones <folder>`. Labels are JSON with calliper diameters per disk.

**Tests** (`ml/tests/test_zones.py`): synthetic plates within ±0.5 mm; overlap and rim cases
flagged; no-zone disks reported at 6 mm.

**Exit criterion (the gate in AST.md):** on 30–50 real photos measured with a calliper, mean
error ≤ 1 mm and ≥ 95 % within ±2 mm.

## 2. Dart port (`app/lib/core/`)

- **`zones.dart`**: `findDisks`, `findWells`, `measureZone` and `measurePlate`, mirroring
  `zones.py`. Reuse `GrayImage`, `background.dart`, `normalize.dart` and the plate finder. Like
  the colony pipeline, it works on a copy scaled to `kWorkShortSide`, runs in an isolate
  (`compute`), and returns results in full-resolution pixels.
- **`Zone`** class: `x`, `y`, `diskRadiusPx`, `radiusPx`, `autoRadiusPx`, `confidence`,
  `flags`, `label`, `manual`.
- **Fixtures:** extend `ml/scripts/make_app_fixtures.py` with 4–5 zone cases (clear, hazy,
  overlap, wells, back-lit). Write the Python result next to each one, and test that the Dart
  diameters agree within 0.2 mm (`app/test/zones_core_test.dart`).

## 3. Data and storage (`app/lib/data/`)

These are separate from `PlateRecord` so colony code paths (estimates, CSVs, accuracy checks,
training export) never see zone plates.

- **`zone_record.dart`:** `ZoneRecord` holds `id`, `createdAt`, `imagePath`, image size,
  `plate`, `format`, `assay` (disk / well), `wellDiameterMm`, `zones`, `experiment`,
  `organism`, `replicate`, `notes`, `verified`, and `toJson`/`fromJson`.
- **`PlateStore`:** a new storage key `zone_plates`, alongside `plates` and `samples`. It gets
  `zoneRecords`, `upsertZone` and `deleteZone`. Generalise `readPhoto(PlateRecord)` to
  `readPhotoPath(String)` so both record types share photo storage.
- **Panels:** saved, named lists of test-item labels in placement order (e.g. "Extract set A:
  EtOH, Hex, Aq, Amp 10, DMSO") under a `zone_panels` setting. After detection, labels are
  assigned clockwise from the 12 o'clock disk. The user can retap to fix the order.
- **Backup (`export.dart`):** add `zone_plates` and `zone_panels` to the manifest, and photos
  to `photos/` as now. `restoreBackup` imports them with the same duplicate-ID and
  photo-name-collision rules as `importAll`. Manifest version stays 1: older app versions
  ignore unknown keys, and colony data restores as before.
- **Stats:** per experiment and label, mean ± SD (n) of diameters across replicates, reusing
  `core/stats.dart`.

## 4. User interface (`app/lib/ui/`)

- **Home:** a fourth tab, **Zones**, with its own list and a "Measure zones" button. The
  colony tabs are untouched.
- **`zone_setup_sheet.dart`:** assay (disk 6 mm or well of N mm), plate format (`dish90`,
  `dish150`, square plates), organism, experiment, replicate, and an optional panel. The last
  choices are remembered, like `save_sheet.dart` does.
- **Capture:** reuse `countNewPlate`'s camera and gallery paths (split the shared part out of
  `photo_flow.dart`). Add a tip: lid off, plate on a dark background, camera straight overhead.
- **`zone_review_screen.dart`:** reuses the `InteractiveViewer` and gesture pattern from
  `review_screen.dart`.
  - Overlay: plate outline, disk dots, zone circles coloured by confidence, and a "23 mm" label
    beside each one, in whole mm.
  - Tap a disk to open a sheet with its label, diameter, −/+ 1 mm buttons, a "No zone"
    switch, delete, and its flags in plain words.
  - Drag a zone circle's edge to resize it. Long-press to add a missed disk; the app then
    measures around it.
  - "Fix plate circle" mode is reused, since the scale depends on it.
  - Save marks the plate checked when every low-confidence zone has been opened.
- **Experiment view:** a table of label → mean ± SD (n) mm and a simple bar chart (reuse
  `chart_colours.dart`).
- **Disclaimer:** shown once before the first zone plate, plus a line on the About screen.

## 5. Export

- **`zones.csv`** (one row per zone): plate_id, date, experiment, organism, assay,
  disk_or_well_mm, label, replicate, diameter_mm (0.1 mm), diameter_mm_rounded (whole mm,
  as shown on screen), auto_diameter_mm, edited,
  confidence, flags, x_mm, y_mm, image.
- **`zone_summary.csv`**: experiment, organism, label, n, mean_mm, sd_mm.
- **Annotated image:** extend `annotate.dart` to draw zone circles and labels.
- The CSVs and photos go in the backup zip, and can be shared from the Zones tab menu.

## 6. Translation and text

- New `app/lib/l10n/parts/zones.json` (en/th), run through the existing gen-l10n step.
- Flags in plain words, e.g. "Zone runs into another zone; measured from the clear side."
- Thai terms to confirm with a Thai microbiologist: วงใส (clear zone), เส้นผ่านศูนย์กลาง,
  แผ่นยา / หลุม.

## 7. Tests

| Level | File | Checks |
|---|---|---|
| Python | `ml/tests/test_zones.py` | Synthetic accuracy, flags, scale check |
| Dart core | `app/test/zones_core_test.dart` | Agreement with Python on fixtures (±0.2 mm) |
| Data | `app/test/zones_data_test.dart` | JSON round-trip, stats, backup and restore with mixed colony and zone plates, restore into an older-format store |
| UI | `app/test/zones_ui_test.dart` | Setup → review → edit → save → appears in list and CSV |
| Regression | Existing 93 tests | Unchanged and passing |

## 8. Docs and store

- README feature list, `docs/` user guide section, and a web help page section (Thai/English).
- Store listing: add the feature with the disclaimer wording. Privacy is unchanged, since
  everything stays on the device.
- Bump the version to 0.6.0 and write release notes.

## Milestones

| # | Milestone | Days | Output |
|---|---|---|---|
| M0 | Collect 30–50 real plates with calliper readings | Runs alongside M1 | Labelled test set |
| M1 | Python detector, synthetic generator, CLI, evaluation | 5 | `zones.py`, metrics on real photos |
| — | **Gate** (AST.md) | — | Go / semi-automatic / shelve |
| M2 | Dart port + fixtures | 3 | `zones.dart`, matches Python |
| M3 | Data model, storage, panels, backup | 2 | `zone_record.dart`, store changes |
| M4 | Setup, capture, review screen | 5 | Working flow on a phone |
| M5 | Experiment stats, CSV, annotated image | 3 | Export files |
| M6 | Translation, disclaimer, docs, store text, tests, beta | 3 | 0.6.0 build for closed testing |

About **21 working days (4–5 weeks)** after the gate, in line with the AST.md estimate.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Hazy edges or colonies inside zones give unstable edges | RANSAC fit, confidence colours, user confirms low-confidence zones |
| Scale error from tilt or wrong plate format | Check against the 6 mm disks; warn above 5 % mismatch; camera guide |
| Wells hard to detect | Long-press to add; wells can be placed entirely by hand in v1 |
| Printed disk codes or coloured disks confuse detection | Detect by size and roundness, not colour; manual add |
| Reflections from the lid | Capture tip: lid off, dark background |
| Users reading results as clinical S/I/R | No S/I/R anywhere; disclaimer in app, listing and CSV header |

## Decisions (made October 2026)

1. **Entry point:** a new **Zones** tab on the home screen. The colony tabs are unchanged.
2. **Wells in v1:** **automatic detection**, the same as disks (`find_wells` / `findWells`),
   with long-press to add any the app misses. The 2 days are kept in the estimate.
3. **Labels:** **saved panels** from the start, with free text still allowed per disk.
4. **Display precision:** **whole mm on screen**, as in EUCAST reading. The CSV keeps
   `diameter_mm` to 0.1 mm, plus `diameter_mm_rounded` as shown on screen. Summary means and
   SDs are calculated from the unrounded values and shown to 0.1 mm.
