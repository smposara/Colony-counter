# Counting Petrifilm plates: opportunity study

Status: **study only** (October 2026). Not scheduled. Implementation plan:
[PETRIFILM_IMPLEMENTATION.md](PETRIFILM_IMPLEMENTATION.md). Compare with the other candidate
features: [AST zone measurement](AST.md) (chosen for 0.6.0) and
[plaque counting](PLAQUE_COUNTING.md).

## What Petrifilm is

Neogen® Petrifilm® plates (formerly 3M) are ready-made dry culture films used widely in food,
dairy and water quality control, including in Thailand. The sample (usually 1 mL) is spread
over a round growth area under a clear top film; a printed 1 cm grid helps counting. Methods
are validated by AOAC International and AFNOR. Similar dry media exist from other makers
(Compact Dry, MC-Media Pad / Sanita-kun, Micro-Fast).

How plates are read (from Neogen's interpretation guides; confirm each value against the
current guide before using it in the app):

| Plate | What counts | Counting range / limit | High counts |
|---|---|---|---|
| Aerobic Count (AC) | Red colonies (tetrazolium indicator), any size | Preferably 25–250 | ~20 cm² growth area: average colonies in a 1 cm² square × 20; very high counts turn the whole area pink |
| E. coli/Coliform (EC) | E. coli: blue colonies with or without gas. Coliforms: red colonies with gas within about one colony diameter, plus the blue ones | Counting limit 150 | Estimate from squares; gel colour change |
| Coliform Count (CC) | Red colonies with gas | (from guide) | (from guide) |
| Enterobacteriaceae (EB) | Red colonies with a yellow zone and/or gas | (from guide) | Gel turns from purple to yellow/cream |
| Yeast & Mold (YM, Rapid YM) | Yeast: small, defined edge, raised, uniform colour. Mold: large, diffuse edge, flat, dark centre | (from guide) | (from guide) |
| Staph Express (STX) | Red-violet colonies; a DNase disk adds pink zones for confirmation | (from guide) | (from guide) |

Gas bubbles **not** next to a colony are background artefacts of the gel and must be
ignored.

## Who would use it

- Food, dairy and beverage QC labs and small producers (Thai SMEs, community enterprises,
  dairy cooperatives) that read Petrifilm by eye, often tens of plates a day.
- University teaching and research labs (food science, veterinary public health).
- Water and environmental testing.

These users are a different group from the current research-lab users, and probably larger
in Thailand. Note: AOAC validation covers the method read by a trained person; an app count is
an aid that the user checks, not a validated result.

## What already exists

- **Neogen Petrifilm Plate Reader Advanced (PPRA):** a dedicated instrument with built-in AI.
  It reads up to 11 plate types in about 6 seconds a plate and stores results. It is a
  commercial lab instrument (price on request), so out of reach for many small labs and
  teaching.
- **General colony-counting apps** (phone, on-device) count colonies on Petri dishes but do not
  handle Petrifilm specifics: the grid, colour classes, gas-associated coliforms, square-based
  estimates, or per-plate-type ranges.
- **Research:** deep-learning colony counters on phone photos; some commercial AI counting
  services list Petrifilm support.
