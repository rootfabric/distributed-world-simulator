from __future__ import annotations

import copy
import importlib.util
import json
import pathlib
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
MODULE_PATH = ROOT / "scripts/research/ecology/ecological_opportunity_field_v1.py"
CONTRACT_PATH = ROOT / "config/ecology/eco-evo3-e3-2-ecological-opportunity-field-contract.v1.json"
SNAPSHOT_PATH = ROOT / "config/ecology/accepted_inputs/e3_1_accepted_planet_field_snapshot.v1.json"
SCHEMA_PATH = ROOT / "config/ecology/eco-evo3-e3-2-ecological-opportunity-field.schema.v1.json"

spec = importlib.util.spec_from_file_location("ecological_opportunity_field_v1", MODULE_PATH)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)


def rehash(obj, field):
    obj[field] = mod.object_hash(obj, field)


def rehash_contract(contract):
    rehash(contract, "contract_hash")


def rehash_snapshot(snapshot):
    rehash(snapshot, "snapshot_hash")


def rehash_field(field):
    for sample in field["samples"]:
        rehash(sample, "opportunity_sample_hash")
    material = {
        "source_snapshot_hash": field["source_snapshot_hash"],
        "source_field_provenance_hash": field["source_field_provenance_hash"],
        "derivation_contract_hash": field["derivation_contract_hash"],
        "opportunity_sample_hashes": [s["opportunity_sample_hash"] for s in field["samples"]],
    }
    field["field_provenance_hash"] = mod.sha256_hex(mod.canonical_bytes(material))
    field["field_id"] = "eco-evo3/e3.2/field/" + field["field_provenance_hash"][:24]
    rehash(field, "opportunity_field_hash")


