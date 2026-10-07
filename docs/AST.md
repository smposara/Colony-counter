# Antibiotic susceptibility testing (AST): research and decision plan

Status: **parked**. Not scheduled. Revisit after the 0.5.x closed test, together with
[plaque counting](PLAQUE_COUNTING.md). Research done October 2026.
Implementation plan for Option A: [AST_IMPLEMENTATION.md](AST_IMPLEMENTATION.md).

## Summary

AST is technically possible. The key choice is whether the app only **measures inhibition
zones in mm**, or also gives **S/I/R** (susceptible / increased exposure / resistant).

- **Zone measurement only:** a research and teaching tool. Low risk, and much of the app is reusable.
- **S/I/R on patient isolates:** an in-vitro diagnostic medical device. Needs regulatory
  approval, and a free CE-marked app (Antibiogo) already exists.

## What already exists

- **Antibiogo** (MSF Foundation): free, offline app. Finds disks, measures zones
  semi-automatically (the technician adjusts), applies CLSI/EUCAST breakpoints and expert rules
  to give S/I/R. 98 % agreement with human experts on zone measurement. CE-marked IVD in May
  2022; an EU IVDR version is in development. Open source except the expert system. Aimed at
  clinical labs in low- and middle-income countries. Image library:
  [AST-image-processing](https://github.com/mpascucci/AST-image-processing) (check its licence
  before reusing).
- **A recent mobile AST validation study:** 90.4 % categorical agreement with manual readings,
  0.83 % major errors, **9.2 % minor errors**. Small mm errors near a breakpoint flip the category.
- **Known hard cases:** low contrast, colonies inside the zone, double zones, hazy edges, zones
  meeting the plate edge.

**Conclusion:** don't compete on clinical S/I/R. A zone-measurement tool for research and
teaching is an open gap and fits this app.

## Standards and licensing

- **EUCAST** breakpoint tables are free to use; updated every January (yearly upkeep if shipped).
- **CLSI M100** is copyrighted; building its tables into software needs written permission
  (permissions@clsi.org).
- **Thailand mostly uses CLSI** (NARST surveillance with WHONET; MORU labs), with discussion of
  moving to EUCAST. Built-in EUCAST may not match what Thai users want. Workaround: let users
  enter their lab's own breakpoints.
- **EUCAST method:** read at complete inhibition, to the nearest mm; **at most 6 disks on a
  90 mm plate**.

## Regulation

- **Thai FDA** (Medical Devices Control Division) regulates IVDs, including software, in four
  risk classes aligned with the ASEAN directive. Patient-result software needs registration, a
  local representative and a UDI.
- **Google Play:** apps that are medical devices need clearance documents. Other health apps
  must state clearly that they are not a medical device and do not diagnose.
- **Practical line:** mm measurement for research and teaching only is fine; S/I/R for patient
  care is out of reach for a one-person project.

## Reuse from the current app

| AST need | Existing code |
|---|---|
| mm scale from the plate | Plate finder and `mmPerPx` (`app/lib/core/plate.dart`) |
| Finding round shapes | Plate circle search, adaptable to 6 mm disks |
| More disks per plate | `dish150`, `square120` formats |
| Lighting correction, contrast | `app/lib/core/normalize.dart` |
| Manual fixes | Plate circle correction, tap editing |
| Samples, replicates, export, backup, Thai/English | Done |

**New work:**
1. Disk (and well) detection.
2. Zone edge measurement from radial brightness profiles, including hazy edges, colonies
   inside zones and overlapping zones.
3. A review screen to drag each zone circle.
4. Assigning a drug to each disk (tap and pick, or a saved panel layout); reading disk codes
   automatically (OCR) can wait.
5. Per-disk CSV export, later in a WHONET-friendly layout.

This is a larger build than plaque counting: a new detector and a new review screen.

## Scope options

| Option | What it does | Users | Regulation | Effort |
|---|---|---|---|---|
| **A. Zone measurement** | Disk and well diffusion zones in mm, mean ± SD, export | Researchers (e.g. plant-extract screening), teaching labs, QC | None; "research and education only" disclaimer | ~3–5 weeks |
| **B. A + user-entered breakpoints** | S/I/R from the lab's own table (or EUCAST), labelled non-clinical | Veterinary, food, environmental surveillance | Grey zone; keep the non-clinical label | +2–3 weeks, plus yearly upkeep if EUCAST is built in |
| **C. Clinical AST** | S/I/R for patient care | Hospitals | Thai FDA IVD registration, ISO 13485 | Not feasible; Antibiogo exists |

