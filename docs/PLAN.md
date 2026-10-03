# Mobile Colony Counter — Research Summary & Build Plan

_Status: draft v0.1 · 2026-10-03_

Goal: a phone app that photographs an agar plate, counts the viable colonies
(CFU) automatically, lets the user check and correct the count, and turns the
plate count into CFU/mL (or CFU/g) using the dilution and plated volume.

---

## 1. What the research says

### 1.1 Existing apps and tools, and where they fall short

| Tool | Approach | What's known |
|---|---|---|
| **OpenCFU** (desktop, open source, 2013) | Classical image processing: thresholding plus circular-object filtering | Median error not significantly different from human counters on high-definition images. Needs well-lit, clean images. A good classical baseline to copy. |
| **APD Colony Counter App** | Watershed plus distance transform to split touching colonies | Developer reported 90.3 ± 6.4 % accuracy on only 12 plates. An independent comparison found it deviated more from manual counts than the other apps tested. |
| **Promega Colony Counter** (iOS) | Automatic count plus manual refine and mask-out | Best on chromogenic and blood agar, but it counted the plate rim as colonies and missed colonies in the centre. Recommended only together with manual correction. |
| **CFU.Ai** | Machine-learning based | Most accurate of the four apps in an independent study (strong on blood agar and LB). |
| **CFUCounter** | Smartphone segmentation | Adequate counting, good segmentation on modern phones. |

**What the independent comparison concluded:** "none of the tested smartphone apps can
fully replace manual counting." The common failures are:
- colonies on and near the plate rim (false positives from reflections, the lid edge and labels)
- small or pinpoint colonies being missed
- touching or merged colonies being counted as one
- glare and haloing from the lid and from domed colony surfaces
- accuracy that varies by medium (blood agar, chromogenic agar, LB)

**What this means for the app:**
1. A review-and-correct screen is required. It also produces training data for free.
2. Rim handling, small colonies and clusters are where the app can beat the others.
3. Capture quality (lighting and angle) matters as much as the model, so the app
   should guide capture actively.

### 1.2 Algorithms

| Family | Examples | Pros | Cons |
|---|---|---|---|
| Classical computer vision | Otsu or adaptive threshold, distance transform plus watershed, Hough circles (OpenCFU, APD, NICE) | No training data, fast, explainable | Fragile with uneven light, coloured or opaque media and clusters; needs tuning per medium |
| Object detection | Faster/Cascade R-CNN (AGAR baselines), YOLO-family, RT-DETR, D-FINE, RF-DETR | Robust, gives colony positions (needed for the review screen), mature mobile export | Small objects suffer when the image is downscaled, so tiling is needed; touching colonies are hard |
| Point-based counting | P2PNet-style models that predict one point per colony | Cheapest labels (one click per colony), handles dense scenes, still gives positions | Fewer off-the-shelf mobile toolkits |
| Density maps | CSRNet-style, Self-Normalized Density Map (SNDM) | Good totals on very crowded plates | No individual colonies to show or edit; poor for a review UI |
| Instance segmentation | Mask R-CNN (Naets 2021), CentroidNetV2, Cellpose | Colony size and shape, which helps split clusters | Masks cost more to label and run slower on phones |
| Foundation models, zero-shot | Colony Grounded SAM2 (Grounding DINO + SAM2, SPIE Medical Imaging 2026): mAP 93.1 %, Dice 0.85 on out-of-distribution data, weights released | No training needed; excellent for **pre-labelling** data | Too heavy for on-device real-time use; better offline or on a server |

Reference points from published results:
- YOLOv8n trained on AGAR: P 0.93, R 0.87, mAP50 0.92 at 640 px. A multi-task YOLOv8 study
  reports 98.3 % "counting accuracy within ±10 colonies", with a 3.2 MB FP16 model on Android.
- An open-source RF-DETR colony detector (1,324 labelled plates): 77.8 % of plates
  counted exactly, 94.1 % within ±1 colony.
- Colony-YOLO (a modified YOLOv8n for micro-colonies, 2025): about +12 % mAP over YOLOv8n.
- Adding synthetic colonies made with SAM (Applied Sciences, 2025) helps a lot when
  real labelled data is scarce.

