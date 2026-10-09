import json
import math
from pathlib import Path

import cv2
import pytest

from colonycounter.zone_calibration import (CalZone, app_span_mm, calibration_summary,
                                            farthest_pair)
from colonycounter.zones import measure_plate

FIXTURES = Path(__file__).resolve().parents[2] / "app" / "test" / "fixtures"


def zones(diffs, sizes=None, rf=None):
    sizes = sizes or [8 + 3 * i for i in range(len(diffs))]
    rf = rf or [0.3] * len(diffs)
    return [CalZone(app_mm=[s + d], user_mm=[s], radial_fraction=r) for s, d, r in zip(sizes, diffs, rf)]


def test_perfect_agreement_is_good():
    s = calibration_summary(zones([0.0] * 6), app_span=60, user_span=60)
    assert s.n == 6 and s.bias == 0 and s.sd == 0
    assert s.verdict == "good" and s.hint == "none"
    assert s.within_1mm == 1.0


def test_bias_and_limits_of_agreement():
    d = [0.3, 0.5, 0.4, 0.6, 0.2, 0.4]
    s = calibration_summary(zones(d))
    assert s.bias == pytest.approx(0.4)
    sd = math.sqrt(sum((x - 0.4) ** 2 for x in d) / 5)
    assert s.sd == pytest.approx(sd)
    assert s.loa_low == pytest.approx(0.4 - 1.96 * sd)
    assert s.loa_high == pytest.approx(0.4 + 1.96 * sd)
    assert s.max_abs == pytest.approx(0.6)


def test_too_few_zones_for_the_tool():
    assert calibration_summary(zones([0.1] * 5)).verdict == "too_few"
    assert calibration_summary(zones([0.1] * 6)).verdict == "good"
    assert calibration_summary(zones([0.1] * 7), tool="ruler").verdict == "too_few"
    assert calibration_summary(zones([0.1] * 8), tool="ruler").verdict == "good"


def test_excluded_and_unmeasured_zones_are_left_out():
    zs = zones([0.0] * 6) + [CalZone(app_mm=[float("nan")], user_mm=[12.0]),
                             CalZone(app_mm=[20.0], user_mm=[25.0], included=False)]
    s = calibration_summary(zs)
    assert s.n == 6 and s.bias == 0


def test_a_scale_error_shows_as_a_slope():
    sizes = [8, 12, 16, 20, 24, 28, 32]
    zs = [CalZone(app_mm=[x * 1.05], user_mm=[x]) for x in sizes]
    s = calibration_summary(zs)
    assert s.slope == pytest.approx(0.05 / 1.025, rel=1e-6)
    assert s.slope_significant and s.hint == "scale"


def test_the_span_alone_flags_the_scale():
    s = calibration_summary(zones([0.6] * 6), app_span=63.0, user_span=60.0)
    assert s.scale_error == pytest.approx(0.05)
    assert s.verdict == "usable" and s.hint == "scale"


def test_lens_hint_when_edge_zones_differ():
    d = [0.0, 0.0, 0.1, 1.3, 1.2, 1.4]
    s = calibration_summary(zones(d, sizes=[15] * 6, rf=[0.2, 0.3, 0.4, 0.8, 0.8, 0.9]))
    assert s.edge_minus_centre == pytest.approx(1.3 - 1 / 30)
    assert s.hint == "lens"


def test_repeatability_from_several_photos():
    zs = [CalZone(app_mm=[10.0, 10.2], user_mm=[10.0]), CalZone(app_mm=[20.0, 20.4], user_mm=[20.0])]
    s = calibration_summary(zs)
    assert s.repeatability_sd == pytest.approx(math.sqrt((0.02 + 0.08) / 2))


def test_farthest_pair_and_span():
    disks = [(100, 100, 30), (400, 100, 30), (300, 500, 30), (120, 130, 30)]
    i, j = farthest_pair(disks)
    assert {i, j} == {0, 2}
    assert app_span_mm(disks[0], disks[1], 0.1) == pytest.approx((300 + 60) * 0.1)


