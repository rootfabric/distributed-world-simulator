from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HARNESS = ROOT / "config" / "control" / "harness"
PLANS = ROOT / "docs" / "plans"

EXPECTED_FOUNDATIONS = {
    "TIME_IDENTITY",
    "ACTION_IDENTITY",
    "OBSERVED_STATE_IDENTITY",
    "ROUTE_PRESERVATION",
    "AUTHORITY_BOUNDARY",
    "READ_ONLY_HISTORICAL_QUERY_CONCEPT",
}

EXPECTED_ROUTE_FIELDS = {
    "realtime_action_id",
    "actor_id",
    "input_sequence_or_equivalent",
    "action_time_identity",
    "observed_state_identity",
    "action_type",
    "action_payload",
}


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


class RTA0RealtimeActionTemporalFoundationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.contract = _load(HARNESS / "rta0-realtime-action-temporal-foundation.v1.json")
        cls.by_id = {entry["id"]: entry for entry in cls.contract["foundations"]}
        cls.plan = (PLANS / "RTA0_REALTIME_ACTION_TEMPORAL_FOUNDATION_RU.md").read_text(
            encoding="utf-8"
        )
        cls.current_work_map = (PLANS / "V0_CURRENT_WORK_MAP_RU.md").read_text(
            encoding="utf-8"
        )
        cls.p6_roadmap = (PLANS / "V0_P6_SEAMLESS_EXECUTION_ROADMAP_RU.md").read_text(
            encoding="utf-8"
        )

    def test_exact_control_subject_and_foundation_allowlist(self) -> None:
        self.assertEqual(
            self.contract["schema"],
            "distributed_world_simulator.rta0_realtime_action_temporal_foundation.v1",
        )
        self.assertEqual(
            self.contract["checkpoint_id"], "RTA0_REALTIME_ACTION_TEMPORAL_FOUNDATION"
        )
        self.assertEqual(self.contract["revision"], "RTA0-2026-08-22-R1")
        self.assertEqual(self.contract["status"], "CONTROL_DESIGN_CANDIDATE")
        self.assertEqual(
            self.contract["canonical_main_anchor"],
            "5b44068d80439deb0f16597ddd36b546d68eebfa",
        )
        ids = [entry["id"] for entry in self.contract["foundations"]]
        self.assertEqual(set(ids), EXPECTED_FOUNDATIONS)
        self.assertEqual(len(ids), len(EXPECTED_FOUNDATIONS))

    def test_time_identity_is_evidence_not_second_clock_truth(self) -> None:
        time_identity = self.by_id["TIME_IDENTITY"]
        self.assertEqual(
            time_identity["policy"], "ONE_SEMANTIC_TIME_IDENTITY_NO_COMPETING_CLOCK_TRUTH"
        )
        self.assertEqual(time_identity["client_supplied_time_role"], "EVIDENCE_NOT_AUTHORITY")
        self.assertIn("REUSE_OR_ADAPT_ACCEPTED_INTERACTION_TIME", time_identity["eg0_alignment"])
        self.assertIn("InteractionTime", self.current_work_map)

    def test_realtime_action_identity_is_not_durable_operation_identity(self) -> None:
        action = self.by_id["ACTION_IDENTITY"]
        self.assertEqual(action["realtime_action_id_lifetime"], "BOUNDED_EPHEMERAL_DEDUP_WINDOW")
        self.assertIn("transport_connection_id", action["realtime_action_id_must_not_encode"])
        self.assertIn("server_process_id", action["realtime_action_id_must_not_encode"])
        self.assertIn("OperationId", self.p6_roadmap)
        self.assertIn("RealtimeActionId != OperationId", self.plan)

    def test_observed_state_is_read_only_evidence(self) -> None:
        observed = self.by_id["OBSERVED_STATE_IDENTITY"]
        self.assertEqual(observed["role"], "READ_ONLY_EVIDENCE")
        self.assertFalse(observed["client_claim_is_authority"])
        self.assertFalse(observed["projection_hit_is_canonical_effect"])
        self.assertIn("snapshot_or_state_revision_when_available", observed["minimum_semantics"])
        self.assertIn("PROJECTION_HIT_IS_CANDIDATE_NOT_CANONICAL_EFFECT", self.current_work_map)

    def test_route_preserves_semantic_action_fields(self) -> None:
        route = self.by_id["ROUTE_PRESERVATION"]
        self.assertEqual(set(route["semantic_fields_preserved"]), EXPECTED_ROUTE_FIELDS)
        self.assertFalse(route["gateway_creates_new_gameplay_action"])
        self.assertIn("RoutePort / CommandRouter", self.p6_roadmap)
        self.assertIn("Gateway preserves time/action/observed-state semantics", self.plan)

    def test_authority_boundary_matches_existing_cwip_direction(self) -> None:
        authority = self.by_id["AUTHORITY_BOUNDARY"]
        self.assertFalse(authority["gateway_can_resolve_gameplay_truth"])
        self.assertTrue(authority["action_authority_validates_action"])
        self.assertTrue(authority["world_authority_validates_own_collision_domain"])
        self.assertTrue(authority["target_effect_authority_commits_canonical_effect"])
        for marker in ["ACTION AUTHORITY", "TARGET EFFECT AUTHORITY", "GATEWAY"]:
            self.assertIn(marker, self.current_work_map)

    def test_historical_query_is_concept_only_and_non_canonical(self) -> None:
        historical = self.by_id["READ_ONLY_HISTORICAL_QUERY_CONCEPT"]
        self.assertFalse(historical["runtime_storage_required_by_rta0"])
        self.assertFalse(historical["may_mutate_live_world"])
        self.assertFalse(historical["may_authorize_mutation"])
        self.assertFalse(historical["may_become_second_canonical_truth"])
        self.assertTrue(historical["domain_opt_in_required"])

    def test_checkpoint_is_control_design_only(self) -> None:
        scope = self.contract["scope"]
        self.assertTrue(scope["control_design_only"])
        for key in [
            "runtime_mutation",
            "combat_runtime",
            "damage_runtime",
            "weapon_runtime",
            "historical_state_storage_runtime",
            "p6_runtime_authority_granted",
            "production_sm1_activated",
            "eg_runtime_activated",
        ]:
            self.assertFalse(scope[key], key)
        self.assertIn("NO server rewind", self.plan)
        self.assertIn("NO anti-cheat runtime", self.plan)

    def test_plan_binds_the_six_foundations_to_p6_integration_points(self) -> None:
        for foundation in EXPECTED_FOUNDATIONS:
            self.assertIn(foundation, json.dumps(self.contract, ensure_ascii=False))
        stages = {entry["stage"] for entry in self.contract["integration_points"]}
        self.assertEqual(
            stages,
            {
                "PRE_P6_EG0_TO_EG5",
                "P6.2",
                "P6.3",
                "P6.4",
                "P6.6",
                "P6.7_TO_P6.11",
                "SM1",
                "FUTURE_NXC_OR_OTHER_FAST_INTERACTION_DOMAIN",
            },
        )
        self.assertIn("P6.2", self.plan)
        self.assertIn("P6.3", self.plan)
        self.assertIn("P6.4", self.plan)
        self.assertIn("P6.6", self.plan)
        self.assertIn("SM1", self.plan)


if __name__ == "__main__":
    unittest.main()