**Recommended approach:** a hybrid pipeline (details in §3).
- A **lightweight detector run on tiles**, outputting points or small boxes, plus a
  **cluster-size head** that estimates how many colonies are inside each merged blob.
- A **classical OpenCV fallback** for the first version, for clean plates, and for
  pre-labelling.
- Grounded-SAM2 **offline only**, to speed up annotation.

### 1.3 Why tiling is required (resolution math)

A 12 MP photo is about 4000 × 3000 px. A 90 mm dish fills roughly 2,800 px across,
which is about 32 µm per pixel, so a 0.2 mm pinpoint colony is about 6 px wide.

If the whole plate is shrunk to the usual 640 px model input, that becomes about
140 µm per pixel and the same colony is about 1.4 px wide. It is effectively lost.

**Decision:** run the model on a crop of the plate at full or near-full resolution,
in overlapping tiles (SAHI-style), then merge the results. A 2,800 px plate cut into
about 5 × 5 tiles of 640 px with overlap is about 25 model runs. On a recent phone
neural chip that takes roughly 0.3–1 s, which is fine for a single capture.

### 1.4 Image capture: what improves accuracy
- **Reflections:** take the lid off where safety allows. Avoid direct overhead light. Use diffuse light or
  dark-field (light at a low, grazing angle), because glare and halos from domed
  colonies cause false detections and missed colonies.
- **Background:** a matte black background under a clear or translucent medium gives
  high contrast. For opaque media (blood agar), light from the top at a low angle.
- **Geometry:** hold the phone parallel to the plate at a fixed distance. A cheap
  3D-printed stand or lightbox (as in CoCoNut, and a portable dark-field box that
  reached 95 % agreement with lab counts) removes most of the variation.
- **Flat-field correction:** dividing by an image of an empty plate removes uneven
  background (as in CoCoNut). This could become an optional calibration step.

### 1.5 Counting rules from the standards (build into the calculator)
- **FDA BAM Chapter 3 (Aerobic Plate Count):** countable range 25–250 CFU per plate.
  Counts below 25 or above 250 are reported as *estimated* (EAPC). Plates with
  spreaders or lab accidents are reported as "Spreader". Count pinpoint colonies too.
- **ISO 4833-1 / ISO 7218:** weighted mean over two successive dilutions:
  `N = ΣC / (V × (n1 + 0.1·n2) × d)`. This simplifies to `ΣC / (V × 1.1 × d)` with one
  plate per dilution. Here ΣC is the total colonies on retained plates, V the plated
  volume in mL, n1 and n2 the number of plates at the first and second dilution, and d
  the first retained dilution. Results are rounded to two significant figures. ISO
  uses a different upper limit, usually 300 per plate. **Verify all limits against the
  purchased standard text before release.**
- Make the range and rule set a **preset** (FDA BAM, ISO 7218, ISO 4833-1, USP, or
  custom). Lab SOPs differ, commonly 30–300 or 25–250.
- Flag "too numerous to count" (TNTC), "too few to count" (TFTC), spreaders, and
  plates outside the range.

### 1.6 Public datasets

| Dataset | Content | Licence or caveat |
|---|---|---|
| **AGAR** (NeuroSYS, 2021) | 18,000 images, 336,442 annotated colonies (5 species: *S. aureus, B. subtilis, P. aeruginosa, E. coli, C. albicans*); labelled countable, uncountable or empty; COCO format | **CC BY-NC 2.0, non-commercial only.** Fine for research and pre-training; not usable in a commercial product without a separate agreement. Taken with lab cameras, not phones. |
| MicrobIA (Segments Enumeration, Haemolysis) | about 29k segments, 7 enumeration categories; about 2.4k haemolysis segments | Check licence |
| OpenCFU sample plates | Small benchmark set | Open |
| "Dataset for quantification of CFUs using AI" (Zenodo 6642518) | Smartphone or AI CFU set | Check size and licence (the page was not reachable during this research) |
| DIBaS | 660 microscope images, 33 species | Classification only; not useful for counting |

**Conclusion:** public data is enough to prototype. A product needs its **own
smartphone dataset** (§4).

### 1.7 Licensing traps
- **Ultralytics YOLO (v5/v8/11/26) is AGPL-3.0**, and that covers trained weights too.
  Shipping it in a closed-source app requires either open-sourcing the whole app or
  buying an Ultralytics licence.
