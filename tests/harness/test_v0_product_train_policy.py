from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HARNESS = ROOT / "config" / "control" / "harness"
sys.path.insert(0, str(ROOT / "scripts"))

from harness.checkpoint_planner import build_plan


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


class V0ProductTrainPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.policy = _load(HARNESS / "v0-product-train-policy.v1.json")
        cls.harness = _load(HARNESS / "harness-policy.v1.json")
        cls.scheduler = _load(HARNESS / "scheduler-policy.v1.json")
        cls.goals = _load(HARNESS / "project-goals.v1.json")
        cls.catalog = _load(HARNESS / "checkpoint-catalog.v1.json")
        cls.acceptance = _load(HARNESS / "acceptance/V0-P4-R1-CHECKPOINT-ACCEPTED-001.v1.json")
        cls.activation = _load(HARNESS / "activation/V0-P5-R1-ACTIVATION-001.v1.json")
        cls.epoch = _load(HARNESS / "executions/E2026-08-18-V0-P5-R1/project-epoch.v1.json")
        cls.work_order = _load(HARNESS / "executions/E2026-08-18-V0-P5-R1/work-orders/V0-P5-R1-WO-001.v1.json")
        cls.contracts = {
            "checkpoint_catalog": cls.catalog,
            "scheduler_policy": cls.scheduler,
        }

    def test_harness_binds_product_train_policy(self) -> None:
        self.assertEqual(self.harness["v0_product_train_policy"], "config/control/harness/v0-product-train-policy.v1.json")
        principles = self.harness["principles"]
        self.assertTrue(principles["product_train_advances_one_accepted_checkpoint_at_a_time"])
        self.assertTrue(principles["successor_product_base_is_exact_accepted_predecessor_lineage"])
        self.assertTrue(principles["runtime_implementation_and_closure_control_are_separate"])
        self.assertTrue(principles["research_frontiers_are_non_blocking_by_default"])

    def test_p4_is_formally_accepted_and_exact(self) -> None:
        expected = "2a6721cdf02fa1134c59d1ab98bb7b597c66821d"
        self.assertEqual(self.acceptance["decision"], "V0_P4_CHECKPOINT_ACCEPTED")
        self.assertEqual(self.acceptance["status"], "ACCEPTED")
        self.assertEqual(self.acceptance["accepted_product_lineage_head"], expected)
        p4 = self.policy["checkpoint_sequence"][0]
        self.assertEqual(p4["state"], "ACCEPTED")
        self.assertEqual(p4["accepted_runtime_head"], expected)

    def test_p5_is_current_pre_dispatch_checkpoint(self) -> None:
        self.assertEqual(self.policy["current_checkpoint"], "V0_P5_EQUIPMENT_TOOLS")
        self.assertEqual(self.policy["current_phase"], "P5_PRE_DISPATCH_CONTROL_READY")
        p5 = self.policy["checkpoint_sequence"][1]
        self.assertEqual(p5["state"], "CURRENT_PRE_DISPATCH")
        self.assertEqual(p5["activation_complete_except"], ["DIRECTOR_DISPATCH"])
        routing = self.scheduler["v0_product_train_routing"]
        self.assertEqual(routing["current_checkpoint"], "V0_P5_EQUIPMENT_TOOLS")
        self.assertEqual(routing["current_phase"], "PRE_DISPATCH_CONTROL_READY")
        self.assertFalse(routing["runtime_mutation_allowed_now"])
        self.assertEqual(routing["p5_remaining_activation_prerequisites"], ["DIRECTOR_DISPATCH"])

    def test_p5_base_epoch_and_work_order_are_exact(self) -> None:
        expected = "2a6721cdf02fa1134c59d1ab98bb7b597c66821d"
        self.assertEqual(self.activation["main_declared_exact_successor_base"], expected)
        self.assertEqual(self.epoch["base_sha"], expected)
        self.assertEqual(self.epoch["eligible_checkpoints"], ["V0_P5_EQUIPMENT_TOOLS"])
        self.assertEqual(self.epoch["status"], "ACTIVE")
        self.assertEqual(self.work_order["goal_checkpoint"], "V0_P5_EQUIPMENT_TOOLS")
        self.assertEqual(self.work_order["base_sha"], expected)
        self.assertEqual(self.work_order["branch"], "feature/v0-p5-equipment-tools")
        dispatch_event = HARNESS / "executions/E2026-08-18-V0-P5-R1/events/V0-P5-R1-WO-001/0002-director-dispatched.v1.json"
        expected_state = "DISPATCHED" if dispatch_event.is_file() else "PLANNED"
        self.assertEqual(self.work_order["state"], expected_state)
        self.assertEqual(self.work_order["risk_class"], "HIGH")
        self.assertEqual(
            self.catalog["checkpoints"]["V0_P5_EQUIPMENT_TOOLS"]["required_predicates"],
            self.work_order["required_predicates"],
        )

    def test_single_mutation_lease_is_rotated_but_inactive_before_dispatch(self) -> None:
        lease = self.scheduler["pre_h0_3_runtime_mutation_lease"]
        self.assertEqual(lease["capacity"], 1)
        self.assertEqual(lease["holder_program"], "V0")
        self.assertEqual(lease["holder_checkpoint"], "V0_P5_EQUIPMENT_TOOLS")
        self.assertEqual(lease["holder_branch"], "feature/v0-p5-equipment-tools")
        self.assertEqual(lease["state"], "RESERVED_FOR_V0_P5_PRE_DISPATCH_NO_ACTIVE_RUNTIME_MUTATION")
        self.assertTrue(lease["successor_rotation_requires_predecessor_checkpoint_acceptance"])
        self.assertEqual(self.activation["mutation_lease"]["rotation_status"], "ROTATED_RESERVED_PRE_DISPATCH")
        self.assertEqual(self.policy["current_p5_activation_route"]["mutation_lease"], "ROTATED_RESERVED_PRE_DISPATCH")
        self.assertEqual(self.policy["current_p5_activation_route"]["runtime_mutation"], "FORBIDDEN_UNTIL_DIRECTOR_DISPATCH")

    def test_p5_planner_waits_for_director_then_grants_exactly_one_worker(self) -> None:
        work_order = {
            "goal_checkpoint": "V0_P5_EQUIPMENT_TOOLS",
            "branch": "feature/v0-p5-equipment-tools",
        }
        planned = {
            "completed_predicates": ["PROJECT_EPOCH_CREATED"],
            "work_order_id": "V0-P5-R1-WO-001",
            "state": "PLANNED",
        }
        plan = build_plan(self.contracts, work_order, planned)
        self.assertEqual(plan["mode"], "PLANNING_ONLY")
        self.assertEqual(plan["autonomous_runtime_workers"], 0)
        self.assertEqual(plan["next_action"], "DIRECTOR_DISPATCH_ACCEPTED_P4_BASE_V0_P5_WORK_ORDER")
        self.assertEqual(plan["v0_p5_gate"]["runtime_mutation"], "FORBIDDEN_UNTIL_DISPATCH")
        self.assertEqual(
            plan["v0_p5_gate"]["accepted_predecessor_base"],
            "2a6721cdf02fa1134c59d1ab98bb7b597c66821d",
        )

        dispatched = dict(planned)
        dispatched["state"] = "DISPATCHED"
        plan = build_plan(self.contracts, work_order, dispatched)
        self.assertEqual(plan["mode"], "SINGLE_HIGH_RISK_PRODUCT_SLICE")
        self.assertEqual(plan["autonomous_runtime_workers"], 1)
        self.assertEqual(plan["next_action"], "BEGIN_V0_P5_EQUIPMENT_TOOLS")
        self.assertEqual(plan["v0_p5_gate"]["runtime_mutation"], "AUTHORIZED_BY_DISPATCH")
        self.assertEqual(plan["v0_p5_gate"]["global_mutation_lease_holder_checkpoint"], "V0_P5_EQUIPMENT_TOOLS")

    def test_future_product_checkpoints_remain_ineligible(self) -> None:
        self.assertEqual(self.scheduler["parallel_product_checkpoints"]["checkpoints"], ["V0_P5_EQUIPMENT_TOOLS"])
        self.assertEqual(
            set(self.scheduler["parallel_product_checkpoints"]["future_checkpoints_not_yet_eligible"]),
            {
                "V0_P6_PERSISTENT_SHARED_OUTPOST",
                "V0_SM1_SEAMLESS_PRODUCT_INTEGRATION",
                "V0_P7_BOUNDED_TERRAIN_MUTATION",
                "V0_P8_FIRST_MOBILE_CONSTRUCT",
            },
        )
        p6 = self.policy["checkpoint_sequence"][2]
        self.assertEqual(p6["state"], "PLANNED_NOT_ELIGIBLE")
        self.assertIn("V0_P5_CHECKPOINT_ACCEPTED", p6["activation_requires"])

    def test_product_sequence_and_research_isolation_remain_unchanged(self) -> None:
        ids = [item["id"] for item in self.policy["checkpoint_sequence"]]
        self.assertEqual(
            ids,
            [
                "V0_P4_REAL_RESOURCE_CONSTRUCTION",
                "V0_P5_EQUIPMENT_TOOLS",
                "V0_P6_PERSISTENT_SHARED_OUTPOST",
                "V0_POST_P6_SEAMLESS_INSERTION_GATE",
                "V0_SM1_SEAMLESS_PRODUCT_INTEGRATION",
                "V0_P7_BOUNDED_TERRAIN_MUTATION",
                "V0_P8_FIRST_MOBILE_CONSTRUCT",
            ],
        )
        self.assertEqual(len(ids), len(set(ids)))
        self.assertIn("ECO", self.policy["research_isolation"]["explicitly_non_blocking_programs_for_current_p_train"])
        self.assertTrue(self.scheduler["research_isolation"]["non_blocking_by_default"])

    def test_project_goal_graph_still_exposes_product_order(self) -> None:
        train = next(item for item in self.goals["current_goal_graph"] if item["id"] == "V0_PRODUCT_TRAIN")
        self.assertEqual(train["policy"], "config/control/harness/v0-product-train-policy.v1.json")
        self.assertEqual(
            train["sequence"][4:],
            [
                "V0_P4_REAL_RESOURCE_CONSTRUCTION",
                "V0_P5_EQUIPMENT_TOOLS",
                "V0_P6_PERSISTENT_SHARED_OUTPOST",
                "V0_POST_P6_SEAMLESS_INSERTION_GATE",
                "V0_SM1_SEAMLESS_PRODUCT_INTEGRATION_OR_EXPLICIT_DEFER",
                "V0_P7_BOUNDED_TERRAIN_MUTATION",
                "V0_P8_FIRST_MOBILE_CONSTRUCT",
            ],
        )


if __name__ == "__main__":
    unittest.main()
