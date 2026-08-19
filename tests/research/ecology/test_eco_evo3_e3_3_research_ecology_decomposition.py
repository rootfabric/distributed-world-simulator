from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import pathlib
import sys
import tempfile
import unittest

from jsonschema import Draft202012Validator
from jsonschema.exceptions import ValidationError

ROOT = pathlib.Path(__file__).resolve().parents[3]
MODULE_PATH = ROOT / "scripts/research/ecology/research_ecology_decomposition_v1.py"
CONTRACT_PATH = ROOT / "config/ecology/eco-evo3-e3-3-research-ecology-decomposition-contract.v1.json"
FIELD_PATH = ROOT / "config/ecology/accepted_inputs/e3_2_accepted_ecological_opportunity_field.v1.json"
SCHEMA_PATH = ROOT / "config/ecology/eco-evo3-e3-3-research-ecology-decomposition.schema.v1.json"

spec = importlib.util.spec_from_file_location("research_ecology_decomposition_v1", MODULE_PATH)
mod = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)


def rehash(obj, field):
    obj[field] = mod.object_hash(obj, field)


def rehash_contract(contract):
    rehash(contract, "contract_hash")


def rehash_source(field):
    for sample in field["samples"]:
        rehash(sample, "opportunity_sample_hash")
    rehash(field, "opportunity_field_hash")


def rehash_output(output):
    for patch in output["patches"]:
        rehash(patch, "patch_hash")
    for edge in output["edges"]:
        rehash(edge, "edge_hash")
    for region in output["regions"]:
        rehash(region, "region_hash")
    material = {
        "source_opportunity_field_hash": output["source_opportunity_field_hash"],
        "source_field_provenance_hash": output["source_field_provenance_hash"],
        "derivation_contract_hash": output["derivation_contract_hash"],
        "patch_hashes": [patch["patch_hash"] for patch in output["patches"]],
        "edge_hashes": [edge["edge_hash"] for edge in output["edges"]],
        "region_hashes": [region["region_hash"] for region in output["regions"]],
    }
    output["decomposition_provenance_hash"] = mod.sha256_hex(mod.canonical_bytes(material))
    output["decomposition_id"] = "eco-evo3/e3.3/decomposition/" + output["decomposition_provenance_hash"][:24]
    rehash(output, "decomposition_hash")


def schema_validator():
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema)