- **Permissive alternatives (Apache-2.0 or MIT):** RF-DETR, RT-DETR, D-FINE, YOLOX,
  LibreYOLO. Use one of these if the app may ever be commercial.
- **AGAR is non-commercial**, as noted in §1.6.

---

## 2. Product scope

### Version 1 (MVP)
- Count colonies on standard round Petri dishes (90 mm first; 60 and 150 mm later),
  spread plates and pour plates.
- Media: start with 2–3 clear or translucent media (for example nutrient agar, TSA, LB),
  then add blood, MacConkey and chromogenic media.
- Guided capture, automatic count, review and edit, CFU/mL calculator, history,
  CSV export.
- Works fully offline on the phone.

### Later versions
- Counting by colour or morphology class (for example blue vs pink on chromogenic agar).
- Team sync, LIMS export, audit trail and e-signatures (21 CFR Part 11 / GLP).
- Spiral plates, membrane filters, Petrifilm, square plates.
- Colony size distribution and time-lapse growth.

### Out of scope for now
- Species identification as a diagnostic claim. This would make it a regulated
  device (IVD) and needs a separate regulatory track.

---

## 3. System architecture

```
┌──────────────────────── Mobile app (on-device, offline) ─────────────────────────┐
│ 1. Guided capture  →  2. Plate finder  →  3. Normalise  →  4. Detect (tiled)     │
│    (live checks)        (circle + rim       (flat-field,      detector + cluster  │
│                          mask, warp)         white balance)   count head; or     │
│                                                               classical fallback │
│ →  5. Post-process & QC  →  6. Review/Edit UI  →  7. CFU calculator  →  8. Store │
│    (merge tiles, size        (tap add/remove,     (presets: BAM,          (SQLite, │
│     filter, TNTC/spreader     lasso exclude,       ISO 7218, custom)       images, │
│     flags)                    zoom)                                        CSV/PDF)│
└──────────────────────────────────────────────────────────────────────────────────┘
                    │ optional sync (phase 4)
┌──────────── Backend ────────────┐   ┌──────────── ML pipeline ─────────────┐
│ API (FastAPI), Postgres,        │   │ Data lake of images + corrections    │
│ object storage, users/teams,    │──▶│ Pre-label (Grounded-SAM2/classical)  │
│ audit log, model registry,      │   │ Annotate (CVAT / Label Studio)       │
│ heavy "second opinion" model    │◀──│ Train (PyTorch) → eval → export      │
└─────────────────────────────────┘   │ (LiteRT for Android, Core ML for iOS)│
                                      └──────────────────────────────────────┘
```

### 3.1 Pipeline steps
1. **Guided capture.** Live preview with a circular guide overlay. Real-time checks:
   - phone tilt from the motion sensor (within about ±3°)
   - plate detected and filling 70–90 % of the frame
   - sharpness (variance of the Laplacian)
   - glare (share of over-exposed pixels)
   - exposure and focus locked before the shot

   Capture at full resolution. Optionally take a burst of 3 and keep the sharpest.
   Gallery import is supported but marked "unguided".
2. **Plate finder.** Find the dish with a Hough circle or ellipse fit, or a tiny
   segmentation model, then correct a slight perspective tilt. Default inner region =
   radius × 0.95 to exclude the rim; the user can adjust it. Mask out handwriting or
   labels (users can lasso them).
3. **Normalise.** Background or flat-field correction (an optional calibration photo
   of an empty plate), grey-world white balance, CLAHE contrast on the brightness
   channel only.
4. **Detect.**
   - **Detector:** tiled inference (640 px tiles, about 20 % overlap) with an
     Apache-licensed detector (RF-DETR-Nano, D-FINE-N or YOLOX-Nano), INT8 or FP16.
     Output: centre point, box and score for each colony. A **cluster-count head**
     (or a second-stage classifier on blob crops) estimates how many colonies are in
     each merged blob (1, 2, 3, …).
   - **Classical fallback:** adaptive threshold, then distance transform, then
     watershed, then filters on area and circularity.
5. **Post-process and QC.**
   - Merge the tiles (NMS or weighted box fusion on point distance).
   - Drop detections inside the rim margin.
   - Raise flags: **TNTC** (count above the preset limit, or colony density/coverage
     too high), **spreader** (large irregular blob covering more than X % of the
     area), **below range**, **low confidence** (many detections near the threshold),
     **mixed morphology** (colour/size clustering finds more than one group).
