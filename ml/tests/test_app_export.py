import io
import json
import zipfile

import numpy as np
from PIL import Image

from colonycounter.app_export import load_app_export


def test_load_app_export(tmp_path):
    img = Image.fromarray(np.full((40, 60, 3), 128, np.uint8))
    buf = io.BytesIO()
    img.save(buf, format="JPEG")
    coco = {
        "categories": [{"id": 1, "name": "colony"}, {"id": 2, "name": "cluster"}],
        "images": [
            {
                "id": 1,
                "file_name": "images/p1.jpg",
                "width": 60,
                "height": 40,
                "plate_id": "p1",
                "plate": {"cx": 30, "cy": 20, "radius": 18, "diameter_mm": 90},
                "mm_per_px": 2.5,
                "checked": True,
            }
        ],
        "annotations": [
            {"id": 1, "image_id": 1, "category_id": 1, "bbox": [8, 8, 4, 4], "center": [10, 10], "radius": 2, "n": 1, "source": "auto"},
            {"id": 2, "image_id": 1, "category_id": 2, "bbox": [16, 16, 8, 8], "center": [20, 20], "radius": 4, "n": 3, "source": "manual"},
        ],
        "rejected": [{"image_id": 1, "bbox": [0, 0, 2, 2], "center": [1, 1], "radius": 1}],
    }
    path = tmp_path / "export.zip"
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("annotations.json", json.dumps(coco))
        z.writestr("images/p1.jpg", buf.getvalue())
    (plate,) = load_app_export(path)
    assert plate.checked and plate.count == 4
    assert [c.source for c in plate.colonies] == ["auto", "manual"]
    assert len(plate.rejected) == 1
    assert plate.read_image().shape == (40, 60, 3)
