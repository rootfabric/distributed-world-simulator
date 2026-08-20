from __future__ import annotations

import ast
import copy
import hashlib
import importlib.util
import inspect
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
IMPL_PATH = ROOT / "scripts/research/ecology/causal_colonization_program_compiler_v1.py"
CONTRACT_PATH = ROOT / "config/ecology/eco-evo3-e3-4-causal-colonization-contract.v1.json"
BINDING_PATH = ROOT / "config/ecology/accepted_inputs/e3_3_accepted_research_ecology_decomposition.binding.v1.json"
DECOMPOSITION_PATH = ROOT / "config/ecology/accepted_inputs/e3_3_candidate_research_ecology_decomposition.v1.json"
CATALOG_PATH = ROOT / "config/ecology/accepted_inputs/evo2_full_persisted_species_catalog.e3_4.v1.json"

EXPECTED_PROGRAM_HASH = "6f0b1cbe134f6b77825f66b356624975cc84e88f08c9aaba789f24c7d1cba4e6"
EXPECTED_PROVENANCE_HASH = "d79a41e95c7cfb39dec2f41b11d4066f1e57ab0260ed991c69077348ce6add9a"
EXPECTED_ARTIFACT_SHA256 = "fa6ece19e76784428fb0251a99d5b88bc1ed6183000e6c99755edbe2439c8463"

impl_spec = importlib.util.spec_from_file_location("e34_repair_r3_impl", IMPL_PATH)
impl = importlib.util.module_from_spec(impl_spec)
assert impl_spec.loader is not None
impl_spec.loader.exec_module(impl)


def load(path: pathlib.Path):
    return json.loads(path.read_text(encoding="utf-8"))


def verified_inputs():
    contract = impl.load_contract(CONTRACT_PATH)
    decomposition = impl.load_accepted_decomposition(DECOMPOSITION_PATH, BINDING_PATH, contract)
    catalog = impl.load_full_persisted_catalog(CATALOG_PATH, contract)
    return contract, decomposition, catalog


