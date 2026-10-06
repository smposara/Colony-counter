# Plaque counting (bacteriophage): idea and decision plan

Status: **parked**. Not scheduled. Revisit after the 0.5.x closed test; earliest target 0.6.
See also the [AST plan](AST.md): run one demand survey for both.

## Origin

Facebook comment from a phage researcher (October 2026):

> "I work on bacteriophage and sometimes I face problems to count tiny plaques
> from plate, so you also can extend this app with plaque counting"

What it tells us:

- **Who:** phage researchers. They run plaque assays on a bacterial lawn and report titre in **PFU/mL**.
- **Pain point:** *tiny* plaques (often 0.2–1 mm, sometimes turbid) are hard to see and easy to miss.
- **Signal:** real demand from a new user group, but one request is not yet proof of wide need.

## What already exists in the app

| Need | Existing code |
|---|---|
| Plaques have the opposite contrast to colonies | `Polarity.dark` / `Polarity.bright` in `app/lib/core/normalize.dart`. The app always uses `auto`; there is no setting for it in the UI |
| Uneven lawn and lighting | Background correction (wide median) |
| Touching plaques | Splitting at distance-transform peaks, cluster estimates |
| Titre from dilutions | `app/lib/core/calculator.dart`; only the unit label (CFU → PFU) differs |
| Spot titration | Drop-plate spots, `app/lib/core/spots.dart` |
| Fixing misses | Tap to add or remove marks |
| Export, backup, replicates, stats | Done |

## Gaps specific to plaques

1. **Size vs resolution.** Photos are reduced to `kWorkShortSide = 1800` px
   (`app/lib/core/pipeline.dart`), about 65 µm/px on a 90 mm dish. A 0.3 mm plaque is ~5 px; the
   `minDiameterMm = 0.15` limit is ~2 px. This is exactly the "tiny plaques" problem.
2. **Lawn texture.** Grainy top agar, bubbles and debris look like tiny spots, so false
   positives rise once the size limit is lowered.
3. **Turbid plaques and halos.** These have low contrast and may fall under the 4σ threshold.
4. **Polarity.** `auto` picks the larger contrast tail. On a lawn with few plaques it can pick
   wrong, so a plaque mode needs a fixed polarity.
5. **Wording and rules.** PFU, top-agar method, countable range (often 30–300, some labs use
   other ranges), and EOP (efficiency of plating) for host-range work.

## Feature options

**MVP (about 1–2 weeks):**
- A "Plaques (PFU)" sample type with fixed polarity, PFU/mL units and plaque defaults.
- Analysis at higher resolution (full-resolution or a crop of the plate) with a smaller
  minimum size.
- A sensitivity slider (`DetectParams.kSigma` already exists, not exposed in the UI).
- Spot assay reused for PFU titration.

**Version 2:**
- Clear vs turbid plaques, using the existing two-class machinery (`classCounts`).
- Plaque size distribution (diameter is already measured).
- EOP calculation across host strains.

**Later:**
- A trained model for very small plaques and dense lawns, using corrected counts the app
  already exports as training data.

## Decision plan

**Step 0: collect evidence (no coding).**
Ask the commenter, and one or two other phage researchers, for 20–30 plate photos with hand
counts: easy plates, tiny plaques, turbid plaques, crowded plates. Ask how they light the
plate (backlight or dark background) and which titre format they report.

**Step 1: feasibility test (about 1 day).**
Run the Python reference pipeline on the photos:

```
colonycounter count photos/*.jpg --polarity dark --overlay out/
colonycounter evaluate labelled/
```

Which polarity applies depends on lighting (plaques look brighter than the lawn when back-lit,
darker on a dark-field box), so try both. Then try a smaller minimum size and full resolution.
Measure count error against the hand counts.

**Decision gate:**
- **Within ~10 % on most plates:** build the MVP. Mostly configuration and UI; low risk.
- **Good on normal plaques, poor on tiny or turbid ones:** ship the MVP for normal plaques,
  flag tiny ones "check by eye", and gather data toward a model.
- **Poor overall:** don't build it now. Reply honestly and keep the photos for later.

**Step 2: MVP behind the new sample type**, so colony counting is unchanged. Add regression
tests on reference images, as already exist for colonies.

**Step 3: beta with the commenter** through closed testing.

## Trade-offs

- **For:** most of the pipeline is reused; opens a new user group; few free apps count plaques well.
- **Against:** takes time from the Play Store launch; tiny-plaque accuracy is unproven until Step 1.
- **Risk control:** a separate sample type means colony users see no change.

**Recommendation when revisited:** do Steps 0 and 1 first (cheap), then decide on the numbers.
