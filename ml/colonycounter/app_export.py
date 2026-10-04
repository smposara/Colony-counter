"""Read a training export made by the Colony Counter app.

The app's *Export training data* menu item writes a zip with the photos, COCO
style ``annotations.json`` and YOLO ``labels/``. This module loads it into
plain Python structures for training or evaluating a detector::

    from colonycounter.app_export import load_app_export
    plates = load_app_export("training_2026-10-04.zip")
    for p in plates:
        image = p.read_image()            # RGB numpy array
        for c in p.colonies:              # every kept or added mark
            print(c.x, c.y, c.radius, c.n, c.source)
"""

from __future__ import annotations

import io
import json
import zipfile
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class Mark:
    x: float
    y: float
    radius: float
    n: int = 1  # colonies in the mark (> 1 for an estimated cluster)
    source: str = "auto"  # "auto" (kept) or "manual" (added by hand)
    colour_class: int = 0


@dataclass
class ExportedPlate:
    plate_id: str
    file_name: str
    width: int
    height: int
    plate: dict
    mm_per_px: float
    checked: bool
    colonies: list[Mark] = field(default_factory=list)
    rejected: list[Mark] = field(default_factory=list)
    _zip_path: Path | None = None

    @property
    def count(self) -> int:
        return sum(c.n for c in self.colonies)

    def read_image(self):
        """The photo as an RGB numpy array (needs Pillow and numpy)."""
        import numpy as np
        from PIL import Image

        with zipfile.ZipFile(self._zip_path) as z:
            data = z.read(self.file_name)
        return np.asarray(Image.open(io.BytesIO(data)).convert("RGB"))


def load_app_export(path: str | Path) -> list[ExportedPlate]:
    path = Path(path)
    with zipfile.ZipFile(path) as z:
        coco = json.loads(z.read("annotations.json"))
    plates: dict[int, ExportedPlate] = {}
    for im in coco["images"]:
        plates[im["id"]] = ExportedPlate(
            plate_id=im["plate_id"],
            file_name=im["file_name"],
            width=im["width"],
            height=im["height"],
            plate=im["plate"],
            mm_per_px=im["mm_per_px"],
            checked=im.get("checked", False),
            _zip_path=path,
        )
    for a in coco["annotations"]:
        cx, cy = a["center"]
        plates[a["image_id"]].colonies.append(
            Mark(cx, cy, a["radius"], a.get("n", 1), a.get("source", "auto"), a.get("colour_class", 0))
        )
    for a in coco.get("rejected", []):
        cx, cy = a["center"]
        plates[a["image_id"]].rejected.append(Mark(cx, cy, a["radius"]))
    return list(plates.values())
