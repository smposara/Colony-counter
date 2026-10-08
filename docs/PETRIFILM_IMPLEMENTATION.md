# Counting Petrifilm plates: implementation plan

Status: **plan only**, not scheduled. Study, options and the go/no-go gate are in
[PETRIFILM.md](PETRIFILM.md). This plan covers **Option A** (Aerobic Count and
E. coli/Coliform plates) and outlines Option B.

## Scope

**In (Option A):**
- Plate types **AC** (Aerobic Count) and **EC** (E. coli/Coliform), chosen per sample.
- Plate and scale found from the round growth area and the printed **1 cm grid**.
- Grid lines removed before counting (reusing the membrane-filter code).
- Colony detection on the colour channel that suits the plate type.
- EC: **blue = E. coli** and **red = other coliforms** as two colour classes. Gas is tagged
  by hand on red colonies; only red colonies with gas count as coliforms.
- Counting ranges per plate type. Above the range, an **estimate from grid squares**
  (mean per 1 cm² × growth area), labelled as an estimate.
- CFU/mL and CFU/g from 1 mL inoculum and dilution. For EC, E. coli and coliform results
  side by side.
- Review, show/hide marks, manual fixes, export, backup and Thai/English, as for dishes.

**Out (Option B or later):** automatic gas detection, CC, EB (yellow zones), YM (yeast vs
mold), STX (disk step), Rapid plates, other dry films (Compact Dry, MC-Media Pad).

**Rules:**
- Colony counting on dishes and membranes must not change. All existing tests pass
  unchanged.
- Every plate-type value (counting range, growth area, colours) lives in one table, with the
  guide it came from, and is checked against Neogen's current interpretation guide before
  release.
- Trademarks are named only to say which plates the app reads, with a notice.

## Architecture overview

```
photo ─► find film + round growth area ─► grid pitch (1 cm) → mm/px, rotation
      ─► mask = growth area ─► remove grid lines (suppressGridLines)
      ─► colony contrast from the plate type's colour channel ─► existing detector
      ─► colour classes (EC: blue / red) ─► count, or square-based estimate if crowded
      ─► review (tag gas, fix marks) ─► PlateRecord (format: petrifilm) ─► CFU, export
```

As with the zone detector, it is built and checked in Python (`ml/`) first, ported to Dart
(`app/lib/core/`), and the two are compared on shared test images.

## 1. Plate-type table (`app/lib/core/petrifilm.dart`, mirrored in `ml/colonycounter/petrifilm.py`)

```dart
enum PetrifilmType {
  aerobic(label: 'Aerobic Count (AC)', min: 25, max: 250, growthAreaCm2: 20,
          classes: ['Colonies'], channel: ColonyChannel.redOnPale),
  ecoliColiform(label: 'E. coli/Coliform (EC)', min: 15, max: 150, growthAreaCm2: 20,
          classes: ['E. coli (blue)', 'Coliform (red + gas)'], channel: ColonyChannel.darkOnRed),
  ...
}
```

- One entry per type: label (en/th), counting range, growth area, inoculum volume (1 mL),
  colour classes, colony channel and a `source` note naming the guide and its version.
- AC 25–250 and the EC limit of 150 come from the guides cited in PETRIFILM.md. The EC lower
  limit (shown as 15) and both growth areas must be confirmed against the current guide
  before release.
- Counting ranges become `CountingRule` entries (e.g. `petrifilmAC`, `petrifilmEC`), so the
  existing calculator and the sample summary handle them.

## 2. Python reference (`ml/colonycounter/`)

**Progress (October 2026):** the Python reference for **all Option B types** (AC, EC, CC, EB,
YM) is done, with automatic gas detection: `petrifilm.py`, `synth_petrifilm.py`, CLI
(`petrifilm`, `evaluate-petrifilm`, `synth-petrifilm`), `scripts/petrifilm_benchmark.py`
and 12 tests. Synthetic benchmark: mean error AC 0.3 %, EC 0.8 %, CC 2.1 %, EB 0.8 %,
YM 1.0 %; crowded AC estimate +10 % (a synthetic artefact, see `ml/README.md`). Changes from
the design below:
- **Grid angle** from the rotation that makes the line map's row/column sums most peaked
  (skew detection); a spectrum-peak search was unreliable.
- **Grid removal** by replacing each line pixel with the colour from across the line, using
  the grid's known positions and measured line width (simple to port; no inpainting).
