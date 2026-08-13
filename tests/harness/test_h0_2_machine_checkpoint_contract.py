from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness.checkpoint_planner import build_plan

CHECKPOINT = "H0_2_NX_C1_HIGH_RISK_PILOT"


def load_json(path: str) -> dict:
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


class H02MachineCheckpointContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.catalog = load_json("config/control/harness/checkpoint-catalog.v1.json")
        self.scheduler = load_json("config/control/harness/scheduler-policy.v1.json")
        self.goals = load_json("config/control/harness/project-goals.v1.json")
        self.contracts = {
            "checkpoint_catalog": self.catalog,
            "scheduler_policy": self.scheduler,
        }
        self.work_order = {
            "work_order_id": "H0-2-NX-C1-WO-TEST",
            "project_epoch": "E-test",
            "goal_checkpoint": CHECKPOINT,
            "branch": "feature/h0-2-test",
        }

    def test_h0_2_checkpoint_exists_and_has_distinct_success_state(self):
        checkpoint = self.catalog["checkpoints"][CHECKPOINT]
        self.assertEqual("HARNESS", checkpoint["kind"])
        self.assertEqual("H0_2_PASS", checkpoint["success_state"])
        self.assertEqual("SOURCE_ACCEPTED", checkpoint["project_success_state"])
        self.assertEqual("H0_3_MULTI_WORKER_SCHEDULER", checkpoint["next_checkpoint"])

    def test_h0_2_is_bound_to_canonical_r3_and_post_r3_pc0(self):
        preconditions = set(self.catalog["checkpoints"][CHECKPOINT]["preconditions"])
        self.assertIn("GLOBAL_P0_R3_CANONICAL", preconditions)
        self.assertIn("REGISTRY_GENERATION_79", preconditions)
        self.assertIn("POST_R3_STANDARD_PC0_NON_RED", preconditions)
        self.assertIn("POST_R3_DIRECTIONAL_PC0_NON_RED", preconditions)
        self.assertIn("NO_GLOBAL_PROJECT_RED", preconditions)

    def test_h0_2_requires_high_risk_runtime_and_dependency_evidence(self):
        required = set(self.catalog["checkpoints"][CHECKPOINT]["required_predicates"])
        expected = {
            "PROJECT_EPOCH_R3_GENERATION_79_EXACT",
            "NX_C1_WORK_ORDER_ISSUED",
            "NX_C1_RISK_CLASSIFIED_HIGH_OR_CRITICAL",
            "FRESH_CURRENT_MAIN_NX_C1_BRANCH_CREATED",
            "OWNER_AUTHORITY_FOCUSED_PASS",
            "PHYSICS_PRESENTATION_SINGLE_WRITER_PASS",
            "ITEM_ROLLBACK_PICKUP_DROP_PASS",
            "TWO_CLIENT_PASS",
            "IMPAIRED_NETWORK_PASS",
            "RECONNECT_OWNERSHIP_EPOCH_PASS",
            "INDEPENDENT_REVIEWER_PASS",
            "STANDARD_PC0_NON_RED",
            "DIRECTIONAL_PC0_NON_RED_FOR_CRITICAL_HITS",
            "CH_TO_NX_DIRECTIONAL_REVALIDATION_PASS",
            "NX_CHECKPOINT_PROPOSED",
        }
        self.assertTrue(expected.issubset(required), sorted(expected - required))

    def test_scheduler_selects_h0_2_but_keeps_single_worker_ceiling(self):
        override = self.scheduler["current_pilot_override"]
        self.assertEqual(CHECKPOINT, override["current_checkpoint"])
        self.assertEqual(CHECKPOINT, override["checkpoint_sequence"][-1])
        self.assertEqual(1, self.scheduler["concurrency"]["h0_2_max_autonomous_runtime_workers"])
        self.assertTrue(self.scheduler["concurrency"]["h0_3_required_before_multi_runtime_worker_scheduler"])

    def test_goal_graph_routes_network_train_through_h0_2(self):
        goals = {entry["id"]: entry for entry in self.goals["current_goal_graph"]}
        self.assertEqual(CHECKPOINT, goals["HARNESS_H0_2"]["target_checkpoint"])
        self.assertEqual("NX_SOURCE_ACCEPTED", goals["HARNESS_H0_2"]["project_checkpoint"])
        self.assertEqual(["HARNESS_H0_2"], goals["NETWORK_TRAIN"]["depends_on"])

    def test_planner_allows_control_only_planning_branch_but_forbids_runtime_mutation_before_dispatch(self):
        reduced = {
            "completed_predicates": [],
            "work_order_id": "H0-2-NX-C1-WO-TEST",
            "state": "PLANNED",
        }
        plan = build_plan(self.contracts, self.work_order, reduced)
        self.assertEqual("PLANNING_ONLY", plan["mode"])
        self.assertEqual(0, plan["autonomous_runtime_workers"])
        self.assertEqual("PLANNING_BRANCH_ALLOWED_CONTROL_ONLY", plan["nx_c1_gate"]["branch_creation"])
        self.assertEqual("FORBIDDEN_UNTIL_DISPATCH", plan["nx_c1_gate"]["runtime_mutation"])
        self.assertEqual("HIGH", plan["nx_c1_gate"]["risk_floor"])
        self.assertIn("NX_C1_RUNTIME_MUTATION_BEFORE_DISPATCH", plan["stop_gates"])
        self.assertIn("H0_3_IMPLEMENTATION", plan["stop_gates"])

    def test_planner_dispatch_authorizes_exactly_one_high_risk_worker_on_current_work_order_branch(self):
        reduced = {
            "completed_predicates": ["PROJECT_EPOCH_CREATED"],
            "work_order_id": "H0-2-NX-C1-WO-TEST",
            "state": "DISPATCHED",
        }
        work_order = dict(self.work_order)
        work_order["global_runtime_mutation_arbiter"] = {"authorized": True}
        plan = build_plan(self.contracts, work_order, reduced)
        self.assertEqual("SINGLE_HIGH_RISK_RUNTIME_PILOT", plan["mode"])
        self.assertEqual(1, plan["autonomous_runtime_workers"])
        self.assertEqual("CURRENT_WORK_ORDER_BRANCH", plan["nx_c1_gate"]["branch_creation"])
        self.assertEqual("AUTHORIZED_BY_MAIN_OWNED_LEASE", plan["nx_c1_gate"]["runtime_mutation"])
        self.assertEqual("BEGIN_BOUNDED_NX_C1_IMPLEMENTATION_ON_DISPATCHED_BRANCH", plan["next_action"])
        self.assertEqual("CH_TO_NX_DIRECTIONAL_REVALIDATION_PASS", plan["nx_c1_gate"]["source_acceptance_requires"])


if __name__ == "__main__":
    unittest.main()
