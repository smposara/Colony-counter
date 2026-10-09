"""Write app/test/fixtures/calibration_cases.json: simulated calliper readings with a
known bias, noise, scale error or edge effect, and the Python summary of each, so the
Dart port (app/lib/core/zone_calibration.dart) can be checked against the same numbers.

Run from the repository root: python ml/scripts/make_calibration_cases.py
"""

import json
import math
import pathlib
import random
from dataclasses import asdict

from colonycounter.zone_calibration import CalZone, calibration_summary


def ring(n_zones, rng, sizes=(8, 30)):
    """Zone diameters spread over sizes, alternating centre and edge positions."""
    out = []
    for i in range(n_zones):
        d = sizes[0] + (sizes[1] - sizes[0]) * i / max(1, n_zones - 1)
        out.append((round(d + rng.uniform(-0.5, 0.5), 2), 0.3 if i % 2 == 0 else 0.75))
    return out


def case(name, rng, n=8, tool="calliper", bias=0.0, noise=0.2, scale=0.0, outer=0.0,
         photos=1, rep_noise=0.1, reading_step=0.1, span_true=64.0, excluded=()):
    zones = []
    for i, (true, rf) in enumerate(ring(n, rng)):
        app_true = true * (1 + scale) + bias + (outer if rf >= 0.6 else 0.0)
        app = [round(app_true + rng.gauss(0, rep_noise if photos > 1 else 0.0), 3) for _ in range(photos)]
        user = round(round((true + rng.gauss(0, noise)) / reading_step) * reading_step, 2)
        zones.append(CalZone(app_mm=app, user_mm=[user], radial_fraction=rf, included=i not in excluded))
    app_span = round(span_true * (1 + scale), 3)
    s = calibration_summary(zones, app_span=app_span, user_span=span_true, tool=tool)
    out = asdict(s)
    for k, v in out.items():
        if isinstance(v, float) and not math.isfinite(v):
            out[k] = None
    return {
        "name": name,
        "tool": tool,
        "app_span": app_span,
        "user_span": span_true,
        "zones": [asdict(z) for z in zones],
        "python": out,
    }


def main():
    rng = random.Random(7)
    cases = [
        case("good calliper", rng),
        case("edge read 0.8 mm larger", rng, bias=0.8),
        case("scale 4 % large", rng, scale=0.04, noise=0.1),
        case("zones near the edge 1.2 mm larger", rng, outer=1.2, noise=0.1),
        case("scattered readings", rng, noise=0.9),
        case("good ruler", rng, n=9, tool="ruler", reading_step=0.5, noise=0.25),
        case("ruler with 6 zones is too few", rng, n=6, tool="ruler", reading_step=0.5),
        case("three photos", rng, photos=3, rep_noise=0.15),
        case("two zones left out", rng, n=8, excluded=(1, 4)),
        case("usable: bias 0.7 mm", rng, bias=0.7, noise=0.15),
        case("poor: edge read 1.5 mm larger", rng, bias=1.5, noise=0.2),
        case("poor: scale 8 % small (rim scale on wells)", rng, scale=-0.08, noise=0.1),
    ]
    path = pathlib.Path("app/test/fixtures/calibration_cases.json")
    path.write_text(json.dumps(cases, indent=1) + "\n")
    for c in cases:
        p = c["python"]
        print(f"{c['name']:38s} n={p['n']} bias={p['bias']:+.2f} sd={p['sd']:.2f} "
              f"scale={p['scale_error']:+.3f} -> {p['verdict']} / {p['hint']}")


if __name__ == "__main__":
    main()
