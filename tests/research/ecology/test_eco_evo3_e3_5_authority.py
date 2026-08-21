#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import inspect
import json
import pathlib
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
IMPL = ROOT / "scripts/research/ecology/population_workset_compiler_v1.py"
CONTRACT = ROOT / "config/ecology/eco-evo3-e3-5-population-workset-contract.v1.json"
BINDING = ROOT / "config/ecology/accepted_inputs/e3_4_accepted_causal_colonization_program.binding.v1.json"
E34 = ROOT / "config/ecology/accepted_inputs/e3_4_candidate_causal_colonization_program.v1.json"
COMMITTED = ROOT / "validation/ecology/eco-evo3-e3-5-population-workset.generated.json"


def load_module():
    spec = importlib.util.spec_from_file_location("e35_population_workset_authority", IMPL)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class E35PopulationWorksetAuthorityTests(unittest.TestCase):
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

    def rehash_output(self, output):
        output = copy.deepcopy(output)
        output["provenance_hash"] = self.mod.sha256_canonical(output["provenance"])
        body = copy.deepcopy(dict(output))
        body.pop("population_workset_hash", None)
        output["population_workset_hash"] = self.mod.sha256_canonical(body)
        return output

    def test_01_loaders_produce_verified_inputs(self):
        contract = self.mod.load_contract(CONTRACT)
        program = self.mod.load_accepted_e3_4(E34, BINDING, contract)
        self.assertIsInstance(contract, self.mod._VerifiedInput)
        self.assertIsInstance(program, self.mod._VerifiedInput)
        self.assertEqual(contract.kind, "contract")
        self.assertEqual(program.kind, "accepted_e3_4")
        self.assertIsNotNone(program.binding_raw)

    def test_02_authoritative_provenance_requires_exact_raw_traversal(self):
        _, _, output = self.authoritative()
        self.assertIsInstance(output, self.mod._VerifiedWorkset)
        self.assertEqual(output["provenance"]["input_verification"], "EXACT_ACCEPTED_E3_4_RAW_BYTES_VERIFIED")
        self.assertEqual(output["provenance"]["accepted_e3_4_git_blob"], "db725ef37912547527dff5fffe39ca63e5f8c22e")

    def test_03_plain_parsed_inputs_are_non_authoritative(self):
        contract, program = self.plain_inputs()
        output = self.mod.build_population_workset(contract, program)
        self.assertEqual(output["authority"], "UNVERIFIED_PARSED_INPUTS_NO_ACCEPTED_INPUT_ATTESTATION")
        self.assertEqual(output["provenance"], {"input_verification": "UNVERIFIED_PARSED_INPUTS_NO_ACCEPTED_INPUT_ATTESTATION"})
        self.assertNotIn("source_colonization_program", output)
        self.assertNotIn("population_workset_hash", output)

    def test_04_copied_accepted_provenance_cannot_promote_plain_input(self):
        contract, program = self.plain_inputs()
        unverified = self.mod.build_population_workset(contract, program)
        _, _, authoritative = self.authoritative()
        unverified["provenance"] = copy.deepcopy(authoritative["provenance"])
        unverified["provenance_hash"] = self.mod.sha256_canonical(unverified["provenance"])
        body = copy.deepcopy(unverified)
        body.pop("population_workset_hash", None)
        unverified["population_workset_hash"] = self.mod.sha256_canonical(body)
        with self.assertRaises(self.mod.E35Error):
            self.mod.serialize_workset(unverified)

    def test_05_tampered_contract_raw_bytes_rejected_before_parse_authority(self):
        raw = CONTRACT.read_bytes().replace(b'"version": "1.0.0"', b'"version": "1.0.1"', 1)
        with tempfile.TemporaryDirectory() as td:
            path = pathlib.Path(td) / "contract.json"
            path.write_bytes(raw)
            with self.assertRaises(self.mod.E35Error):
                self.mod.load_contract(path)

    def test_06_tampered_binding_raw_bytes_rejected(self):
        contract = self.mod.load_contract(CONTRACT)
        raw = BINDING.read_bytes().replace(b'"binding_state": "ACCEPTED_E3_4_EXACT_INPUT"', b'"binding_state": "CANDIDATE_ALIAS"', 1)
        with tempfile.TemporaryDirectory() as td:
            path = pathlib.Path(td) / "binding.json"
            path.write_bytes(raw)
            with self.assertRaises(self.mod.E35Error):
                self.mod.load_accepted_e3_4(E34, path, contract)

    def test_07_rehashed_candidate_alias_rejected_by_exact_git_blob(self):
        contract = self.mod.load_contract(CONTRACT)
        candidate = json.loads(E34.read_text(encoding="utf-8"))
        candidate["source_decomposition"]["stable_time_key"] += "/candidate-alias"
        body = copy.deepcopy(candidate)
        body.pop("colonization_program_hash", None)
        candidate["colonization_program_hash"] = self.mod.sha256_canonical(body)
        raw = self.mod._canonical_bytes(candidate) + b"\n"
        with tempfile.TemporaryDirectory() as td:
            path = pathlib.Path(td) / "candidate.json"
            path.write_bytes(raw)
            with self.assertRaises(self.mod.E35Error):
                self.mod.load_accepted_e3_4(path, BINDING, contract)

    def test_08_mutating_verified_contract_dict_does_not_change_authoritative_build(self):
        contract = self.mod.load_contract(CONTRACT)
        program = self.mod.load_accepted_e3_4(E34, BINDING, contract)
        contract["budget_policy"]["overhead_units"]["PLANET"] = 999999
        output = self.mod.build_population_workset(contract, program)
        planet_hint = next(hint for hint in output["execution_budget_hints"] if hint["scale"] == "PLANET")
        self.assertEqual(planet_hint["budget_units"], 144)

    def test_09_mutating_verified_program_dict_does_not_change_authoritative_build(self):
        contract = self.mod.load_contract(CONTRACT)
        program = self.mod.load_accepted_e3_4(E34, BINDING, contract)
        program["colonization_result"] = "NO_COLONIZATION"
        program["species_programs"] = []
        output = self.mod.build_population_workset(contract, program)
        self.assertEqual(output["workset_result"], "ACTIVE_WORKSETS")
        self.assertEqual(output["summary"]["active_basis_count"], 22)

    def test_10_mutating_verified_program_raw_bytes_is_rejected_on_build(self):
        contract = self.mod.load_contract(CONTRACT)
        program = self.mod.load_accepted_e3_4(E34, BINDING, contract)
        program.raw += b" "
        with self.assertRaises(self.mod.E35Error):
            self.mod.build_population_workset(contract, program)

    def test_11_mutating_verified_binding_raw_bytes_is_rejected_on_build(self):
        contract = self.mod.load_contract(CONTRACT)
        program = self.mod.load_accepted_e3_4(E34, BINDING, contract)
        assert program.binding_raw is not None
        program.binding_raw += b" "
        with self.assertRaises(self.mod.E35Error):
            self.mod.build_population_workset(contract, program)

    def test_12_unverified_output_cannot_be_serialized_as_authoritative_artifact(self):
        contract, program = self.plain_inputs()
        output = self.mod.build_population_workset(contract, program)
        with self.assertRaises(self.mod.E35Error):
            self.mod.serialize_workset(output)

    def test_13_rehashed_canonical_binding_promotion_rejected(self):
        _, _, output = self.authoritative()
        mutated = copy.deepcopy(output)
        mutated["canonical_binding_resolved"] = True
        mutated = self.rehash_output(mutated)
        with self.assertRaises(self.mod.E35Error):
            self.mod.validate_output_integrity(mutated)

    def test_14_rehashed_production_binding_promotion_rejected(self):
        _, _, output = self.authoritative()
        mutated = copy.deepcopy(output)
        mutated["production_binding_authorized"] = True
        mutated = self.rehash_output(mutated)
        with self.assertRaises(self.mod.E35Error):
            self.mod.validate_output_integrity(mutated)

    def test_15_rehashed_individual_truth_injection_rejected(self):
        _, _, output = self.authoritative()
        mutated = copy.deepcopy(output)
        mutated["summary"]["individual_entity_count"] = 1
        mutated = self.rehash_output(mutated)
        with self.assertRaises(self.mod.E35Error):
            self.mod.validate_output_integrity(mutated)

    def test_16_rehashed_work_unit_authority_promotion_rejected(self):
        _, _, output = self.authoritative()
        mutated = copy.deepcopy(output)
        mutated["population_work_units"][0]["authority"] = "CANONICAL_POPULATION_AUTHORITY"
        mutated = self.rehash_output(mutated)
        with self.assertRaises(self.mod.E35Error):
            self.mod.validate_output_integrity(mutated)

    def test_17_rehashed_budget_semantics_mutation_rejected(self):
        _, _, output = self.authoritative()
        mutated = copy.deepcopy(output)
        mutated["execution_budget_hints"][0]["budget_units"] += 1
        mutated = self.rehash_output(mutated)
        with self.assertRaises(self.mod.E35Error):
            self.mod.validate_output_integrity(mutated)

    def test_18_rehashed_extra_top_level_authority_surface_rejected(self):
        _, _, output = self.authoritative()
        mutated = copy.deepcopy(output)
        mutated["network_authority"] = "server-1"
        mutated = self.rehash_output(mutated)
        with self.assertRaises(self.mod.E35Error):
            self.mod.validate_output_integrity(mutated)

    def test_19_source_has_no_rng_or_rehash_authority_helper(self):
        source = IMPL.read_text(encoding="utf-8")
        for forbidden in ("import random", "from random", "import secrets", "import uuid", "random.", "_rehash"):
            self.assertNotIn(forbidden, source)

    def test_20_authority_entrypoint_accepts_no_caller_provenance_or_transport(self):
        parameters = list(inspect.signature(self.mod.build_population_workset).parameters)
        self.assertEqual(parameters, ["contract", "program"])

    def test_21_fully_shaped_parsed_artifact_cannot_serialize(self):
        _, _, output = self.authoritative()
        parsed = json.loads(self.mod.serialize_workset(output).decode("utf-8"))
        self.mod.validate_output_structure(parsed)
        with self.assertRaisesRegex(self.mod.E35Error, "E3_5_VERIFIED_WORKSET_REQUIRED"):
            self.mod.serialize_workset(parsed)

    def test_22_reviewer_provenance_replacement_reproducer_fails_closed(self):
        _, _, output = self.authoritative()
        forged = json.loads(self.mod.serialize_workset(output).decode("utf-8"))
        source = forged["source_colonization_program"]
        provenance = forged["provenance"]
        source["colonization_program_hash"] = "0" * 64
        source["provenance_hash"] = "1" * 64
        source["artifact_sha256"] = "2" * 64
        source["accepted_control_head"] = "3" * 40
        source["canonical_merge_commit"] = "4" * 40
        provenance["accepted_e3_4_program_hash"] = source["colonization_program_hash"]
        provenance["accepted_e3_4_provenance_hash"] = source["provenance_hash"]
        provenance["accepted_e3_4_artifact_sha256"] = source["artifact_sha256"]
        provenance["accepted_e3_4_control_head"] = source["accepted_control_head"]
        provenance["accepted_e3_4_merge_commit"] = source["canonical_merge_commit"]
        provenance["contract_hash"] = "5" * 64
        provenance["full_persisted_evo2_catalog_hash"] = "6" * 64
        forged["provenance_hash"] = self.mod.sha256_canonical(provenance)
        body = copy.deepcopy(forged)
        body.pop("population_workset_hash", None)
        forged["population_workset_hash"] = self.mod.sha256_canonical(body)
        with self.assertRaises(self.mod.E35Error):
            self.mod.validate_output_structure(forged)
        with self.assertRaises(self.mod.E35Error):
            self.mod.serialize_workset(forged)

    def test_23_verified_workset_rebuild_detects_rehashed_source_mutation(self):
        _, _, output = self.authoritative()
        mutated = copy.deepcopy(output)
        mutated["source_colonization_program"]["stable_time_key"] += "/forged"
        mutated = self.rehash_output(mutated)
        with self.assertRaises(self.mod.E35Error):
            self.mod.serialize_workset(mutated)

    def test_24_committed_generated_artifact_is_plain_evidence_not_serialization_capability(self):
        parsed = json.loads(COMMITTED.read_text(encoding="utf-8"))
        self.mod.validate_output_structure(parsed)
        self.assertEqual(parsed["population_workset_hash"], self.mod.EXPECTED_E3_5_WORKSET_HASH)
        with self.assertRaisesRegex(self.mod.E35Error, "E3_5_VERIFIED_WORKSET_REQUIRED"):
            self.mod.serialize_workset(parsed)


if __name__ == "__main__":
    unittest.main()