class E34RepairR3Tests(unittest.TestCase):
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
    injection_parameter_names = {
        "provenance",
        "transport_sha256",
        "transport_bytes",
        "decomposition_hash",
        "decomposition_provenance_hash",
        "catalog_hash",
        "e2_final_aggregate",
        "e2_final_aggregate_hash",
        "historical_anchor",
        "historical_eco_anchor",
        "hashes",
    }

    def assert_non_authoritative(self, out):
        self.assertEqual(out["provenance"], {"input_verification": impl.UNVERIFIED_INPUT_MARKER})
        for key in self.forbidden_attestation_keys:
            self.assertNotIn(key, out["provenance"])
        self.assertNotIn("transport_sha256", out["source_catalog"])
        self.assertNotIn("transport_bytes", out["source_catalog"])

    def wrapper_program_injection_helpers(self):
        offenders = []
        for name, fn in inspect.getmembers(impl, inspect.isfunction):
            if fn.__module__ != impl.__name__:
                continue
            params = set(inspect.signature(fn).parameters)
            if "program" in params and params.intersection(self.injection_parameter_names):
                offenders.append((name, tuple(sorted(params))))
        return offenders

    def accepted_provenance(self):
        out = impl.build_colonization_program(*verified_inputs())
        return copy.deepcopy(out["provenance"])

    def test_01_reviewer_reproducer_rehash_program_surface_removed(self):
        self.assertFalse(hasattr(impl, "_rehash_program"))
        self.assertEqual(self.wrapper_program_injection_helpers(), [])

    def test_02_mutated_core_output_plus_copied_accepted_provenance_cannot_be_completed(self):
        contract = load(CONTRACT_PATH)
        decomposition = load(DECOMPOSITION_PATH)
        catalog = load(CATALOG_PATH)
        decomposition["patches"][0]["opportunity_vector"]["water_opportunity_ppm"] = 1
        out = impl._core.build_colonization_program(contract, decomposition, catalog)
        copied = self.accepted_provenance()
        self.assertTrue(copied["accepted_e3_3_decomposition_hash"])
        self.assert_non_authoritative(out)
        self.assertEqual(self.wrapper_program_injection_helpers(), [])
        self.assertFalse(hasattr(impl, "_rehash_program"))

    def test_03_exact_core_output_plus_copied_accepted_provenance_cannot_be_completed(self):
        out = impl._core.build_colonization_program(load(CONTRACT_PATH), load(DECOMPOSITION_PATH), load(CATALOG_PATH))
        copied = self.accepted_provenance()
        self.assertEqual(copied["e2_final_aggregate_hash"], "6daab256af3d1e7693c66a8afaad4d04fd1564c4376b9f3cd747a268a10c2250")
        self.assert_non_authoritative(out)
        self.assertEqual(self.wrapper_program_injection_helpers(), [])

    def test_04_arbitrary_transport_sha_and_bytes_are_not_authority_entrypoint_parameters(self):
        contract, decomposition, catalog = verified_inputs()
        with self.assertRaises(TypeError):
            impl.build_colonization_program(
                contract,
                decomposition,
                catalog,
                transport_sha256="0" * 64,
                transport_bytes=1,
            )
        self.assertEqual(self.wrapper_program_injection_helpers(), [])

    def test_05_arbitrary_e2_final_aggregate_is_not_authority_entrypoint_parameter(self):
        contract, decomposition, catalog = verified_inputs()
        with self.assertRaises(TypeError):
            impl.build_colonization_program(
                contract,
                decomposition,
                catalog,
                e2_final_aggregate_hash="0" * 64,
            )
        self.assertEqual(self.wrapper_program_injection_helpers(), [])

    def test_06_arbitrary_historical_anchor_is_not_authority_entrypoint_parameter(self):
        contract, decomposition, catalog = verified_inputs()
        with self.assertRaises(TypeError):
            impl.build_colonization_program(
                contract,
                decomposition,
                catalog,
                historical_eco_anchor="0" * 40,
            )
        self.assertEqual(self.wrapper_program_injection_helpers(), [])

    def test_07_source_has_no_replacement_top_level_program_provenance_injector(self):
        tree = ast.parse(IMPL_PATH.read_text(encoding="utf-8"))
        offenders = []
        for node in tree.body:
            if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                continue
            params = {
                arg.arg
                for arg in (
                    list(node.args.posonlyargs)
                    + list(node.args.args)
                    + list(node.args.kwonlyargs)
                )
            }
            if node.args.vararg is not None:
                params.add(node.args.vararg.arg)
            if node.args.kwarg is not None:
                params.add(node.args.kwarg.arg)
            if "program" in params and params.intersection(self.injection_parameter_names):
                offenders.append((node.name, tuple(sorted(params))))
        self.assertEqual(offenders, [])
        self.assertNotIn("def _rehash_program(", IMPL_PATH.read_text(encoding="utf-8"))

    def test_08_direct_core_remains_explicitly_non_authoritative(self):
        out = impl._core.build_colonization_program(load(CONTRACT_PATH), load(DECOMPOSITION_PATH), load(CATALOG_PATH))
        self.assert_non_authoritative(out)

    def test_09_wrapper_core_handle_remains_explicitly_non_authoritative(self):
        decomposition = load(DECOMPOSITION_PATH)
        decomposition["patches"][0]["opportunity_vector"]["water_opportunity_ppm"] = 1
        out = impl._core.build_colonization_program(load(CONTRACT_PATH), decomposition, load(CATALOG_PATH))
        self.assert_non_authoritative(out)

    def test_10_verified_exact_wrapper_is_authoritative_and_deterministic(self):
        first = impl.build_colonization_program(*verified_inputs())
        second = impl.build_colonization_program(*verified_inputs())
        self.assertEqual(first, second)
        self.assertEqual(first["colonization_program_hash"], EXPECTED_PROGRAM_HASH)
        self.assertEqual(first["provenance_hash"], EXPECTED_PROVENANCE_HASH)
        self.assertEqual(
            hashlib.sha256(impl.serialize_program(first)).hexdigest(),
            EXPECTED_ARTIFACT_SHA256,
        )
        self.assertEqual(
            first["provenance"]["persisted_evo2_transport_sha256"],
            first["source_catalog"]["transport_sha256"],
        )


if __name__ == "__main__":
    unittest.main()
