from __future__ import annotations

import copy
import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
IMPL = ROOT / "scripts/research/ecology/temporal_disturbance_program_compiler_v1.py"
CONTRACT = ROOT / "config/ecology/eco-evo3-e3-6-temporal-disturbance-contract.v1.json"
BINDING = ROOT / "config/ecology/eco-evo3-e3-6-inputs.binding.v1.json"
WORKSET = ROOT / "validation/ecology/eco-evo3-e3-5-population-workset.generated.json"
SNAPSHOT = ROOT / "config/ecology/accepted_inputs/e3_1_accepted_planet_field_snapshot.v1.json"


def load_impl():
    spec = importlib.util.spec_from_file_location("e3_6_temporal_compiler", IMPL)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot load E3.6 compiler")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class E3_6TemporalDisturbanceProgramTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.mod = load_impl()
        cls.inputs = cls.mod.load_verified_inputs(CONTRACT, BINDING, WORKSET, SNAPSHOT)
        cls.program = cls.mod.build_temporal_program(cls.inputs)

    def test_exact_accepted_inputs_build(self) -> None:
        program = self.program
        self.assertEqual(program["checkpoint"], "ECO.EVO3/E3.6")
        self.assertEqual(program["compiler_stage"], "TEMPORAL_PROGRAM")
        self.assertEqual(program["authority"], "RESEARCH_DERIVED_NON_AUTHORITATIVE")
        self.assertFalse(program["canonical_binding_resolved"])
        self.assertFalse(program["production_binding_authorized"])
        self.assertEqual(program["temporal_result"], "TEMPORAL_PROGRAM_PRESENT")
        self.assertEqual(program["source_population_workset"]["accepted_control_head"], self.mod.EXPECTED_E3_5_CONTROL_HEAD)
        self.assertEqual(program["source_population_workset"]["canonical_merge_commit"], self.mod.EXPECTED_E3_5_MERGE)
        self.assertEqual(program["source_population_workset"]["population_workset_hash"], self.mod.EXPECTED_E3_5_WORKSET_HASH)
        self.assertEqual(program["source_tf_env_snapshot"]["snapshot_hash"], self.mod.EXPECTED_E3_1_SNAPSHOT_HASH)
        self.assertEqual(program["source_tf_env_snapshot"]["context_role"], "IMMUTABLE_UPSTREAM_CONTEXT_NOT_ECOLOGY_PREDECESSOR")

    def test_active_basis_and_spatial_coverage(self) -> None:
        manifest = self.inputs.workset["work_basis_manifest"]
        expected_basis = {row["basis_key"] for row in manifest}
        expected_spatial = {row["stable_spatial_key"] for row in manifest}
        actual_basis = [basis for envelope in self.program["temporal_envelopes"] for basis in envelope["basis_keys"]]
        actual_spatial = [envelope["stable_spatial_key"] for envelope in self.program["temporal_envelopes"]]
        self.assertEqual(len(expected_basis), 22)
        self.assertEqual(len(expected_spatial), 11)
        self.assertEqual(set(actual_basis), expected_basis)
        self.assertEqual(len(actual_basis), len(set(actual_basis)))
        self.assertEqual(set(actual_spatial), expected_spatial)
        self.assertEqual(actual_spatial, sorted(actual_spatial))
        self.assertEqual(self.program["summary"]["active_basis_count"], 22)
        self.assertEqual(self.program["summary"]["active_spatial_key_count"], 11)
        self.assertEqual(self.program["summary"]["temporal_envelope_count"], 11)

    def test_inactive_cell_is_not_promoted_to_temporal_population_work(self) -> None:
        keys = {envelope["stable_spatial_key"] for envelope in self.program["temporal_envelopes"]}
        self.assertNotIn("eco-evo3-fixture/planet-alpha/cell-12", keys)
        self.assertEqual(keys, {row["stable_spatial_key"] for row in self.inputs.workset["work_basis_manifest"]})

    def test_each_envelope_is_exactly_snapshot_anchored(self) -> None:
        samples = {sample["stable_spatial_key"]: sample for sample in self.inputs.snapshot["samples"]}
        for envelope in self.program["temporal_envelopes"]:
            sample = samples[envelope["stable_spatial_key"]]
            self.assertEqual(envelope["stable_time_key"], self.inputs.snapshot["stable_time_key"])
            self.assertEqual(envelope["source_sample_id"], sample["sample_id"])
            self.assertEqual(envelope["source_sample_hash"], sample["sample_hash"])
            self.assertEqual(envelope["source_field_provenance_hash"], sample["field_provenance_hash"])
            for field in self.mod.OBSERVED_FIELDS:
                value = sample[field]
                self.assertEqual(envelope["observed_envelopes"][field], {"min": value, "anchor": value, "max": value})

    def test_single_snapshot_does_not_invent_seasonal_cycle(self) -> None:
        self.assertEqual(self.program["refresh_contract"]["seasonality_evidence_state"], "UNRESOLVED_SINGLE_SNAPSHOT")
        self.assertEqual(self.program["refresh_contract"]["stable_time_key_semantics"], "OPAQUE_OWNER_TIME_IDENTITY_NOT_NUMERIC_TIME")
        self.assertEqual(self.program["summary"]["unresolved_seasonality_count"], 11)
        for envelope in self.program["temporal_envelopes"]:
            self.assertEqual(envelope["seasonality_state"], "UNRESOLVED_SINGLE_SNAPSHOT")
            self.assertEqual(envelope["temporal_evidence_state"], "SINGLE_ACCEPTED_OWNER_SNAPSHOT_ONLY")

    def test_disturbance_is_observation_not_future_schedule(self) -> None:
        samples = {sample["stable_spatial_key"]: sample for sample in self.inputs.snapshot["samples"]}
        for envelope in self.program["temporal_envelopes"]:
            disturbance = envelope["disturbance_schedule"]
            self.assertEqual(disturbance["state"], "NOT_DERIVABLE_FROM_SINGLE_SNAPSHOT")
            self.assertEqual(disturbance["observed_pressure_ppm"], samples[envelope["stable_spatial_key"]]["disturbance_pressure_ppm"])
            self.assertEqual(disturbance["scheduled_events"], [])
            self.assertEqual(disturbance["authority"], "NO_FUTURE_DISTURBANCE_EVENT_AUTHORITY")
        self.assertEqual(self.program["summary"]["future_disturbance_event_count"], 0)

    def test_tf_env_ownership_stays_external(self) -> None:
        refresh = self.program["refresh_contract"]
        self.assertEqual(refresh["policy"], "RECOMPILE_FROM_NEW_EXACT_OWNER_SNAPSHOT")
        self.assertFalse(refresh["history_write_allowed"])
        self.assertFalse(refresh["forecast_authorized"])
        self.assertFalse(refresh["canonical_time_ownership"])
        self.assertFalse(refresh["canonical_environment_ownership"])
        self.assertEqual(self.program["summary"]["canonical_history_write_count"], 0)
        self.assertEqual(self.program["summary"]["individual_entity_count"], 0)

    def test_manifest_and_snapshot_order_do_not_change_envelopes(self) -> None:
        workset = copy.deepcopy(self.inputs.workset)
        snapshot = copy.deepcopy(self.inputs.snapshot)
        workset["work_basis_manifest"] = list(reversed(workset["work_basis_manifest"]))
        snapshot["samples"] = list(reversed(snapshot["samples"]))
        reordered = self.mod._compile_envelopes(workset, snapshot)
        self.assertEqual(reordered, self.program["temporal_envelopes"])

    def test_no_active_population_core_semantics_are_empty(self) -> None:
        workset = copy.deepcopy(self.inputs.workset)
        workset["work_basis_manifest"] = []
        self.assertEqual(self.mod._compile_envelopes(workset, self.inputs.snapshot), [])
        fake_inputs = self.mod._VerifiedInputs(
            contract=self.inputs.contract,
            binding=self.inputs.binding,
            workset=workset,
            snapshot=self.inputs.snapshot,
            contract_raw=self.inputs.contract_raw,
            binding_raw=self.inputs.binding_raw,
            workset_raw=self.inputs.workset_raw,
            snapshot_raw=self.inputs.snapshot_raw,
        )
        output = self.mod._build_temporal_program(fake_inputs)
        self.assertEqual(output["temporal_result"], "NO_ACTIVE_POPULATION_TEMPORAL_WORK")
        self.assertEqual(output["temporal_envelopes"], [])
        self.assertEqual(output["summary"]["active_basis_count"], 0)
        self.assertEqual(output["summary"]["temporal_envelope_count"], 0)

    def test_hashes_are_canonical_and_deterministic(self) -> None:
        self.mod.validate_output_structure(self.program)
        self.assertEqual(
            self.program["provenance_hash"],
            self.mod.sha256_hex(self.mod.canonical_bytes(self.program["provenance"])),
        )
        self.assertEqual(
            self.program["temporal_program_hash"],
            self.mod.object_hash(self.program, "temporal_program_hash"),
        )
        again = self.mod.build_temporal_program(self.mod.load_verified_inputs(CONTRACT, BINDING, WORKSET, SNAPSHOT))
        self.assertEqual(self.mod.serialize_temporal_program(self.program), self.mod.serialize_temporal_program(again))


if __name__ == "__main__":
    unittest.main()
