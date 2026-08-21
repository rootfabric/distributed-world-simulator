from __future__ import annotations

import hashlib
import importlib.util
import json
import pathlib
import subprocess
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
GENERATOR_PATH = ROOT / "scripts/research/ecology/evo4_bridge_catalog_extender_v1.py"
SOURCE_PATH = ROOT / "config/ecology/accepted_inputs/evo2_full_persisted_species_catalog.e3_4.v1.json"
OUTPUT_PATH = ROOT / "validation/ecology/evo4_b1_dev_traits_extended_catalog.v1.json"

PH0_SCHEMA = "distributed_world_simulator.ecology.plant_development_traits.v1"
PH0_VERSION = "1.0.0"
EXPECTED_TRAIT_FIELDS = {
    "schema", "version", "traits_id",
    "max_height_m", "internode_length_m", "apical_dominance", "branch_probability",
    "branch_angle_deg", "branch_length_ratio", "branching_depth", "crown_spread_m",
    "checksum",
}
# Independent copy of PH0 bounds (from plant_development_traits_v1.gd).
BOUNDS = {
    "max_height_m": (0.10, 40.0),
    "internode_length_m": (0.02, 4.0),
    "apical_dominance": (0.0, 1.0),
    "branch_probability": (0.0, 1.0),
    "branch_angle_deg": (0.0, 89.0),
    "branch_length_ratio": (0.05, 2.0),
    "branching_depth": (1, 8),
    "crown_spread_m": (0.05, 30.0),
}


def run_generator() -> str:
    result = subprocess.run(
        [sys.executable, str(GENERATOR_PATH)], capture_output=True, text=True
    )
    if result.returncode != 0:
        raise AssertionError(f"generator failed: {result.stdout}\n{result.stderr}")
    return hashlib.sha256(OUTPUT_PATH.read_bytes()).hexdigest()


def independent_checksum(traits: dict) -> str:
    """Recompute the PH0 checksum from raw values without importing the derivation module."""
    tokens = [
        PH0_SCHEMA,
        PH0_VERSION,
        str(traits["traits_id"]),
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


class Evo4B1CatalogExtensionTests(unittest.TestCase):
    def setUp(self):
        self.source_bytes_before = SOURCE_PATH.read_bytes()
        self.source_sha256_before = hashlib.sha256(self.source_bytes_before).hexdigest()
        self.artifact_sha256 = run_generator()
        self.document = json.loads(OUTPUT_PATH.read_text(encoding="utf-8"))
        self.source_catalog = json.loads(self.source_bytes_before.decode("utf-8"))

    def test_01_artifact_schema_and_provenance(self):
        self.assertEqual(
            self.document["schema"],
            "distributed_world_simulator.ecology.evo4_b1_extended_species_catalog.v1",
        )
        prov = self.document["extension_provenance"]
        self.assertEqual(prov["derivation_rule_id"], "evo4-b0-derivation-v0")
        self.assertEqual(prov["source_catalog_hash"], self.source_catalog["catalog_hash"])
        self.assertEqual(prov["source_catalog_sha256"], self.source_sha256_before)
        self.assertEqual(
            prov["source_catalog_path"],
            "config/ecology/accepted_inputs/evo2_full_persisted_species_catalog.e3_4.v1.json",
        )

    def test_02_source_catalog_untouched(self):
        current = SOURCE_PATH.read_bytes()
        self.assertEqual(hashlib.sha256(current).hexdigest(), self.source_sha256_before)

    def test_03_entry_count_and_additive_blocks(self):
        self.assertEqual(len(self.document["entries"]), len(self.source_catalog["entries"]))
        for entry in self.document["entries"]:
            self.assertIn("development_traits", entry)
            self.assertIn("evo4_bridge", entry)
            bridge = entry["evo4_bridge"]
            self.assertEqual(bridge["derivation_rule_id"], "evo4-b0-derivation-v0")
            self.assertEqual(bridge["source_genome_checksum"], entry["genome"]["checksum"])
            self.assertIsInstance(bridge["individual_seed_demo"], int)
            self.assertGreaterEqual(bridge["individual_seed_demo"], 0)

    def test_04_traits_field_exactness(self):
        for entry in self.document["entries"]:
            traits = entry["development_traits"]
            self.assertEqual(set(traits.keys()), EXPECTED_TRAIT_FIELDS)
            self.assertEqual(traits["schema"], PH0_SCHEMA)
            self.assertEqual(traits["version"], PH0_VERSION)
            self.assertIsInstance(traits["branching_depth"], int)

    def test_05_bounds_respected(self):
        for entry in self.document["entries"]:
            traits = entry["development_traits"]
            for name, (low, high) in BOUNDS.items():
                value = float(traits[name])
                self.assertGreaterEqual(value, low, name)
                self.assertLessEqual(value, high, name)

    def test_06_checksum_independent_recompute(self):
        for entry in self.document["entries"]:
            traits = entry["development_traits"]
            self.assertTrue(str(traits["traits_id"]).startswith("plant-development/evo4-b0-derivation-v0/"))
            self.assertEqual(traits["checksum"], independent_checksum(traits))

    def test_07_determinism_fresh_process_byte_identical(self):
        second = run_generator()
        self.assertEqual(second, self.artifact_sha256)


if __name__ == "__main__":
    unittest.main()
