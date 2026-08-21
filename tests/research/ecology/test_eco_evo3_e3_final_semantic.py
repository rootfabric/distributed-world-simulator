from __future__ import annotations

import importlib.util
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
IMPL = ROOT / "scripts/research/ecology/planetary_ecology_final_compiler_v1.py"
CONTRACT = ROOT / "config/ecology/eco-evo3-e3-final-unseen-world-challenge-contract.v1.json"
SCHEMA = ROOT / "config/ecology/eco-evo3-e3-final-unseen-world-program.schema.v1.json"
EXPECTED_CONTRACT_HASH = "ee66f06dd186ba914508c1f7d157d01288a8d51d7c04f6be7147d558849ece99"


def load_module(path: pathlib.Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class SemanticE3Final(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_module(IMPL, "e3final_semantic_impl")
        cls.inputs = cls.mod.load_verified_inputs(CONTRACT)
        cls.program = cls.mod.build_unseen_world_program(cls.inputs)

    def test_verified_input_capability_type(self):
        self.assertEqual(type(self.inputs).__name__, "_VerifiedChallengeInputs")

    def test_contract_hash_pinned(self):
        self.assertEqual(self.inputs.contract["contract_hash"], EXPECTED_CONTRACT_HASH)
        self.assertEqual(
            self.mod.object_hash(self.inputs.contract, "contract_hash"),
            EXPECTED_CONTRACT_HASH,
        )

    def test_twelve_combinations_exact_ids(self):
        combos = self.program["combinations"]
        self.assertEqual(len(combos), 12)
        ids = [c["combination_id"] for c in combos]
        self.assertEqual(ids, sorted(ids))
        expected = {f"{slug}__{label}" for slug in (
            "arid-basin-02", "oceanic-ridge-03", "polar-plateau-04", "volcanic-isles-05"
        ) for label in ("baseline", "extended_r1", "mono_r1")}
        self.assertEqual(set(ids), expected)

    def test_catalog_variants_enter_source_port_whole(self):
        counts = {c["catalog"]["variant"]: set() for c in self.program["combinations"]}
        for c in self.program["combinations"]:
            counts[c["catalog"]["variant"]].add(c["catalog"]["entry_count"])
        self.assertEqual(counts["baseline"], {2})
        self.assertEqual(counts["extended_r1"], {12})
        self.assertEqual(counts["mono_r1"], {1})
        for combo in self.program["combinations"]:
            prog = combo["colonization_program"]
            self.assertEqual(len(prog["input_species_manifest"]), prog["source_port"]["species_entry_count"])

    def test_chain_reuse_digests_match_live_files(self):
        reused = self.program["provenance"]["reused_modules"]
        self.assertEqual(len(reused), 6)
        for filename, digest in reused.items():
            live = (ROOT / "scripts/research/ecology" / filename).read_bytes()
            self.assertEqual(self.mod.sha256_hex(live), digest, filename)

    def test_thresholds_untouched_per_combination(self):
        for combo in self.program["combinations"]:
            thresholds = combo["colonization_program"]["causal_thresholds"]
            self.assertEqual(thresholds["minimum_establishment_ppm"], 60000)
            self.assertEqual(thresholds["minimum_edge_arrival_ppm"], 150000)

    def test_embedded_programs_pass_accepted_integrity(self):
        core, _ = self.mod._load_stage_module("causal_colonization_program_compiler_v1_core.py")
        for combo in self.program["combinations"]:
            core.validate_program_integrity(combo["colonization_program"])
            self.assertNotIn("UNVERIFIED_PARSED_INPUTS", combo["colonization_program"]["provenance"]["input_verification"])

    def test_downstream_projection_consistency(self):
        for combo in self.program["combinations"]:
            established = sum(s["established_patch_count"] for s in combo["species_outcomes"])
            self.assertEqual(combo["downstream_projection"]["work_basis_count"], established)
            keys = combo["downstream_projection"]["envelope_stable_spatial_keys"]
            self.assertEqual(keys, sorted(set(keys)))
            if established == 0:
                self.assertEqual(combo["downstream_projection"]["temporal_envelope_count"], 0)

    def test_outcome_diversity_and_null_validity(self):
        summary = self.program["summary"]
        self.assertTrue(summary["null_outcome_valid"])
        self.assertTrue(summary["outcome_diversity_present"])
        classes = {c["observed_outcome_class"] for c in self.program["combinations"]}
        self.assertEqual(classes, {"COLONIZED_ALL_SPECIES", "MIXED_PARTIAL_COLONIZATION", "NO_COLONIZATION_ALL_SPECIES"})
        self.assertEqual(summary["combination_count"], 12)
        self.assertGreaterEqual(summary["total_species_outcomes"], 15)

    def test_sealed_commitments_bound_to_artifact(self):
        commitments = self.inputs.commitments["commitments"]
        self.assertEqual(len(commitments), 12)
        for combo in self.program["combinations"]:
            digest = combo["sealed_prediction_digest"]
            self.assertRegex(digest, r"^[0-9a-f]{64}$")
            self.assertEqual(commitments[combo["combination_id"]], digest)

    def test_in_process_build_determinism(self):
        second = self.mod.build_unseen_world_program(self.mod.load_verified_inputs(CONTRACT))
        self.assertEqual(
            self.mod.canonical_bytes(dict(second)),
            self.mod.canonical_bytes(dict(self.program)),
        )

    def test_planetary_hash_and_provenance_recompute(self):
        p = self.program
        self.assertEqual(p["planetary_ecology_program_hash"], self.mod.object_hash(dict(p), "planetary_ecology_program_hash"))
        self.assertEqual(p["provenance_hash"], self.mod.sha256_hex(self.mod.canonical_bytes(p["provenance"])))
        self.assertEqual(p["challenge"]["contract_hash"], EXPECTED_CONTRACT_HASH)

    def test_schema_validation(self):
        import jsonschema
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        jsonschema.Draft202012Validator.check_schema(schema)
        jsonschema.Draft202012Validator(schema).validate(dict(self.program))


if __name__ == "__main__":
    unittest.main()