6. **Review and edit.** Markers drawn over the image, with:
   - tap to add or remove a colony; long-press a cluster to set "×N"
   - lasso to exclude a region; pinch to zoom; undo
   - a confidence slider showing how the count changes
   - a split-screen view of the original vs the overlay

   Every edit is saved as a correction. These are high-value training labels.
7. **Calculator.** Enter the sample ID (or scan a barcode or QR code), dilution
   factor, plated volume, sample mass or volume, and pick a rule preset. Several
   plates (duplicates and successive dilutions) feed the weighted-mean formula. The
   result is reported with its flags (estimated, TNTC, spreader).
8. **Store and export.** Keep the original image, the processed overlay, model
   version, parameters, automatic count, final count and edit history. Export CSV
   or PDF reports and share via the system share sheet.

### 3.2 Technology stack (recommended)

| Layer | Choice | Why |
|---|---|---|
| App framework | **Flutter** (Dart). Native Kotlin/Swift platform channels for camera controls | One codebase for Android and iOS, a good custom canvas for the review screen, mature LiteRT plugins. Alternative: React Native + VisionCamera, or fully native if the team is native. |
| Camera | Android CameraX / Camera2, iOS AVFoundation, through a thin native module | Manual exposure, focus and white-balance lock, full-resolution stills |
| Classical computer vision | OpenCV (native library via Dart FFI, or `opencv_dart`) | Circle finding, normalisation, watershed fallback |
| On-device ML | **LiteRT** (`.tflite`, GPU/NNAPI delegate) on Android, **Core ML** (Neural Engine) on iOS. Alternative: ONNX Runtime Mobile on both | Fastest on-device inference; one PyTorch → ONNX → LiteRT / Core ML export path |
| Local data | SQLite (drift), images in the app sandbox | Offline first |
| Training | PyTorch, plus SAHI-style tiling, Albumentations, MLflow or W&B | Standard, reproducible |
| Annotation | CVAT or Label Studio (point and box), with Grounded-SAM2 pre-labels | Faster labelling |
| Backend (phase 4) | FastAPI, Postgres, S3-compatible storage, Auth (OIDC) | Sync, teams, audit trail, model registry |

### 3.3 Proposed repository layout
```
/app            Flutter app (lib/, android/, ios/)
/ml             training, evaluation, export scripts, configs
/ml/notebooks   exploration
/vision-core    shared classical computer vision and post-processing (Python reference + C++/Dart port)
/hardware       3D-printable stand / lightbox (STL + build notes)
/backend        (phase 4) API service
/docs           plan, data protocol, validation reports
```
Keep a **Python reference implementation** of the whole pipeline in `/ml`. The
mobile version must match it on a fixed test set (the "golden images" test, see
§5.3).

---

## 4. Data strategy

1. **Data collection protocol** (to write in phase 0):
   - **Phones:** at least 6 models (low/mid/high-end Android plus 2–3 iPhones).
   - **Lighting:** lightbox, lab bench, window light.
   - **Plate condition:** lid on and off.
   - **Plates:** media × organisms × densities (0, 1–30, 30–300, 300+ / TNTC), plus
     spreaders, condensation, bubbles, handwriting and scratches.
   - Store the metadata with every image.
2. **Ground truth:** manual counts by 2 trained people on a subset to measure
   person-to-person variation, which is the target to match. Label with points (one
   click per colony), plus "cluster × N" points for merged colonies.
3. **Volume target:** 300 plates for the prototype; **1,500–3,000 plates** for v1;
   then keep growing through in-app corrections (with user consent).
4. **Pre-labelling:** run Grounded-SAM2 and the classical pipeline, and have people
   correct the output. This should make labelling 3–5× faster.
5. **Synthetic data:** cut colonies out with SAM and paste them onto photos of
   empty plates; vary density, size, colour and blur. Mainly useful for the dense
   and small-colony cases.
6. **Splits:** split by plate *and* by phone or session, never by image, to avoid
   leaking the same plate into train and test. Keep one phone model and one medium
   entirely unseen to test generalisation.
7. **Pre-training:** AGAR and other public sets for research or pre-training only,
   if the licence allows. Train the final production weights on owned data if the
   app is commercial.

