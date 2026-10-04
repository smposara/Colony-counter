# Colony Counter app (Flutter, Android + iOS)

Photograph a 90 mm agar plate, get an automatic colony count, correct it by
tapping, and turn plate counts into CFU/mL. Everything runs on the phone, offline.

| Sample plan & replicates | Drop plate, blue/white | Time-kill comparison |
|---|---|---|
| ![sample](../docs/screenshots/sample-detail.png) | ![drops](../docs/screenshots/drop-plate.png) | ![compare](../docs/screenshots/compare.png) |

_Screenshots from the web build in Chromium on synthetic plates and demo data._

## Features (v0.2)
- **Guided capture** (`ui/capture_screen.dart`, phones): circle guide for the dish and
  live checks for level, focus and glare; tap to focus, focus and exposure lock.
- **Automatic count** (`core/`): a pure-Dart port of the Python reference pipeline in
  `ml/`. Steps: find the plate, mask the rim, correct the background, threshold, split
  touching colonies, estimate clusters, flag spreaders and too-numerous plates. Each
  colony's colour is measured too.
- **Review and edit** (`ui/review_screen.dart`):
  - tap to remove or add a colony; long-press to set "×N" for clusters
  - undo, zoom, move or resize the plate circle, sensitivity slider and recount
- **Samples with dilution series and replicates** (`ui/samples_screen.dart`,
  `data/sample_info.dart`):
  - Set up a sample once: dilutions (e.g. 10⁻⁴ to 10⁻⁶), number of replicates,
    volume, and optionally experiment, condition and time point.
  - The app lists every plate in the plan and offers "Photograph 10⁻⁵ · R2" for the
    next one. Sample, dilution and replicate are filled in automatically.
  - The result is **mean ± SD, CV and log₁₀ CFU/mL ± SD** across replicates. Each
    replicate pools its countable plates as ΣC / Σ(V·d). Counting rules: FDA BAM
    25–250, ISO 7218 10–300, or 30–300.
  - "New sample like this" copies a plan, e.g. for the next time point.
- **Drop plates (Miles–Misra)**:
  - Drops are found automatically by grouping nearby colonies. Tap a drop to set its
    dilution, replicate or TNTC, tap empty agar to add one, and drag to move it.
  - Two layouts: one dilution per plate (drops are replicates), or all dilutions on
    one plate. Drops are counted with the 3–30 colony range and the drop volume.
- **Colony colours**: *Blue / white* (X-gal screening) or *Two colours* (chromogenic
  agar). Each colony's colour is classified automatically, the app shows counts per
  class and the percentage, and you tap a colony to switch its class.
- **Compare** (`ui/compare_screen.dart`): samples with the same *Experiment* name are
  tabulated by condition and time point as log₁₀ ± SD.
  - **log reduction ± SD** and **% kill** against a chosen control (at the same time
    point, or the control's only one).
  - A **time-kill / growth chart** with error bars when there are two or more time
    points.
- **Export and backup**:
  - *Export CSV* shares two files: one row per plate (including drops and colour
    classes), and one row per sample with mean, SD, CV and log₁₀.
  - *Back up all data* makes one zip with every plate, plan, photo and both CSVs.
  - *Restore from backup* merges a zip back in; plates already present are kept.
    Use this to move data between phones and browsers, or to protect the web
    version's data.

## Layout
```
lib/
  core/   gray_image, plate, normalize, classical, pipeline   ← counting (pure Dart)
          colour (Lab, blue/white), spots (drop plates)
          calculator, stats (replicates, log reduction), capture_quality
  data/   plate_record, sample_info (plans, slots), plate_store, export (CSV, backup)
          storage/ (files on phones, IndexedDB on web)
  ui/     home (tabs), capture, photo_flow, review, save sheet,
          samples, sample_setup, compare (table + chart)
test/
  core_test.dart     golden plates: accuracy vs truth and vs the Python pipeline
  widget_test.dart   count → tap-edit → undo → save, end to end
  drop_plate_test.dart  drop plate from a plan: drops, dilutions, blue/white, CFU/mL
  ui_flows_test.dart    sample setup, replicate stats + next plate, log reduction
  features_test.dart    replicate stats, colour classes, drop-spot detection
  data_test.dart        CSVs, plan slots, backup → restore round trip
  capture_quality_test.dart
  fixtures/          synthetic plates + labels (ml/scripts/make_app_fixtures.py)
tool/compare.dart    prints Dart vs Python vs true counts
```

## Run it
```
flutter pub get
flutter test             # 42 tests
python tool/check_font_coverage.py   # every character in lib/ is in the bundled fonts
flutter run              # on a connected phone
dart run tool/compare.dart
```
CI (`.github/workflows/app.yml`) runs analyze and tests, then builds a release APK
(downloadable as a workflow artifact) and an unsigned iOS build.

To regenerate the golden fixtures after changing the Python pipeline, run
`python ml/scripts/make_app_fixtures.py` from the repo root. The Dart count must stay
within ±5 % of Python's.

## Web version (iPhone without the App Store)
The same app also builds as a web app that runs in Safari on iPhone, or in any
modern browser:
```
app/tool/package_web.sh        # → dist/colony-counter-web.zip (about 6 MB)
```
**Hosting:** unzip into any folder on a static web host. No server code and no
rewrite rules are needed, and the app works from a subfolder. Requirements:
- **HTTPS.** The browser only allows the camera on secure pages (`localhost` is
  fine for testing).
- `.wasm` files should be served as `application/wasm` (most hosts already do; on
  Apache add `AddType application/wasm .wasm`).
- Fonts and the rendering engine are bundled; nothing loads from Google or any
  CDN.

**On the iPhone:** open the URL in Safari, then Share → *Add to Home Screen* so it
opens full screen like an app.
- **Camera:** "Count plate" opens the iPhone's own camera. The in-app guide circle and
  live level/focus/glare checks are phone-app only.
- **Counting:** runs in the browser on the phone. Nothing is uploaded. Photos are
  scaled to 3000 px on the long side first.
- **Storage:** plates are saved in the browser's IndexedDB. Safari may clear a site's
  data if it is unused for about 7 days unless it was added to the Home Screen, so
  export the CSV regularly.
- **Speed:** counting runs on the page's main thread (browsers have no isolates), so
  the screen pauses for a few seconds while counting.


- **Not yet tried on a physical phone.** The build environment had no Android SDK or
  Xcode. Check the camera flow, the live checks and timing on real devices first.
- Photos are analysed with their short side scaled to 1800 px (about 65 µm/px for a
  dish filling 80 % of the frame). Colonies under about 0.2 mm may be missed until
  tiled full-resolution detection is added together with the trained model.
- The classical detector is the baseline. A trained detector (LiteRT / Core ML) will
  plug in behind `countColonies`, and the review screen stays the same.
