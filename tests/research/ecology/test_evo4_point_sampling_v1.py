from __future__ import annotations

import importlib.util
import json
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
MODULE_PATH = ROOT / "scripts/research/ecology/evo4_point_sampling_v1.py"
REAL_SNAPSHOT_PATH = (
    ROOT
    / "config/ecology/accepted_inputs/e3_final/e3_final_unseen_planet_field_snapshot.arid-basin-02.v1.json"
)
spec = importlib.util.spec_from_file_location("evo4_point_sampling_v1", MODULE_PATH)
assert spec is not None and spec.loader is not None
sys.modules[spec.name] = mod = importlib.util.module_from_spec(spec)  # type: ignore[attr-defined]
spec.loader.exec_module(mod)

# Synthetic fixture mirroring the real arid-basin-02 snapshot shape:
# geometry in latitude/longitude microdeg, ppm/milli-c condition keys.
FIXTURE_SAMPLES = [
    {
        "latitude_microdeg": -75_000_000,
        "longitude_microdeg": -150_000_000,
        "sample_id": "pf-01",
        "stable_spatial_key": "eco-evo3-fixture/planet-alpha/cell-01",
        "light_availability_ppm": 384_000,
        "soil_moisture_ppm": 30_000,
        "nutrient_availability_ppm": 180_000,
        "disturbance_pressure_ppm": 80_000,
        "temperature_milli_c": -10_000,
    },
    {
        "latitude_microdeg": -60_000_000,
        "longitude_microdeg": -120_000_000,
        "sample_id": "pf-02",
        "stable_spatial_key": "eco-evo3-fixture/planet-alpha/cell-02",
        "light_availability_ppm": 468_000,
        "soil_moisture_ppm": 45_000,
        "nutrient_availability_ppm": 240_000,
        "disturbance_pressure_ppm": 120_000,
        "temperature_milli_c": -4_000,
    },
    {
        "latitude_microdeg": -80_000_000,
        "longitude_microdeg": -140_000_000,
        "sample_id": "pf-03",
        "stable_spatial_key": "eco-evo3-fixture/planet-alpha/cell-03",
        "light_availability_ppm": 300_000,
        "soil_moisture_ppm": 20_000,
        "nutrient_availability_ppm": 150_000,
        "disturbance_pressure_ppm": 60_000,
        "temperature_milli_c": -18_000,
    },
]


def make_index(samples=None):
    return mod.build_sample_index(FIXTURE_SAMPLES if samples is None else samples)


class Evo4B5PointSamplingTests(unittest.TestCase):
    def setUp(self):
        self.index = make_index()

    def test_01_exact_hit_returns_zero_distance_and_conditions(self):
        result = mod.sample(self.index, -75_000_000, -150_000_000)
        self.assertTrue(result["ok"])
        self.assertEqual(result["distance_squared_microdeg2"], 0.0)
        self.assertEqual(result["sample_id"], "pf-01")
        self.assertEqual(result["conditions"]["light_availability_ppm"], 384_000)

    def test_02_nearest_selection(self):
        # Point closer to pf-02 than to any other sample.
        result = mod.sample(self.index, -61_000_000, -121_000_000)
        self.assertEqual(result["sample_id"], "pf-02")
        self.assertGreater(result["distance_squared_microdeg2"], 0.0)

    def test_03_equidistant_tie_break_by_stable_spatial_key(self):
        # Dedicated two-candidate symmetry: point exactly between A and B.
        candidate_a = dict(FIXTURE_SAMPLES[0], latitude_microdeg=-70_000_000, longitude_microdeg=-135_000_000,
                           stable_spatial_key="eco-evo3-fixture/planet-alpha/cell-zz", sample_id="pf-a")
        candidate_b = dict(FIXTURE_SAMPLES[1], latitude_microdeg=-65_000_000, longitude_microdeg=-135_000_000,
                           stable_spatial_key="eco-evo3-fixture/planet-alpha/cell-aa", sample_id="pf-b")
        result = mod.sample(make_index([candidate_a, candidate_b]), -67_500_000, -135_000_000)
        self.assertTrue(result["ok"])
        self.assertEqual(result["stable_spatial_key"], candidate_b["stable_spatial_key"])
        swapped = mod.sample(make_index([candidate_b, candidate_a]), -67_500_000, -135_000_000)
        self.assertEqual(swapped, result)

    def test_04_ordering_independence(self):
        reversed_index = make_index(list(reversed(FIXTURE_SAMPLES)))
        point = (-70_000_000, -130_000_000)
        self.assertEqual(mod.sample(self.index, *point), mod.sample(reversed_index, *point))

    def test_05_empty_index_fail_closed(self):
        result = mod.sample(mod.build_sample_index([]), 0, 0)
        self.assertFalse(result["ok"])
        self.assertEqual(result["error_code"], mod.ERROR_EMPTY_INDEX)

    def test_06_nonfinite_point_fail_closed(self):
        for lat, lon in ((float("nan"), 0.0), (float("inf"), 0.0), (0, float("-inf")), ("x", 0)):
            result = mod.sample(self.index, lat, lon)
            self.assertFalse(result["ok"])
            self.assertEqual(result["error_code"], mod.ERROR_NONFINITE_POINT)

    def test_07_out_of_extent_fail_closed(self):
        north = mod.sample(self.index, 90_000_001, 0)
        south = mod.sample(self.index, -90_000_001, 0)
        east = mod.sample(self.index, 0, 180_000_001)
        west = mod.sample(self.index, 0, -180_000_001)
        for result in (north, south, east, west):
            self.assertEqual(result["error_code"], mod.ERROR_OUT_OF_EXTENT)
        self.assertTrue(mod.sample(self.index, 90_000_000, 180_000_000)["ok"])

    def test_08_determinism_repeated_calls_identical(self):
        results = {json.dumps(mod.sample(self.index, -62_000_000, -118_000_000)) for _ in range(25)}
        self.assertEqual(len(results), 1)

    def test_09_real_artifact_smoke_arid_basin_02(self):
        if not REAL_SNAPSHOT_PATH.exists():
            self.skipTest("real snapshot artifact not present")
        snapshot = json.loads(REAL_SNAPSHOT_PATH.read_text(encoding="utf-8"))
        index = mod.build_sample_index(snapshot["samples"])
        first = snapshot["samples"][0]
        exact = mod.sample(index, first["latitude_microdeg"], first["longitude_microdeg"])
        self.assertTrue(exact["ok"])
        self.assertEqual(exact["sample_id"], first["sample_id"])
        self.assertEqual(exact["conditions"]["light_availability_ppm"], first["light_availability_ppm"])


if __name__ == "__main__":
    unittest.main()
