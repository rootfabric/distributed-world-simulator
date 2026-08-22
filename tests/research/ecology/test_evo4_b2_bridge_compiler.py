from __future__ import annotations

import hashlib
import importlib.util
import itertools
import json
import pathlib
import subprocess
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
COMPILER_PATH = ROOT / "scripts/research/ecology/evo4_bridge_compiler_v1.py"
DERIVATION_PATH = ROOT / "scripts/research/ecology/evo4_bridge_derivation_v0.py"
B1_PATH = ROOT / "validation/ecology/evo4_b1_dev_traits_extended_catalog.v1.json"
SNAPSHOT_PATH = (
    ROOT
    / "config/ecology/accepted_inputs/e3_final/e3_final_unseen_planet_field_snapshot.arid-basin-02.v1.json"
)
OUTPUT_PATH = ROOT / "validation/ecology/evo4_b2_development_state.v1.json"

PH0_BOUNDS = {
    "max_height_m": (0.10, 40.0),
    "internode_length_m": (0.02, 4.0),
    "apical_dominance": (0.0, 1.0),
    "branch_probability": (0.0, 1.0),
    "branch_angle_deg": (0.0, 89.0),
    "branch_length_ratio": (0.05, 2.0),
    "branching_depth": (1, 8),
    "crown_spread_m": (0.05, 30.0),
}


