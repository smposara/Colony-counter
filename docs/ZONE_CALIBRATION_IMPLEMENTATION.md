# Camera calibration wizard for zone measurement: implementation plan

A short guided check, run once per phone and setup before measuring inhibition zones. It
shows how accurately this camera, at this distance and with this lighting, measures known
diameters, and keeps the result with every zone plate. It builds on the zone feature
([AST_IMPLEMENTATION.md](AST_IMPLEMENTATION.md)), which is in beta until it has been checked
against calliper readings on real plates.

## Why calibrate

Zones are read to the nearest mm, and a 1 % scale error is 0.3 mm on a 30 mm zone. The
detector already takes its scale from the 6.0 mm paper disks, but some errors are invisible
to it:

| Error source | Size | Seen today? |
|---|---|---|
| Scale from the dish rim (wells have no disks) | The rim is up to about 10 mm above the agar. At 120 mm camera height that is up to about 8 %, depending on which edge the plate finder locks onto | No: wells use the plate scale |
| Lens distortion (barrel/pincushion) after the phone's own correction | 0.2–1 % between centre and edge; more on ultra-wide lenses | No |
| Phone switches lens at close range (macro / ultra-wide) | Changes scale and distortion between photos | No |
| Printer or disk tolerance (disks are 6.0 ± ~0.1 mm) | Up to about 2 % | Partly (`scale_mismatch` above 5 %) |
| Tilt | cos 3° ≈ 0.14 %, small | Yes (accelerometer check, 3°) |
| Where the edge is read (50 % threshold vs. the eye) | Up to about ±0.5 mm, depends on the lawn | No |

The calibration measures all of these together, end to end, through the same detector
the zone plates use.

## Scope

**In:**
- A printable calibration target: a "zone plate on paper" with zones of known size.
- A guided wizard: get the target, check the print, set up, take 3 photos, see the result.
- A saved calibration profile for each camera and setup.
- A cross-check of every zone plate against the profile.
- A check of every well plate's scale against the profile (warn only).
- An optional calliper check on real plates (Bland–Altman summary). The same data serves
  as the real-photo gate data the zone feature still needs.

**Out (v1):**
- Full camera intrinsics (checkerboard, multi-pose).
- Correcting tilt from the photo.
- Colour or exposure calibration.
- Automatic correction of measured zones beyond scale. Radial distortion correction is
  a decision below.

## Architecture overview

```
calibration_target.dart (geometry, one source of truth)
   ├─► calibration_sheet.dart ─► PDF (A4 / Letter, print at 100 %)
   ├─► ml/colonycounter/calibration.py ─► synthetic target photos for tests
   └─► zone_calibration.dart: photo ─► find target ─► measure its zones with zones.dart
                                       ─► compare with true sizes ─► CalibrationResult
CalibrationWizard (ui) ─► CalibrationProfile (store) ─► used by every zone plate:
   flags, scale cross-check for disks and wells, re-check reminders (warn only)
```

## 1. The calibration target

`app/lib/core/calibration_target.dart` holds the geometry, all in mm, used by the PDF, the
detector and the Python generator.

- An **85 mm disc** that fits inside a 90 mm dish (cut along the printed outline).
- **Zones:**
  - The lawn is printed light grey with a fine noise texture, so the detector sees a lawn
    rather than flat paper.
  - Each zone is a dark grey disc with a white 6.0 mm "paper disk" at its centre. This
    matches the reflected-light, `dark_zone` polarity.
  - One centre zone of **30 mm**.
  - Six zones at 24 mm from the centre, of **10, 11, 12, 13, 14 and 16 mm**. The sizes are
    all different, so each zone is identified by its size and clockwise order, and none
    reaches past 32 mm from the centre.
- **A thin 80.0 mm reference circle** near the edge. It gives a precise large-scale value
  and a third radius for estimating distortion (centre, 24 mm, 40 mm).
- **An orientation mark:** a small black triangle at 12 o'clock.
- **A 60.0 mm print-check bar** across the lower part of the disc, with 10 mm ticks. The
  user measures it before cutting the target out.
- **Under the disc:** the target version (`CC-ZT1`), "print at 100 % / actual size", and
  a QR code with the version, so a photo of the wrong target is rejected.

Disks and zones are printed as filled shapes with sharp edges, so the "true" zone edge is
known exactly. A real lawn's edge is softer; the calliper check (section 6) covers that.

