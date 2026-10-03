# Data collection protocol (v1: Nutrient Agar, 90 mm dishes)

Goal: a set of labelled plate photos to measure and improve counting accuracy.
**Target for Phase 1: 300 plates; for v1: 1,500 or more.**

## 1. What to plate

Coverage matters more than volume. Aim for a spread across all of these:

| Factor | Levels |
|---|---|
| Organisms | At least 5 with different colony looks. For example *E. coli* (smooth, cream), *S. aureus* (small, golden), *B. subtilis* (large, irregular, dry), *P. aeruginosa* (spreading, green tint), *S. epidermidis* or *Micrococcus* (pinpoint). Use local lab strains as they suit your biosafety level. |
| Density, colonies per plate | 0 · 1–25 · 25–100 · 100–250 · 250–500 · too many to count. Get there with a serial dilution series. |
| Incubation time | Typical endpoint (for example 24 h at 37 °C), plus some early (16 h, tiny colonies) and late (48 h, merged colonies) |
| Method | Spread plate (main); some pour plates (colonies inside the agar) |
| Artefacts on purpose (about 10 % of plates) | Condensation, bubbles, scratches, marker writing on the bottom, a spreader, a mixed culture |

## 2. Photographing
- Use the lightbox and the camera settings in `hardware/README.md`. Remove the lid.
- **Phones:** use at least 3 phone models in Phase 1 and 6 for v1 (Android and iPhone,
  low to high end). Photograph **every plate with every phone** on the same day. This is
  the best way to measure differences between phones.
- **Variation set:** on about 10 % of plates, also take photos without the lightbox
  (bench light, lid on, slight tilt). This measures how robust the app is outside the box.
- **File names:** `<plateID>_<phone>_<setup>.jpg`, for example `P0042_pixel8_box.jpg`.
  Never edit or crop the originals.

## 3. Information to record for each plate (`plates.csv`)
`plate_id, date, organism, medium, method (spread/pour), dilution (e.g. 1e-5),
volume_ml, incubation_h, incubation_temp_c, manual_count, counter_initials,
second_count, second_counter, notes`

## 4. Ground truth
- **Manual count:** count on the physical plate, marking colonies with a pen on the
  bottom, the usual way.
- **Second count:** a second person counts 20 % of plates without seeing the first
  count. This measures how much people disagree, which is the benchmark the app is
  aiming for.
- **Point labels:** one click per colony on the box photo from one reference phone.
  Use CVAT or Label Studio, "points" tool. Mark merged colonies with the "cluster"
  label and a count attribute. Save as `<image stem>.json`:
  `{"count": 87, "points": [[x, y], ...]}`. Then `colonycounter evaluate <folder>`
  reads them directly.
- Pre-label with `colonycounter count --json` and correct the output, rather than
  clicking from scratch. Once Phase 1 is running, Grounded-SAM2 can also help.

## 5. Splits
Assign each **plate** (all its photos, from all phones) to train, validation or test.
Never split by photo. Keep one phone model and one organism entirely in the test
set to check generalisation.

## 6. Storage and licence
- Keep originals, `plates.csv` and labels together. Back them up (lab drive or
  institutional cloud).
- Decide early whether to publish the dataset (for example on Zenodo, CC BY 4.0).
  A public smartphone colony dataset would be a useful contribution in its own right.
