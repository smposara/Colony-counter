import numpy as np
import pytest

from colonycounter.metrics import match_zones
from colonycounter.petrifilm import TYPES, count_petrifilm, find_grid
from colonycounter.synth_petrifilm import make_film


@pytest.mark.parametrize("angle", [0.0, 9.0, -14.0])
def test_grid_gives_scale_and_angle(angle):
    s = make_film("ac", n=30, seed=1, angle_deg=angle, px_per_mm=11.0)
    import cv2
    g = find_grid(cv2.cvtColor(s.image, cv2.COLOR_BGR2GRAY))
    assert g.pitch_px == pytest.approx(110.0, rel=0.01)
    # The grid is symmetric under 90° turns.
    d = (g.angle_deg - angle + 45) % 90 - 45
    assert abs(d) < 0.3


def test_growth_area_found():
    s = make_film("ec", n=40, seed=2, angle_deg=5)
    r = count_petrifilm(s.image, "ec")
    assert np.hypot(r.plate.cx - s.centre[0], r.plate.cy - s.centre[1]) < 0.02 * s.radius_px
    assert r.plate.radius == pytest.approx(s.radius_px, rel=0.03)
    assert r.plate.diameter_mm == pytest.approx(50.5, rel=0.03)


def test_aerobic_count():
    s = make_film("ac", n=80, seed=3, angle_deg=-6)
    r = count_petrifilm(s.image, "ac")
    assert r.counts["aerobic"] == pytest.approx(s.truth()["aerobic"], abs=3)
    assert "estimated" not in r.flags


def test_ecoli_coliform_split_and_gas():
    s = make_film("ec", n=60, seed=5, angle_deg=4)
    r = count_petrifilm(s.image, "ec")
    t = s.truth()
    assert r.counts["ecoli"] == pytest.approx(t["ecoli"], abs=1)
    assert r.counts["coliform"] == pytest.approx(t["coliform"], abs=3)


def test_loose_bubbles_do_not_make_coliforms():
    # Red colonies without gas plus loose bubbles: no coliforms.
    s = make_film("cc", n=30, seed=6, gas_fraction=0.0, loose_bubbles=10)
    r = count_petrifilm(s.image, "cc")
    assert s.truth()["coliform"] == 0
    assert r.counts["coliform"] <= 1


def test_gas_bubbles_found():
    s = make_film("cc", n=50, seed=3, angle_deg=-4)
    r = count_petrifilm(s.image, "cc")
    m = match_zones([(x, y) for x, y, _ in r.bubbles], [(x, y) for x, y, _ in s.bubbles], 0.4 * s.px_per_mm)
    assert len(m) >= 0.85 * len(s.bubbles)
    assert len(r.bubbles) - len(m) <= 1
    assert r.counts["coliform"] == pytest.approx(s.truth()["coliform"], abs=2)


def test_enterobacteriaceae_yellow_zones_or_gas():
    s = make_film("eb", n=50, seed=3, angle_deg=-4)
    r = count_petrifilm(s.image, "eb")
    assert r.counts["enterobacteriaceae"] == pytest.approx(s.truth()["enterobacteriaceae"], abs=3)


def test_yeast_and_mold():
    s = make_film("ym", n=50, seed=5, angle_deg=6)
    r = count_petrifilm(s.image, "ym")
    t = s.truth()
    assert r.counts["yeast"] == pytest.approx(t["yeast"], rel=0.15, abs=3)
    assert r.counts["mold"] == pytest.approx(t["mold"], rel=0.25, abs=3)


def test_crowded_plate_is_estimated_from_squares():
    s = make_film("ac", n=700, seed=900, angle_deg=3)
    r = count_petrifilm(s.image, "ac")
    assert "estimated" in r.flags
    assert r.squares_used >= 3
    assert r.values["aerobic"] == pytest.approx(s.truth()["aerobic"], rel=0.2)


def test_type_table_is_complete():
    for key, ft in TYPES.items():
        assert ft.key == key
        assert ft.count_min < ft.count_max
        assert ft.results
    assert TYPES["ac"].confirmed and (TYPES["ac"].count_min, TYPES["ac"].count_max) == (25, 250)