- **Open data:** a few community datasets on Roboflow Universe, e.g.
  [Cropped_Petrifilm](https://universe.roboflow.com/colony-5268j/cropped_petrifilm) (CC BY 4.0),
  [rcbecoli](https://universe.roboflow.com/ecoli/rcbecoli),
  [E.coli Detection](https://universe.roboflow.com/aquascanproject/e.coli-detection-74vy0)
  (269 images). Licences and labelling quality must be checked; none comes with counts verified
  against the interpretation guide.

**Gap:** a free, offline phone app that reads Petrifilm the way the guide says (colour classes,
gas rule, grid-based estimate, plate-type ranges) and turns counts into CFU/mL or CFU/g.

## What the app already has

| Petrifilm need | Existing code |
|---|---|
| Small round counting area with a printed grid | `PlateFormat.membrane47` and `suppressGridLines` (`app/lib/core/grid.dart`) |
| Two colour classes per plate | `ColourMode` and Lab colour measurement (`app/lib/core/colour.dart`) |
| Counting range per method | `CountingRule` (membrane 20–80 / 20–200 already) |
| CFU/mL and CFU/g, dilutions, replicates | Calculator, sample plans, CFU/g |
| Manual fixes, check-this-count warnings, show/hide marks | Review screen |
| Several plates in one photo | Multi-plate finder (round areas) |
| Export, backup, accuracy tracking, Thai/English | Done |

## Gaps specific to Petrifilm

1. **Finding the plate and its scale.** The film is rectangular; the growth area is a ~20 cm²
   circle (about 50 mm across) marked by a foam ring on most types but only by the spread gel
   on AC plates. The **printed 1 cm grid** is a precise ruler and shows any rotation; the app
   should measure the grid pitch instead of trusting a circle edge.
2. **Colony contrast.** Colonies are coloured dots on a coloured gel (red on pale for AC;
   blue and red on a red-purple gel for EC). Detection should use the colour channel that
   separates colony from gel for each plate type, not brightness alone.
3. **Gas rule (EC, CC, EB).** Coliforms count only with a gas bubble within about one colony
   diameter; loose bubbles must be ignored. Automatic bubble detection is new work; a manual
   "has gas" tag is a simple first step.
4. **Yellow zones (EB)** and **yeast vs mold (YM)** need new classifiers (halo colour; size,
   edge and texture).
5. **High-count estimate.** The guide's method (mean per 1 cm² square × 20) differs from the
   dish rules; the app should do it from the grid and label it as an estimate.
6. **Plate-type ranges and units.** Per-type counting ranges, results per mL or g from a 1 mL
   inoculum, and E. coli and coliform results side by side for EC plates.
7. **Names and trademarks.** "Petrifilm" and "Neogen" are Neogen trademarks. Use them only to
   say which plates the app reads ("for Neogen® Petrifilm® plates"), with a trademark notice
   and no suggestion of endorsement; never in the app name or icon.

## Options

| Option | Plate types | Effort (after a go) | Value |
|---|---|---|---|
| **A. Core** | AC and EC (gas tagged by hand), grid scale, square estimate, per-type ranges | ~4–5 weeks | Covers the most-used plates |
| **B. A + more types** | CC, EB (yellow zones), YM (yeast vs mold), automatic gas detection | +3–4 weeks | Full food-QC set |
| **C. B + others** | STX with disk step, Rapid plates, other dry films (Compact Dry etc.) | Later | Broader market |

## Decision plan

**Step 0: demand and plate types (no coding).** Ask testers, food-science contacts and dairy
cooperatives: do you use Petrifilm (or other dry films)? Which plate types? How many plates a
day? Count by eye or with a reader? CFU/mL or CFU/g? Ask for 20–40 photos per plate type with
their manual counts.

**Step 1: feasibility (about 1 week, Python).** Synthetic Petrifilm plates plus the photos from
Step 0: grid detection and scale, colony detection for AC and EC, blue/red split.

**Gate:** count within ±10 % (or ±5 colonies) on ≥ 90 % of plates in the counting range, and
E. coli vs coliform class correct for ≥ 95 % of colonies, for AC and EC.

**Step 2: build Option A** as a "Petrifilm" plating method (colony plates stay unchanged).

**Step 3: beta** with one or two food or dairy labs through closed testing.

## Trade-offs and recommendation

- **For:** it is colony counting, the app's core, so much is reused (grid removal, colour
  classes, calculator, review, exports); a large, clearly defined user group; no free tool
  follows the interpretation guide.
- **Against:** the gas and yellow-zone rules need new detection; plate appearance differs by
  type and by lot; an app count is not AOAC-validated.
- **Compared with AST (zones):** Petrifilm reuses more of the app and serves routine QC daily;
  AST serves research and teaching. Both are worth the same Step 0 survey.

**Recommendation:** run Step 0 for Petrifilm together with the AST survey. If Petrifilm demand
is clearly larger, consider building Option A before or alongside AST for 0.6/0.7.

## Sources

- [Neogen Petrifilm Aerobic Count Plate interpretation guide](https://media.neogen.com/m/7a03e221597d2cd2)
- [Raw Milk Institute copy of the Aerobic Count interpretation guide](https://www.rawmilkinstitute.org/s/3M-SPC-Interpretation-Guide.pdf)
- [Aerobic Plate Count in Foods (Petrifilm method), AOAC 990.12 (Australian Department of Agriculture)](https://www.agriculture.gov.au/sites/default/files/sitecollectiondocuments/aqis/exporting/meat/elmer3/approved-methods-manual/Aerobic-Plate-Count-TVC-Petrifilm-AOAC-998.12.doc)
- [Petrifilm E. coli/Coliform interpretation guide (Georgia Adopt-A-Stream copy)](https://adoptastream.georgia.gov/document/document/ecolicoliform-interpretation-guide/download)
- [Petrifilm EC interpretation guide (Hygiene Diagnostics copy)](https://hygiene-diagnostics.se/wp-content/uploads/2022/05/petrifilm_ecc_ig.pdf)
- [Petrifilm Enterobacteriaceae Count Plates](https://hygiene-diagnostics.se/en/product/mikrobiologi/petrifilm-agarplattor/3m-petrifilm-enterobacteriaceae-count-eb-plate-50st/)
- [Petrifilm Staph Express Count Plates (Neogen)](https://www.neogen.com/categories/microbiology/petrifilm-staph-express-count-plates)
- [Petrifilm Rapid Yeast and Mold Count Plates (Neogen)](https://www.neogen.com/categories/microbiology/petrifilm-rapid-yeast-mold-count-plates/)
- [Rapid YM interpretation guide (Techno-Path copy)](https://www.techno-path.com/wp-content/uploads/2020/02/Rapid_YM_Interpretation_Guide.pdf)
- [Neogen Petrifilm Plate Reader Advanced](https://www.neogen.com/de/aunz/brands/petrifilm/plate-reader/)
- [Petrifilm Plates and Plate Reader Advanced brochure](https://media.neogen.com/m/709626bb542e44d8/original/Petrifilm-Plates-and-Petrifilm-Plate-Reader-Advanced-Brochure.PDF)
- [MC-Media Pad product comparison (Merck)](https://www.merckmillipore.com/BM/en/technical-documents/protocol/microbiological-testing/microbial-culture-media-preparation/mc-media-pad-product-comparison)
- [Evaluation of a Compact Dry method (AGRIS)](https://agris.fao.org/search/en/records/67f4dcece01f7420ea8532d3)
- [IAFP 2019: Petrifilm Rapid EC and Rapid Aerobic Count for raw milk in Thailand](https://iafp.confex.com/iafp/2019/meetingapp.cgi/Paper/21327)
- [Roboflow Universe: Cropped_Petrifilm](https://universe.roboflow.com/colony-5268j/cropped_petrifilm),
  [rcbecoli](https://universe.roboflow.com/ecoli/rcbecoli),
  [E.coli Detection](https://universe.roboflow.com/aquascanproject/e.coli-detection-74vy0)
- [AI-supported colony counting (Vitaris)](https://vitaris.com/en/kolonienzaehlung-mittels-ki-gestuetzter-bildanalyse/)
