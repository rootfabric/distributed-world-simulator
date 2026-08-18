from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HARNESS = ROOT / "config" / "control" / "harness"


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
        cls.acceptance = _load(
            HARNESS / "acceptance/V0-P4-R1-CHECKPOINT-ACCEPTED-001.v1.json"
        )
        cls.activation = _load(
            HARNESS / "activation/V0-P5-R1-ACTIVATION-001.v1.json"
        )
        cls.epoch = _load(
            HARNESS / "executions/E2026-08-18-V0-P5-R1/project-epoch.v1.json"
        )
        cls.work_order = _load(
            HARNESS
            / "executions/E2026-08-18-V0-P5-R1/work-orders/V0-P5-R1-WO-001.v1.json"
        )

    def test_harness_binds_product_train_policy(self) -> None:
        self.assertEqual(
            self.harness["v0_product_train_policy"],
            "config/control/harness/v0-product-train-policy.v1.json",
        )
        principles = self.harness["principles"]
        self.assertTrue(principles["product_train_advances_one_accepted_checkpoint_at_a_time"])
        self.assertTrue(principles["successor_product_base_is_exact_accepted_predecessor_lineage"])
        self.assertTrue(principles["runtime_implementation_and_closure_control_are_separate"])
        self.assertTrue(principles["research_frontiers_are_non_blocking_by_default"])

    def test_p4_is_formally_accepted_and_exact(self) -> None:
        self.assertEqual(self.acceptance["decision"], "V0_P4_CHECKPOINT_ACCEPTED")
        self.assertEqual(self.acceptance["status"], "ACCEPTED")
        self.assertEqual(
            self.acceptance["accepted_product_lineage_head"],
            "2a6721cdf02fa1134c59d1ab98bb7b597c66821d",
        )
        p4 = self.policy["checkpoint_sequence"][0]
        self.assertEqual(p4["id"], "V0_P4_REAL_RESOURCE_CONSTRUCTION")
        self.assertEqual(p4["state"], "ACCEPTED")
        self.assertEqual(
            p4["accepted_runtime_head"],
            self.acceptance["accepted_product_lineage_head"],
        )

    def test_p5_is_current_preactivation_checkpoint(self) -> None:
        self.assertEqual(self.policy["current_checkpoint"], "V0_P5_EQUIPMENT_TOOLS")
        self.assertEqual(self.policy["current_phase"], "P5_PREACTIVATION_CONTROL_READY")
        p5 = self.policy["checkpoint_sequence"][1]
        self.assertEqual(p5["state"], "CURRENT_PREACTIVATION")
        self.assertEqual(
            p5["activation_complete_except"],
            ["V0_PRODUCT_MUTATION_LEASE_ROTATED_TO_P5", "DIRECTOR_DISPATCH"],
        )
        self.assertEqual(
            self.policy["current_p5_activation_route"]["mutation_lease"],
            "PENDING_MAIN_OWNED_ROTATION",
        )

    def test_p5_base_epoch_and_work_order_are_exact(self) -> None:
        expected = "2a6721cdf02fa1134c59d1ab98bb7b597c66821d"
        self.assertEqual(self.activation["main_declared_exact_successor_base"], expected)
        self.assertEqual(self.epoch["base_sha"], expected)
        self.assertEqual(self.epoch["eligible_checkpoints"], ["V0_P5_EQUIPMENT_TOOLS"])
        self.assertEqual(self.epoch["status"], "ACTIVE")
        self.assertEqual(self.work_order["goal_checkpoint"], "V0_P5_EQUIPMENT_TOOLS")
        self.assertEqual(self.work_order["base_sha"], expected)
        self.assertEqual(self.work_order["branch"], "feature/v0-p5-equipment-tools")
        self.assertEqual(self.work_order["state"], "PLANNED")
        self.assertEqual(self.work_order["risk_class"], "HIGH")

    def test_single_mutation_lease_remains_fail_closed_until_dedicated_rotation(self) -> None:
        lease = self.scheduler["pre_h0_3_runtime_mutation_lease"]
        self.assertEqual(lease["capacity"], 1)
        self.assertEqual(lease["holder_program"], "V0")
        self.assertEqual(lease["holder_checkpoint"], "V0_P4_REAL_RESOURCE_CONSTRUCTION")
        self.assertEqual(lease["holder_branch"], "feature/v0-p4-construction-real-resources")
        self.assertTrue(lease["successor_rotation_requires_predecessor_checkpoint_acceptance"])
        self.assertEqual(
            self.activation["mutation_lease"]["rotation_status"],
            "PENDING_MAIN_OWNED_ROTATION",
        )
        self.assertFalse(self.activation["mutation_lease"]["runtime_mutation_authorized"])
        self.assertFalse(self.activation["director_dispatch"]["runtime_mutation_authorized"])

    def test_scheduler_still_blocks_p5_runtime_before_rotation(self) -> None:
        routing = self.scheduler["v0_product_train_routing"]
        self.assertEqual(routing["current_checkpoint"], "V0_P4_REAL_RESOURCE_CONSTRUCTION")
        self.assertEqual(routing["current_phase"], "CLOSURE_CONTROL_ONLY")
        self.assertFalse(routing["runtime_mutation_allowed_now"])
        self.assertFalse(routing["next_runtime_checkpoint_eligible"])
        self.assertEqual(routing["next_runtime_checkpoint"], "V0_P5_EQUIPMENT_TOOLS")

    def test_future_product_checkpoints_remain_ineligible(self) -> None:
        self.assertEqual(
            self.scheduler["parallel_product_checkpoints"]["checkpoints"],
            ["V0_P4_REAL_RESOURCE_CONSTRUCTION"],
        )
        self.assertIn(
            "V0_P5_EQUIPMENT_TOOLS",
            self.scheduler["parallel_product_checkpoints"]["future_checkpoints_not_yet_eligible"],
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