def load_module(name: str, path: pathlib.Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


compiler = load_module("evo4_bridge_compiler_v1", COMPILER_PATH)


def independent_checksum(traits_id: str, traits: dict) -> str:
    tokens = [
        "distributed_world_simulator.ecology.plant_development_traits.v1",
        "1.0.0",
        str(traits_id),
        "%.9f" % float(traits["max_height_m"]),
        "%.9f" % float(traits["internode_length_m"]),
        "%.9f" % float(traits["apical_dominance"]),
        "%.9f" % float(traits["branch_probability"]),
        "%.9f" % float(traits["branch_angle_deg"]),
        "%.9f" % float(traits["branch_length_ratio"]),
        str(int(traits["branching_depth"])),
        "%.9f" % float(traits["crown_spread_m"]),
    ]
    return hashlib.sha256("|".join(tokens).encode("utf-8")).hexdigest()


BASE_ENTRY = json.loads(B1_PATH.read_text(encoding="utf-8"))["entries"][0]
NEUTRAL_CONDITIONS = {
    "light_availability_ppm": 500_000,
    "soil_moisture_ppm": 500_000,
    "nutrient_availability_ppm": 500_000,
    "disturbance_pressure_ppm": 0,
    "temperature_milli_c": 12_000,
}


class Evo4B2BridgeCompilerTests(unittest.TestCase):
    def test_01_neutral_point_identity(self):
        result = compiler.compile_one(BASE_ENTRY, NEUTRAL_CONDITIONS, 2.0)
        base = BASE_ENTRY["development_traits"]
        effective = result["effective_development_traits"]
        for name in PH0_BOUNDS:
            self.assertAlmostEqual(float(effective[name]), float(base[name]), places=12, msg=name)
        self.assertEqual(result["development_state"]["dormancy_state"], "ACTIVE")
        self.assertEqual(result["development_state"]["stress_index"], 0.0)

    def test_02_light_monotonicity(self):
        low = compiler.compile_one(BASE_ENTRY, dict(NEUTRAL_CONDITIONS, light_availability_ppm=200_000), 2.0)
        high = compiler.compile_one(BASE_ENTRY, dict(NEUTRAL_CONDITIONS, light_availability_ppm=800_000), 2.0)
        self.assertLess(
            float(low["effective_development_traits"]["max_height_m"]),
            float(high["effective_development_traits"]["max_height_m"]),
        )

    def test_03_stress_stunts_height_and_internode(self):
        calm = compiler.compile_one(BASE_ENTRY, NEUTRAL_CONDITIONS, 2.0)
        stressed = compiler.compile_one(
            BASE_ENTRY, dict(NEUTRAL_CONDITIONS, disturbance_pressure_ppm=800_000), 2.0
        )
        self.assertLess(
            float(stressed["effective_development_traits"]["max_height_m"]),
            float(calm["effective_development_traits"]["max_height_m"]),
        )
        self.assertLess(
            float(stressed["effective_development_traits"]["internode_length_m"]),
            float(calm["effective_development_traits"]["internode_length_m"]),
        )

    def test_04_effective_traits_within_bounds_under_extremes(self):
        for lights, soils, nutrients, disturbances, temps in itertools.product(
            (0, 1_000_000), (0, 1_000_000), (0, 1_000_000), (0, 1_000_000), (-40_000, 40_000)
        ):
            conditions = {
                "light_availability_ppm": lights,
                "soil_moisture_ppm": soils,
                "nutrient_availability_ppm": nutrients,
                "disturbance_pressure_ppm": disturbances,
                "temperature_milli_c": temps,
            }
            result = compiler.compile_one(BASE_ENTRY, conditions, 2.0)
            effective = result["effective_development_traits"]
            for name, (low, high) in PH0_BOUNDS.items():
                value = float(effective[name])
                self.assertGreaterEqual(value, low, f"{name} @ {conditions}")
                self.assertLessEqual(value, high, f"{name} @ {conditions}")

    def test_05_dormancy_states_both_reachable(self):
        cold = compiler.compile_one(BASE_ENTRY, dict(NEUTRAL_CONDITIONS, temperature_milli_c=-4_000), 2.0)
        warm = compiler.compile_one(BASE_ENTRY, dict(NEUTRAL_CONDITIONS, temperature_milli_c=4_000), 2.0)
        self.assertEqual(cold["development_state"]["dormancy_state"], "DORMANT_COLD")
        self.assertEqual(warm["development_state"]["dormancy_state"], "ACTIVE")

    def test_06_effective_checksum_independent_recompute(self):
        result = compiler.compile_one(BASE_ENTRY, NEUTRAL_CONDITIONS, 2.0)
        effective = result["effective_development_traits"]
        self.assertTrue(str(effective["traits_id"]).endswith("+evo4-b2"))
        self.assertEqual(effective["checksum"], independent_checksum(effective["traits_id"], effective))

    def test_07_age_synthesis_contract(self):
        self.assertEqual(compiler.synthesize_cohort_age(3.0, 0), 2.0)
        self.assertEqual(compiler.synthesize_cohort_age(8.5, 2), 5.0)
        self.assertEqual(compiler.synthesize_cohort_age(2.5, 5), 2.5)

    def test_08_artifact_provenance_record_count_and_sha(self):
        first = subprocess.run([sys.executable, str(COMPILER_PATH)], capture_output=True, text=True)
        self.assertEqual(first.returncode, 0, first.stderr)
        document = json.loads(OUTPUT_PATH.read_text(encoding="utf-8"))
        b1_count = len(json.loads(B1_PATH.read_text(encoding="utf-8"))["entries"])
        snapshot_count = len(json.loads(SNAPSHOT_PATH.read_text(encoding="utf-8"))["samples"])
        self.assertEqual(document["rule_id"], "evo4-b2-plasticity-v0")
        prov = document["provenance"]["inputs"]
        self.assertEqual(prov["b1_artifact_sha256"], hashlib.sha256(B1_PATH.read_bytes()).hexdigest())
        self.assertEqual(prov["snapshot_sha256"], hashlib.sha256(SNAPSHOT_PATH.read_bytes()).hexdigest())
        self.assertEqual(len(document["records"]), b1_count * snapshot_count)

    def test_09_fresh_process_determinism_byte_identical(self):
        run_a = subprocess.run([sys.executable, str(COMPILER_PATH)], capture_output=True, text=True)
        digest_a = hashlib.sha256(OUTPUT_PATH.read_bytes()).hexdigest()
        run_b = subprocess.run([sys.executable, str(COMPILER_PATH)], capture_output=True, text=True)
        digest_b = hashlib.sha256(OUTPUT_PATH.read_bytes()).hexdigest()
        self.assertEqual(run_a.returncode, 0)
        self.assertEqual(run_b.returncode, 0)
        self.assertEqual(digest_a, digest_b)


if __name__ == "__main__":
    unittest.main()
