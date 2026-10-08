import numpy as np
import pytest

from colonycounter.drop_stats import DropCount, dilution_table, drop_counts, estimate_drops
from colonycounter.drops import Layout, count_drop_plate, drop_diameter_mm, layout_positions_mm
from colonycounter.synth_drops import make_drop_plate

SECTORS = Layout("sectors", n=8, ring_mm=25)
GRID = Layout("grid", rows=4, cols=3, pitch_mm=12)


def _nearest(drops, t):
    return min(drops, key=lambda d: np.hypot(d.x - t.x, d.y - t.y))


def test_drop_diameter_scales_with_volume():
    assert drop_diameter_mm(10) == pytest.approx(7.0)
    assert drop_diameter_mm(80) == pytest.approx(14.0)


def test_layout_positions():
    pos = layout_positions_mm(SECTORS, list(range(3, 11)))
    assert len(pos) == 8
    assert [p[2] for p in pos] == list(range(3, 11))
    assert pos[0][:2] == pytest.approx((0.0, -25.0))  # first sector at the top
    assert pos[2][:2] == pytest.approx((25.0, 0.0), abs=1e-9)  # then clockwise
    grid = layout_positions_mm(GRID, [4, 5, 6, 7])
    assert [p[2] for p in grid] == [4, 4, 4, 5, 5, 5, 6, 6, 6, 7, 7, 7]
    assert [p[3] for p in grid[:3]] == [1, 2, 3]


@pytest.mark.parametrize("layout,dils,seed", [
    (SECTORS, list(range(3, 11)), 1),
    (GRID, [4, 5, 6, 7], 2),
    (Layout("grid", rows=5, cols=5, pitch_mm=11), [3, 4, 5, 6, 7], 3),
])
def test_every_drop_found_and_labelled(layout, dils, seed):
    s = make_drop_plate(layout, dils, cfu_per_ml=3e7, seed=seed)
    r = count_drop_plate(s.image, layout, dils)
    assert len(r.drops) == len(s.drops)
    for t in s.drops:
        d = _nearest(r.drops, t)
        assert np.hypot(d.x - t.x, d.y - t.y) / s.px_per_mm < 2.8
        assert d.dilution_exp == t.dilution_exp
        if t.confluent:
            assert d.confluent
        elif t.count <= 30:
            assert not d.confluent
            # Crowded drops near the top of the window are counted partly by area.
            tol = max(2, 0.15 * t.count) if d.crowded else 2
            assert d.count == pytest.approx(t.count, abs=tol)


def test_empty_drops_keep_their_dilution():
    # Most drops are empty: they have no colonies to be found by, only the layout.
    s = make_drop_plate(SECTORS, list(range(3, 11)), cfu_per_ml=1e6, seed=4, rotation_deg=40)
    r = count_drop_plate(s.image, SECTORS, list(range(3, 11)))
    empty = [t for t in s.drops if t.count == 0]
    assert len(empty) >= 4
    for t in empty:
        d = _nearest(r.drops, t)
        assert d.count == 0 and d.dilution_exp == t.dilution_exp


def test_stray_colonies_are_not_drops():
    s = make_drop_plate(GRID, [4, 5, 6, 7], cfu_per_ml=2e7, seed=5, strays=4)
    r = count_drop_plate(s.image, GRID, [4, 5, 6, 7])
    assert len(r.drops) == 12
    assert len(r.strays) >= 3
    assert "colonies_outside_drops" in r.flags


def test_replicates_numbered_within_a_dilution():
    s = make_drop_plate(GRID, [4, 5, 6, 7], cfu_per_ml=2e7, seed=6)
    r = count_drop_plate(s.image, GRID, [4, 5, 6, 7])
    for dil in (4, 5, 6, 7):
        assert sorted(d.replicate for d in r.drops if d.dilution_exp == dil) == [1, 2, 3]


# ---------------------------------------------------------------------------
# Statistics


def _drops(rows):
    return [DropCount(d, i + 1, c) for d, cs in rows for i, c in enumerate(cs)]


