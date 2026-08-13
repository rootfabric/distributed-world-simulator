from __future__ import annotations

import json
import copy
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness.checkpoint_planner import (
    arbitrate_pre_h0_3_runtime_mutation,
    build_plan,
    classify_v0_nx_foundation_scope,
)

CHECKPOINT = "V0_S1_NETWORKED_PLANETARY_OUTPOST"
H0_2 = "H0_2_NX_C1_HIGH_RISK_PILOT"


def load_json(path: str) -> dict:
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


class V0S1NetworkedCheckpointContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.catalog = load_json("config/control/harness/checkpoint-catalog.v1.json")
        self.scheduler = load_json("config/control/harness/scheduler-policy.v1.json")
        self.goals = load_json("config/control/harness/project-goals.v1.json")
        self.registry = load_json("config/control/project-program-registry.v1.json")
        self.contracts = {
            "checkpoint_catalog": self.catalog,
            "scheduler_policy": self.scheduler,
        }

    def test_checkpoint_exists_as_high_risk_product_checkpoint(self):
        checkpoint = self.catalog["checkpoints"][CHECKPOINT]
        self.assertEqual("PROJECT", checkpoint["kind"])
        self.assertEqual("V0", checkpoint["program"])
        self.assertEqual("HIGH", checkpoint["default_risk_floor"])
        self.assertEqual("V0_S1_PASS", checkpoint["success_state"])
        self.assertEqual("SERVER_PREDICTED", checkpoint["network_baseline"])
        self.assertEqual("V0_S1_BLOCKED_REQUIRES_NX", checkpoint["blocked_state_if_network_foundation_change_required"])
        self.assertEqual("RUNTIME_FEATURE_MERGE", checkpoint["human_gate_after"])

    def test_checkpoint_requires_r3_c22_pc0_and_network_runtime_not_nx_c1_acceptance(self):
        checkpoint = self.catalog["checkpoints"][CHECKPOINT]
        preconditions = set(checkpoint["preconditions"])
        non_preconditions = set(checkpoint["non_preconditions"])
        expected_preconditions = {
            "H0_1_PASS",
            "C22_MAIN_INTEGRATED",
            "GLOBAL_P0_R3_CANONICAL",
            "POST_R3_STANDARD_PC0_NON_RED",
            "POST_R3_DIRECTIONAL_PC0_NON_RED",
            "CANONICAL_MAIN_KNOWN",
            "NO_GLOBAL_PROJECT_RED",
            "CANONICAL_NETWORK_RUNTIME_PRESENT",
            "PRE_H0_3_RUNTIME_IMPLEMENTATION_WORKERS_LE_1",
        }
        self.assertTrue(expected_preconditions.issubset(preconditions), sorted(expected_preconditions - preconditions))
        self.assertIn("H0_2_PASS", non_preconditions)
        self.assertIn("NX_SOURCE_ACCEPTED", non_preconditions)
        self.assertIn("H0_3_SCHEDULER_ACCEPTED", non_preconditions)
        self.assertIn("OWNER_AUTHORITATIVE_VALIDATED_ACCEPTED", non_preconditions)
        self.assertNotIn("H0_2_PASS", preconditions)
        self.assertNotIn("NX_SOURCE_ACCEPTED", preconditions)

    def test_required_predicates_cover_planet_two_clients_movement_construction_reconnect_and_soak(self):
        required = set(self.catalog["checkpoints"][CHECKPOINT]["required_predicates"])
        expected = {
            "V0_S1_SERVER_BOOT_PASS",
            "V0_S1_PROCEDURAL_PLANET_PASS",
            "V0_S1_CANONICAL_SPAWN_POINT_PASS",
            "V0_S1_PLAYER_OR_SPECTATOR_CONTROL_PASS",
            "V0_S1_TWO_CLIENT_JOIN_SAME_WORLD_PASS",
            "V0_S1_TWO_PLAYABLE_CHARACTERS_PASS",
            "V0_S1_REMOTE_CHARACTER_VISIBILITY_PASS",
            "V0_S1_BIDIRECTIONAL_MOVEMENT_REPLICATION_PASS",
            "V0_S1_CANONICAL_ITEM_PICKUP_MOVE_DROP_PASS",
            "V0_S1_SECOND_CLIENT_ITEM_REPLICATION_PASS",
            "V0_S1_CANONICAL_CONSTRUCTION_COMMIT_PASS",
            "V0_S1_SECOND_CLIENT_CONSTRUCTION_REPLICATION_PASS",
            "V0_S1_NO_CLIENT_PRIVATE_CONSTRUCTION_TRUTH_PASS",
            "V0_S1_RECONNECT_SAME_WORLD_PASS",
            "V0_S1_RECONNECT_CONSTRUCTION_STATE_PASS",
            "V0_S1_30_MIN_TWO_CLIENT_SOAK_PASS",
            "V0_S1_NETWORK_BASELINE_SERVER_PREDICTED_PASS",
            "V0_S1_FAIL_CLOSED_TO_NX_IF_AUTHORITY_CHANGE_REQUIRED",
            "FULL_WORLD_CORE_REGRESSION_PASS",
            "INDEPENDENT_REVIEWER_PASS",
            "INDEPENDENT_VERIFIER_PASS",
            "STANDARD_PC0_NON_RED",
            "DIRECTIONAL_PC0_NON_RED_FOR_CRITICAL_HITS",
            "V0_S1_CHECKPOINT_PROPOSED",
        }
        self.assertTrue(expected.issubset(required), sorted(expected - required))

    def test_goal_graph_declares_v0_product_lane_without_replacing_h0_2_pilot(self):
        goals = {entry["id"]: entry for entry in self.goals["current_goal_graph"]}
        self.assertEqual(CHECKPOINT, goals["V0_S1_PRODUCT"]["target_checkpoint"])
        self.assertIn("C22_MAIN_INTEGRATED", goals["V0_S1_PRODUCT"]["depends_on"])
        self.assertEqual(H0_2, self.scheduler["current_pilot_override"]["current_checkpoint"])
        self.assertIn(CHECKPOINT, self.scheduler["parallel_product_checkpoints"]["checkpoints"])

    def test_registry_generation_80_activates_scenario_gate_without_weakening_nx(self):
        self.assertEqual(80, self.registry["registry_generation"])
        self.assertIn("V0", self.registry["programs"])
        v0 = self.registry["programs"]["V0"]
        self.assertEqual("COMPOSITION_FRONTIER", v0["role"])
        self.assertEqual("ELIGIBLE_FOR_FRESH_EXACT_MAIN_HIGH_RISK_WORK_ORDER", v0["stage_status"])

        transitions = {
            item["stage"]: item["blocked_by"]
            for item in self.registry["global_blocked_transitions"]
        }
        self.assertNotIn("V0 RUNTIME START", transitions)
        self.assertIn("V0-S1 NETWORKED PLANETARY OUTPOST START", transitions)
        self.assertNotIn("H0_3_SCHEDULER_ACCEPTED", transitions["V0-S1 NETWORKED PLANETARY OUTPOST START"])
        self.assertEqual("H0_3_SCHEDULER_ACCEPTED_REQUIRED", transitions["MULTI_RUNTIME_IMPLEMENTATION_WORKERS"])
        self.assertIn("CH_TO_NX_DIRECTIONAL_DEPENDENCY_REVALIDATION_REQUIRED", transitions["NX.C1 SOURCE ACCEPTANCE"])
        self.assertEqual("V0_S1_BLOCKED_REQUIRES_NX", transitions["V0-S1 NETWORK FOUNDATION OR AUTHORITY CHANGE"])

    def test_pre_h0_3_concurrency_is_one_mutation_worker_and_verification_can_coexist(self):
        concurrency = self.scheduler["concurrency"]
        rules = self.scheduler["parallel_product_checkpoints"]["rules"]
        self.assertEqual(1, concurrency["pre_h0_3_total_autonomous_runtime_mutation_workers"])
        self.assertEqual(1, concurrency["v0_s1_max_autonomous_runtime_mutation_workers"])
        self.assertTrue(concurrency["verification_review_only_may_wait_in_parallel_with_one_runtime_mutation_worker"])
        self.assertEqual(1, rules["pre_h0_3_total_runtime_mutation_workers_max"])
        self.assertTrue(rules["verification_or_review_only_work_does_not_consume_mutation_worker_slot"])
        self.assertTrue(rules["v0_mutation_plus_nx_nontrivial_fix_mutation_forbidden"])

    def test_v0_planner_waits_for_dispatch_and_global_reservation_release(self):
        work_order = {"goal_checkpoint": CHECKPOINT, "allowed_paths": ["scripts/app/lunar_app.gd"]}
        planned = {
            "completed_predicates": [],
            "work_order_id": "V0-S1-WO-TEST",
            "state": "PLANNED",
        }
        plan = build_plan(self.contracts, work_order, planned)
        self.assertEqual("PLANNING_ONLY", plan["mode"])
        self.assertEqual(0, plan["autonomous_runtime_workers"])
        self.assertEqual("SERVER_PREDICTED", plan["v0_s1_gate"]["network_baseline"])
        self.assertEqual("V0_S1_BLOCKED_REQUIRES_NX", plan["v0_s1_gate"]["network_foundation_change_fails_closed_to"])
        self.assertEqual("FORBIDDEN_UNTIL_DISPATCH", plan["v0_s1_gate"]["runtime_mutation"])

        dispatched = {
            "completed_predicates": ["PROJECT_EPOCH_CREATED"],
            "work_order_id": "V0-S1-WO-TEST",
            "state": "DISPATCHED",
        }
        reserved = dict(work_order)
        reserved["global_mutation_authorized"] = False
        plan = build_plan(self.contracts, reserved, dispatched)
        self.assertEqual(0, plan["autonomous_runtime_workers"])
        self.assertEqual("BLOCKED_BY_GLOBAL_MUTATION_RESERVATION", plan["v0_s1_gate"]["runtime_mutation"])
        self.assertEqual("PRE_H0_3_GLOBAL_RUNTIME_MUTATION_SLOT_UNAVAILABLE", plan["next_action"])

        released = dict(work_order)
        released["global_mutation_authorized"] = True
        plan = build_plan(self.contracts, released, dispatched)
        self.assertEqual("SINGLE_HIGH_RISK_PRODUCT_SLICE", plan["mode"])
        self.assertEqual(1, plan["autonomous_runtime_workers"])
        self.assertEqual("BEGIN_V0_S1_NETWORKED_PLANETARY_OUTPOST_COMPOSITION", plan["next_action"])

    def test_verifying_releases_mutation_slot_for_both_v0_and_h0_2(self):
        v0_work_order = {"goal_checkpoint": CHECKPOINT, "allowed_paths": ["scripts/app/lunar_app.gd"]}
        v0_verifying = {
            "completed_predicates": ["V0_S1_SERVER_BOOT_PASS"],
            "work_order_id": "V0-S1-WO-TEST",
            "state": "VERIFYING",
        }
        v0_plan = build_plan(self.contracts, v0_work_order, v0_verifying)
        self.assertEqual("PRODUCT_RUNTIME_VERIFICATION", v0_plan["mode"])
        self.assertEqual(0, v0_plan["autonomous_runtime_workers"])
        self.assertEqual("NO_ACTIVE_MUTATION_SLOT", v0_plan["v0_s1_gate"]["runtime_mutation"])

        h0_2_work_order = {"goal_checkpoint": H0_2}
        h0_2_verifying = {
            "completed_predicates": ["PROJECT_EPOCH_CREATED"],
            "work_order_id": "H0-2-WO-TEST",
            "state": "VERIFYING",
        }
        h0_2_plan = build_plan(self.contracts, h0_2_work_order, h0_2_verifying)
        self.assertEqual("HIGH_RISK_RUNTIME_VERIFICATION", h0_2_plan["mode"])
        self.assertEqual(0, h0_2_plan["autonomous_runtime_workers"])
        self.assertEqual("NO_ACTIVE_MUTATION_SLOT", h0_2_plan["nx_c1_gate"]["runtime_mutation"])

    def test_global_pre_h0_3_mutation_arbiter_is_fail_closed(self):
        contracts = copy.deepcopy(self.contracts)
        contracts["scheduler_policy"]["pre_h0_3_runtime_mutation_reservations"] = []
        v0 = ({"work_order_id": "V0"}, {"work_order_id": "V0", "state": "DISPATCHED"})
        nx_fix = ({"work_order_id": "NX"}, {"work_order_id": "NX", "state": "IN_PROGRESS"})
        verifying = ({"work_order_id": "VERIFY"}, {"work_order_id": "VERIFY", "state": "VERIFYING"})

        blocked = arbitrate_pre_h0_3_runtime_mutation(contracts, [v0, nx_fix])
        self.assertFalse(blocked["authorized"])
        self.assertEqual("PRE_H0_3_GLOBAL_RUNTIME_MUTATION_LIMIT_EXCEEDED", blocked["status"])

        for allowed in ([v0, verifying], [verifying, nx_fix]):
            result = arbitrate_pre_h0_3_runtime_mutation(contracts, allowed)
            self.assertTrue(result["authorized"], result)
            self.assertEqual(1, len(result["active_mutation_work_orders"]))

        two_v0_mutators = arbitrate_pre_h0_3_runtime_mutation(
            contracts,
            [v0, ({"work_order_id": "V0-B"}, {"work_order_id": "V0-B", "state": "IMPLEMENTED"})],
        )
        self.assertFalse(two_v0_mutators["authorized"])

        reserved = arbitrate_pre_h0_3_runtime_mutation(self.contracts, [v0])
        self.assertFalse(reserved["authorized"])
        self.assertIn("H0-2-R3-NX-C1-WO-001", reserved["active_mutation_work_orders"])

    def test_v0_network_foundation_scope_classifier_blocks_all_forbidden_categories(self):
        forbidden = [
            "scripts/network/contracts/network_protocol_manifest.gd",
            "scripts/runtime/networked_gameplay/networked_gameplay_service.gd",
            "scripts/runtime/networked_gameplay/transports/dedicated_gameplay_server_runtime.gd",
            "scripts/runtime/networked_gameplay/services/player_ownership_service.gd",
            "scripts/characters/character_owner.gd",
            "config/network/nx4-client-prediction-reconciliation.v1.json",
        ]
        for path in forbidden:
            with self.subTest(path=path):
                work_order = {"goal_checkpoint": CHECKPOINT, "allowed_paths": [path]}
                result = classify_v0_nx_foundation_scope(work_order)
                self.assertTrue(result["blocked"], result)
                self.assertEqual("V0_S1_BLOCKED_REQUIRES_NX", result["status"])
                plan = build_plan(
                    self.contracts,
                    work_order,
                    {"completed_predicates": [], "work_order_id": "V0", "state": "DISPATCHED"},
                )
                self.assertEqual(0, plan["autonomous_runtime_workers"])
                self.assertEqual("V0_S1_BLOCKED_REQUIRES_NX", plan["next_action"])

        safe = classify_v0_nx_foundation_scope(
            {"goal_checkpoint": CHECKPOINT, "allowed_paths": ["scripts/app/lunar_app.gd"]}
        )
        self.assertFalse(safe["blocked"], safe)

    def test_nx_c1_acceptance_contract_is_still_strict(self):
        required = set(self.catalog["checkpoints"][H0_2]["required_predicates"])
        expected = {
            "OWNER_AUTHORITY_FOCUSED_PASS",
            "PHYSICS_PRESENTATION_SINGLE_WRITER_PASS",
            "ITEM_ROLLBACK_PICKUP_DROP_PASS",
            "TWO_CLIENT_PASS",
            "IMPAIRED_NETWORK_PASS",
            "RECONNECT_OWNERSHIP_EPOCH_PASS",
            "CH_TO_NX_DIRECTIONAL_REVALIDATION_PASS",
            "INDEPENDENT_REVIEWER_PASS",
            "TESTED_HEADS_EXACT_AND_FRESH",
            "NX_CHECKPOINT_PROPOSED",
        }
        self.assertTrue(expected.issubset(required), sorted(expected - required))


if __name__ == "__main__":
    unittest.main()
