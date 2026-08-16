from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness.checkpoint_planner import build_plan

P4 = "V0_P4_REAL_RESOURCE_CONSTRUCTION"
S1 = "V0_S1_NETWORKED_PLANETARY_OUTPOST"
H0_2 = "H0_2_NX_C1_HIGH_RISK_PILOT"


def load_json(path: str) -> dict:
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


class V0ProductCheckpointContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.catalog = load_json("config/control/harness/checkpoint-catalog.v1.json")
        self.scheduler = load_json("config/control/harness/scheduler-policy.v1.json")
        self.goals = load_json("config/control/harness/project-goals.v1.json")
        self.registry = load_json("config/control/project-program-registry.v1.json")
        self.contracts = {
            "checkpoint_catalog": self.catalog,
            "scheduler_policy": self.scheduler,
        }

    def test_p4_is_current_high_risk_product_checkpoint(self):
        checkpoint = self.catalog["checkpoints"][P4]
        self.assertEqual("PROJECT", checkpoint["kind"])
        self.assertEqual("V0", checkpoint["program"])
        self.assertEqual("HIGH", checkpoint["default_risk_floor"])
        self.assertEqual("V0_P4_PASS", checkpoint["success_state"])
        self.assertEqual("SERVER_PREDICTED", checkpoint["network_baseline"])
        self.assertEqual("V0_BLOCKED_REQUIRES_NX", checkpoint["blocked_state_if_network_foundation_change_required"])
        self.assertEqual("RUNTIME_FEATURE_MERGE", checkpoint["human_gate_after"])

    def test_p4_uses_main_declared_product_execution_base_not_bare_main(self):
        checkpoint = self.catalog["checkpoints"][P4]
        preconditions = set(checkpoint["preconditions"])
        self.assertIn("MAIN_DECLARED_V0_PRODUCT_EXECUTION_BASE_PRESENT", preconditions)
        self.assertIn("V0_P4_EXECUTION_BASE_DESCENDS_FROM_PLAYABLE_FRONTIER", preconditions)
        self.assertNotIn("V0_P4_EXACT_CURRENT_MAIN_BASE", checkpoint["required_predicates"])
        self.assertIn("V0_P4_MAIN_DECLARED_PRODUCT_EXECUTION_BASE", checkpoint["required_predicates"])

        rules = self.scheduler["parallel_product_checkpoints"]["rules"]
        self.assertTrue(rules["requires_main_declared_product_execution_base"])
        self.assertTrue(rules["control_epoch_remains_anchored_to_current_main"])
        self.assertTrue(rules["runtime_branch_may_continue_from_main_declared_stacked_product_lineage"])
        self.assertTrue(rules["product_execution_base_is_not_automatic_checkpoint_acceptance"])

    def test_prior_acceptance_debt_does_not_block_bounded_implementation_but_blocks_acceptance(self):
        checkpoint = self.catalog["checkpoints"][P4]
        non_preconditions = set(checkpoint["non_preconditions_for_bounded_implementation"])
        self.assertIn("P2_DIRECTOR_CHECKPOINT_VERDICT_COMPLETE", non_preconditions)
        self.assertIn("P3_AGGREGATE_ACCEPTANCE_COMPLETE", non_preconditions)
        self.assertIn("P3_REPLICA_REPAIR_ACCEPTED", non_preconditions)
        self.assertIn("V0_PRIOR_ACCEPTANCE_DEBT_RESOLVED", checkpoint["required_predicates"])

        rules = self.scheduler["parallel_product_checkpoints"]["rules"]
        self.assertTrue(rules["bounded_implementation_may_proceed_with_prior_acceptance_debt"])
        self.assertTrue(rules["checkpoint_acceptance_requires_prior_acceptance_debt_resolved"])

    def test_p4_required_predicates_cover_real_resource_atomicity_and_replication(self):
        required = set(self.catalog["checkpoints"][P4]["required_predicates"])
        expected = {
            "V0_P4_EXACT_CONSUME_RED_REPRODUCED",
            "V0_P4_EXACT_CONSUME_GREEN",
            "V0_P4_DETERMINISTIC_SERVER_ALLOCATOR_PASS",
            "V0_P4_LIVE_M4_SINGLE_OWNER_TRANSACTION_PORT_PASS",
            "V0_P4_ATOMIC_ITEM_GRAPH_AND_CONSTRUCTION_COMMIT_PASS",
            "V0_P4_INSUFFICIENT_RESOURCES_MUTATION_FREE_PASS",
            "V0_P4_DUPLICATE_EXACT_ONCE_PASS",
            "V0_P4_OPERATION_ID_CONFLICT_PASS",
            "V0_P4_FAULT_INJECTION_ROLLBACK_PASS",
            "V0_P4_FOREIGN_PLAYER_OWNERSHIP_ISOLATION_PASS",
            "V0_P4_ITEM_GRAPH_DELTA_AND_CONSTRUCTION_EVENT_PUBLICATION_PASS",
            "V0_P4_TWO_CLIENT_REPLICATION_PASS",
            "V0_P4_RECONNECT_CONVERGENCE_PASS",
            "V0_P4_NO_SECOND_ITEM_GRAPH_OR_PERSISTENCE_OWNER_PASS",
            "V0_P4_FAIL_CLOSED_TO_NX_IF_NETWORK_FOUNDATION_CHANGE_REQUIRED",
            "V0_PRIOR_ACCEPTANCE_DEBT_RESOLVED",
            "INDEPENDENT_REVIEWER_PASS",
            "INDEPENDENT_VERIFIER_PASS",
            "V0_P4_CHECKPOINT_PROPOSED",
        }
        self.assertTrue(expected.issubset(required), sorted(expected - required))

    def test_goal_graph_matches_actual_p0_p8_product_order(self):
        goals = {entry["id"]: entry for entry in self.goals["current_goal_graph"]}
        self.assertEqual(P4, goals["V0_P4_PRODUCT"]["target_checkpoint"])
        sequence = goals["V0_PRODUCT_TRAIN"]["sequence"]
        self.assertEqual(
            [
                "V0_P0_PLAYABLE_FRONTIER",
                "V0_P1_WORLD_ITEMS_CONTAINERS",
                "V0_P2_RECONNECTABLE_SHARED_STATE",
                "V0_P3_RESOURCE_MINING",
                "V0_P4_REAL_RESOURCE_CONSTRUCTION",
                "V0_P5_EQUIPMENT_TOOLS",
                "V0_P6_PERSISTENT_SHARED_OUTPOST",
                "V0_P7_BOUNDED_TERRAIN_MUTATION",
                "V0_P8_FIRST_MOBILE_CONSTRUCT",
            ],
            sequence,
        )
        self.assertNotIn("V0_S2_NETWORKED_LANDED_SHIP_0", sequence)
        self.assertIn(P4, self.scheduler["parallel_product_checkpoints"]["checkpoints"])
        self.assertEqual(H0_2, self.scheduler["current_pilot_override"]["current_checkpoint"])

    def test_registry_generation_80_declares_exact_product_lineage_without_false_acceptance(self):
        self.assertEqual(80, self.registry["registry_generation"])
        v0 = self.registry["programs"]["V0"]
        self.assertEqual("COMPOSITION_FRONTIER", v0["role"])
        self.assertEqual("feature/v0-p4-construction-real-resources", v0["branch"])
        execution = v0["product_execution_base"]
        self.assertEqual("repair/v0-p3-visual-interaction-r1", execution["branch"])
        self.assertEqual("ef3ad5f0afc433802d639171d938e4720b3a46ec", execution["sha"])
        self.assertFalse(execution["declares_checkpoint_acceptance"])
        self.assertIn("P2_DIRECTOR_VERDICT_PENDING", v0["acceptance_debt"])
        self.assertIn("P3_AGGREGATE_REVIEW_VERIFICATION_DIRECTOR_PENDING", v0["acceptance_debt"])

    def test_pre_h0_3_concurrency_is_one_mutation_worker(self):
        concurrency = self.scheduler["concurrency"]
        rules = self.scheduler["parallel_product_checkpoints"]["rules"]
        self.assertEqual(1, concurrency["pre_h0_3_total_autonomous_runtime_mutation_workers"])
        self.assertEqual(1, concurrency["v0_product_max_autonomous_runtime_mutation_workers"])
        self.assertTrue(concurrency["verification_review_only_may_wait_in_parallel_with_one_runtime_mutation_worker"])
        self.assertEqual(1, rules["pre_h0_3_total_runtime_mutation_workers_max"])
        self.assertTrue(rules["v0_mutation_plus_nx_or_sm0_nontrivial_fix_mutation_forbidden"])

    def test_p4_planner_waits_for_dispatch_then_allocates_one_mutation_worker(self):
        work_order = {"goal_checkpoint": P4}
        planned = {
            "completed_predicates": [],
            "work_order_id": "V0-P4-WO-TEST",
            "state": "PLANNED",
        }
        plan = build_plan(self.contracts, work_order, planned)
        self.assertEqual("PLANNING_ONLY", plan["mode"])
        self.assertEqual(0, plan["autonomous_runtime_workers"])
        self.assertEqual("MAIN_DECLARED_V0_PRODUCT_LINEAGE", plan["v0_p4_gate"]["runtime_execution_base"])
        self.assertEqual("FORBIDDEN_UNTIL_DISPATCH", plan["v0_p4_gate"]["runtime_mutation"])
        self.assertTrue(plan["v0_p4_gate"]["bounded_implementation_may_proceed_with_prior_acceptance_debt"])

        dispatched = {
            "completed_predicates": ["PROJECT_EPOCH_CREATED"],
            "work_order_id": "V0-P4-WO-TEST",
            "state": "DISPATCHED",
        }
        plan = build_plan(self.contracts, work_order, dispatched)
        self.assertEqual("SINGLE_HIGH_RISK_PRODUCT_SLICE", plan["mode"])
        self.assertEqual(1, plan["autonomous_runtime_workers"])
        self.assertEqual("AUTHORIZED_BY_DISPATCH", plan["v0_p4_gate"]["runtime_mutation"])
        self.assertEqual("BEGIN_V0_P4_REAL_RESOURCE_CONSTRUCTION", plan["next_action"])
        self.assertIn("SECOND_PRE_H0_3_RUNTIME_MUTATION_WORKER", plan["stop_gates"])

    def test_nx_c1_acceptance_contract_remains_strict(self):
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
        self.assertIn(S1, self.catalog["checkpoints"])


if __name__ == "__main__":
    unittest.main()