## Decision plan

**Step 0: check demand (no coding, 1–2 weeks).** Ask testers and the Facebook audience: do you
measure zones and how often? Disks or wells? Research, teaching or clinical? CLSI or EUCAST?
What do you use now? Run this survey together with the plaque-counting questions.

**Step 1: collect data.** 30–50 plate photos with calliper readings: disk plates, well plates,
and the hard cases.

**Step 2: prototype in the Python pipeline (`ml/`, about 1 week).** Disk/well detection and zone
measurement, compared against the calliper readings.

**Decision gate:**
- **Mean error ≤ 1 mm and ≥ 95 % within ±2 mm:** build Option A.
- **Good on clear zones, poor on hazy ones:** build Option A as semi-automatic (app suggests,
  user confirms each circle).
- **Poor overall:** shelve it and keep the data.

**Step 3: build Option A** as a separate "Inhibition zones" sample type, so colony counting is
unchanged. Add the disclaimer in the app and the store listing.

**Step 4: consider Option B only if** non-clinical labs ask for S/I/R. User-entered breakpoints
first; EUCAST tables only with a plan to update them yearly. Never ship CLSI tables without
permission.

## Trade-offs

- **For:** real gap in free research tools; large academic audience in Thailand; good reuse.
- **Against:** biggest new feature so far; 1 mm accuracy unproven; drifts from the "colony
  counter" identity (could be handled with a name like "Plate tools").
- **Compared with plaque counting:** plaques are cheaper (mostly settings); AST measurement
  probably has the larger audience.

**Recommendation when revisited:** one demand survey for both AST and plaques, then build
whichever shows more demand. Keep AST to measurement only; leave clinical S/I/R to Antibiogo.

## Sources

- [AI-based mobile application to fight antibiotic resistance (Nature Communications)](https://www.nature.com/articles/s41467-021-21187-3)
- [Antibiogo, MSF Foundation](https://fondation.msf.fr/en/projects/antibiogo)
- [Antibiogo becomes first CE-marked medical device developed by MSF](https://fondation.msf.fr/en/newsroom/after-5-years-development-antibiogo-becomes-first-medical-device-ce-marking-developed-msf)
- [Reflections from the ICARS-supported Antibiogo project](https://icars-global.org/reflections-antibiogo/)
- [AST-image-processing library (Zenodo)](https://zenodo.org/records/4421398)
- [A mobile based antimicrobial susceptibility testing device: prototype and validation (PubMed)](https://pubmed.ncbi.nlm.nih.gov/42555697/)
- [Evaluating deep learning models for Kirby-Bauer images (ScienceDirect)](https://www.sciencedirect.com/org/science/article/pii/S1875036225000056)
- [EUCAST](https://eucast.org/)
- [EUCAST disk diffusion reading guide v10.0](https://szu.cz/wp-content/uploads/2023/06/Reading_guide_v_10.0_EUCAST_Disk_Test_2023.pdf)
- [CLSI M100 sample (copyright terms)](https://clsi.org/media/fp0hqmu0/m100ed35e_sample.pdf)
- [Time to switch from CLSI to EUCAST? A Southeast Asian perspective](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC6587905/)
- [NARST Annual Report 2567](https://narst.dmsc.moph.go.th/static/NARST%20Annual%20Report%202567.pdf)
- [Thailand regulatory approval process for medical and IVD devices (Emergo)](https://www.emergobyul.com/resources/thailand-regulatory-approval-process-medical-and-ivd-devices)
- [Thailand UDI labelling for software as a medical device (Tilleke)](https://www.tilleke.com/insights/thailand-introduces-udi-labeling-requirements-for-software-as-a-medical-device/37/)
- [Google Play health content and services policy](https://support.google.com/googleplay/android-developer/answer/16679511?hl=en)
- [WHONET overview](https://intuitionlabs.ai/software/clinical-laboratory-information-systems/microbiology-lab-systems/whonet)