**No printer?** A fallback mode uses any flat, round object up to 30 mm across that the
user has measured with a calliper (for example a coin), laid on the agar. It checks the
scale only (one size, one position), and the profile is marked "scale only".

## 2. Analysis (`app/lib/core/zone_calibration.dart`)

`analyseCalibrationPhoto((Uint8List, CalibrationOptions))` runs in `compute`, like
`measureZonesInPhoto`. For each photo:

1. **Find the plate and the target:**
   - `findPlate`, then `findDisks` with `diskMm: 6`. It should find 7 white disks.
   - Identify each zone by its expected size and its angle from the orientation mark.
     The photo is rejected if fewer than 6 of the 7 are found ("Target not found:
     centre it in the dish and keep the whole disc in view").
2. **Measure:**
   - Measure the 7 zones with `measureZones`, with the disks given, exactly as on a real
     plate. Also fit the 80 mm reference circle.
3. **Compare:**
   - Each true size is the nominal size × the print factor (section 3, step 2).
   - Compute, in mm, the error of each zone (measured − true), the mean bias and the
     largest absolute error.
4. **Scale:**
   - The disk-based scale the detector used, compared with the true scale from the
     80 mm circle (the `diskScaleError` %).
   - The plate-rim scale compared with the true scale (the `rimScaleError` %).
5. **Distortion:**
   - Fit `s(r) = s0 · (1 + k1 · r²)` to the scale at the three radii (centre zone, ring
     zones, 80 mm circle). `r` is measured from the image centre and normalised by half
     the image diagonal.
   - Report the edge-to-centre difference as a percentage.

Over the 3 photos (the user turns the target between photos):
- **Repeatability:** the SD of each zone's diameter across photos.
- Turning separates print errors (they move with the target) from lens errors (they stay
  with the image).
- The final error is the per-zone mean.

**Verdict.** EUCAST reads to the nearest mm, so the limits sit at half of that:

| Verdict | Largest error | Repeatability SD | Advice shown |
|---|---|---|---|
| **Good** | ≤ 0.5 mm | ≤ 0.2 mm | — |
| **Usable** | ≤ 1.0 mm | ≤ 0.4 mm | "Zones within about 1 mm; check borderline ones by hand" |
| **Not good enough** | > 1.0 mm | > 0.4 mm | Specific advice (see below) |

For "not good enough", the advice depends on what failed:
- Large `diskScaleError`: check that the print factor was measured correctly, or that
  the disks aren't a different size.
- Error growing towards the edge: move the camera further away, or use the main lens and
  not 2× zoom.
- High SD: lock focus, use the stand, check the lighting for glare.

## 3. The wizard (`app/lib/ui/zone_calibration_wizard.dart`)

A full-screen stepper. Each step is short, with one picture and one action.

1. **Why and what you need:**
   - About 5 minutes, a printer (or a calliper and a round object), a ruler or calliper,
     scissors, and an unused agar plate.
   - It uses the same stand, distance and light as for real plates.
2. **Get the target:**
   - "Share PDF" (A4 or Letter) with the warning "print at 100 % (actual size), not
     'fit to page'".
   - Or "I have no printer" → the object mode.
3. **Check the print:**
   - Measure the 60 mm bar and enter the length (to 0.1 mm with a calliper, 0.5 mm with
     a ruler).
   - Outside 57–63 mm: "Printed at the wrong size: print again at 100 %".
   - Otherwise save `printFactor = measured / 60`.
4. **Set up:**
   - Cut out the disc and lay it flat on the agar of an unused plate, lid off. Putting it
     on the agar keeps it at the height where real zones are. An empty dish is not offered:
     the paper would sit lower than the agar surface.
   - Choose the setup: **on the Colony Counter stand** or **hand-held**.
5. **Take 3 photos:**
   - The in-app camera (`CaptureScreen`) with the zone tip and all checks green, plus a
     prompt: "Turn the target a little between photos".
   - On the web: the phone's own camera, with a note that the browser may change lens or
     resolution.
6. **Result:**
   - The verdict in plain words, then a table of the 7 zones (true, measured, error), the
     scale checks, the edge-to-centre difference and the repeatability.
   - "Save calibration", or "Try again" with the advice.
7. **Optional:** "Check against your calliper on real plates" (section 6), now or later.

**Entry points:**
- After the disclaimer, before the first zone plate: a strong suggestion, "Calibrate now
  (5 min)" or "Later". It isn't required: users without a printer can still measure, and
  their plates are flagged *Not calibrated*.
- Settings → *Zone camera calibration*: run it again, see the history, delete a profile.
- On the Zones tab, a chip: *Calibrated: Good* / *Not calibrated*.

## 4. Data (`app/lib/data/zone_calibration_record.dart`, `plate_store.dart`)

- **`CalibrationProfile`:**
  - `id`, `createdAt`
  - `name` ("Stand, main camera", editable)
  - `cameraName` (`CameraDescription.name`) and `imageWidth` / `imageHeight`
  - `platform` (`android`, `ios`, `web`)
  - `setup` (`stand` or `handheld`), `targetVersion`, `mode` (`target` or `object`)
  - `printFactor`
  - per-zone results (true, measured mean, SD), `bias`, `maxAbsError`, `repeatabilitySd`,
    `diskScaleError`, `rimScaleError`, `k1`
  - for the stand only: `mmPerPxAtAgar` (true mm per pixel at agar height) and
    `rimRadiusPx` (to recognise the same setup again)
  - `verdict`, and the 3 photos (kept for audit and export).
- **Storage:** store key `zone_calibrations` (a list); the newest one valid for the
  current camera is "active". The profiles and photos go in the backup zip.
- **`ZoneRecord`:** gains `calibrationId` (or empty) and plate flags:
  - `uncalibrated`
  - `calibration_other_camera`: the camera name or resolution differs.
  - `calibration_setup_changed`: the rim radius differs by more than 3 % from the
    profile's. This happens on a stand at a different height, or when hand-held.
  - `scale_disagrees_calibration`: the disk scale and the profile's scale differ by more
    than 2 %.
- **No new dependency:** the camera is identified by its plugin name and resolution, not
  the phone model, so nothing is added (privacy and offline unchanged).

## 5. Using the profile on zone plates

v1 only checks and warns. It never changes a measured zone or the scale it was
measured at. Corrections (the stand scale for wells, the radial `k1`) stay off until the
calliper data supports them (see Decisions).

- **Disk plates:** the disk-based scale is still used. If the profile is from the same
  setup, compare the two scales: more than 2 % apart gives the
  `scale_disagrees_calibration` warning, with the advice "check the disk size and the plate
  type".
- **Well plates:** with no disks, the rim scale is still used. If the profile is from the
  same setup (rim radius within 3 %), compare the rim scale with the profile's
  `mmPerPxAtAgar`. More than 2 % apart gives the `scale_disagrees_calibration` warning, with
  the size of the likely error: "Zones may read about N % small" (N from the two scales). On the stand this is the
  expected case (the rim sits above the agar), so the warning is the main help for wells
  in v1.
- **Re-check reminders:** a profile older than 90 days, or a plate whose camera, resolution
  or stand setup no longer matches the profile, shows "Calibrate again". It is shown on the
  plate and on the Zones tab chip, and offered again before the next zone plate.
- **Review screen:** a chip shows *Calibrated: Good (±0.5 mm)*, *Usable (±1 mm)* or
  *Not calibrated*, and the export notes the calibration.
- **CSV:** `zones.csv` gains `calibration_id`, `calibration_verdict` and
  `calibration_max_error_mm`.

## 6. Calliper check on real plates (optional)

The printed target has sharp edges; real lawns don't. This step measures what matters to
the user: the app against their own calliper.

- In the zone sheet, an optional **"Calliper (mm)"** field for each zone (0.1 mm).
- *Zone camera calibration → Calliper check*: a Bland–Altman summary over every zone
  with a calliper value:
  - n, mean difference (bias) ± SD, 95 % limits of agreement, and % within 1 mm;
  - a scatter plot of app vs. calliper, and a difference plot;
  - all of it per setup and per assay (disks / wells).
  This reuses the pattern of the colony accuracy screen (`accuracy.dart`).
- **Export:** `zones.csv` gains `calliper_mm`. The same photos and values are the labelled
  set the AST gate needs (30–50 plates). A "Share as test data" option creates a zip that
  matches `colonycounter evaluate-zones`.
- When n ≥ 30 and the bias and limits meet the gate (AST.md), the app can say so. It
  doesn't drop the beta label by itself.

## 7. Python reference (`ml/colonycounter/calibration.py`)

- **Target:** `render_target(params)` draws the target from the same geometry. The
  geometry is exported as `calibration_target.json`, so Dart and Python can't drift.
- **Synthetic photos:** `synth_calibration_photo(...)` adds:
  - a known scale and print factor;
  - radial distortion `k1`;
  - tilt (perspective);
  - a height offset;
  - blur, noise and uneven light;
  - the target turned by a random angle.
- **Analysis:** `analyse_calibration(photo, print_factor)` mirrors the Dart analysis.
  Fixtures (`calib_*.jpg/json`) check that Dart and Python agree, as for zones.
- **CLI:** `colonycounter calibrate photo1.jpg photo2.jpg photo3.jpg --print-bar-mm 59.8`.

## 8. Tests

| Level | File | Checks |
|---|---|---|
| Python | `ml/tests/test_calibration.py` | Target found when turned and tilted; k1 recovered within ±20 %; scale within 0.2 %; verdicts on good, distorted and blurred cases |
| Dart core | `app/test/zone_calibration_test.dart` | Same fixtures as Python (agreement ±0.1 mm); print factor applied; wrong target rejected; fewer than 6 zones → not found |
| Data | `app/test/zone_calibration_data_test.dart` | Profile JSON round trip; active profile per camera; backup and restore; plate flags for other camera, changed setup and disagreeing scale |
| UI | `app/test/zone_calibration_ui_test.dart` | The wizard end to end on fixtures; bad print size refused; the result table; entry after the disclaimer; Settings; chips; Thai at 360 × 640 |
| PDF | in the UI test | Target dimensions in the PDF match the geometry (points → mm) |
| Wells | in the data test | Stand scale used when the setup matches, rim scale plus a warning when not |
| Regression | the existing 208 tests | Unchanged and passing |

## Milestones

| # | Milestone | Days | Output |
|---|---|---|---|
| C1 | Target geometry, PDF sheet, Python renderer and synthetic photos | 2 | `calibration_target.dart/json`, `calibration_sheet.dart`, `calibration.py` |
| C2 | Analysis in Python and Dart, with fixtures | 3 | `zone_calibration.dart`, matches Python |
| C3 | Wizard, profile storage, backup, Settings entry | 3 | Working wizard on a phone |
| C4 | Profiles on zone plates: flags, scale cross-check (disks and wells), re-check reminders, chips, CSV columns | 2 | Zone plates show their calibration |
| C5 | Calliper check: field, Bland–Altman screen, test-data export | 2 | Gate data from users' own plates |
| C6 | Strings (en/th), docs, store text, tests, release | 2 | Beta build |

About **14 working days**. C1–C4 can ship on their own; C5 can follow.

**First real-world check:** print the target on 2–3 printers. Run the wizard on 3 phones
(one with an ultra-wide or macro lens switch), on the stand and hand-held. Compare the
reported errors with calliper readings of the printed zones.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Printed at the wrong size ("fit to page") | Measured 60 mm bar; refused outside 57–63 mm; the print factor corrects the rest |
| Paper on wet agar curls or soaks | Short exposure (photos take under a minute); heavier paper or a laminated print, laid flat on the agar |
| Phone switches lens close up | Profile keyed by camera name and resolution; rim-radius check catches a changed field of view; advice to move further away |
| Printed edges are sharper than real zones, so the result looks better than reality | Section 6 calliper check; results worded as "camera and scale accuracy", not "zone accuracy" |
| Users skip calibration | Prompt after the disclaimer; *Not calibrated* chip and flag on every plate; CSV column |
| Calibration read as validation of the method | The wizard and result say what was checked (scale, lens, repeatability) and what wasn't (the lawn edge, the method); the beta label stays until the gate passes |
| Web camera gives a different resolution or lens each time | Web profiles keyed by image size; a note in the wizard; scale cross-check on every plate |

## Decisions (made October 2026)

1. **Mandatory or optional:** **strongly suggested.** Offered after the disclaimer, with
   "Later" allowed; uncalibrated plates are flagged *Not calibrated*.
2. **Correct or only check:** **check only.** v1 never changes measurements. It compares
   each plate's scale with the profile and warns, for disks and for wells. The stand scale
   for wells and the radial `k1` correction stay off until the C5 calliper data shows they
   help.
3. **Where the target goes:** **on the agar of an unused plate.** No empty-dish fallback.
4. **Re-check:** **every 90 days, and whenever the setup changes:** a different camera
   name, resolution or stand height (rim radius off by more than 3 %).
5. **Gate data through the app (C5):** **yes.** It's opt-in, stays on the phone, and the
   user shares it as a zip.
