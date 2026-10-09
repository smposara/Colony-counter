# Calibration wizard for zone measurement: implementation plan

A short guided check of the zone measurement on one phone and setup. You need only:
- a **calliper** (or a ruler);
- a **used inhibition-zone plate**, already incubated.

No printer, target or special object is needed. The app measures the plate from a photo,
you measure the same plate with your calliper, and the app shows how well the two agree.
That agreement is kept with every zone plate measured on this phone and setup afterwards.

It builds on the zone feature ([AST_IMPLEMENTATION.md](AST_IMPLEMENTATION.md)), which is in
beta until it has been checked against calliper readings on real plates. The readings
collected here are that check.

## Why calibrate

Zones are read to the nearest mm, and a 1 % scale error is 0.3 mm on a 30 mm zone. The
detector takes its scale from the 6.0 mm paper disks, but some errors are invisible to it:

| Error source | Size | Seen today? |
|---|---|---|
| Scale from the dish rim (wells have no disks) | The rim is up to about 10 mm above the agar. At 120 mm camera height that is up to about 8 %, depending on which edge the plate finder locks onto | No: wells use the plate scale |
| Disk tolerance (6.0 ± ~0.1 mm) | Up to about 2 % | Partly (`scale_mismatch` above 5 %) |
| Lens distortion after the phone's own correction | 0.2–1 % between centre and edge; more on ultra-wide lenses | No |
| Phone switches lens at close range (macro / ultra-wide) | Changes scale between photos | No |
| Tilt | cos 3° ≈ 0.14 %, small | Yes (accelerometer check, 3°) |
| Where the edge is read (the app's 50 % threshold vs. the eye) | Up to about ±1 mm, depends on the lawn | No |

A printed target would only catch the first four. Comparing with calliper readings on a
real plate catches all of them, including the last one, which is usually the largest: how
this lab reads a zone edge.

## Scope

**In:**
- A guided wizard. Photograph a used zone plate, measure one long span and the zones with
  a calliper or ruler, enter them, and see the agreement.
- A saved calibration profile for each camera and setup, with a verdict, the bias and the
  limits of agreement.
- On every zone plate: whether it is calibrated, how the app compared with your calliper,
  scale checks and re-check reminders.
- More plates can be added to a calibration at any time, with a running agreement summary.
- Exporting the photos and readings as labelled test data for the zone feature's
  real-photo gate (opt-in).

**Out (v1):**
- Printed targets, rulers detected in the photo, and other reference objects.
- Any correction of measured zones or of the scale: v1 checks and reports only.
- Colour or exposure calibration.

## What the user measures

The plate is a **used, incubated zone plate** (disks or wells) from routine work. A good
calibration plate has:
- at least **6 clear zones**, ideally of different sizes;
- some zones near the edge of the plate (to show lens effects);
- no zones that overlap, and none with very hazy edges. The app suggests which zones to
  skip.

Two kinds of reading are entered, all in mm:

1. **One span: the scale check.**
   - The app picks the two disks (or wells) farthest apart and highlights them on the
     photo.
   - The user measures across them from outer edge to outer edge, usually 50–70 mm.
   - This is the plain scale at agar height. It doesn't depend on how a zone edge is
     read, so it separates "the camera scale is off" from "we read edges differently".
2. **Each zone's diameter,** numbered as on the screen.
   - Measure the way the lab normally reads zones, for example from the back of the plate
     against a dark background with the lid on.
   - A non-round zone is measured across two directions at right angles; the app averages
     them. It measures the mean diameter too.

**Tools:**
- **Calliper:** readings to 0.1 mm. 6 zones are enough.
- **Ruler:** readings to 0.5 mm. The app asks for at least 8 zones and widens the
  verdict limits (below), because a ruler adds its own reading error.

**Biosafety:** the plate is a used culture. Measure with the lid on, from the outside;
the calliper never touches the agar. Follow the lab's own rules for handling and
disposal. The wizard says this in one line.

## Analysis (`app/lib/core/zone_calibration.dart`)

`analyseCalibration(CalibrationInput)` is pure Dart and fast, so it needs no isolate. It
takes the zone measurement of each photo (from `measureZonesInPhoto`, as for a normal
plate) and the user's readings.

1. **Scale check:**
   - The app's span is the distance between the two disk centres plus both disk radii,
     in mm at the plate's scale.
   - `scaleError = appSpan / userSpan − 1`, in %.
   - For wells this checks the rim-based scale directly, which is the weakest part
     today.
2. **Zone agreement:**
   - For each zone, the difference is the app's diameter minus the user's (the mean over
     photos when there are several).
   - **Bias** is the mean difference. **SD** is the spread of the differences.
   - **95 % limits of agreement** are bias ± 1.96 SD (Bland–Altman).
   - Also reported: the largest absolute difference, and the % within 1 mm.
3. **Where the error comes from,** shown as hints, not numbers:
   - **Scale:** if the bias grows with zone size (the slope of the difference against the
     diameter is clearly not zero), the cause is the scale. The span check confirms it.
   - **Edge reading:** a steady offset with no slope means the app and the user read the
     edge at different places.
   - **Lens:** a larger difference for zones near the plate edge than for central ones
     points to lens distortion or tilt.
4. **Repeatability** (optional, from 2–3 photos with the plate turned a little between
   them): the SD of each zone's app diameter across photos.

Zones the detector flagged as `overlap`, `hazy` or `unmeasured` are offered but marked;
the summary leaves them out unless the user includes them.

**Verdict.** The calliper limits are set at half and all of the 1 mm reading step; the
ruler adds its own reading error.

| Verdict | Calliper | Ruler | Shown as |
|---|---|---|---|
| **Good** | \|bias\| ≤ 0.5 mm, limits within ±1.0 mm, \|scale error\| ≤ 1 % | \|bias\| ≤ 0.5 mm, limits within ±1.5 mm, \|scale error\| ≤ 1.5 % | "The app agrees with your calliper within about 1 mm" |
| **Usable** | \|bias\| ≤ 1.0 mm, limits within ±2.0 mm | \|bias\| ≤ 1.0 mm, limits within ±2.5 mm | "Within about 2 mm; check borderline zones by hand" |
| **Not good enough** | otherwise | otherwise | With the hint from step 3 |

Each hint comes with advice:
- **Scale:** check the disk size and plate type, the stand height, and use the main lens
  rather than zoom.
- **Edge reading:** "the app reads zones X mm larger than you do". Check the lighting,
  then decide whether to read borderline zones by hand. The app doesn't shift its edge:
  check only.
- **Lens:** move the camera further away and keep the plate centred.

**Progress (October 2026):** C1 is done.
- **Code:** `ml/colonycounter/zone_calibration.py` and `app/lib/core/zone_calibration.dart`
  hold the summary (`calibration_summary` / `calibrationSummary`), `farthest_pair` and
  `app_span_mm`.
- **Shared cases:** `ml/scripts/make_calibration_cases.py` writes 12 simulated cases to
  `app/test/fixtures/calibration_cases.json`: good, edge offset, 4 % and 8 % scale error,
  edge-of-plate zones, scattered readings, ruler, too few zones, 3 photos, excluded zones,
  usable and poor. Dart matches Python on every number to 1e-9.
- **A change from the plan above:** the slope is only judged when the zones differ in size
  by at least 5 mm (`kMinSizeSpread`). With zones of one size, the mean of the two readings
  varies mostly with the difference itself, so random scatter looked like a scale error.
- **CLI:** `colonycounter evaluate-zones` also prints the calibration summary when a label
  has `span_mm` (and `tool`).
- **Tests:** `ml/tests/test_zone_calibration.py` (12) and
  `app/test/zone_calibration_test.dart` (11), including end-to-end runs on the
  `zones_reflected` plate with readings set to the truth + 0.4 mm.

## The wizard (`app/lib/ui/zone_calibration_wizard.dart`)

A full-screen stepper. Each step is short, with one picture and one action.

1. **What you need:**
   - A calliper or ruler, and a used zone plate with at least 6 clear zones.
   - The same stand, distance and light as for real plates. About 5–10 minutes.
   - Choose **calliper** or **ruler**.
2. **Photograph the plate:**
   - The in-app camera with the zone tip (lid off, dark background, straight overhead) and
     all checks green.
   - Optionally 1–2 more photos with the plate turned a little, for repeatability.
   - Or "Use a plate I just measured": a zone plate from today, same camera and setup.
   - Choose the setup: **on the Colony Counter stand** or **hand-held**.
3. **Check the zones:**
   - The usual zone review, with large numbers on each zone. Fix the plate circle or add a
     missed disk if needed.
   - Zones to skip are marked; the user can turn any zone on or off.
4. **Measure the span:**
   - The two farthest disks are highlighted: "Measure from the outer edge of disk 2 to the
     outer edge of disk 5".
   - One number field. Values below 20 mm or above 90 mm are refused.
5. **Measure the zones:**
   - One field per zone, in screen order, with the zone highlighted on a small photo as
     each field gets focus.
   - An optional second field for non-round zones.
   - The keyboard's next key moves to the next zone.
6. **Result:**
   - The verdict in plain words.
   - A difference plot (app − calliper against the mean), the bias and limits, the scale
     check, and the hint.
   - A per-zone table: number, label, yours, app, difference.
   - "Save calibration", "Add another plate" (the profile then pools them) or "Try again".

**Entry points:**
- After the disclaimer, before the first zone plate: a strong suggestion, "Calibrate now"
  or "Later".
  - It isn't required. Users without a calibration can still measure, and their plates
    are flagged *Not calibrated*.
  - A user with no used plate yet can measure their first plate as usual, then calibrate
    with it ("Use a plate I just measured").
- On a saved zone plate: "Use for calibration" (same camera and setup, within 1 day).
- Settings → *Zone calibration*: run it again, add plates, see the history, delete a
  profile.
- On the Zones tab, a chip: *Calibrated: Good* / *Usable* / *Not calibrated* /
  *Calibrate again*.

## Data (`app/lib/data/zone_calibration_record.dart`, `plate_store.dart`)

- **`CalibrationProfile`:**
  - `id`, `createdAt`, `updatedAt`
  - `name` ("Stand, main camera", editable)
  - `cameraName` (`CameraDescription.name`), `imageWidth` / `imageHeight`, `platform`
    (`android`, `ios`, `web`)
  - `setup` (`stand` or `handheld`) and `rimRadiusPx` (to recognise the same setup)
  - `tool` (`calliper` or `ruler`)
  - `plates`: one entry per calibration plate, with the zone record ID, the span (user and
    app), and per zone the user reading(s), the app diameter(s) and whether it is
    included
  - the summary: n, bias, SD, limits of agreement, largest difference, % within 1 mm,
    scale error, slope, the edge-vs-centre difference, repeatability, verdict, hint
- **Storage:** store key `zone_calibrations` (a list); the newest one valid for the
  current camera and setup is "active". Calibration plates are ordinary `ZoneRecord`s,
  with their photos, marked `usedForCalibration`. Everything goes in the backup zip.
- **`ZoneMark`:** gains `calliperMm` (and `calliperMm2` for the second direction).
  - These are the user's readings. They are kept apart from `diameterMm`, the app's value
    as edited, and never change it.
- **`ZoneRecord`:** gains `calibrationId` (or empty) and plate flags:
  - `uncalibrated`
  - `calibration_old`: the profile is more than 90 days old.
  - `calibration_other_camera`: the camera name or resolution differs.
  - `calibration_setup_changed`: the rim radius differs by more than 3 % from the
    profile's. This happens on a stand at a different height, or when hand-held.
- **No new dependency:** the camera is identified by its plugin name and resolution, not
  the phone model, so nothing is added (privacy and offline unchanged).

**Progress (October 2026):** C2 is done.
- **Zone marks** gain `calliperMm`: one reading, or two at right angles. It is kept apart
  from `diameterMm` and never counts as an edit. **Zone plates** gain `camera`,
  `calibrationId` and `usedForCalibration`. Older data loads with none of them.
- **`zone_calibration_record.dart`:**
  - `CalibrationPlate.fromRecord` snapshots the zones that have readings, with the span
    across the farthest pair of disks. `doubtfulForCalibration` spots overlap, hazy and
    unmeasured zones, which are left out by default.
  - `CalibrationProfile` stores camera, photo size, platform, setup, rim radius, tool and
    plates. Its `summary` is pooled over plates; the span check is the mean of the per-plate
    span ratios. `withPlate` replaces an earlier snapshot of the same plate.
- **Matching:**
  - `activeCalibration` picks the newest profile for the camera and photo size. The size
    matches in either orientation.
  - `statusAgainst` judges a photo against a profile: calibrated, uncalibrated, old
    (more than 90 days since the last plate was added, counted on the photo's day),
    other camera, or setup changed (stand rim radius more than 3 % off; hand-held
    profiles skip this check).
  - `recordCalibration` uses the profile a plate was saved with, else the active one.
  - `calibrationFlags` gives the plate flags.
- **Store and backup:** the `zone_calibrations` key in the store and in the backup
  manifest. Restore skips known IDs, and calibration plates restore with their readings.
- **Tests:** `app/test/zone_calibration_data_test.dart` (18).

## Using the profile on zone plates (check only)

The profile never changes a measured zone or the scale it was measured at.

- **Review screen:** a chip shows *Calibrated: Good (bias +0.3 mm, ±0.9 mm)*, *Usable*,
  *Not calibrated* or *Calibrate again*. Tapping it opens the profile.
- **Wells:** when the profile's span check found the rim scale off by more than 2 % on the
  same setup, well plates on that setup get a warning with the likely size: "Zones may
  read about N % small" (N from the profile's scale error).
- **Disks:** when the disk-based scale differs by more than 2 % from the scale the
  profile was checked at, the warning is "check the disk size and the plate type".
- **Re-check reminders:** the chip and the plate show "Calibrate again" when the profile
  is older than 90 days, or the camera, resolution or stand setup no longer matches. It is
  offered again before the next zone plate.
- **CSV:** `zones.csv` gains `calliper_mm`, `calibration_id`, `calibration_verdict` and
  `calibration_bias_mm`. `zone_summary.csv` is unchanged.

## Gate data export

The calibration readings are real photos paired with calliper values, which is exactly
what the zone feature's real-photo gate needs (30–50 plates, AST.md). Settings → *Zone
calibration* → **Share as test data** makes a zip:
- the photos;
- one JSON per plate with the zones, the app's and the user's readings, the span, the
  tool, the camera and the setup.

It matches `colonycounter evaluate-zones`. It's opt-in and stays on the phone until the
user shares it. When the pooled readings reach n ≥ 30 plates and meet the gate's limits,
the profile says so. The beta label is only dropped by a release, not by the app itself.

## Python reference (`ml/colonycounter/zones.py`)

- `evaluate_zones` gains the same summary as the Dart analysis: span check, bias, limits,
  slope and edge-vs-centre difference. Dart and Python then report the same numbers on
  the same data.
- **Fixtures:** the existing synthetic zone plates (`zones_*.jpg/json`). Their true
  diameters and disk positions stand in for calliper readings. Each fixture gets
  "readings" with a known bias, noise and scale error added (for example the true value
  + 0.4 mm + N(0, 0.3)), so the analysis must recover the bias, the limits and the scale
  error.

## Tests

| Level | File | Checks |
|---|---|---|
| Python | `ml/tests/test_zone_calibration.py` | Known bias, noise, scale error and edge effects recovered from simulated readings; verdicts for calliper and ruler |
| Dart core | `app/test/zone_calibration_test.dart` | Same cases as Python (agreement within 0.01 mm); span from the farthest disks; skipped zones left out; slope → scale hint, offset → edge hint |
| Data | `app/test/zone_calibration_data_test.dart` | Profile JSON round trip; `calliperMm` kept apart from `diameterMm`; active profile per camera and setup; flags (old, other camera, setup changed); backup and restore; test-data zip contents |
| UI | `app/test/zone_calibration_ui_test.dart` | The wizard end to end on a fixture; span limits refused; ruler needs 8 zones; the result and difference plot; "Use a plate I just measured"; entry after the disclaimer; chips and reminders; Thai at 360 × 640 |
| Regression | the existing 208 tests | Unchanged and passing |

## Milestones

| # | Milestone | Days | Output |
|---|---|---|---|
| C1 | Analysis in Dart and Python, simulated-reading fixtures | 2 | `zone_calibration.dart`, `evaluate_zones` summary, matching tests |
| C2 | Calliper fields on zone marks, profile storage, backup | 2 | `zone_calibration_record.dart`, store changes |
| C3 | Wizard: photo, span, zones, result, add a plate | 3 | Working wizard on a phone |
| C4 | Profiles on zone plates: chips, warnings, reminders, CSV columns | 2 | Zone plates show their calibration |
| C5 | Test-data export, strings (en/th), docs, store text, release | 2 | Beta build |

About **11 working days**, shorter than the printed-target plan because there is no target,
PDF or target detector.

**First real-world check:** two people calibrate on the same 3 plates with the same calliper,
on 2 phones, on the stand and hand-held. The difference between the two people shows the
reading error that any calliper calibration has, and sets how strict the verdict limits
can usefully be.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Calliper readings have their own error (often ±0.5 mm between readers) | The verdict uses limits of agreement, not a single zone; ruler limits are wider; the first real-world check measures reader error; the result says "agrees with your readings", not "is accurate" |
| Few zones, or all of a similar size, so the slope (scale) can't be judged | At least 6 zones (8 with a ruler); the span check gives the scale on its own; "Add another plate" pools plates |
| Zones that aren't round | Two directions measured and averaged; the app uses its fitted mean diameter |
| Hazy or overlapping zones inflate the differences | They are marked and left out by default |
| Wrong zone typed into the wrong field | The zone is highlighted as each field gets focus; a difference above 3 mm asks "Is this zone N?" |
| Used plates are live cultures | Measure with the lid on, from the outside; a biosafety line in the wizard; the lab's own rules apply |
| The plate dries or the lawn changes between the photo and the readings | Measure right after the photo; the wizard keeps both steps together |
| Users skip calibration | Prompt after the disclaimer; *Not calibrated* chip and flag on every plate; CSV column |
| Calibration read as validation of the method | The result says it compares the app with this user's own readings on this setup; the beta label stays until the gate passes |
| Web camera gives a different resolution or lens each time | Web profiles keyed by image size; a note in the wizard; the setup check on every plate |

## Decisions (made October 2026)

1. **Mandatory or optional:** **strongly suggested.** Offered after the disclaimer, with
   "Later" allowed; uncalibrated plates are flagged *Not calibrated*.
2. **Correct or only check:** **check only.** v1 never changes measurements. It reports
   the agreement and warns, for disks and for wells.
3. **What is used:** **only a calliper (or ruler) and a used agar plate.** No printed
   target and no reference object. The calibration plate is a real, incubated zone plate.
4. **Re-check:** **every 90 days, and whenever the setup changes:** a different camera
   name, resolution or stand height (rim radius off by more than 3 %).
5. **Gate data through the app:** **yes.** It's opt-in, stays on the phone, and the user
   shares it as a zip.
