import math

import pytest

from colonycounter.calculator import PlateCount, cfu_per_ml, estimate, format_sci, round_sig


def test_single_plate():
    assert cfu_per_ml(150, 1e-4, 0.1) == pytest.approx(1.5e7)


def test_iso7218_two_successive_dilutions():
    # ISO 7218 worked example form: N = ΣC / (V × 1.1 × d)
    plates = [PlateCount(168, 1e-2, 1.0), PlateCount(14, 1e-3, 1.0)]
    est = estimate(plates, rule="ISO_7218")
    expected = (168 + 14) / (1.0 * 1.1 * 1e-2)
    assert est.value == pytest.approx(round_sig(expected))
    assert est.qualifier == ""
    assert len(est.plates_used) == 2


def test_bam_duplicates_pooled():
    plates = [PlateCount(232, 1e-2), PlateCount(244, 1e-2), PlateCount(33, 1e-3), PlateCount(28, 1e-3)]
    est = estimate(plates, rule="FDA_BAM")
    expected = (232 + 244 + 33 + 28) / (0.1 * (2e-2 + 2e-3))
    assert est.value == pytest.approx(round_sig(expected))


def test_all_below_range_uses_least_diluted():
    est = estimate([PlateCount(12, 1e-1), PlateCount(1, 1e-2)], rule="FDA_BAM")
    assert est.qualifier == "~"
    assert est.value == pytest.approx(1200)


def test_zero_colonies_reports_less_than():
    est = estimate([PlateCount(0, 1e-1, 0.1)], rule="FDA_BAM")
    assert est.qualifier == "<"
    assert est.value == pytest.approx(100)


def test_tntc_reports_greater_than():
    est = estimate([PlateCount(300, 1e-3, tntc=True), PlateCount(300, 1e-4, tntc=True)])
    assert est.qualifier == ">"
    assert est.value == pytest.approx(3e7)


def test_spreader_plates_excluded():
    est = estimate([PlateCount(100, 1e-3, spreader=True), PlateCount(40, 1e-3)])
    assert est.plates_used == [PlateCount(40, 1e-3)]


def test_all_spreaders():
    est = estimate([PlateCount(100, 1e-3, spreader=True)])
    assert math.isnan(est.value)


def test_formatting():
    assert round_sig(16545, 2) == 17000
    assert format_sci(16545) == "1.7 × 10^4"
    assert format_sci(99600) == "1.0 × 10^5"
