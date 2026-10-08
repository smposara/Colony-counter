# Counting drop plates (Miles–Misra): study

Status: **study only** (October 2026). Not scheduled. Implementation plan:
[DROP_PLATE_IMPLEMENTATION.md](DROP_PLATE_IMPLEMENTATION.md). Related:
[plaque counting](PLAQUE_COUNTING.md) (phage spot titration reuses drops).

## Summary

The app already counts drop plates (since v0.3): drops are found by grouping colonies, each
drop gets a dilution and replicate, and CFU/mL comes from the 3–30 rule. What it lacks is what
makes drop plates reliable in practice: finding **empty and confluent drops**, using the
**layout** the user plated (rows on a square plate, sectors on a round one), checking that
**drops agree with each other** (Poisson), and showing a **per-dilution drop table** in the
results. This study proposes three options; Option A fixes the core gaps in about 3–4 weeks.

## The method

Miles, Misra and Irwin (1938) placed 20 µL drops of each tenfold dilution on a dried agar
plate, one drop per sector, and counted the colonies in the drops of the dilution that gave
countable numbers. Today the method is used in many variants:

| Variant | Drop volume | Layout | Counting |
|---|---|---|---|
| Classic Miles–Misra | 20 µL (calibrated dropper, 50 drops/mL) | One dilution per plate, several drops in sectors | Mean colonies per drop |
| Drop plate (Herigstad 2001; Naghili 2013) | 10 µL (10–30 µL in use) | 5 drops per dilution, often two dilutions per plate | Dilution with **3–30 colonies per 10 µL drop** |
| Spot plating from a 96-well dilution plate | 5–10 µL, multichannel pipette | A row (or column) per dilution on a square or round plate, triplicates | Same window, scaled to the drop volume |
| Single-plate serial dilution spotting (SP-SDS) | 5–10 µL | All dilutions on one plate, one zone each | Per zone |

Calculation (all variants): **CFU/mL = mean colonies per drop ÷ (drop volume in mL × dilution)**,
for example 20 colonies per 10 µL drop at 10⁻⁵ → 20 ÷ (0.01 × 10⁻⁵) = 2 × 10⁸ CFU/mL.

What practice and the literature agree on:

- **Counting window:** 3–30 colonies per 10 µL drop is the most cited window (Naghili et al.
  2013, Montana State biofilm protocols); there is no single standard, and drop size,
  replicates and number of sectors are not standardised.
- **Total volume matters, not the number of drops:** the standard deviation of the estimate
  depends on the total volume plated (10 drops of 20 µL equal 20 drops of 10 µL)
  (Herigstad et al. 2001).
- **One dilution is enough:** using only the first countable dilution matches conventional
  practice; weighting in other dilutions adds little for usual designs (Christen & Parker 2020,
  citing Hamilton & Parker 2010). The app's current pooled ΣC/Σ(V·d) over in-range drops is
  also acceptable, but labs expect to see the per-dilution mean.
- **Drops follow Poisson:** colonies per drop are Poisson-distributed for well-mixed
  suspensions (Miles & Misra 1938; Davis 1940). The variance-to-mean ratio (index of
  dispersion) should be about 1; χ² = (N − 1) × VMR with N − 1 degrees of freedom tests it.
  Overdispersion points to clumping, pipetting or dilution errors.
- **Read early:** colonies in a small drop merge as they grow; overcrowded drops become
  confluent. Spreading organisms make the method unreliable.
- **Agreement with spread plates:** drop and spread counts correlate strongly (p < 0.001;
  Spearman ρ 0.62–0.87) and their means do not differ (Naghili et al. 2013); drop plates save
  time, media and incubator space.

## What the app already has

From the code (see the implementation plan for file references):

- **Plan:** `PlatingMethod.drop`, drop volume (default 10 µL), two layouts: one dilution per
  plate with drops as replicates, or all dilutions on one plate with one drop each.
- **Drops:** found by grouping nearby colonies (gap ≤ 2.5 mm), each at least 7 mm across;
  tap to add, drag to move, tap to set dilution, replicate or TNTC; carried over to later
  photos (time-lapse).
- **Counting:** colonies whose centre is inside the drop circle; clusters count as their
  estimate.
- **Results:** rule "Drop 3–30"; drops in range pooled as ΣC / Σ(V·d) per replicate, then mean
  ± SD and log₁₀ across replicates; below range "<" from the least diluted drop.
- **Export:** a `spots` column ("1e-5/r1:12; …") and the drop of each colony.
- **Tests:** a synthetic four-drop plate (one drop empty) and data tests.

## Gaps

1. **Empty drops are never found** (no colonies to group), and labels are given by reading
   order, so one missing empty drop **shifts the dilution of every later drop**.
2. **Confluent drops are not found** (a lawn has no separate colonies); TNTC can only be set by
   hand.
