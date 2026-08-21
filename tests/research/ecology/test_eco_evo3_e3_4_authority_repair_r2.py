from __future__ import annotations

import copy
import importlib.util
import json
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
IMPL_PATH = ROOT / "scripts/research/ecology/causal_colonization_program_compiler_v1.py"
CORE_PATH = ROOT / "scripts/research/ecology/causal_colonization_program_compiler_v1_core.py"
CONTRACT_PATH = ROOT / "config/ecology/eco-evo3-e3-4-causal-colonization-contract.v1.json"
BINDING_PATH = ROOT / "config/ecology/accepted_inputs/e3_3_accepted_research_ecology_decomposition.binding.v1.json"
DECOMPOSITION_PATH = ROOT / "config/ecology/accepted_inputs/e3_3_candidate_research_ecology_decomposition.v1.json"
CATALOG_PATH = ROOT / "config/ecology/accepted_inputs/evo2_full_persisted_species_catalog.e3_4.v1.json"
E2_8_PATH = ROOT / "validation/ecology/eco-evo2-e2-8-catalog-persistence-validation.json"
EXPECTED_PROGRAM_HASH = "6f0b1cbe134f6b77825f66b356624975cc84e88f08c9aaba789f24c7d1cba4e6"

impl_spec = importlib.util.spec_from_file_location("e34_repair_r2_impl", IMPL_PATH)
impl = importlib.util.module_from_spec(impl_spec)
assert impl_spec.loader is not None
impl_spec.loader.exec_module(impl)

core_spec = importlib.util.spec_from_file_location("e34_repair_r2_core", CORE_PATH)
core = importlib.util.module_from_spec(core_spec)
assert core_spec.loader is not None
core_spec.loader.exec_module(core)


def load(path: pathlib.Path):
    return json.loads(path.read_text(encoding="utf-8"))


def verified_inputs():
    contract = impl.load_contract(CONTRACT_PATH)
    decomposition = impl.load_accepted_decomposition(DECOMPOSITION_PATH, BINDING_PATH, contract)
    catalog = impl.load_full_persisted_catalog(CATALOG_PATH, contract)
    return contract, decomposition, catalog