class E33ResearchEcologyDecompositionTests(unittest.TestCase):
    def setUp(self):
        self.contract = mod.load_json(CONTRACT_PATH)
        self.field = mod.load_accepted_opportunity_field(FIELD_PATH, self.contract)
        self.output = mod.build_decomposition(self.contract, self.field)

    def rejected(self, fn):
        with self.assertRaises(ValueError):
            fn()

    def test_01_contract_valid(self):
        mod.validate_contract(self.contract)

    def test_02_exact_accepted_e32_field_loads(self):
        self.assertEqual(
            self.field["opportunity_field_hash"],
            mod.EXPECTED_PARENT["e3_2_opportunity_field_hash"],
        )

    def test_03_exact_accepted_e32_artifact_sha(self):
        self.assertEqual(
            hashlib.sha256(FIELD_PATH.read_bytes()).hexdigest(),
            mod.EXPECTED_PARENT["e3_2_field_artifact_sha256"],
        )

    def test_04_output_valid(self):
        mod.validate_decomposition(self.output, self.contract, self.field)

    def test_05_deterministic_same_process(self):
        other = mod.build_decomposition(self.contract, self.field)
        self.assertEqual(mod.canonical_bytes(self.output), mod.canonical_bytes(other))

    def test_06_parent_e32_reviewed_head_lock(self):
        c = copy.deepcopy(self.contract)
        c["parent"]["e3_2_reviewed_head"] = "0" * 40
        rehash_contract(c)
        self.rejected(lambda: mod.validate_contract(c))

    def test_07_parent_e32_merge_commit_lock(self):
        c = copy.deepcopy(self.contract)
        c["parent"]["e3_2_merge_commit"] = "0" * 40
        rehash_contract(c)
        self.rejected(lambda: mod.validate_contract(c))

    def test_08_parent_e32_aggregate_lock(self):
        c = copy.deepcopy(self.contract)
        c["parent"]["e3_2_aggregate_hash"] = "0" * 64
        rehash_contract(c)
        self.rejected(lambda: mod.validate_contract(c))

    def test_09_parent_e32_field_hash_lock(self):
        c = copy.deepcopy(self.contract)
        c["parent"]["e3_2_opportunity_field_hash"] = "0" * 64
        rehash_contract(c)
        self.rejected(lambda: mod.validate_contract(c))

    def test_10_parent_e32_artifact_lock(self):
        c = copy.deepcopy(self.contract)
        c["parent"]["e3_2_field_artifact_sha256"] = "0" * 64
        rehash_contract(c)
        self.rejected(lambda: mod.validate_contract(c))

    def test_11_parent_architecture_lock(self):
        c = copy.deepcopy(self.contract)
        c["parent"]["e3_0_architecture_hash"] = "0" * 64
        rehash_contract(c)
        self.rejected(lambda: mod.validate_contract(c))

    def test_12_e31_direct_input_policy_cannot_flip(self):
        c = copy.deepcopy(self.contract)
        c["input_policy"]["e3_1_snapshot_direct_input_forbidden"] = False
        rehash_contract(c)
        self.rejected(lambda: mod.validate_contract(c))

    def test_13_raw_fixture_policy_cannot_flip(self):
        c = copy.deepcopy(self.contract)
        c["input_policy"]["raw_fixture_input_forbidden"] = False
        rehash_contract(c)
        self.rejected(lambda: mod.validate_contract(c))

    def test_14_candidate_alias_policy_cannot_flip(self):
        c = copy.deepcopy(self.contract)
        c["input_policy"]["candidate_alias_input_forbidden"] = False
        rehash_contract(c)
        self.rejected(lambda: mod.validate_contract(c))

    def test_15_neighbor_count_cannot_tune_after_rehash(self):
        c = copy.deepcopy(self.contract)
        c["decomposition_semantics"]["neighbor_count"] = 3
        rehash_contract(c)
        self.rejected(lambda: mod.validate_contract(c))

    def test_16_species_partition_policy_cannot_flip(self):
        c = copy.deepcopy(self.contract)
        c["decomposition_semantics"]["species_identity_partition_key_forbidden"] = False
        rehash_contract(c)
        self.rejected(lambda: mod.validate_contract(c))

    def test_17_patch_count_exact(self):
        self.assertEqual(len(self.output["patches"]), 12)
        self.assertEqual(self.output["summary"]["patch_count"], 12)

    def test_18_patch_order_exact(self):
        keys = [patch["stable_spatial_key"] for patch in self.output["patches"]]
        self.assertEqual(keys, sorted(keys))
        self.assertEqual(keys, [sample["stable_spatial_key"] for sample in self.field["samples"]])

    def test_19_patch_ids_namespaced_unique(self):
        ids = [patch["research_patch_id"] for patch in self.output["patches"]]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertTrue(all(value.startswith("eco-evo3/e3.3/patch/") for value in ids))

    def test_20_patch_source_provenance_retained(self):
        by_key = {sample["stable_spatial_key"]: sample for sample in self.field["samples"]}
        for patch in self.output["patches"]:
            source = by_key[patch["stable_spatial_key"]]
            self.assertEqual(patch["source_opportunity_id"], source["opportunity_id"])
            self.assertEqual(
                patch["source_opportunity_sample_hash"], source["opportunity_sample_hash"]
            )

    def test_21_patch_opportunity_vector_exact(self):
        by_key = {sample["stable_spatial_key"]: sample for sample in self.field["samples"]}
        for patch in self.output["patches"]:
            source = by_key[patch["stable_spatial_key"]]
            self.assertEqual(
                patch["opportunity_vector"],
                {key: source[key] for key in mod.CONTINUITY_KEYS},
            )

    def test_22_wrapped_longitude_metric(self):
        a = {"latitude_microdeg": 0, "longitude_microdeg": 179_000_000}
        b = {"latitude_microdeg": 0, "longitude_microdeg": -179_000_000}
        self.assertEqual(mod.spatial_distance_sq(a, b), 2_000_000 ** 2)

    def test_23_neighbor_map_exact_cell01(self):
        neighbors = mod._neighbor_map(self.field["samples"])
        key = "eco-evo3-fixture/planet-alpha/cell-01"
        self.assertEqual(
            neighbors[key],
            [
                "eco-evo3-fixture/planet-alpha/cell-02",
                "eco-evo3-fixture/planet-alpha/cell-03",
            ],
        )

    def test_24_neighbor_map_exact_cell12(self):
        neighbors = mod._neighbor_map(self.field["samples"])
        key = "eco-evo3-fixture/planet-alpha/cell-12"
        self.assertEqual(
            neighbors[key],
            [
                "eco-evo3-fixture/planet-alpha/cell-11",
                "eco-evo3-fixture/planet-alpha/cell-02",
            ],
        )

    def test_25_mutual_edge_count_exact(self):
        self.assertEqual(len(self.output["edges"]), 10)
        self.assertEqual(self.output["summary"]["edge_count"], 10)

    def test_26_mutual_edges_form_main_chain(self):
        pairs = [
            tuple(key.rsplit("/", 1)[-1] for key in edge["endpoint_spatial_keys"])
            for edge in self.output["edges"]
        ]
        self.assertEqual(
            pairs,
            [(f"cell-{i:02d}", f"cell-{i+1:02d}") for i in range(1, 11)],
        )

    def test_27_cell12_has_no_mutual_edge(self):
        text = mod.canonical_bytes(self.output["edges"]).decode("utf-8")
        self.assertNotIn("cell-12", text)

    def test_28_edge_distance_exact_for_chain(self):
        self.assertTrue(
            all(
                edge["spatial_distance_sq_microdeg2"] == 1_125_000_000_000_000
                for edge in self.output["edges"]
            )
        )

    def test_29_edge_continuity_formula(self):
        for edge in self.output["edges"]:
            self.assertEqual(
                edge["continuity_ppm"],
                1_000_000 - edge["opportunity_delta_mean_ppm"],
            )

    def test_30_first_edge_continuity_exact(self):
        edge = self.output["edges"][0]
        self.assertEqual(edge["opportunity_delta_mean_ppm"], 56333)
        self.assertEqual(edge["continuity_ppm"], 943667)

    def test_31_region_count_exact(self):
        self.assertEqual(len(self.output["regions"]), 2)
        self.assertEqual(self.output["summary"]["region_count"], 2)

    def test_32_region_partition_exact(self):
        sizes = [len(region["patch_ids"]) for region in self.output["regions"]]
        self.assertEqual(sizes, [11, 1])
        self.assertEqual(self.output["summary"]["singleton_region_count"], 1)
        self.assertEqual(self.output["summary"]["largest_region_patch_count"], 11)

    def test_33_singleton_region_is_cell12(self):
        singleton = [region for region in self.output["regions"] if len(region["patch_ids"]) == 1][0]
        self.assertEqual(
            singleton["stable_spatial_keys"],
            ["eco-evo3-fixture/planet-alpha/cell-12"],
        )
        self.assertIsNone(singleton["mean_internal_continuity_ppm"])

    def test_34_main_region_mean_continuity_exact(self):
        main_region = self.output["regions"][0]
        self.assertEqual(main_region["mean_internal_continuity_ppm"], 914200)

    def test_35_all_patch_ids_partition_once(self):
        patch_ids = [patch["research_patch_id"] for patch in self.output["patches"]]
        region_patch_ids = [
            patch_id
            for region in self.output["regions"]
            for patch_id in region["patch_ids"]
        ]
        self.assertEqual(sorted(patch_ids), sorted(region_patch_ids))
        self.assertEqual(len(region_patch_ids), len(set(region_patch_ids)))

    def test_36_source_authority_promotion_rejected(self):
        field = copy.deepcopy(self.field)
        field["authority"] = "CANONICAL_WORLD_STATE"
        rehash_source(field)
        self.rejected(lambda: mod.validate_source_field(field, self.contract))

    def test_37_source_canonical_binding_promotion_rejected(self):
        field = copy.deepcopy(self.field)
        field["canonical_binding_resolved"] = True
        rehash_source(field)
        self.rejected(lambda: mod.validate_source_field(field, self.contract))

    def test_38_source_semantic_mutation_rejected_even_if_rehashed(self):
        field = copy.deepcopy(self.field)
        field["samples"][0]["water_opportunity_ppm"] += 1
        rehash_source(field)
        self.rejected(lambda: mod.validate_source_field(field, self.contract))

    def test_39_candidate_alias_exact_bytes_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            path = pathlib.Path(td) / "e3_2_candidate_ecological_opportunity_field.v1.json"
            path.write_bytes(FIELD_PATH.read_bytes())
            self.rejected(lambda: mod.load_accepted_opportunity_field(path, self.contract))

    def test_40_raw_fixture_rejected_through_accepted_field_boundary(self):
        raw_fixture = {
            "schema": "distributed_world_simulator.ecology.evo3_planet_field_semantic_fixture.v1",
            "version": "1.0.0",
            "samples": [],
        }
        with tempfile.TemporaryDirectory() as td:
            path = (
                pathlib.Path(td)
                / "config/ecology/accepted_inputs/e3_2_accepted_ecological_opportunity_field.v1.json"
            )
            path.parent.mkdir(parents=True)
            path.write_bytes(mod.canonical_bytes(raw_fixture) + b"\n")
            self.rejected(lambda: mod.load_accepted_opportunity_field(path, self.contract))

    def test_41_noncanonical_accepted_field_bytes_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            path = (
                pathlib.Path(td)
                / "config/ecology/accepted_inputs/e3_2_accepted_ecological_opportunity_field.v1.json"
            )
            path.parent.mkdir(parents=True)
            path.write_text(json.dumps(self.field, indent=2), encoding="utf-8")
            self.rejected(lambda: mod.load_accepted_opportunity_field(path, self.contract))

    def test_42_output_authority_promotion_rejected(self):
        output = copy.deepcopy(self.output)
        output["authority"] = "CANONICAL_WORLD_STATE"
        rehash_output(output)
        self.rejected(lambda: mod.validate_decomposition(output, self.contract, self.field))

    def test_43_output_canonical_binding_promotion_rejected(self):
        output = copy.deepcopy(self.output)
        output["canonical_binding_resolved"] = True
        rehash_output(output)
        self.rejected(lambda: mod.validate_decomposition(output, self.contract, self.field))

    def test_44_species_partition_injection_rejected_after_rehash(self):
        output = copy.deepcopy(self.output)
        output["patches"][0]["species_partition_key"] = "species-x"
        rehash_output(output)
        self.rejected(lambda: mod.validate_decomposition(output, self.contract, self.field))

    def test_45_biome_injection_rejected_after_rehash(self):
        output = copy.deepcopy(self.output)
        output["regions"][0]["biome_label"] = "wet"
        rehash_output(output)
        self.rejected(lambda: mod.validate_decomposition(output, self.contract, self.field))

    def test_46_canonical_sd_injection_rejected_after_rehash(self):
        output = copy.deepcopy(self.output)
        output["regions"][0]["canonical_sd_domain"] = "sd/x"
        rehash_output(output)
        self.rejected(lambda: mod.validate_decomposition(output, self.contract, self.field))

    def test_47_duplicate_patch_rejected_after_full_rehash(self):
        output = copy.deepcopy(self.output)
        output["patches"][1] = copy.deepcopy(output["patches"][0])
        rehash_output(output)
        self.rejected(lambda: mod.validate_decomposition(output, self.contract, self.field))

    def test_48_edge_drop_rejected_after_full_rehash(self):
        output = copy.deepcopy(self.output)
        output["edges"].pop()
        output["summary"]["edge_count"] -= 1
        rehash_output(output)
        self.rejected(lambda: mod.validate_decomposition(output, self.contract, self.field))

    def test_49_edge_continuity_tamper_rejected_after_full_rehash(self):
        output = copy.deepcopy(self.output)
        output["edges"][0]["opportunity_delta_mean_ppm"] += 1
        output["edges"][0]["continuity_ppm"] -= 1
        rehash_output(output)
        self.rejected(lambda: mod.validate_decomposition(output, self.contract, self.field))

    def test_50_region_partition_tamper_rejected_after_full_rehash(self):
        output = copy.deepcopy(self.output)
        moved = output["regions"][0]["patch_ids"].pop()
        output["regions"][1]["patch_ids"].append(moved)
        rehash_output(output)
        self.rejected(lambda: mod.validate_decomposition(output, self.contract, self.field))

    def test_51_decomposition_hash_exact_recomputation(self):
        self.assertEqual(
            self.output["decomposition_hash"],
            mod.object_hash(self.output, "decomposition_hash"),
        )

    def test_52_schema_validates_generated_decomposition(self):
        schema_validator().validate(self.output)

    def test_53_schema_rejects_unexpected_patch_property(self):
        output = copy.deepcopy(self.output)
        output["patches"][0]["extra"] = 1
        with self.assertRaises(ValidationError):
            schema_validator().validate(output)

    def test_54_no_forbidden_semantics_in_output(self):
        text = mod.canonical_bytes(self.output).decode("utf-8").lower()
        for token in mod.FORBIDDEN_OUTPUT_TOKENS:
            self.assertNotIn(token, text)

    def test_55_no_global_rng_import(self):
        source = MODULE_PATH.read_text(encoding="utf-8")
        self.assertNotIn("import random", source)
        self.assertNotIn("from random", source)
        self.assertNotIn("import secrets", source)

    def test_56_no_e31_snapshot_or_fixture_cli_surface(self):
        source = MODULE_PATH.read_text(encoding="utf-8")
        self.assertNotIn('add_argument("--snapshot"', source)
        self.assertNotIn("add_argument('--snapshot'", source)
        self.assertNotIn('add_argument("--fixture"', source)
        self.assertNotIn("add_argument('--fixture'", source)

    def test_57_accepted_field_cli_surface_is_explicit(self):
        source = MODULE_PATH.read_text(encoding="utf-8")
        self.assertIn('add_argument("--accepted-field"', source)

    def test_58_region_ids_namespaced_unique(self):
        ids = [region["research_region_id"] for region in self.output["regions"]]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertTrue(all(value.startswith("eco-evo3/e3.3/region/") for value in ids))

    def test_59_edges_ids_namespaced_unique(self):
        ids = [edge["research_edge_id"] for edge in self.output["edges"]]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertTrue(all(value.startswith("eco-evo3/e3.3/edge/") for value in ids))

    def test_60_summary_exact(self):
        self.assertEqual(
            self.output["summary"],
            {
                "patch_count": 12,
                "edge_count": 10,
                "region_count": 2,
                "singleton_region_count": 1,
                "largest_region_patch_count": 11,
            },
        )


if __name__ == "__main__":
    unittest.main()