class E32EcologicalOpportunityFieldTests(unittest.TestCase):
    def setUp(self):
        self.contract = mod.load_json(CONTRACT_PATH)
        self.snapshot = mod.load_accepted_snapshot(SNAPSHOT_PATH, self.contract)
        self.field = mod.build_opportunity_field(self.contract, self.snapshot)

    def rejected(self, fn):
        with self.assertRaises(ValueError):
            fn()

    def test_01_contract_valid(self):
        mod.validate_contract(self.contract)

    def test_02_exact_accepted_snapshot_loads(self):
        self.assertEqual(self.snapshot["snapshot_hash"], mod.EXPECTED_PARENT["e3_1_snapshot_hash"])

    def test_03_field_valid(self):
        mod.validate_opportunity_field(self.field, self.contract, self.snapshot)

    def test_04_deterministic_same_process(self):
        other = mod.build_opportunity_field(self.contract, self.snapshot)
        self.assertEqual(mod.canonical_bytes(self.field), mod.canonical_bytes(other))

    def test_05_parent_e31_head_lock(self):
        c = copy.deepcopy(self.contract)
        c["parent"]["e3_1_code_under_test_head"] = "0" * 40
        rehash_contract(c)
        self.rejected(lambda: mod.validate_contract(c))

    def test_06_parent_e31_aggregate_lock(self):
        c = copy.deepcopy(self.contract)
        c["parent"]["e3_1_aggregate_hash"] = "0" * 64
        rehash_contract(c)
        self.rejected(lambda: mod.validate_contract(c))

    def test_07_parent_snapshot_hash_lock(self):
        c = copy.deepcopy(self.contract)
        c["parent"]["e3_1_snapshot_hash"] = "0" * 64
        rehash_contract(c)
        self.rejected(lambda: mod.validate_contract(c))

    def test_08_parent_snapshot_artifact_lock(self):
        c = copy.deepcopy(self.contract)
        c["parent"]["e3_1_snapshot_artifact_sha256"] = "0" * 64
        rehash_contract(c)
        self.rejected(lambda: mod.validate_contract(c))

    def test_09_parent_architecture_lock(self):
        c = copy.deepcopy(self.contract)
        c["parent"]["e3_0_architecture_hash"] = "0" * 64
        rehash_contract(c)
        self.rejected(lambda: mod.validate_contract(c))

    def test_10_raw_fixture_policy_cannot_flip(self):
        c = copy.deepcopy(self.contract)
        c["input_policy"]["raw_fixture_input_forbidden"] = False
        rehash_contract(c)
        self.rejected(lambda: mod.validate_contract(c))

    def test_11_raw_owner_policy_cannot_flip(self):
        c = copy.deepcopy(self.contract)
        c["input_policy"]["raw_owner_field_input_forbidden"] = False
        rehash_contract(c)
        self.rejected(lambda: mod.validate_contract(c))

    def test_12_transform_formula_cannot_tune_after_rehash(self):
        c = copy.deepcopy(self.contract)
        c["transform_semantics"]["limiting_resource_opportunity_ppm"] = "max(water_opportunity_ppm,light_opportunity_ppm,nutrient_opportunity_ppm)"
        rehash_contract(c)
        self.rejected(lambda: mod.validate_contract(c))

    def test_13_thermal_context_is_passthrough_not_optimum(self):
        self.assertEqual(self.contract["transform_semantics"]["thermal_context"], "temperature_milli_c_passthrough_only_not_a_target_or_fitness_optimum")
        for source, out in zip(self.snapshot["samples"], self.field["samples"]):
            self.assertEqual(out["thermal_context_milli_c"], source["temperature_milli_c"])

    def test_14_sample_count_exact(self):
        self.assertEqual(len(self.field["samples"]), 12)
        self.assertEqual(self.field["summary"]["sample_count"], 12)

    def test_15_sample_order_exact(self):
        keys = [s["stable_spatial_key"] for s in self.field["samples"]]
        self.assertEqual(keys, sorted(keys))
        self.assertEqual(keys, [s["stable_spatial_key"] for s in self.snapshot["samples"]])

    def test_16_water_passthrough(self):
        for source, out in zip(self.snapshot["samples"], self.field["samples"]):
            self.assertEqual(out["water_opportunity_ppm"], source["soil_moisture_ppm"])

    def test_17_light_passthrough(self):
        for source, out in zip(self.snapshot["samples"], self.field["samples"]):
            self.assertEqual(out["light_opportunity_ppm"], source["light_availability_ppm"])

    def test_18_nutrient_passthrough(self):
        for source, out in zip(self.snapshot["samples"], self.field["samples"]):
            self.assertEqual(out["nutrient_opportunity_ppm"], source["nutrient_availability_ppm"])

    def test_19_persistence_formula(self):
        for source, out in zip(self.snapshot["samples"], self.field["samples"]):
            self.assertEqual(out["persistence_opportunity_ppm"], 1_000_000 - source["disturbance_pressure_ppm"])

    def test_20_limiting_resource_formula(self):
        for out in self.field["samples"]:
            expected = min(out["water_opportunity_ppm"], out["light_opportunity_ppm"], out["nutrient_opportunity_ppm"])
            self.assertEqual(out["limiting_resource_opportunity_ppm"], expected)

    def test_21_establishment_formula(self):
        for out in self.field["samples"]:
            expected = (out["limiting_resource_opportunity_ppm"] * out["persistence_opportunity_ppm"]) // 1_000_000
            self.assertEqual(out["establishment_opportunity_ppm"], expected)

    def test_22_fixed_summary_values(self):
        self.assertEqual(self.field["summary"], {
            "sample_count": 12,
            "limiting_resource_min_ppm": 120000,
            "limiting_resource_max_ppm": 700000,
            "limiting_resource_mean_ppm": 390833,
            "establishment_min_ppm": 52500,
            "establishment_max_ppm": 402600,
            "establishment_mean_ppm": 262050,
        })

    def test_23_summary_recomputes_all_samples(self):
        vals = [s["establishment_opportunity_ppm"] for s in self.field["samples"]]
        self.assertEqual(self.field["summary"]["establishment_mean_ppm"], sum(vals) // len(vals))
        self.assertEqual(self.field["summary"]["establishment_min_ppm"], min(vals))
        self.assertEqual(self.field["summary"]["establishment_max_ppm"], max(vals))

    def test_24_sample_hashes_unique(self):
        hashes = [s["opportunity_sample_hash"] for s in self.field["samples"]]
        self.assertEqual(len(hashes), len(set(hashes)))

    def test_25_source_provenance_retained(self):
        for source, out in zip(self.snapshot["samples"], self.field["samples"]):
            self.assertEqual(out["source_sample_hash"], source["sample_hash"])
            self.assertEqual(out["source_field_provenance_hash"], source["field_provenance_hash"])

    def test_26_field_source_locks(self):
        self.assertEqual(self.field["source_snapshot_hash"], self.snapshot["snapshot_hash"])
        self.assertEqual(self.field["source_field_provenance_hash"], self.snapshot["field_provenance_hash"])
        self.assertEqual(self.field["derivation_contract_hash"], self.contract["contract_hash"])

    def test_27_snapshot_semantic_mutation_rejected_even_if_rehashed(self):
        s = copy.deepcopy(self.snapshot)
        s["samples"][0]["soil_moisture_ppm"] += 1
        source_shape = {k: s["samples"][0][k] for k in mod.SNAPSHOT_SAMPLE_KEYS if k != "field_provenance_hash"}
        rehash(source_shape, "sample_hash")
        s["samples"][0]["sample_hash"] = source_shape["sample_hash"]
        rehash_snapshot(s)
        self.rejected(lambda: mod.validate_accepted_snapshot(s, self.contract))

    def test_28_snapshot_authority_promotion_rejected(self):
        s = copy.deepcopy(self.snapshot)
        s["authority"] = "CANONICAL_WORLD_STATE"
        rehash_snapshot(s)
        self.rejected(lambda: mod.validate_accepted_snapshot(s, self.contract))

    def test_29_snapshot_reorder_rejected(self):
        s = copy.deepcopy(self.snapshot)
        s["samples"][0], s["samples"][1] = s["samples"][1], s["samples"][0]
        rehash_snapshot(s)
        self.rejected(lambda: mod.validate_accepted_snapshot(s, self.contract))

    def test_30_noncanonical_snapshot_artifact_bytes_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            p = pathlib.Path(td) / "snapshot.json"
            p.write_text(json.dumps(self.snapshot, indent=2), encoding="utf-8")
            self.rejected(lambda: mod.load_accepted_snapshot(p, self.contract))

    def test_31_output_authority_promotion_rejected(self):
        f = copy.deepcopy(self.field)
        f["authority"] = "CANONICAL_WORLD_STATE"
        rehash(f, "opportunity_field_hash")
        self.rejected(lambda: mod.validate_opportunity_field(f, self.contract, self.snapshot))

    def test_32_species_injection_rejected_after_rehash(self):
        f = copy.deepcopy(self.field)
        f["samples"][0]["species_assignment"] = "x"
        rehash_field(f)
        self.rejected(lambda: mod.validate_opportunity_field(f, self.contract, self.snapshot))

    def test_33_biome_injection_rejected_after_rehash(self):
        f = copy.deepcopy(self.field)
        f["biome_label"] = "wet"
        rehash(f, "opportunity_field_hash")
        self.rejected(lambda: mod.validate_opportunity_field(f, self.contract, self.snapshot))

    def test_34_population_injection_rejected_after_rehash(self):
        f = copy.deepcopy(self.field)
        f["population_truth"] = {}
        rehash(f, "opportunity_field_hash")
        self.rejected(lambda: mod.validate_opportunity_field(f, self.contract, self.snapshot))

    def test_35_semantic_tamper_rejected_after_full_rehash(self):
        f = copy.deepcopy(self.field)
        f["samples"][0]["establishment_opportunity_ppm"] += 1
        rehash_field(f)
        self.rejected(lambda: mod.validate_opportunity_field(f, self.contract, self.snapshot))

    def test_36_drop_sample_rejected(self):
        f = copy.deepcopy(self.field)
        f["samples"].pop()
        rehash_field(f)
        self.rejected(lambda: mod.validate_opportunity_field(f, self.contract, self.snapshot))

    def test_37_reorder_output_rejected(self):
        f = copy.deepcopy(self.field)
        f["samples"][0], f["samples"][1] = f["samples"][1], f["samples"][0]
        rehash_field(f)
        self.rejected(lambda: mod.validate_opportunity_field(f, self.contract, self.snapshot))

    def test_38_unexpected_output_field_rejected(self):
        f = copy.deepcopy(self.field)
        f["projection_hint"] = "x"
        rehash(f, "opportunity_field_hash")
        self.rejected(lambda: mod.validate_opportunity_field(f, self.contract, self.snapshot))

    def test_39_no_forbidden_semantics_in_output(self):
        text = mod.canonical_bytes(self.field).decode("utf-8").lower()
        for token in mod.FORBIDDEN_OUTPUT_TOKENS:
            self.assertNotIn(token, text)

    def test_40_no_global_rng_import(self):
        src = MODULE_PATH.read_text(encoding="utf-8")
        self.assertNotIn("import random", src)
        self.assertNotIn("from random", src)
        self.assertNotIn("import secrets", src)

    def test_41_no_raw_fixture_cli_surface(self):
        src = MODULE_PATH.read_text(encoding="utf-8")
        self.assertNotIn('add_argument("--fixture"', src)
        self.assertNotIn("add_argument('--fixture'", src)

    def test_42_schema_parses_and_matches_output_identity(self):
        schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
        self.assertEqual(schema["$id"], mod.OUTPUT_SCHEMA)
        self.assertEqual(schema["properties"]["schema"]["const"], mod.OUTPUT_SCHEMA)


if __name__ == "__main__":
    unittest.main()