- **Growth area** by chroma edges voting for a centre one radius inwards, then refined
  along rays; thresholding failed on crowded plates.
- **Grid search** works on a line map with blobs removed (crowded plates otherwise give a
  wrong pitch) and on photos scaled to a short side of 1800 px, as in the app.
- **Gas bubbles** are found with the zone detector's sector ring score (bright rim only),
  radii every 0.75 px, two of eight sectors may fail; rings centred on colonies (yellow
  zones) are ignored, and specks on a bubble's dark outline are dropped.
- **Yeast/mold** uses each mark's own size (distance transform), merges molds split in two,
  and looks for yeasts merged into a mold's diffuse edge.

**Dart port (§3) done:** `app/lib/core/petrifilm.dart` (`countPetrifilmInPhoto`,
`countPetrifilm`, `findGrid`, `fillGridLines`, `findGrowthArea`, `findBubbles`), with six
golden films (`make_app_fixtures.py --petrifilm`: AC, EC, CC, EB, YM, crowded AC) checked in
`app/test/petrifilm_core_test.dart`. Dart and Python agree on the grid (pitch within 0.2 px),
growth area (within 1 px), counts and at least 90 % of the marks one by one. Shared helpers
were made public: `edt` (classical.dart), `RingTaps.ridgeSectorsAt`, `sobel3`,
`sampleBilinear` and `fitCircle` (zones.dart). On crowded synthetic films the growth area
comes out ~6 % small (the edge of the colony band, as the synthetic colonies stay 1.5 mm
inside the rim); check on real crowded films.

**Data and UI (§4–5) done** for all five types (AC, EC, CC, EB, YM), with these choices:
- Each film type is a `PlateFormat` (`filmAc` … `filmYm`, `film: 'ac'` …), so every format
  picker, record, backup and export carries the type with no separate field. Plating method
  `PlatingMethod.film`; counting ranges `CountingRule.filmAc` (25–250), `film150`, `film100`.
- Marks reuse `Colony.cls` for the type's two kinds (red/blue, yeast/mold) and gain `gas` and
  `yellow`. `PlateRecord.filmGrid` keeps the grid, so results and square estimates
  (`tallyFilm`) are recomputed after every edit. Older records load unchanged.
- Sample results per film result (`SampleInfo.analyse(..., result: 'coliform')`); the first
  result (e.g. E. coli) is the sample's headline value. A plate estimated from squares is
  not marked TNTC automatically.
- Review: film counter instead of the dish counter; modes Kind (EC, EB, YM), Gas (EC, CC, EB)
  and Zone (EB); faint marks for colonies that count towards no result; estimate banner with
  the squares used drawn on the photo. Sensitivity, drop plate and colour modes are hidden.
- Setup: "Film" method with a film-type picker and its counting range, 1 mL and 10⁻¹–10⁻³ by
  default. Plate list, sample card and save sheet show each result. CSV: `film_type`,
  `film_counts`, `film_estimates`, `film_squares` (plates), one row per result (samples,
  `result` column), `gas` and `yellow_zone` (colonies). Camera guide: film outline with its
  round area and a glare tip. About: the trademark notice. Strings: `l10n/parts/petrifilm.json`.
- Not done yet: tapping a grid square to include or exclude it; the store-listing notice
  (add with the release); a Thai food microbiologist's check of the terms.

**Grid check:** `find_grid` / `findGrid` score how clearly the grid repeats
(autocorrelation one pitch away minus half a pitch away, weaker axis). Below 0.3 the result
is flagged `grid_not_found` and the review shows a warning (synthetic films score 0.59–0.84,
also blurred or washed out; dish photos −0.18–0.23). The sub-pixel pitch step is limited to
±0.5 px, which stopped photos without a grid from giving a negative pitch (a crash in Python).
The 0.3 limit must be checked on real film photos.

Next: thresholds for colours, bubbles and molds must be set from real photos.

**`petrifilm.py`:**
- `find_growth_area(image)`: find the round growth area, about 50 mm across. Use a circle
  search tuned for that size (the foam ring on EC, the gel edge on AC). Fall back to the
  largest round region inside the film.
- `grid_pitch(gray, area)`: measure the grid spacing and angle. Use a line-response image (as
  in `grid.dart`), then the peak of its 2D autocorrelation (or FFT) gives the 1 cm pitch in
  pixels and the rotation. This is the scale (mm/px), checked against the circle size; flag
  `scale_mismatch` when they differ by more than 5 %.
