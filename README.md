# Colony Counter

A mobile app (Android and iOS) that uses the phone camera to count viable colony-forming
units (CFUs) on agar plates and calculate CFU/mL from the dilution series.
Built for research labs. Version 1 targets **Nutrient Agar in 90 mm dishes**,
photographed in a 3D-printed dark-field lightbox.

| Folder | What's there |
|---|---|
| [`docs/PLAN.md`](docs/PLAN.md) | Research summary, architecture, roadmap, decisions |
| [`docs/DATA_PROTOCOL.md`](docs/DATA_PROTOCOL.md) | How to plate, photograph and label the training/test set |
| [`app/`](app/) | Flutter app (Android + iOS): guided capture, on-device counting, review/edit, CFU/mL |
| [`ml/`](ml/) | Python reference pipeline: plate finder, colony detection, CFU calculator, evaluation |
| [`hardware/`](hardware/) | Printable dark-field lightbox and phone stand (OpenSCAD) |

## Quick start (reference pipeline)
```
pip install -e "ml[dev]"
colonycounter count my_plate.jpg --overlay out/
colonycounter synth demo/ --n 10 && colonycounter evaluate demo/
pytest ml
```
## App
```
cd app && flutter pub get && flutter test && flutter run
```
See [`app/README.md`](app/README.md) for features and screenshots.