def test_dilution_table_by_hand():
    rows = dilution_table(_drops([(5, [10, 12, 14]), (6, [1, 2, 0])]))
    r = rows[0]
    assert r.mean == pytest.approx(12.0)
    assert r.sd == pytest.approx(2.0)
    assert r.vmr == pytest.approx(4 / 12)
    assert r.chi2 == pytest.approx(8 / 12)  # Σ(x − x̄)² / x̄
    assert r.p > 0.5
    assert r.flags == []


def test_overdispersed_and_outlier():
    rows = dilution_table(_drops([(5, [20, 21, 19, 20, 60])]))
    assert "overdispersed" in rows[0].flags
    assert "outlier_drop" in rows[0].flags
    assert rows[0].outliers == [4]


def test_not_tenfold():
    rows = dilution_table(_drops([(5, [20, 22, 18]), (6, [15, 14, 16])]))
    assert "not_tenfold" in rows[0].flags
    rows = dilution_table(_drops([(5, [20, 22, 18]), (6, [2, 3, 1])]))
    assert "not_tenfold" not in rows[0].flags


def test_tntc_and_excluded_left_out():
    drops = [DropCount(4, 1, 0, tntc=True), DropCount(4, 2, 99, excluded=True), DropCount(4, 3, 25)]
    r = dilution_table(drops)[0]
    assert r.counts == [25] and r.tntc == 1 and r.excluded == 1


def test_first_and_pooled_estimates():
    rows = dilution_table(_drops([(4, [40, 45, 38]), (5, [20, 25, 15]), (6, [3, 2, 1])]))
    first = estimate_drops(rows, 10, mode="first")
    assert first.qualifier == "exact"
    assert first.dilutions_used == [5]
    assert first.cfu_per_ml == pytest.approx(20 / (0.01 * 1e-5))  # 2e8
    pooled = estimate_drops(rows, 10, mode="pooled")
    # In-window drops: 20, 25, 15 at 1e-5 and 3 at 1e-6.
    assert pooled.cfu_per_ml == pytest.approx(63 / (3 * 0.01e-5 + 0.01e-6))
    assert pooled.dilutions_used == [5, 6]
    assert pooled.low < pooled.cfu_per_ml < pooled.high


def test_garwood_interval():
    rows = dilution_table(_drops([(5, [10])]))
    e = estimate_drops(rows, 10, mode="first")
    vd = 0.01 * 1e-5
    # Exact Poisson 95 % limits for 10 counts: 4.795 and 18.39.
    assert e.low * vd == pytest.approx(4.795, abs=0.01)
    assert e.high * vd == pytest.approx(18.39, abs=0.01)


def test_detection_limit_when_nothing_grew():
    rows = dilution_table(_drops([(2, [0, 0, 0, 0, 0]), (3, [0, 0, 0, 0, 0])]))
    e = estimate_drops(rows, 10)
    assert e.qualifier == "<"
    assert e.cfu_per_ml == pytest.approx(1 / (5 * 0.01 * 1e-2))  # 20 CFU/mL


def test_below_and_above_window():
    e = estimate_drops(dilution_table(_drops([(2, [1, 2, 0])])), 10)
    assert e.qualifier == "estimated" and "below" in e.note
    drops = [DropCount(3, i, 0, tntc=True) for i in (1, 2)] + [DropCount(4, i, 0, tntc=True) for i in (1, 2)]
    e = estimate_drops(dilution_table(drops), 10)
    assert e.qualifier == ">"
    assert e.cfu_per_ml == pytest.approx(30 * 2 / (2 * 0.01e-4))


def test_plate_estimate_near_truth():
    s = make_drop_plate(GRID, [4, 5, 6, 7], cfu_per_ml=2.5e7, seed=7)
    r = count_drop_plate(s.image, GRID, [4, 5, 6, 7])
    truth = estimate_drops(dilution_table(
        [DropCount(t.dilution_exp, t.replicate, t.count, t.confluent) for t in s.drops]), 10)
    est = estimate_drops(dilution_table(drop_counts(r)), 10)
    assert est.qualifier == truth.qualifier == "exact"
    assert est.cfu_per_ml == pytest.approx(truth.cfu_per_ml, rel=0.15)