- `colony_contrast(image, type)`: a signed contrast map from Lab. AC: red colonies on a pale
  gel (a* and lightness against the local background). EC: colonies darker or more saturated
  than the red gel. Then the existing background correction, grid removal and `detect()`.
- `classify_ec(colonies, image)`: blue vs red in Lab (hue / b*), reusing the
  `classify_colours` two-means approach with a minimum colour gap.
- `estimate_from_squares(colonies, grid, area)`: when the count is above the range, take the
  complete 1 cm squares inside the growth area. Use the mean colonies per square (the
  less-crowded squares, as a person would pick representative ones) × growth area in cm².
  Return the estimate and the squares used.
- `count_petrifilm(image, type) -> PetrifilmResult`: the whole pipeline. It returns colonies
  with class, flags (`estimated`, `tntc`, `scale_mismatch`, `gel_colour_change` for a whole
  plate gone pink or yellow) and per-class counts.

**`synth_petrifilm.py`:** synthetic films with a rectangular film, a round growth area,
printed grid lines, gel colour per type, coloured colonies (AC red; EC blue and red), gas
bubbles near some red colonies plus loose background bubbles, lighting gradient and glare.
Ground truth comes with each image.

**CLI and tests:**
- `colonycounter petrifilm photos/*.jpg --type ac|ec --overlay out/` and
  `colonycounter evaluate-petrifilm folder/`. Labels give counts per class and optional
  points.
- `tests/test_petrifilm.py`: grid pitch within 1 %; counts within ±5 % on synthetic plates in
  range; blue/red split ≥ 98 % on synthetic EC; estimate within ±15 % on crowded plates; dish
  pipeline unchanged.

**Gate (PETRIFILM.md):** on real photos, counts within ±10 % (or ±5) on ≥ 90 % of plates in
range, and class correct for ≥ 95 % of EC colonies.

## 3. Dart port (`app/lib/core/`)

- `petrifilm.dart`: the type table, `findGrowthArea`, `gridPitch`, `petrifilmContrast`,
  `estimateFromSquares` and `countPetrifilm`. Reuse `GrayImage`, `background.dart`,
  `grid.dart` (`suppressGridLines`), `classical.dart` (`detect`) and `colour.dart` (Lab).
- `pipeline.dart`: `countPhoto` takes the format; for `PlateFormat.petrifilm` it calls
  `countPetrifilm` and returns the usual `CountResult` (colonies with classes, flags), so the
  review screen works unchanged.
- Golden plates: extend `make_app_fixtures.py` with 4–5 Petrifilm cases (AC normal, AC crowded,
  EC mixed, EC with loose bubbles, rotated film). Add `test/petrifilm_core_test.dart` checking
  agreement with Python (counts ±3 %, class split ±2 colonies).

## 4. Data (`app/lib/data/`)

- `PlateFormat.petrifilm` ("Petrifilm growth area", round, about 50 mm, `film: true`). The
  plate finder uses the grid scale, not the nominal size.
- `PlatingMethod.film` ("Petrifilm (dry film)") in `sample_info.dart`, with
  `SampleInfo.filmType` (`PetrifilmType`) saved in JSON. Its counting rule comes from the type,
  the same way `membraneRule` works today.
- `PlateRecord`: `filmType` and per-colony `gas` (a bool on `Colony`, default false) for EC.
  Older records load unchanged, with no film type and no gas.
- Results: AC gives one CFU value. EC gives **E. coli** = blue colonies and **coliforms** =
  blue + red with gas, each through the calculator. The sample summary shows both.
- Estimates set the record's qualifier to "estimated", like TNTC today.
- Export: `plates.csv` gains `film_type`, `ecoli`, `coliform`, `red_without_gas` and
  `estimated_from_squares`. `colonies.csv` gains `gas`. Backup carries the new fields.

## 5. User interface (`app/lib/ui/`)

- **Sample setup:** plating method "Petrifilm (dry film)" with a plate-type picker (AC, EC).
  Volume defaults to 1 mL, and the counting rule comes from the type.
- **Capture:** a rectangular film guide in the camera (film outline, with the round growth
  area marked). Tips: lay the film flat on a white or dark background, avoid glare on the
  clear top film, photograph straight down.
