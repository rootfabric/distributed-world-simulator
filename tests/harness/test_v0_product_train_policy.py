from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HARNESS = ROOT / "config" / "control" / "harness"
sys.path.insert(0, str(ROOT / "scripts"))


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
        cls.acceptance_p4 = _load(HARNESS / "acceptance/V0-P4-R1-CHECKPOINT-ACCEPTED-001.v1.json")
        cls.acceptance_p5 = _load(HARNESS / "acceptance/V0-P5-R2-CHECKPOINT-ACCEPTED-001.v1.json")
        cls.acceptance_p6 = _load(HARNESS / "acceptance/V0-P6-R2-CHECKPOINT-ACCEPTED-001.v1.json")
        cls.activation_p5 = _load(HARNESS / "activation/V0-P5-R1-ACTIVATION-001.v1.json")
        cls.activation_p6 = _load(HARNESS / "activation/V0-P6-R2-ACTIVATION-001.v1.json")
        cls.activation_sm1 = _load(HARNESS / "activation/V0-SM1-R1-ACTIVATION-001.v1.json")
        cls.epoch_p5 = _load(HARNESS / "executions/E2026-08-18-V0-P5-R1/project-epoch.v1.json")
        cls.epoch_p6 = _load(HARNESS / "executions/E2026-08-23-V0-P6-R2/project-epoch.v1.json")
        cls.epoch_sm1 = _load(HARNESS / "executions/E2026-08-24-V0-SM1-R1/project-epoch.v1.json")
        cls.work_order_p5 = _load(HARNESS / "executions/E2026-08-18-V0-P5-R1/work-orders/V0-P5-R1-WO-001.v1.json")
        cls.work_order_p6 = _load(HARNESS / "executions/E2026-08-23-V0-P6-R2/work-orders/V0-P6-R2-WO-001.v1.json")
        cls.work_order_sm1 = _load(HARNESS / "executions/E2026-08-24-V0-SM1-R1/work-orders/V0-SM1-R1-WO-001.v1.json")
        cls.sm1_plan = _load(HARNESS / "v0-sm1-production-handoff-plan.v1.json")

    def test_harness_binds_product_train_policy(self) -> None:
        self.assertEqual(self.harness["v0_product_train_policy"], "config/control/harness/v0-product-train-policy.v1.json")
        principles = self.harness["principles"]
        self.assertTrue(principles["product_train_advances_one_accepted_checkpoint_at_a_time"])
        self.assertTrue(principles["successor_product_base_is_exact_accepted_predecessor_lineage"])
        self.assertTrue(principles["runtime_implementation_and_closure_control_are_separate"])
        self.assertTrue(principles["research_frontiers_are_non_blocking_by_default"])

    def test_p4_and_p5_remain_formally_accepted(self) -> None:
        self.assertEqual(self.acceptance_p4["decision"], "V0_P4_CHECKPOINT_ACCEPTED")
        self.assertEqual(self.acceptance_p5["decision"], "V0_P5_CHECKPOINT_ACCEPTED")
        self.assertEqual(self.policy["checkpoint_sequence"][0]["state"], "ACCEPTED")
        self.assertEqual(self.policy["checkpoint_sequence"][1]["state"], "ACCEPTED")
        self.assertEqual(
            self.policy["checkpoint_sequence"][1]["accepted_runtime_head"],
            "491ca7d058690d3de5fcea5e41aaee230a31b3ab",
        )

    def test_p6_is_formally_accepted_on_exact_main(self) -> None:
        self.assertEqual(self.acceptance_p6["decision"], "V0_P6_CHECKPOINT_ACCEPTED")
        self.assertEqual(self.acceptance_p6["status"], "ACCEPTED")
        self.assertEqual(
            self.acceptance_p6["accepted_runtime_head"],
            "7a77c048caa680871d4895c09eca89e84136b154",
        )
        self.assertEqual(
            self.acceptance_p6["accepted_product_lineage_head"],
            "9ade3233f8d9f16b77edcc8cf273fe8e649d5637",
        )
        p6 = self.policy["checkpoint_sequence"][2]
        self.assertEqual(p6["state"], "ACCEPTED")
        self.assertEqual(p6["acceptance_record"], "config/control/harness/acceptance/V0-P6-R2-CHECKPOINT-ACCEPTED-001.v1.json")

    def test_post_p6_gate_is_current_and_sm1_decision_recorded(self) -> None:
        self.assertEqual(self.policy["current_checkpoint"], "V0_POST_P6_SEAMLESS_INSERTION_GATE")
        self.assertEqual(self.policy["current_phase"], "POST_P6_SM1_ACTIVATION_CONTROL_CANDIDATE")
        gate = self.policy["checkpoint_sequence"][3]
        self.assertEqual(gate["state"], "CURRENT_DECISION_RECORDED_PENDING_CONTROL_REVIEW")
        self.assertEqual(gate["decision"], "ACTIVATE_V0_SM1")
        routing = self.scheduler["v0_product_train_routing"]
        self.assertEqual(routing["current_checkpoint"], "V0_POST_P6_SEAMLESS_INSERTION_GATE")
        self.assertEqual(routing["current_phase"], "POST_P6_SM1_ACTIVATION_CONTROL_CANDIDATE")
        self.assertFalse(routing["runtime_mutation_allowed_now"])
        self.assertEqual(routing["post_p6_decision"]["decision"], "ACTIVATE_V0_SM1")

    def test_sm1_activation_candidate_uses_exact_accepted_p6_base(self) -> None:
        expected = "9ade3233f8d9f16b77edcc8cf273fe8e649d5637"
        self.assertEqual(self.activation_sm1["checkpoint"], "V0_SM1_SEAMLESS_PRODUCT_INTEGRATION")
        self.assertEqual(self.activation_sm1["main_declared_exact_successor_base"], expected)
        self.assertEqual(self.activation_sm1["accepted_predecessor"]["accepted_product_lineage_head"], expected)
        self.assertFalse(self.activation_sm1["mutation_lease"]["runtime_mutation_authorized"])
        self.assertEqual(self.epoch_sm1["base_sha"], expected)
        self.assertEqual(self.epoch_sm1["eligible_checkpoints"], ["V0_SM1_SEAMLESS_PRODUCT_INTEGRATION"])
        self.assertEqual(self.epoch_sm1["status"], "ACTIVE")
        self.assertEqual(self.work_order_sm1["goal_checkpoint"], "V0_SM1_SEAMLESS_PRODUCT_INTEGRATION")
        self.assertEqual(self.work_order_sm1["base_sha"], expected)
        self.assertEqual(self.work_order_sm1["branch"], "feature/v0-sm1-seamless-product-integration")
        self.assertEqual(self.work_order_sm1["risk_class"], "CRITICAL")
        event_dir = HARNESS / "executions/E2026-08-24-V0-SM1-R1/events/V0-SM1-R1-WO-001"
        self.assertEqual(self.work_order_sm1["state"], _latest_work_state(event_dir))

    def test_sm1_runtime_is_fail_closed_until_remaining_control_gates(self) -> None:
        sm1 = self.policy["checkpoint_sequence"][4]
        self.assertEqual(sm1["state"], "ACTIVATION_CANDIDATE_NOT_RUNTIME_ELIGIBLE")
        self.assertIn("DIRECTOR_DISPATCH", sm1["activation_complete_except"])
        self.assertIn(
            "EG5_TELEMETRY_HYSTERESIS_REPAIR_REVIEWED_OR_EXPLICITLY_NON_BLOCKING",
            sm1["activation_complete_except"],
        )
        routing = self.scheduler["v0_product_train_routing"]
        self.assertFalse(routing["next_runtime_checkpoint_eligible"])
        self.assertIn("DIRECTOR_DISPATCH", routing["sm1_remaining_activation_prerequisites"])
        self.assertIn("MUTATION_LEASE_ROTATED_TO_SM1", routing["sm1_remaining_activation_prerequisites"])

    def test_runtime_mutation_lease_is_free_after_p6_not_silently_granted_to_sm1(self) -> None:
        lease = self.scheduler["pre_h0_3_runtime_mutation_lease"]
        self.assertEqual(lease["capacity"], 1)
        self.assertEqual(lease["holder_checkpoint"], "NONE")
        self.assertEqual(lease["holder_branch"], "NONE")
        self.assertEqual(lease["state"], "FREE_CONTROL_ONLY_AWAITING_SM1_ACTIVATION")
        self.assertEqual(lease["proposed_next_holder_checkpoint"], "V0_SM1_SEAMLESS_PRODUCT_INTEGRATION")
        self.assertEqual(lease["proposed_next_holder_branch"], "feature/v0-sm1-seamless-product-integration")
        self.assertTrue(lease["successor_rotation_requires_predecessor_checkpoint_acceptance"])

    def test_historical_p5_and_p6_execution_snapshots_still_match_events(self) -> None:
        p5_events = HARNESS / "executions/E2026-08-18-V0-P5-R1/events/V0-P5-R1-WO-001"
        p6_events = HARNESS / "executions/E2026-08-23-V0-P6-R2/events/V0-P6-R2-WO-001"
        self.assertEqual(self.work_order_p5["state"], _latest_work_state(p5_events))
        self.assertEqual(self.work_order_p6["state"], _latest_work_state(p6_events))
        self.assertEqual(
            self.catalog["checkpoints"]["V0_P6_PERSISTENT_SHARED_OUTPOST"]["required_predicates"],
            self.work_order_p6["required_predicates"],
        )

    def test_product_checkpoints_and_future_eligibility_are_exact(self) -> None:
        self.assertEqual(
            self.scheduler["parallel_product_checkpoints"]["checkpoints"],
            ["V0_POST_P6_SEAMLESS_INSERTION_GATE"],
        )
        self.assertEqual(
            set(self.scheduler["parallel_product_checkpoints"]["future_checkpoints_not_yet_eligible"]),
            {
                "V0_SM1_SEAMLESS_PRODUCT_INTEGRATION",
                "V0_P7_BOUNDED_TERRAIN_MUTATION",
                "V0_P8_FIRST_MOBILE_CONSTRUCT",
            },
        )
        self.assertEqual(self.sm1_plan["accepted_p6_product_base"], "9ade3233f8d9f16b77edcc8cf273fe8e649d5637")
        self.assertEqual(self.sm1_plan["risk_class"], "CRITICAL")

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
        self.assertIn("SM0", self.policy["checkpoint_sequence"][4]["donors_are_not_product_bases"])

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
