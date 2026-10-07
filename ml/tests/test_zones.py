import math

import numpy as np
import pytest

from colonycounter.metrics import match_zones, zone_metrics
from colonycounter.synth_zones import make_zone_plate
from colonycounter.zones import Disk, Zone, measure_plate


def _pairs(s, res, max_mm=2.0):
    """(true, measured) zone pairs matched by disk position."""
    radius = max_mm / s.plate.mm_per_px
    pairs = match_zones([[z.x, z.y] for z in res.zones], [[t.x, t.y] for t in s.zones], radius)
    assert len(pairs) == len(s.zones), "every disk should be found"
    assert len(res.zones) == len(s.zones), "no extra disks"
    return [(s.zones[ti], res.zones[pi]) for pi, ti in pairs]


def _measure(s, **kw):
    return measure_plate(s.image, plate_diameter_mm=s.plate.diameter_mm, assay=s.assay,
                         disk_mm=s.disk_mm, **kw)


@pytest.mark.parametrize("seed", [1, 5])
def test_sharp_zones_reflected_light(seed):
    s = make_zone_plate(seed=seed, edge_mm=(0.1, 0.3))
    res = _measure(s)
    assert res.polarity == "dark_zone"
    assert res.flags == []
    for t, z in _pairs(s, res):
        assert abs(z.diameter_mm - t.diameter_mm) <= 0.5, (t.diameter_mm, z.diameter_mm, z.flags)
        assert "hazy" not in z.flags


def test_hazy_zones_backlit():
    s = make_zone_plate(seed=2, lighting="backlit", edge_mm=(0.6, 1.0))
    res = _measure(s)
    assert res.polarity == "bright_zone"
    for t, z in _pairs(s, res):
        assert abs(z.diameter_mm - t.diameter_mm) <= 1.0
        assert "hazy" in z.flags


def test_agar_wells():
    s = make_zone_plate(seed=3, assay="well", disk_mm=8.0, zone_mm=(12.0, 24.0))
    res = _measure(s)
    for t, z in _pairs(s, res):
        assert abs(z.diameter_mm - t.diameter_mm) <= 0.5


def test_no_zone_reads_disk_diameter():
    s = make_zone_plate(seed=4, zone_mm=[6, 20, 6, 24, 6, 18])
    res = _measure(s)
    for t, z in _pairs(s, res):
        if t.diameter_mm == 6:
            assert "no_zone" in z.flags
            assert z.diameter_mm == 6.0
        else:
            assert "no_zone" not in z.flags
            assert abs(z.diameter_mm - t.diameter_mm) <= 0.5


def test_overlapping_zones_are_flagged_and_measured():
    s0 = make_zone_plate(n_disks=1)
    c, mm = s0.plate.cx, s0.plate.mm_per_px
    pts = [(c - 11 / mm, c), (c + 11 / mm, c)]  # 22 mm apart, 28 mm zones overlap
    s = make_zone_plate(seed=6, positions=pts, zone_mm=[28.0, 26.0])
    res = _measure(s)
    for t, z in _pairs(s, res):
        assert "overlap" in z.flags
        assert abs(z.diameter_mm - t.diameter_mm) <= 1.0


def test_zone_reaching_rim_is_flagged():
    s0 = make_zone_plate(n_disks=1)
    c, mm = s0.plate.cx, s0.plate.mm_per_px
    pts = [(c + 32 / mm, c), (c - 20 / mm, c)]  # first disk 13 mm from the rim, 34 mm zone
    s = make_zone_plate(seed=7, positions=pts, zone_mm=[34.0, 16.0])
    res = _measure(s)
    pairs = _pairs(s, res)
    near_rim = next(z for t, z in pairs if t.diameter_mm == 34.0)
    assert "hits_rim" in near_rim.flags
    assert abs(near_rim.diameter_mm - 34.0) <= 1.0


def test_colonies_inside_zones_do_not_shift_the_edge():
    s = make_zone_plate(seed=8, zone_mm=(18.0, 30.0), colonies_in_zones=12)
    res = _measure(s)
    pairs = _pairs(s, res)
    for t, z in pairs:
        assert abs(z.diameter_mm - t.diameter_mm) <= 0.5
    assert any("colonies_in_zone" in z.flags for _, z in pairs)


def test_wrong_plate_size_is_flagged():
    s = make_zone_plate(seed=9)
    res = measure_plate(s.image, plate_diameter_mm=120.0, assay="disk", disk_mm=6.0)
    assert "scale_mismatch" in res.flags


def test_large_photo_returns_full_resolution_coordinates():
    s = make_zone_plate(seed=10, size=2400, n_disks=4, zone_mm=(14.0, 26.0))
    res = _measure(s)
    for t, z in _pairs(s, res, max_mm=1.0):
        assert abs(z.diameter_mm - t.diameter_mm) <= 0.5
        assert abs(z.disk_radius_px - t.disk_radius_px) < 0.1 * t.disk_radius_px


def test_given_plate_and_disks_skip_detection():
    s = make_zone_plate(seed=11, n_disks=3, zone_mm=[15.0, 22.0, 30.0])
    disks = [Disk(t.x, t.y, t.disk_radius_px) for t in s.zones[:2]]
    res = measure_plate(s.image, plate=s.plate, disks=disks, assay="disk", disk_mm=6.0)
    assert len(res.zones) == 2
    for t, z in zip(s.zones, res.zones):
        assert abs(z.diameter_mm - t.diameter_mm) <= 0.3


def test_rounding_and_unmeasured():
    def zone(d):
        return Zone(0, 0, 1, 1, d, 1.0, 0.0)
    assert zone(22.5).diameter_rounded == 23
    assert zone(22.49).diameter_rounded == 22
    assert zone(math.nan).diameter_rounded is None


def test_zone_metrics_gate():
    good = zone_metrics([20.2, 15.8, 30.4, 6.0], [20.0, 16.0, 30.0, 6.0])
    assert good["gate_pass"] and good["within_1mm"] == 1.0
    assert good["mae_mm"] == pytest.approx(0.2, abs=1e-9)
    bad = zone_metrics(np.array([20.0, 15.0, 33.0]), np.array([22.5, 15.0, 30.0]))
    assert not bad["gate_pass"]
