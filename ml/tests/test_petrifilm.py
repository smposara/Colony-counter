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


def test_only_results_above_range_are_estimated():
    """An EC film above the range for coliforms keeps its E. coli count."""
    from colonycounter.petrifilm import FilmColony, Grid, tally_film
    from colonycounter.plate import Plate
    grid = Grid(120, 0, 0, 0, (600, 600))
    area = Plate(600, 600, 303, 50.5)
    marks = [FilmColony(600 + i * 120 + 10 + k * 3, 600 + j * 120 + 60, 1, "red", gas=True)
             for i in range(-2, 2) for j in range(-2, 2) for k in range(20)]
    marks += [FilmColony(615, 615, 1, "blue") for _ in range(8)]
    counts, est, used = tally_film("ec", marks, grid, area)
    assert counts == {"ecoli": 8, "coliform": 328}
    assert used >= 3 and set(est) == {"coliform"}


def test_given_grid_is_scaled_to_work_size():
    import cv2
    s = make_film("ac", n=30, seed=12)
    big = cv2.resize(s.image, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_LINEAR)
    g = count_petrifilm(big, "ac").grid
    res = count_petrifilm(big, "ac", grid=g)
    assert abs(res.grid.pitch_px - g.pitch_px) < 0.01 * g.pitch_px
    assert abs(res.counts["aerobic"] - 30) <= 2


def test_grid_not_found_on_a_dish_photo():
    """A dish photo has no printed grid: flagged, and the pitch stays sane."""
    import cv2
    from colonycounter.synth import make_plate
    plate = make_plate(n_colonies=60, seed=5)
    img = plate.image if plate.image.ndim == 3 else cv2.cvtColor(plate.image, cv2.COLOR_GRAY2BGR)
    try:
        res = count_petrifilm(img, "ac")
    except ValueError:  # no growth area found is also acceptable
        return
    assert "grid_not_found" in res.flags
    assert res.grid.pitch_px > 0


def test_films_have_a_strong_grid():
    for t, seed in [("ac", 21), ("ec", 22), ("ym", 23)]:
        res = count_petrifilm(make_film(t, n=40, seed=seed, angle_deg=7).image, t)
        assert "grid_not_found" not in res.flags
        assert res.grid.strength > 0.5