- **Review:** the same screen and modes.
  - The grid is not drawn over the photo.
  - **EC:** the colour mode shows blue (E. coli) and red (coliform) marks. In a new **Gas**
    mode, tapping a red colony toggles "gas", shown as a small ring. The panel shows "E. coli
    12 · coliforms 31 (5 red without gas not counted)".
  - **Above the range:** a banner reads "Estimated from 4 grid squares: 1,240". In plate mode
    the squares used are highlighted, and tapping a square includes or excludes it.
  - A whole plate gone pink or yellow shows the existing check-this-count warning with a
    Petrifilm-specific message.
- **Plate list and samples:** a film icon, plate type, and E. coli / coliform values.
- **Notices:** an About line and the store listing: "Reads Neogen® Petrifilm® AC and EC
  plates. Petrifilm and Neogen are trademarks of Neogen Corporation; this app is not made or
  endorsed by Neogen." Plus a reminder that counts are an aid to be checked, not an
  AOAC-validated result.

## 6. Translation

New `app/lib/l10n/parts/petrifilm.json` (en/th): plate-type names, the Gas mode, the estimate
banner, capture tips and warnings. Have a Thai food microbiologist check the terms for
coliform (โคลิฟอร์ม), E. coli, gas (ฟองแก๊ส) and grid square (ช่องตาราง).

## 7. Tests

| Level | File | Checks |
|---|---|---|
| Python | `ml/tests/test_petrifilm.py` | Grid pitch, counts, EC classes, square estimate, flags |
| Dart core | `app/test/petrifilm_core_test.dart` | Agreement with Python on golden films |
| Data | `app/test/petrifilm_data_test.dart` | JSON round trip with `filmType` and `gas`; E. coli / coliform arithmetic; CSV columns; older backups restore |
| UI | `app/test/petrifilm_ui_test.dart` | Setup → capture (gallery) → review → tag gas → save → sample summary shows both values |
| Regression | All existing tests | Unchanged and passing |

## 8. Milestones

| # | Milestone | Days | Output |
|---|---|---|---|
| M0 | Step 0 survey; collect 20–40 photos per type with manual counts; check open datasets | Runs alongside M1 | Labelled test set |
| M1 | Plate-type table; Python grid scale, contrast, detection, EC classes, square estimate; synthetic films; CLI | 6 | `petrifilm.py`, metrics |
| — | **Gate** (PETRIFILM.md) | — | Go / adjust / shelve |
| M2 | Dart port + golden films | 4 | `petrifilm.dart`, matches Python |
| M3 | Data: plating method, film type, gas flag, E. coli/coliform results, export, backup | 3 | Data layer and tests |
| M4 | UI: setup, film capture guide, Gas mode, estimate banner and square picking | 5 | Working flow on a phone |
| M5 | Translation, notices, docs, store text, tests, beta build | 3 | Release candidate for closed testing |

About **21 working days (4–5 weeks)** after the gate.

## 9. Option B outline (later)

- **Automatic gas detection:** bubbles are round, with a bright rim and a dark edge, about
  0.3–2 mm across. Find them with the ring score from the zone detector (`ring_score`, signed
  sectors) at several sizes. Link a bubble to a red colony when it lies within about one
  colony diameter; loose bubbles are ignored. Keep the manual tag as an override.
- **CC:** like EC without the blue class.
- **EB:** red colonies plus a yellow halo test (a b* ring around the colony) and/or gas.
- **YM:** yeast vs mold from size, edge sharpness and texture (a third class), with mold
  counted separately.
- **STX:** a second photo after the disk step; pink-zone association.

## 10. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Plate appearance varies by type, lot and incubation time | Per-type channel and thresholds in one table; collect photos from several lots; accuracy tracking already in the app |
| Glare on the clear top film | Capture tips; glare check (`capture_quality.dart`); mask glare areas |
| Grid lines counted as colonies or splitting them | Existing grid removal (tested on membranes); golden films with grid |
| Gas rule done by hand is slow on busy plates | Option B automatic detection; Gas mode tap-to-toggle is fast meanwhile |
| Users treat app counts as validated results | Notices in app and listing; counts flagged when estimated or uncertain |
| Trademark misuse | Nominative use only, with notice; no logo; not in the app name |
| Values in the type table out of date | Each value carries its guide reference; recheck before each release |