class E34RepairR2Tests(unittest.TestCase):
    forbidden_attestation_keys = (
        "accepted_e3_3_merge_commit",
        "accepted_e3_3_decomposition_hash",
        "accepted_e3_3_decomposition_provenance_hash",
        "persisted_evo2_catalog_hash",
        "persisted_evo2_catalog_semantic_artifact_sha256",
        "persisted_evo2_transport_sha256",
        "e2_final_aggregate_hash",
        "historical_eco_anchor",
    )

    def assert_non_authoritative(self, out):
        self.assertEqual(out["provenance"], {"input_verification": core.UNVERIFIED_INPUT_MARKER})
        for key in self.forbidden_attestation_keys:
            self.assertNotIn(key, out["provenance"])
        self.assertNotIn("transport_sha256", out["source_catalog"])
        self.assertNotIn("transport_bytes", out["source_catalog"])

    def test_01_direct_core_exact_parsed_inputs_never_attest_accepted_identity(self):
        out = core.build_colonization_program(load(CONTRACT_PATH), load(DECOMPOSITION_PATH), load(CATALOG_PATH))
        self.assert_non_authoritative(out)

    def test_02_direct_core_reviewer_decomposition_bypass_is_non_authoritative(self):
        contract = load(CONTRACT_PATH)
        decomposition = load(DECOMPOSITION_PATH)
        catalog = load(CATALOG_PATH)
        decomposition["patches"][0]["opportunity_vector"]["water_opportunity_ppm"] = 1
        out = core.build_colonization_program(contract, decomposition, catalog)
        self.assert_non_authoritative(out)

    def test_03_direct_core_reviewer_catalog_bypass_is_non_authoritative(self):
        contract = load(CONTRACT_PATH)
        decomposition = load(DECOMPOSITION_PATH)
        catalog = load(CATALOG_PATH)
        catalog["entries"][0]["genome"]["seed_count"] += 1
        catalog["entries"][0]["recruitment_traits"]["dormancy_fraction"] = 0.99
        out = core.build_colonization_program(contract, decomposition, catalog)
        self.assert_non_authoritative(out)

    def test_04_wrapper_core_handle_cannot_emit_accepted_attestation(self):
        contract = load(CONTRACT_PATH)
        decomposition = load(DECOMPOSITION_PATH)
        catalog = load(CATALOG_PATH)
        decomposition["patches"][0]["opportunity_vector"]["water_opportunity_ppm"] = 1
        out = impl._core.build_colonization_program(contract, decomposition, catalog)
        self.assertEqual(out["provenance"], {"input_verification": impl.UNVERIFIED_INPUT_MARKER})
        for key in self.forbidden_attestation_keys:
            self.assertNotIn(key, out["provenance"])

    def test_05_core_source_contains_no_accepted_or_historical_provenance_keys(self):
        text = CORE_PATH.read_text(encoding="utf-8")
        for key in self.forbidden_attestation_keys:
            self.assertNotIn(f'"{key}"', text)

    def test_06_plain_wrapper_path_does_not_historically_attest_contract_constants(self):
        out = impl.build_colonization_program(load(CONTRACT_PATH), load(DECOMPOSITION_PATH), load(CATALOG_PATH))
        self.assertEqual(out["provenance"], {"input_verification": impl.UNVERIFIED_INPUT_MARKER})
        for key in self.forbidden_attestation_keys:
            self.assertNotIn(key, out["provenance"])

    def test_07_verified_wrapper_is_only_path_that_emits_authoritative_provenance(self):
        contract, decomposition, catalog = verified_inputs()
        out = impl.build_colonization_program(contract, decomposition, catalog)
        self.assertEqual(out["colonization_program_hash"], EXPECTED_PROGRAM_HASH)
        self.assertEqual(out["provenance"]["accepted_e3_3_decomposition_hash"], load(DECOMPOSITION_PATH)["decomposition_hash"])
        self.assertEqual(out["provenance"]["persisted_evo2_catalog_hash"], impl._catalog_hash(load(CATALOG_PATH)))
        self.assertEqual(out["source_catalog"]["transport_sha256"], out["provenance"]["persisted_evo2_transport_sha256"])

    def test_08_historical_lineage_comes_from_preexisting_accepted_evidence(self):
        contract = load(CONTRACT_PATH)
        catalog = load(CATALOG_PATH)
        lineage = impl._verify_historical_lineage(contract, catalog["catalog_hash"])
        self.assertEqual(lineage["e2_8_validation_git_blob"], "47d55332591ef59fcf324701fece19df10781d44")
        self.assertEqual(lineage["e2_final_validation_git_blob"], "bd7999a7bbaba4048844333f509994b2668ed227")
        self.assertEqual(lineage["persisted_evo2_transport_sha256"], "b31c863f8e1943e5778d56631f8c8ad75b95f3b9d3930a699f80fd07595d45d1")
        self.assertEqual(lineage["e2_final_aggregate_hash"], "6daab256af3d1e7693c66a8afaad4d04fd1564c4376b9f3cd747a268a10c2250")

    def test_09_tampered_historical_e2_8_evidence_rejected_before_parse_authority(self):
        tampered = copy.deepcopy(load(E2_8_PATH))
        tampered["acceptance"]["catalog_hash"] = "0" * 64
        with tempfile.TemporaryDirectory() as td:
            path = pathlib.Path(td) / "e2_8.json"
            path.write_text(json.dumps(tampered, indent=2) + "\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "E3_4_E2_8_EVIDENCE_GIT_BLOB"):
                impl._verify_historical_lineage(load(CONTRACT_PATH), load(CATALOG_PATH)["catalog_hash"], e2_8_path=path)

    def test_10_historical_anchor_substitution_fails_git_lineage_check(self):
        contract = load(CONTRACT_PATH)
        contract["persisted_evo2_catalog"]["historical_eco_anchor"] = "0" * 40
        with self.assertRaisesRegex(ValueError, "E3_4_HISTORICAL_ECO_ANCHOR_E2_8_LINEAGE"):
            impl._verify_historical_lineage(contract, load(CATALOG_PATH)["catalog_hash"])


if __name__ == "__main__":
    unittest.main()