---

## 5. Evaluation and validation

### 5.1 Metrics
- **Per plate (count):** mean absolute error (MAE), mean absolute percentage error
  (MAPE), share of plates within ±5 % / ±10 % / ±5 colonies, Bland–Altman bias and
  limits of agreement, Lin's concordance (CCC), linearity (slope and R²) over the
  range.
- **Per colony (detection):** precision, recall and F1 with point matching (match
  radius ≈ 0.5 × median colony radius); mAP for boxes.
- **Workflow:** time per plate including review; edits per plate; flag
  precision and recall (TNTC, spreader).
- Break every metric down by medium, phone, density bucket and lighting.

### 5.2 Acceptance targets for v1 (proposed)
- In the 25–250 range on supported media: **median absolute error ≤ 5 %** and
  **≥ 90 % of plates within ±10 % with no edits**.
- The bias from Bland–Altman stays within the person-to-person variation.
- Under 1 s from shutter to count on a mid-range 2023 phone.
- Under 60 s per plate including review.
- TNTC and spreader flag recall ≥ 95 %.

### 5.3 Engineering quality gates
- Golden-image regression suite: counts from the mobile pipeline must stay within
  ±1 of the Python reference.
- Benchmark speed and memory on a fixed set of real devices on each release.
- Every model release comes with a model card (data, metrics by group, known failure
  modes).

### 5.4 Formal validation (for regulated or quality-control labs, phase 4+)
- Follow the alternative-method validation ideas in USP <1223> and ISO 16140:
  accuracy, precision (repeatability and intermediate precision across operators and
  phones), linearity, range, limits of detection and quantification, robustness, and
  equivalence to manual counting.
- 21 CFR Part 11 features: user accounts, unchangeable audit trail, e-signatures,
  locked model versions.

---

## 6. Roadmap

| Phase | Duration | Deliverables |
|---|---|---|
| **0. Foundations** | 2 wks | Requirements and choice of rule presets; data collection protocol; 3D-printed stand / lightbox v1; first 200–300 plates imaged and counted manually; licence decisions (§8) |
| **1. Algorithm prototype** (Python) | 4–6 wks | Evaluation harness and metrics; plate finder; classical baseline; first detector (tiled) trained with pre-training plus own data; cluster-count head; error analysis report |
| **2. Mobile MVP** | 6–8 wks | Flutter app: guided capture, on-device inference (LiteRT / Core ML), classical fallback, review/edit UI, CFU calculator with presets, history, CSV export; internal beta with 5–10 lab users |
| **3. Accuracy hardening** | 6 wks | Corrections fed back into training (active learning); more media (blood, MacConkey, chromogenic) and colour-class counting; TNTC / spreader / low-confidence flags; testing across the phone set; v1 acceptance test |
| **4. Team & compliance** | 6–8 wks | Backend sync, workspaces, PDF reports, LIMS export, audit trail; validation study (§5.4); App Store / Play release |
| **5. Extensions** | ongoing | Membrane filters, Petrifilm, spiral plates; colony size statistics; time-lapse early counts; optional server "second opinion" model |

Rough total to a validated v1: **about 6–8 months** for a team of 1 mobile developer,
1 machine-learning engineer and a part-time microbiologist (who can also handle quality assurance).

---

## 7. Main risks and mitigations

