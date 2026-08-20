#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import json
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
IMPL = ROOT / "scripts/research/ecology/population_workset_compiler_v1.py"
CONTRACT = ROOT / "config/ecology/eco-evo3-e3-5-population-workset-contract.v1.json"
BINDING = ROOT / "config/ecology/accepted_inputs/e3_4_accepted_causal_colonization_program.binding.v1.json"
E34 = ROOT / "config/ecology/accepted_inputs/e3_4_candidate_causal_colonization_program.v1.json"
SCHEMA = ROOT / "config/ecology/eco-evo3-e3-5-population-workset.schema.v1.json"


def load_module():
    spec = importlib.util.spec_from_file_location("e35_population_workset_semantics", IMPL)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class E35PopulationWorksetSemanticsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mod = load_module()

    def authoritative(self):
        contract = self.mod.load_contract(CONTRACT)
        program = self.mod.load_accepted_e3_4(E34, BINDING, contract)
        output = self.mod.build_population_workset(contract, program)
        self.mod.validate_output_integrity(output)
        return contract, program, output

    def plain_inputs(self):
        return (
            json.loads(CONTRACT.read_text(encoding="utf-8")),
            json.loads(E34.read_text(encoding="utf-8")),
        )

    def test_01_authoritative_output_boundary(self):
        _, _, output = self.authoritative()
        self.assertEqual(output["authority"], "RESEARCH_DERIVED_NON_AUTHORITATIVE")
        self.assertFalse(output["canonical_binding_resolved"])
        self.assertFalse(output["production_binding_authorized"])
        self.assertEqual(output["workset_result"], "ACTIVE_WORKSETS")

    def test_02_exact_accepted_e34_source_identity(self):
        _, _, output = self.authoritative()
        source = output["source_colonization_program"]
        self.assertEqual(source["git_blob"], "db725ef37912547527dff5fffe39ca63e5f8c22e")
        self.assertEqual(source["artifact_sha256"], "fa6ece19e76784428fb0251a99d5b88bc1ed6183000e6c99755edbe2439c8463")
        self.assertEqual(source["colonization_program_hash"], "6f0b1cbe134f6b77825f66b356624975cc84e88f08c9aaba789f24c7d1cba4e6")
        self.assertEqual(source["provenance_hash"], "d79a41e95c7cfb39dec2f41b11d4066f1e57ab0260ed991c69077348ce6add9a")

    def test_03_expected_summary(self):
        _, _, output = self.authoritative()
        self.assertEqual(output["summary"], {
            "active_basis_count": 22,
            "active_species_count": 2,
            "active_patch_count": 11,
            "active_scheduling_region_count": 1,
            "planet_work_unit_count": 1,
            "region_work_unit_count": 1,
            "patch_work_unit_count": 11,
            "local_active_work_unit_count": 11,
            "total_work_unit_count": 24,
            "budget_hint_count": 24,
            "individual_entity_count": 0,
        })

    def test_04_basis_manifest_exact_and_unique(self):
        _, _, output = self.authoritative()
        basis = output["work_basis_manifest"]
        self.assertEqual(len(basis), 22)
        self.assertEqual(len({item["basis_key"] for item in basis}), 22)
        self.assertEqual(len({(item["research_species_id"], item["research_patch_id"]) for item in basis}), 22)

    def test_05_basis_only_from_established_decisions(self):
        _, _, output = self.authoritative()
        self.assertTrue(output["work_basis_manifest"])
        self.assertEqual({item["source_decision"] for item in output["work_basis_manifest"]}, {"ESTABLISHED"})

    def test_06_scale_unit_counts(self):
        _, _, output = self.authoritative()
        units = output["population_work_units"]
        counts = {scale: sum(1 for unit in units if unit["scale"] == scale) for scale in ("PLANET", "REGION", "PATCH", "LOCAL_ACTIVE")}
        self.assertEqual(counts, {"PLANET": 1, "REGION": 1, "PATCH": 11, "LOCAL_ACTIVE": 11})

    def test_07_every_scale_covers_same_basis_exactly_once(self):
        _, _, output = self.authoritative()
        expected = sorted(item["basis_key"] for item in output["work_basis_manifest"])
        for scale in ("PLANET", "REGION", "PATCH", "LOCAL_ACTIVE"):
            covered = sorted(key for unit in output["population_work_units"] if unit["scale"] == scale for key in unit["basis_keys"])
            self.assertEqual(covered, expected, scale)

    def test_08_planet_workset_is_aggregate(self):
        _, _, output = self.authoritative()
        unit = next(unit for unit in output["population_work_units"] if unit["scale"] == "PLANET")
        self.assertEqual(unit["representation"], "PLANET_AGGREGATE")
        self.assertEqual(unit["aggregate_member_count"], 22)
        self.assertNotIn("scheduling_region_id", unit)

    def test_09_region_workset_is_noncanonical_scheduling_identity(self):
        _, _, output = self.authoritative()
        unit = next(unit for unit in output["population_work_units"] if unit["scale"] == "REGION")
        self.assertEqual(unit["representation"], "REGION_AGGREGATE")
        self.assertEqual(unit["aggregate_member_count"], 22)
        self.assertTrue(unit["scheduling_region_id"].startswith("eco-evo3/e3.5/scheduling-region/"))
        self.assertNotIn("sd/", unit["scheduling_region_id"].lower())

    def test_10_patch_worksets_are_species_patch_aggregates(self):
        _, _, output = self.authoritative()
        units = [unit for unit in output["population_work_units"] if unit["scale"] == "PATCH"]
        self.assertEqual(len(units), 11)
        self.assertEqual({unit["aggregate_member_count"] for unit in units}, {2})
        self.assertEqual({unit["representation"] for unit in units}, {"PATCH_AGGREGATE"})

    def test_11_local_active_is_aggregate_projection_not_individuals(self):
        _, _, output = self.authoritative()
        units = [unit for unit in output["population_work_units"] if unit["scale"] == "LOCAL_ACTIVE"]
        self.assertEqual(len(units), 11)
        self.assertEqual({unit["aggregate_member_count"] for unit in units}, {2})
        self.assertEqual({unit["representation"] for unit in units}, {"LOCAL_ACTIVE_AGGREGATE_COHORT_PROJECTION"})

    def test_12_budget_formula_is_integer_and_exact(self):
        contract, _, output = self.authoritative()
        by_id = {unit["work_unit_id"]: unit for unit in output["population_work_units"]}
        overhead = contract["budget_policy"]["overhead_units"]
        per_member = contract["budget_policy"]["per_basis_member_units"]
        for hint in output["execution_budget_hints"]:
            unit = by_id[hint["work_unit_id"]]
            expected = int(overhead[unit["scale"]]) + unit["aggregate_member_count"] * int(per_member[unit["scale"]])
            self.assertEqual(hint["budget_units"], expected)
            self.assertIsInstance(hint["budget_units"], int)

    def test_13_budget_known_values(self):
        _, _, output = self.authoritative()
        values = {}
        for hint in output["execution_budget_hints"]:
            values.setdefault(hint["scale"], set()).add(hint["budget_units"])
        self.assertEqual(values["PLANET"], {144})
        self.assertEqual(values["REGION"], {168})
        self.assertEqual(values["PATCH"], {56})
        self.assertEqual(values["LOCAL_ACTIVE"], {132})

    def test_14_all_work_unit_authority_is_scheduling_only(self):
        _, _, output = self.authoritative()
        self.assertEqual({unit["authority"] for unit in output["population_work_units"]}, {"RESEARCH_SCHEDULING_IDENTITY_NON_CANONICAL"})
        self.assertEqual({hint["meaning"] for hint in output["execution_budget_hints"]}, {"NON_AUTHORITATIVE_EXECUTION_BUDGET_HINT_ONLY"})

    def test_15_no_planet_wide_individual_truth_surface(self):
        _, _, output = self.authoritative()
        text = json.dumps(output, sort_keys=True).lower()
        for forbidden in ("individual_entity_id", "individual_entities", "entity_registry", "population_registry"):
            self.assertNotIn(forbidden, text)
        self.assertEqual(output["summary"]["individual_entity_count"], 0)

    def test_16_no_network_persistence_transaction_authority_surface(self):
        _, _, output = self.authoritative()
        key_names: set[str] = set()
        def walk(value):
            if isinstance(value, dict):
                key_names.update(str(key).lower() for key in value)
                for child in value.values():
                    walk(child)
            elif isinstance(value, list):
                for child in value:
                    walk(child)
        walk(output)
        for forbidden in ("network_authority", "persistence_authority", "transaction_authority", "canonical_sd_domain", "canonical_population_registry"):
            self.assertNotIn(forbidden, key_names)

    def test_17_repeated_authoritative_builds_are_byte_identical(self):
        _, _, a = self.authoritative()
        _, _, b = self.authoritative()
        self.assertEqual(self.mod.serialize_workset(a), self.mod.serialize_workset(b))
        self.assertEqual(a["population_workset_hash"], b["population_workset_hash"])

    def test_18_draft_2020_12_schema_accepts_output(self):
        from jsonschema import Draft202012Validator
        _, _, output = self.authoritative()
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        Draft202012Validator.check_schema(schema)
        errors = sorted(Draft202012Validator(schema).iter_errors(output), key=lambda error: list(error.path))
        self.assertEqual(errors, [])

    def test_19_output_hash_integrity_rejects_mutation(self):
        _, _, output = self.authoritative()
        mutated = copy.deepcopy(output)
        mutated["summary"]["active_basis_count"] += 1
        with self.assertRaises(self.mod.E35Error):
            self.mod.validate_output_integrity(mutated)

    def test_20_source_planet_and_time_are_preserved(self):
        _, program, output = self.authoritative()
        self.assertEqual(output["source_colonization_program"]["stable_planet_identity"], program["source_decomposition"]["stable_planet_identity"])
        self.assertEqual(output["source_colonization_program"]["stable_time_key"], program["source_decomposition"]["stable_time_key"])

    def test_21_order_permutation_does_not_change_derived_core(self):
        contract, program = self.plain_inputs()
        baseline = self.mod._derive_core(copy.deepcopy(program), copy.deepcopy(contract))
        permuted = copy.deepcopy(program)
        permuted["species_programs"].reverse()
        for species in permuted["species_programs"]:
            species["patch_evaluations"].reverse()
            species["established_patch_ids"].reverse()
        candidate = self.mod._derive_core(permuted, copy.deepcopy(contract))
        self.assertEqual(candidate, baseline)

    def test_22_no_colonization_maps_to_empty_valid_workset_core(self):
        contract, program = self.plain_inputs()
        empty = copy.deepcopy(program)
        empty["colonization_result"] = "NO_COLONIZATION"
        for species in empty["species_programs"]:
            species["established_patch_ids"] = []
            for evaluation in species["patch_evaluations"]:
                if evaluation["decision"] == "ESTABLISHED":
                    evaluation["decision"] = "NOT_ESTABLISHED"
        derived = self.mod._derive_core(empty, contract)
        self.assertEqual(derived["workset_result"], "NO_ACTIVE_POPULATION_WORK")
        self.assertEqual(derived["work_basis_manifest"], [])
        self.assertEqual(derived["population_work_units"], [])
        self.assertEqual(derived["execution_budget_hints"], [])
        self.assertEqual(derived["summary"]["individual_entity_count"], 0)

    def test_23_declared_established_patch_mismatch_rejected(self):
        contract, program = self.plain_inputs()
        bad = copy.deepcopy(program)
        bad["species_programs"][0]["established_patch_ids"] = bad["species_programs"][0]["established_patch_ids"][1:]
        with self.assertRaises(self.mod.E35Error):
            self.mod._derive_core(bad, contract)

    def test_24_duplicate_species_patch_basis_rejected(self):
        contract, program = self.plain_inputs()
        bad = copy.deepcopy(program)
        bad["species_programs"][0]["patch_evaluations"].append(copy.deepcopy(bad["species_programs"][0]["patch_evaluations"][0]))
        with self.assertRaises(self.mod.E35Error):
            self.mod._derive_core(bad, contract)

    def test_25_patch_spatial_identity_conflict_rejected(self):
        contract, program = self.plain_inputs()
        bad = copy.deepcopy(program)
        bad["species_programs"][1]["patch_evaluations"][0]["stable_spatial_key"] += "/conflict"
        with self.assertRaises(self.mod.E35Error):
            self.mod._derive_core(bad, contract)

    def test_26_invalid_species_identity_rejected(self):
        contract, program = self.plain_inputs()
        bad = copy.deepcopy(program)
        bad["species_programs"][0]["research_species_id"] = "canonical-species/not-allowed"
        with self.assertRaises(self.mod.E35Error):
            self.mod._derive_core(bad, contract)

    def test_27_missing_planet_source_identity_rejected(self):
        contract, program = self.plain_inputs()
        bad = copy.deepcopy(program)
        bad["source_decomposition"]["stable_planet_identity"] = ""
        with self.assertRaises(self.mod.E35Error):
            self.mod._derive_core(bad, contract)


if __name__ == "__main__":
    unittest.main()