3. **No layout:** the planned number of drops and their arrangement (rows, sectors) are not
   used, so stray colonies or contaminants become extra drops and nothing checks the count of
   drops against the plan.
4. **Drop size is fixed at 7 mm** whatever the drop volume (5 or 20 µL), and neighbouring
   drops on dense layouts can merge.
5. **No drop statistics:** no per-dilution mean/SD of drops, no Poisson dispersion check, no
   outlier drop, no check that neighbouring dilutions differ by about tenfold, no confidence
   interval.
6. **Merged colonies in small drops** get no drop-specific warning.
7. **Smaller issues:** replicate numbers wrap when there are more drops than replicates
   (duplicates pool silently); plate-level spreader is ignored for drops; layout is not
   inferred for older samples; drop plates are left out of the accuracy check; the shared
   photo has no CFU/mL line for drops; no Python reference to check the Dart code against.

## Options

| Option | What | Effort | Value |
|---|---|---|---|
| **A. Reliable drops** | Layout templates (rows/columns, sectors, free) fitted to the found drops; empty drops filled in from the layout; drop size from volume; confluent-drop detection; labels from layout position; per-drop crowding flag; fixes from gap 7 | ~3–4 weeks | Removes the errors users meet today |
| **B. A + drop statistics** | Per-dilution drop table (mean, SD, VMR), Poisson dispersion and outlier flags, tenfold check, Poisson CI and detection limit, choice of "first countable dilution" or "pooled" calculation, CSV and report table | +2 weeks | What a methods section or QC report needs |
| **C. B + more spotting** | Single-plate serial-dilution zones, 96-well spot grids (8 × 12 on square plates), phage spot titration (plaques in drops, see plaque plan), tilt/track dilution | Later | New user groups (phage labs, high throughput) |

## Decision plan

**Step 0: what users plate (no coding).** Ask testers who use drop plates: drop volume (5, 10,
20 µL)? Layout (sectors on a round plate, rows on a square plate, one plate per dilution)?
Drops per dilution? Counting window? First countable dilution or pooled? Collect 20–40 photos
with manual per-drop counts, including empty and confluent drops.

**Step 1: feasibility in Python (about 1 week).** Synthetic drop plates (layouts, empty,
confluent and crowded drops, stray colonies) plus Step 0 photos: layout fitting and empty-drop
recovery.

**Gate:** every planned drop found and labelled correctly on ≥ 95 % of plates; per-drop count
within ±2 (or ±10 %) for drops in the window on ≥ 90 % of drops; confluent drops flagged on
≥ 90 %.

**Step 2: build Option A, then B** in the Flutter app, with tests against the Python fixtures.

## Trade-offs and recommendation

- **For:** the feature already exists and has users; the fixes are mostly geometry and
  statistics on top of the existing colony detector; drop plates are popular in research labs
  (cheaper and faster than spread plates); Option B's drop table is what reviewers ask for.
- **Against:** layouts vary a lot by lab; confluent-drop detection depends on lighting and
  medium; real photos are needed to set limits.
- **Compared with other candidates:** AST zones and Petrifilm open new user groups; this
  improves an existing workflow with lower risk.

**Recommendation:** do Step 0 with the next tester round and build **Option A + B together**
(about 5–6 weeks), with "first countable dilution" as an option next to the current pooled
calculation. Leave Option C for after the plaque-counting decision.

## Sources

- [Miles and Misra method (Wikipedia)](https://en.wikipedia.org/wiki/Miles_and_Misra_method)
- [Herigstad, Hamilton & Heersink (2001), How to optimize the drop plate method for enumerating bacteria, J Microbiol Methods 44:121–129](https://www.sciencedirect.com/science/article/abs/pii/S0167701200002414)
- [Naghili et al. (2013), Validation of drop plate technique for bacterial enumeration by parametric and nonparametric tests, Vet Res Forum 4:179–183](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC4312378/)
- [Drop plate method for counting biofilm cells (Montana State University)](https://www.cs.montana.edu/webworks/projects/oldbiofilmbooks/contents/appendices/appendix001/pages/page007.html)
- [Christen & Parker (2020), Systematic statistical analysis of microbial data from dilution series](https://arxiv.org/abs/2003.09039v1)
- [Barrick Lab, CFU counts (spot plating from 96-well dilutions)](https://barricklab.org/twiki/bin/view/Lab/ProtocolsCFUCounts)
- [Titering and EOP calculator (index of dispersion for spot counts)](https://titering.phage.org/)
- [The drop plate method as an alternative for Azospirillum spp. enumeration (REDCAI network)](https://www.elsevier.es/en-revista-revista-argentina-microbiologia-372-articulo-the-drop-plate-method-as-S0325754121000560)
- [Miles and Misra enumeration: formula, procedure, disadvantages (StudyMicrobio)](https://studymicrobio.com/miles-and-mishra-enumeration-surface-drop-introduction-formula-procedure-disadvantage)