def test_shared_cases_match_the_fixture():
    cases = json.loads((FIXTURES / "calibration_cases.json").read_text())
    assert len(cases) >= 10
    for c in cases:
        zs = [CalZone(**z) for z in c["zones"]]
        s = calibration_summary(zs, app_span=c["app_span"], user_span=c["user_span"], tool=c["tool"])
        assert s.verdict == c["python"]["verdict"], c["name"]
        assert s.hint == c["python"]["hint"], c["name"]
        assert s.bias == pytest.approx(c["python"]["bias"]), c["name"]
    names = {c["name"]: c["python"] for c in cases}
    assert names["scale 4 % large"]["hint"] == "scale"
    assert names["zones near the edge 1.2 mm larger"]["hint"] == "lens"
    assert names["edge read 0.8 mm larger"]["hint"] == "edge"
    assert names["poor: edge read 1.5 mm larger"]["verdict"] == "poor"


def test_end_to_end_on_a_synthetic_plate():
    """The detector's diameters against simulated readings: truth + 0.4 mm."""
    label = json.loads((FIXTURES / "zones_reflected.json").read_text())
    img = cv2.imread(str(FIXTURES / "zones_reflected.jpg"))
    res = measure_plate(img, plate_diameter_mm=label["plate_mm"], assay="disk", disk_mm=6.0)
    true_mm_per_px = label["plate_mm"] / (2 * label["plate"]["radius"])
    zs = []
    for t in label["true"]:
        z = min(res.zones, key=lambda z: (z.x - t["x"]) ** 2 + (z.y - t["y"]) ** 2)
        rf = math.hypot(t["x"] - res.plate.cx, t["y"] - res.plate.cy) / res.plate.radius
        zs.append(CalZone(app_mm=[z.diameter_mm], user_mm=[t["diameter_mm"] + 0.4], radial_fraction=rf))
    disks = [(t["x"], t["y"], 3.0 / true_mm_per_px) for t in label["true"]]
    i, j = farthest_pair(disks)
    user_span = app_span_mm(disks[i], disks[j], true_mm_per_px)
    app_disks = [(z.x, z.y, z.disk_radius_px) for z in res.zones]
    a = min(range(len(app_disks)), key=lambda k: math.hypot(app_disks[k][0] - disks[i][0], app_disks[k][1] - disks[i][1]))
    b = min(range(len(app_disks)), key=lambda k: math.hypot(app_disks[k][0] - disks[j][0], app_disks[k][1] - disks[j][1]))
    # The scale the zones were measured at (from the 6 mm disks).
    mm_per_px = res.zones[0].diameter_mm / (2 * res.zones[0].radius_px)
    s = calibration_summary(zs, app_span=app_span_mm(app_disks[a], app_disks[b], mm_per_px), user_span=user_span)
    assert s.n == 6
    assert s.bias == pytest.approx(-0.4, abs=0.25)
    assert abs(s.scale_error) < 0.01
    assert s.verdict == "good"


def test_evaluate_zones_prints_the_calibration(tmp_path, capsys):
    import argparse
    import shutil

    from colonycounter.cli import cmd_evaluate_zones

    label = json.loads((FIXTURES / "zones_reflected.json").read_text())
    true_mm_per_px = label["plate_mm"] / (2 * label["plate"]["radius"])
    disks = [(t["x"], t["y"], 3.0 / true_mm_per_px) for t in label["true"]]
    i, j = farthest_pair(disks)
    shutil.copy(FIXTURES / "zones_reflected.jpg", tmp_path / "plate1.jpg")
    (tmp_path / "plate1.json").write_text(json.dumps({
        "plate_mm": 90, "assay": "disk", "disk_mm": 6, "tool": "calliper",
        "span_mm": round(app_span_mm(disks[i], disks[j], true_mm_per_px), 1),
        "zones": label["true"]}))
    args = argparse.Namespace(folder=str(tmp_path), assay="disk", disk_mm=6.0, plate_mm=90.0)
    assert cmd_evaluate_zones(args) == 0
    out = capsys.readouterr().out
    cal = json.loads(out[out.index('{\n  "calibration"'):])["calibration"]
    assert cal["n"] == 6
    assert abs(cal["bias_mm"]) < 0.25
    assert abs(cal["scale_error_pct"]) < 1
    assert cal["verdict"] == "good"
