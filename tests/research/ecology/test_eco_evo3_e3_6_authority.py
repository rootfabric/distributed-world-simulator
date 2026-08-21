from __future__ import annotations

import copy
import importlib.util
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
IMPL = ROOT / "scripts/research/ecology/temporal_disturbance_program_compiler_v1.py"
CONTRACT = ROOT / "config/ecology/eco-evo3-e3-6-temporal-disturbance-contract.v1.json"
BINDING = ROOT / "config/ecology/eco-evo3-e3-6-inputs.binding.v1.json"
WORKSET = ROOT / "validation/ecology/eco-evo3-e3-5-population-workset.generated.json"
SNAPSHOT = ROOT / "config/ecology/accepted_inputs/e3_1_accepted_planet_field_snapshot.v1.json"


def load_impl():
    spec = importlib.util.spec_from_file_location("e3_6_temporal_compiler_authority", IMPL)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load E3.6 compiler")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class E3_6AuthorityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mod = load_impl()
        cls.inputs = cls.mod.load_verified_inputs(CONTRACT, BINDING, WORKSET, SNAPSHOT)
        cls.program = cls.mod.build_temporal_program(cls.inputs)

    def test_plain_parsed_json_has_no_serialization_authority(self) -> None:
        parsed = copy.deepcopy(dict(self.program))
        self.mod.validate_output_structure(parsed)
        with self.assertRaisesRegex(ValueError, "_VerifiedTemporalProgram"):
            self.mod.serialize_temporal_program(parsed)

    def test_fully_rehashed_provenance_replacement_still_has_no_authority(self) -> None:
        forged = copy.deepcopy(dict(self.program))
        forged["source_population_workset"]["accepted_control_head"] = "a" * 40
        forged["source_population_workset"]["canonical_merge_commit"] = "b" * 40
        forged["source_population_workset"]["artifact_sha256"] = "c" * 64
        forged["source_population_workset"]["git_blob"] = "d" * 40
        forged["source_population_workset"]["population_workset_hash"] = "e" * 64
        forged["source_population_workset"]["provenance_hash"] = "f" * 64
        forged["provenance"]["accepted_e3_5_control_head"] = "a" * 40
        forged["provenance"]["accepted_e3_5_merge_commit"] = "b" * 40
        forged["provenance"]["accepted_e3_5_artifact_sha256"] = "c" * 64
        forged["provenance"]["accepted_e3_5_git_blob"] = "d" * 40
        forged["provenance"]["accepted_e3_5_population_workset_hash"] = "e" * 64
        forged["provenance"]["accepted_e3_5_provenance_hash"] = "f" * 64
        forged["provenance_hash"] = self.mod.sha256_hex(self.mod.canonical_bytes(forged["provenance"]))
        forged["temporal_program_hash"] = self.mod.object_hash(forged, "temporal_program_hash")
        with self.assertRaises(ValueError):
            self.mod.serialize_temporal_program(forged)

    def test_forged_verified_wrapper_is_rebuilt_from_exact_inputs(self) -> None:
        forged = copy.deepcopy(dict(self.program))
        envelope = forged["temporal_envelopes"][0]
        triple = envelope["observed_envelopes"]["temperature_milli_c"]
        triple["min"] += 1
        triple["anchor"] += 1
        triple["max"] += 1
        forged["temporal_program_hash"] = self.mod.object_hash(forged, "temporal_program_hash")
        wrapped = self.mod._VerifiedTemporalProgram(
            forged,
            contract_raw=self.inputs.contract_raw,
            binding_raw=self.inputs.binding_raw,
            workset_raw=self.inputs.workset_raw,
            snapshot_raw=self.inputs.snapshot_raw,
        )
        with self.assertRaisesRegex(ValueError, "independent exact-input rebuild"):
            self.mod.serialize_temporal_program(wrapped)

    def test_mutating_legitimate_verified_output_is_detected(self) -> None:
        altered = self.mod.build_temporal_program(self.mod.load_verified_inputs(CONTRACT, BINDING, WORKSET, SNAPSHOT))
        envelope = altered["temporal_envelopes"][0]
        triple = envelope["observed_envelopes"]["soil_moisture_ppm"]
        triple["min"] += 1
        triple["anchor"] += 1
        triple["max"] += 1
        altered["temporal_program_hash"] = self.mod.object_hash(altered, "temporal_program_hash")
        with self.assertRaisesRegex(ValueError, "independent exact-input rebuild"):
            self.mod.serialize_temporal_program(altered)

    def _assert_tampered_file_rejected(self, original: pathlib.Path, argument: str) -> None:
        with tempfile.TemporaryDirectory() as td:
            tampered = pathlib.Path(td) / original.name
            tampered.write_bytes(original.read_bytes() + b" ")
            paths = {
                "contract_path": CONTRACT,
                "binding_path": BINDING,
                "workset_path": WORKSET,
                "snapshot_path": SNAPSHOT,
            }
            paths[argument] = tampered
            with self.assertRaisesRegex(ValueError, "git blob mismatch"):
                self.mod.load_verified_inputs(**paths)

    def test_contract_raw_byte_drift_rejected(self) -> None:
        self._assert_tampered_file_rejected(CONTRACT, "contract_path")

    def test_binding_raw_byte_drift_rejected(self) -> None:
        self._assert_tampered_file_rejected(BINDING, "binding_path")

    def test_e3_5_raw_byte_drift_rejected(self) -> None:
        self._assert_tampered_file_rejected(WORKSET, "workset_path")

    def test_tf_env_snapshot_raw_byte_drift_rejected(self) -> None:
        self._assert_tampered_file_rejected(SNAPSHOT, "snapshot_path")

    def test_exact_e3_5_semantic_hash_is_recomputed(self) -> None:
        tampered = copy.deepcopy(self.inputs.workset)
        tampered["summary"]["active_basis_count"] = 999
        with tempfile.TemporaryDirectory() as td:
            path = pathlib.Path(td) / "workset.json"
            path.write_bytes(self.mod.canonical_bytes(tampered) + b"\n")
            with self.assertRaises(ValueError):
                self.mod.load_verified_inputs(CONTRACT, BINDING, path, SNAPSHOT)

    def test_tf_env_sample_hash_and_provenance_are_recomputed(self) -> None:
        tampered = copy.deepcopy(self.inputs.snapshot)
        tampered["samples"][0]["temperature_milli_c"] += 1
        with tempfile.TemporaryDirectory() as td:
            path = pathlib.Path(td) / "snapshot.json"
            path.write_bytes(self.mod.canonical_bytes(tampered) + b"\n")
            with self.assertRaises(ValueError):
                self.mod.load_verified_inputs(CONTRACT, BINDING, WORKSET, path)

    def test_no_rng_or_clock_in_compiler_source(self) -> None:
        source = IMPL.read_text(encoding="utf-8")
        self.assertNotIn("import random", source)
        self.assertNotIn("from random", source)
        self.assertNotIn("import time", source)
        self.assertNotIn("from time", source)
        self.assertNotIn("import datetime", source)
        self.assertNotIn("from datetime", source)
        self.assertNotIn("time.time(", source)
        self.assertNotIn("datetime.now(", source)

    def test_opaque_stable_time_key_is_preserved_exactly(self) -> None:
        self.assertEqual(self.program["source_population_workset"]["stable_time_key"], "tf-fixture/planet-alpha/t000180")
        self.assertEqual(self.program["source_tf_env_snapshot"]["stable_time_key"], "tf-fixture/planet-alpha/t000180")
        for envelope in self.program["temporal_envelopes"]:
            self.assertEqual(envelope["stable_time_key"], "tf-fixture/planet-alpha/t000180")

    def test_no_future_or_canonical_authority_fields(self) -> None:
        text = self.mod.canonical_bytes(dict(self.program)).decode("utf-8")
        for forbidden in (
            '"canonical_time_value"',
            '"canonical_history"',
            '"predicted_future"',
            '"forecast_value"',
            '"network_authority"',
            '"persistence_authority"',
            '"transaction_authority"',
        ):
            self.assertNotIn(forbidden, text)
        self.assertIn('"canonical_time_ownership":false', text)
        self.assertIn('"canonical_environment_ownership":false', text)
        self.assertIn('"forecast_authorized":false', text)
        self.assertIn('"history_write_allowed":false', text)


if __name__ == "__main__":
    unittest.main()
