from __future__ import annotations

import copy
import importlib.util
import json
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
IMPL_PATH = ROOT / "scripts/research/ecology/causal_colonization_program_compiler_v1.py"
CONTRACT_PATH = ROOT / "config/ecology/eco-evo3-e3-4-causal-colonization-contract.v1.json"
BINDING_PATH = ROOT / "config/ecology/accepted_inputs/e3_3_accepted_research_ecology_decomposition.binding.v1.json"
DECOMPOSITION_PATH = ROOT / "config/ecology/accepted_inputs/e3_3_candidate_research_ecology_decomposition.v1.json"
CATALOG_PATH = ROOT / "config/ecology/accepted_inputs/evo2_full_persisted_species_catalog.e3_4.v1.json"
EXPECTED_PROGRAM_HASH = "6f0b1cbe134f6b77825f66b356624975cc84e88f08c9aaba789f24c7d1cba4e6"

spec = importlib.util.spec_from_file_location("e34_repair_impl", IMPL_PATH)
impl = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(impl)


def load(path: pathlib.Path):
    return json.loads(path.read_text(encoding="utf-8"))


def verified_inputs():
    contract = impl.load_contract(CONTRACT_PATH)
    decomposition = impl.load_accepted_decomposition(DECOMPOSITION_PATH, BINDING_PATH, contract)
    catalog = impl.load_full_persisted_catalog(CATALOG_PATH, contract)
    return contract, decomposition, catalog


class E34RepairR1Tests(unittest.TestCase):
    def test_01_plain_parsed_inputs_cannot_attest_accepted_provenance(self):
        out = impl.build_colonization_program(load(CONTRACT_PATH), load(DECOMPOSITION_PATH), load(CATALOG_PATH))
        self.assertEqual(out["provenance"]["input_verification"], "UNVERIFIED_PARSED_INPUTS_NO_ACCEPTED_INPUT_ATTESTATION")
        self.assertNotIn("accepted_e3_3_decomposition_hash", out["provenance"])
        self.assertNotIn("persisted_evo2_catalog_hash", out["provenance"])

    def test_02_reviewer_decomposition_dict_bypass_cannot_false_attest(self):
        contract = load(CONTRACT_PATH)
        decomposition = load(DECOMPOSITION_PATH)
        catalog = load(CATALOG_PATH)
        decomposition["patches"][0]["opportunity_vector"]["water_opportunity_ppm"] = 1
        out = impl.build_colonization_program(contract, decomposition, catalog)
        self.assertEqual(out["provenance"]["input_verification"], "UNVERIFIED_PARSED_INPUTS_NO_ACCEPTED_INPUT_ATTESTATION")
        self.assertNotIn("accepted_e3_3_decomposition_hash", out["provenance"])

    def test_03_reviewer_catalog_dict_bypass_cannot_false_attest(self):
        contract = load(CONTRACT_PATH)
        decomposition = load(DECOMPOSITION_PATH)
        catalog = load(CATALOG_PATH)
        catalog["entries"][0]["genome"]["seed_count"] += 1
        catalog["entries"][0]["recruitment_traits"]["dormancy_fraction"] = 0.99
        out = impl.build_colonization_program(contract, decomposition, catalog)
        self.assertEqual(out["provenance"]["input_verification"], "UNVERIFIED_PARSED_INPUTS_NO_ACCEPTED_INPUT_ATTESTATION")
        self.assertNotIn("persisted_evo2_catalog_hash", out["provenance"])

    def test_04_verified_object_mutation_is_ignored_and_raw_is_reparsed(self):
        contract, decomposition, catalog = verified_inputs()
        decomposition["patches"][0]["opportunity_vector"]["water_opportunity_ppm"] = 1
        catalog["entries"][0]["genome"]["seed_count"] = 999999
        out = impl.build_colonization_program(contract, decomposition, catalog)
        self.assertEqual(out["colonization_program_hash"], EXPECTED_PROGRAM_HASH)

    def test_05_tampered_decomposition_bytes_rejected_before_parse(self):
        contract = impl.load_contract(CONTRACT_PATH)
        tampered = copy.deepcopy(load(DECOMPOSITION_PATH))
        tampered["patches"][0]["opportunity_vector"]["water_opportunity_ppm"] = 1
        with tempfile.TemporaryDirectory() as td:
            path = pathlib.Path(td) / "decomposition.json"
            path.write_text(json.dumps(tampered, indent=2) + "\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "E3_4_DECOMPOSITION_ARTIFACT_GIT_BLOB"):
                impl.load_accepted_decomposition(path, BINDING_PATH, contract)

    def test_06_tampered_catalog_bytes_rejected_before_parse(self):
        contract = impl.load_contract(CONTRACT_PATH)
        tampered = copy.deepcopy(load(CATALOG_PATH))
        tampered["entries"][0]["genome"]["seed_count"] += 1
        with tempfile.TemporaryDirectory() as td:
            path = pathlib.Path(td) / "catalog.json"
            path.write_text(json.dumps(tampered, indent=2) + "\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "E3_4_CATALOG_ARTIFACT_GIT_BLOB"):
                impl.load_full_persisted_catalog(path, contract)

    def test_07_genome_checksum_is_recomputed_from_actual_content(self):
        contract = load(CONTRACT_PATH)
        catalog = copy.deepcopy(load(CATALOG_PATH))
        catalog["entries"][0]["genome"]["seed_count"] += 1
        with self.assertRaisesRegex(ValueError, "E3_4_GENOME_CHECKSUM_CONTENT"):
            impl.validate_catalog(catalog, contract)

    def test_08_recruitment_checksum_is_recomputed_from_actual_content(self):
        contract = load(CONTRACT_PATH)
        catalog = copy.deepcopy(load(CATALOG_PATH))
        catalog["entries"][0]["recruitment_traits"]["dormancy_fraction"] = 0.99
        with self.assertRaisesRegex(ValueError, "E3_4_RECRUITMENT_CHECKSUM_CONTENT"):
            impl.validate_catalog(catalog, contract)

    def test_09_entry_hash_is_recomputed_from_actual_content(self):
        contract = load(CONTRACT_PATH)
        catalog = copy.deepcopy(load(CATALOG_PATH))
        catalog["entries"][0]["entry_hash"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "E3_4_CATALOG_ENTRY_HASH_CONTENT"):
            impl.validate_catalog(catalog, contract)

    def test_10_catalog_hash_and_authoritative_provenance_use_verified_identities(self):
        contract, decomposition, catalog = verified_inputs()
        out = impl.build_colonization_program(contract, decomposition, catalog)
        self.assertEqual(impl.validate_catalog(catalog, contract), catalog["catalog_hash"])
        self.assertEqual(out["provenance"]["accepted_e3_3_decomposition_hash"], load(DECOMPOSITION_PATH)["decomposition_hash"])
        self.assertEqual(out["provenance"]["persisted_evo2_catalog_hash"], impl._catalog_hash(load(CATALOG_PATH)))
        self.assertEqual(out["colonization_program_hash"], EXPECTED_PROGRAM_HASH)


if __name__ == "__main__":
    unittest.main()
