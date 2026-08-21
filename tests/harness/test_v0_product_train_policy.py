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


def _latest_work_state(event_dir: Path) -> str:
    event_paths = sorted(event_dir.glob("*.json"))
    if not event_paths:
        return "PLANNED"
    latest = _load(event_paths[-1])
    state = str(latest.get("work_state", ""))
    if not state:
        raise AssertionError(f"latest event has no work_state: {event_paths[-1]}")
    return state


class V0ProductTrainPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.policy = _load(HARNESS / "v0-product-train-policy.v1.json")
        cls.harness = _load(HARNESS / "harness-policy.v1.json")
        cls.scheduler = _load(HARNESS / "scheduler-policy.v1.json")
        cls.goals = _load(HARNESS / "project-goals.v1.json")
        cls.catalog = _load(HARNESS / "checkpoint-catalog.v1.json")
        cls.p4_acceptance = _load(HARNESS / "acceptance/V0-P4-R1-CHECKPOINT-ACCEPTED-001.v1.json")
        cls.p5_acceptance = _load(HARNESS / "acceptance/V0-P5-R2-CHECKPOINT-ACCEPTED-001.v1.json")
        cls.p5_activation = _load(HARNESS / "activation/V0-P5-R1-ACTIVATION-001.v1.json")
        cls.p5_epoch = _load(HARNESS / "executions/E2026-08-18-V0-P5-R1/project-epoch.v1.json")
        cls.p5_work_order = _load(HARNESS / "executions/E2026-08-18-V0-P5-R1/work-orders/V0-P5-R1-WO-001.v1.json")
        cls.p6_activation = _load(HARNESS / "activation/V0-P6-R1-ACTIVATION-001.v1.json")
        cls.p6_epoch = _load(HARNESS / "executions/E2026-08-21-V0-P6-R1/project-epoch.v1.json")
        cls.p6_work_order = _load(HARNESS / "executions/E2026-08-21-V0-P6-R1/work-orders/V0-P6-R1-WO-001.v1.json")
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
        self.assertEqual(self.p4_acceptance["decision"], "V0_P4_CHECKPOINT_ACCEPTED")
        self.assertEqual(self.p4_acceptance["status"], "ACCEPTED")
        self.assertEqual(self.p4_acceptance["accepted_product_lineage_head"], expected)
        p4 = self.policy["checkpoint_sequence"][0]
        self.assertEqual(p4["state"], "ACCEPTED")
        self.assertEqual(p4["accepted_runtime_head"], expected)

    def test_p5_is_formally_accepted_and_declares_exact_p6_base(self) -> None:
        accepted_runtime = "5434558856c00b588eed5369d2c613cd4b9858bb"
        accepted_lineage = "491ca7d058690d3de5fcea5e41aaee230a31b3ab"
        self.assertEqual(self.p5_acceptance["decision"], "V0_P5_CHECKPOINT_ACCEPTED")
        self.assertEqual(self.p5_acceptance["status"], "ACCEPTED")
        self.assertEqual(self.p5_acceptance["accepted_runtime_head"], accepted_runtime)
        self.assertEqual(self.p5_acceptance["accepted_product_lineage_head"], accepted_lineage)
        self.assertEqual(
            self.p5_acceptance["successor"]["main_declared_exact_successor_base"],
            accepted_lineage,
        )
        p5 = self.policy["checkpoint_sequence"][1]
        self.assertEqual(p5["state"], "ACCEPTED")
        self.assertEqual(p5["accepted_runtime_head"], accepted_runtime)
        self.assertEqual(p5["accepted_product_lineage_head"], accepted_lineage)

    def test_p6_is_current_preactivation_checkpoint_without_runtime_authority(self) -> None:
        self.assertEqual(self.policy["current_checkpoint"], "V0_P6_PERSISTENT_SHARED_OUTPOST")
        self.assertEqual(self.policy["current_phase"], "P6_PREACTIVATION_CONTROL_READY")
        p6 = self.policy["checkpoint_sequence"][2]
        self.assertEqual(p6["state"], "CURRENT_PREACTIVATION")
        self.assertEqual(p6["execution_base"], "491ca7d058690d3de5fcea5e41aaee230a31b3ab")
        self.assertEqual(p6["project_epoch"], "E2026-08-21-V0-P6-R1")
        self.assertEqual(p6["work_order_id"], "V0-P6-R1-WO-001")
        self.assertIn("V0_PRODUCT_MUTATION_LEASE_ROTATED_TO_P6", p6["activation_requires"])
        self.assertIn("DIRECTOR_DISPATCH", p6["activation_requires"])
        self.assertIn("MAIN_OWNED_MUTATION_LEASE_ROTATION_TO_P6", p6["activation_pending"])
        self.assertIn("DIRECTOR_DISPATCH", p6["activation_pending"])
        self.assertFalse(self.p6_activation["mutation_lease"]["runtime_mutation_authorized"])
        self.assertFalse(self.p6_activation["director_dispatch"]["runtime_mutation_authorized"])

    def test_p6_base_epoch_and_work_order_are_exact(self) -> None:
        expected = "491ca7d058690d3de5fcea5e41aaee230a31b3ab"
        self.assertEqual(self.p6_activation["main_declared_exact_successor_base"], expected)
        self.assertEqual(self.p6_epoch["base_sha"], expected)
        self.assertEqual(self.p6_epoch["eligible_checkpoints"], ["V0_P6_PERSISTENT_SHARED_OUTPOST"])
        self.assertEqual(self.p6_epoch["status"], "ACTIVE")
        self.assertEqual(self.p6_work_order["goal_checkpoint"], "V0_P6_PERSISTENT_SHARED_OUTPOST")
        self.assertEqual(self.p6_work_order["base_sha"], expected)
        self.assertEqual(self.p6_work_order["branch"], "feature/v0-p6-persistent-shared-outpost")
        event_dir = HARNESS / "executions/E2026-08-21-V0-P6-R1/events/V0-P6-R1-WO-001"
        self.assertEqual(self.p6_work_order["state"], _latest_work_state(event_dir))
        self.assertEqual(self.p6_work_order["risk_class"], "HIGH")
        self.assertIn("V0_P6_VISUAL_MANUAL_GATES_PASS", self.p6_work_order["required_predicates"])
        self.assertIn("V0_P6_WARM_SHADOW_READ_ONLY_COMPATIBILITY_PASS", self.p6_work_order["required_predicates"])
        self.assertIn("V0_P6_NO_PRIVATE_NETWORK_FOUNDATION_PASS", self.p6_work_order["required_predicates"])

    def test_p6_preactivation_does_not_self_rotate_live_mutation_lease(self) -> None:
        lease = self.scheduler["pre_h0_3_runtime_mutation_lease"]
        self.assertEqual(lease["capacity"], 1)
        self.assertEqual(lease["holder_program"], "V0")
        # P6 preactivation deliberately does not mutate scheduler ownership. The
        # live lease remains on the accepted P5 lane until a separate main-owned
        # lease-rotation candidate updates scheduler/catalog/planner together.
        self.assertEqual(lease["holder_checkpoint"], "V0_P5_EQUIPMENT_TOOLS")
        self.assertEqual(lease["holder_branch"], "feature/v0-p5-equipment-tools")
        self.assertEqual(lease["state"], "RESERVED_FOR_V0_P5_PRE_DISPATCH_NO_ACTIVE_RUNTIME_MUTATION")
        self.assertTrue(lease["successor_rotation_requires_predecessor_checkpoint_acceptance"])
        self.assertEqual(self.p6_activation["mutation_lease"]["rotation_status"], "PENDING_MAIN_OWNED_ROTATION")
        self.assertFalse(self.p6_activation["mutation_lease"]["runtime_mutation_authorized"])
        self.assertEqual(self.policy["current_p6_activation_route"]["mutation_lease"], "PENDING_MAIN_OWNED_ROTATION")
        self.assertEqual(
            self.policy["current_p6_activation_route"]["runtime_mutation"],
            "FORBIDDEN_UNTIL_LEASE_ROTATION_AND_DIRECTOR_DISPATCH",
        )

    def test_historical_p5_lease_and_planner_remain_unchanged_until_p6_rotation(self) -> None:
        self.assertEqual(self.p5_activation["mutation_lease"]["rotation_status"], "ROTATED_RESERVED_PRE_DISPATCH")
        self.assertEqual(self.p5_epoch["base_sha"], "2a6721cdf02fa1134c59d1ab98bb7b597c66821d")
        self.assertEqual(self.p5_work_order["goal_checkpoint"], "V0_P5_EQUIPMENT_TOOLS")
        self.assertEqual(
            self.catalog["checkpoints"]["V0_P5_EQUIPMENT_TOOLS"]["required_predicates"],
            self.p5_work_order["required_predicates"],
        )

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

    def test_p6_is_preactivated_while_sm1_p7_p8_remain_ineligible(self) -> None:
        # Scheduler still represents the pre-rotation lease owner. P6 becoming
        # the main-owned preactivation pointer does not make it schedulable yet.
        self.assertEqual(self.scheduler["parallel_product_checkpoints"]["checkpoints"], ["V0_P5_EQUIPMENT_TOOLS"])
        self.assertIn(
            "V0_P6_PERSISTENT_SHARED_OUTPOST",
            self.scheduler["parallel_product_checkpoints"]["future_checkpoints_not_yet_eligible"],
        )
        p6 = self.policy["checkpoint_sequence"][2]
        self.assertEqual(p6["state"], "CURRENT_PREACTIVATION")
        self.assertEqual(p6["activation_pending"][0], "FRESH_EXACT_PREACTIVATION_PROJECT_CONTROL_NON_RED")

        by_id = {item["id"]: item for item in self.policy["checkpoint_sequence"]}
        self.assertEqual(by_id["V0_SM1_SEAMLESS_PRODUCT_INTEGRATION"]["state"], "FUTURE_CONTROL_ACTIVATION")
        self.assertEqual(by_id["V0_P7_BOUNDED_TERRAIN_MUTATION"]["state"], "FUTURE")
        self.assertEqual(by_id["V0_P8_FIRST_MOBILE_CONSTRUCT"]["state"], "FUTURE")

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
        self.assertTrue(self.policy["research_isolation"]["seamless_research_parallel_train"])
        self.assertFalse(self.policy["research_isolation"]["seamless_research_production_base"])
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
