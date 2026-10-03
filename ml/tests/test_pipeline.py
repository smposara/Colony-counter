import numpy as np
import pytest

from colonycounter import count_colonies, find_plate
from colonycounter.metrics import count_metrics, lins_ccc, match_points
from colonycounter.pipeline import draw_overlay
from colonycounter.synth import make_plate


def _points(res):
    return np.array([[c.x, c.y] for c in res.colonies]).reshape(-1, 2)


def test_find_plate_on_synthetic():
    s = make_plate(30, seed=1)
    p = find_plate(s.image)
    assert abs(p.cx - s.plate.cx) < 0.02 * s.plate.radius
    assert abs(p.cy - s.plate.cy) < 0.02 * s.plate.radius
    assert abs(p.radius - s.plate.radius) < 0.03 * s.plate.radius


def test_empty_plate_counts_zero():
    for seed in range(3):
        assert count_colonies(make_plate(0, seed=seed).image).count == 0


@pytest.mark.parametrize("n", [50, 150, 300])
def test_count_accuracy_bright(n):
    for seed in range(2):
        s = make_plate(n, seed=seed)
        res = count_colonies(s.image)
        assert res.polarity == "bright"
        assert abs(res.count - n) <= max(3, 0.08 * n)
        m = match_points(_points(res), s.points, radius=12)
        assert m["precision"] > 0.95
        assert m["recall"] > 0.92


def test_count_accuracy_backlit():
    s = make_plate(100, seed=4, polarity="dark")
    res = count_colonies(s.image)
    assert res.polarity == "dark"
    assert abs(res.count - 100) <= 8


def test_overlay_shape():
    s = make_plate(20, seed=2)
    res = count_colonies(s.image)
    assert draw_overlay(s.image, res).shape == s.image.shape


def test_metrics():
    m = count_metrics([100, 52, 9], [100, 50, 10])
    assert m["mae"] == pytest.approx(1.0)
    assert m["within_10pct"] == pytest.approx(1.0)
    assert lins_ccc([1, 2, 3], [1, 2, 3]) == pytest.approx(1.0)
    pm = match_points([[0, 0], [10, 10], [50, 50]], [[1, 0], [11, 10]], radius=3)
    assert (pm["tp"], pm["fp"], pm["fn"]) == (2, 1, 0)