| Risk | Mitigation |
|---|---|
| Accuracy changes with phone model and lighting | Guided capture, optional stand, a training set covering many phones, a phone held out for testing, flat-field calibration |
| Small or pinpoint colonies missed | Full-resolution tiled inference, small-object anchors and settings, synthetic dense data |
| Touching or merged colonies | Cluster-count head, watershed refinement, "×N" editing in the UI |
| Rim false positives (a known failure of Promega's app) | Strict rim mask, rim-region training negatives, user-adjustable inner region |
| Coloured or opaque media | Per-medium normalisation, a medium chosen in the UI as a model input, staged media support |
| Licences (AGPL models, non-commercial data) | Apache/MIT detectors; owned training data for production weights |
| Users trusting a wrong automatic count | Always show the overlay and flags; require review for flagged plates; never hide uncertainty |
| Regulatory scope creep (species ID) | Keep claims to "enumeration aid"; any ID feature on a separate regulatory track |

---

## 8. Decisions needed from you
1. **Commercial or academic/internal?** This decides whether AGAR and Ultralytics
   YOLO can be used, or Apache models and owned data only.
2. **Platforms:** Android only, iOS only, or both (Flutter assumes both)?
3. **Target users and rules:** food/water quality control (FDA BAM / ISO presets),
   pharma (USP), or research labs? Is GLP / Part 11 needed?
4. **Media and plate types for v1:** which 2–3 media and which dish sizes?
5. **Hardware accessory:** is an optional 3D-printed stand or lightbox acceptable,
   or must the app work freehand only?
6. **Team and budget:** who labels data, and roughly how many plates per week can
   the lab produce?

## 9. Immediate next steps (proposed)
1. Answer §8.
2. Set up the repository (`/app`, `/ml`, `/docs`) with CI, and add a data
   collection protocol document.
3. Image and manually count 200–300 plates (several phones, 2–3 media).
4. Build the Python evaluation harness and the classical baseline, and get first
   numbers.
5. Train the first tiled detector, compare it with the baseline, and choose the
   on-device model.

---

## Sources
- Performance of four bacterial cell counting apps for smartphones (J. Microbiol. Methods, 2022): https://www.sciencedirect.com/science/article/pii/S0167701222001038
- OpenCFU (PLOS ONE, 2013): https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0054072
- APD Colony Counter App, watershed: https://www.researchgate.net/publication/306018986_APD_Colony_Counter_App_Using_Watershed_Algorithm_for_improved_colony_counting
- Comparative study of colony counting apps and software (SN Computer Science, 2025): https://link.springer.com/article/10.1007/s42979-025-03883-9
- AGAR dataset: https://agar.neurosys.com/ · paper: https://arxiv.org/abs/2108.01234
- Assessing microbial colony counting with AGAR (Neurocomputing, 2025): https://www.sciencedirect.com/science/article/abs/pii/S0925231225003261
- Microbial counting resource list: https://github.com/majsylw/microbial-counting-review
- Self-Normalized Density Map for counting: https://arxiv.org/abs/2203.09474
- Colony Grounded SAM2 (SPIE Medical Imaging 2026): https://arxiv.org/abs/2603.13393
- Multi-task YOLOv8 colony detection with edge optimisation: https://arxiv.org/abs/2609.09818
- Colony-YOLO (Microorganisms, 2025): https://doi.org/10.3390/microorganisms13071617
- SAM-based synthetic augmentation for colony detection (Applied Sciences, 2025): https://doi.org/10.3390/app15031260
- RF-DETR / multi-engine colony detector (open source): https://github.com/akashbabu9392/colony_detector
- AGAR YOLO + style-transfer experiments: https://github.com/pranyprany/agar-colony-vision
- P2PNet, point-based counting (ICCV 2021): https://openaccess.thecvf.com/content/ICCV2021/papers/Song_Rethinking_Counting_and_Localization_in_Crowds_A_Purely_Point-Based_Framework_ICCV_2021_paper.pdf
- CoCoNut colony counter and lightbox (PLOS ONE): https://journals.plos.org/plosone/article?id=10.1371%2Fjournal.pone.0205823
- FDA BAM Chapter 3, Aerobic Plate Count: https://www.fda.gov/media/178943/download
- ISO 7218 colony-count calculator verification (ISO TC34/SC9): https://committee.iso.org/files/live/sites/tc34sc9/files/7218/Verification%20report_Calculator_CCT_V1.6_S%20Grosz_28-08-2020.pdf
- Ultralytics licence: https://www.ultralytics.com/license · Ultralytics LiteRT export: https://docs.ultralytics.com/integrations/tflite
- Ultralytics alternatives and licences (2026): https://www.lightly.ai/blog/best-ultralytics-alternatives-in-2026
- Flutter LiteRT plugin: https://pub.dev/packages/flutter_litert · ultralytics_yolo Flutter plugin: https://pub.dev/packages/ultralytics_yolo
- Promega Colony Counter: https://apps.apple.com/us/app/promega-colony-counter/id620431249

_Research note: several publisher sites (ScienceDirect, Springer, arXiv, PMC, Zenodo)
could not be reached from the research environment. Figures from those sources come
from abstracts or search summaries and should be checked against the full papers
before they are relied on._
