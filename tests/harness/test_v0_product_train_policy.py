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
        self.assertTrue(
            principles[
                "research_becomes_product_blocking_only_via_explicit_registered_dependency_or_proven_ownership_watch_intersection"
            ]
        )

    def test_current_runtime_checkpoint_is_p4_closure_only(self) -> None:
        self.assertEqual(self.policy["current_checkpoint"], "V0_P4_REAL_RESOURCE_CONSTRUCTION")
        self.assertEqual(self.policy["current_phase"], "P4_IMPLEMENTED_VERIFIED_CLOSURE_CONTROL")
        routing = self.scheduler["v0_product_train_routing"]
        self.assertEqual(routing["current_checkpoint"], "V0_P4_REAL_RESOURCE_CONSTRUCTION")
        self.assertEqual(routing["current_phase"], "CLOSURE_CONTROL_ONLY")
        self.assertFalse(routing["runtime_mutation_allowed_now"])
        self.assertFalse(routing["next_runtime_checkpoint_eligible"])

    def test_future_product_checkpoints_are_plans_not_current_catalog_permissions(self) -> None:
        catalog = self.catalog["checkpoints"]
        self.assertIn("V0_P4_REAL_RESOURCE_CONSTRUCTION", catalog)
        future = {
            "V0_P5_EQUIPMENT_TOOLS",
            "V0_P6_PERSISTENT_SHARED_OUTPOST",
            "V0_SM1_SEAMLESS_PRODUCT_INTEGRATION",
            "V0_P7_BOUNDED_TERRAIN_MUTATION",
            "V0_P8_FIRST_MOBILE_CONSTRUCT",
        }
        self.assertTrue(future.isdisjoint(catalog))
        self.assertEqual(
            set(self.scheduler["parallel_product_checkpoints"]["future_checkpoints_not_yet_eligible"]),
            future,
        )
        self.assertEqual(
            self.scheduler["parallel_product_checkpoints"]["checkpoints"],
            ["V0_P4_REAL_RESOURCE_CONSTRUCTION"],
        )

    def test_sequence_requires_p4_then_p5_then_p6_then_seamless_decision(self) -> None:
        ids = [item["id"] for item in self.policy["checkpoint_sequence"]]
        required_order = [
            "V0_P4_REAL_RESOURCE_CONSTRUCTION",
            "V0_P5_EQUIPMENT_TOOLS",
            "V0_P6_PERSISTENT_SHARED_OUTPOST",
            "V0_POST_P6_SEAMLESS_INSERTION_GATE",
            "V0_SM1_SEAMLESS_PRODUCT_INTEGRATION",
            "V0_P7_BOUNDED_TERRAIN_MUTATION",
            "V0_P8_FIRST_MOBILE_CONSTRUCT",
        ]
        self.assertEqual(ids, required_order)
        self.assertEqual(len(ids), len(set(ids)))
        p5 = self.policy["checkpoint_sequence"][1]
        p6 = self.policy["checkpoint_sequence"][2]
        self.assertEqual(p5["state"], "PLANNED_NOT_ELIGIBLE")
        self.assertIn("V0_P4_CHECKPOINT_ACCEPTED", p5["activation_requires"])
        self.assertEqual(p6["state"], "PLANNED_NOT_ELIGIBLE")
        self.assertIn("V0_P5_CHECKPOINT_ACCEPTED", p6["activation_requires"])

    def test_scheduler_lease_fails_closed_on_p4_until_explicit_rotation(self) -> None:
        lease = self.scheduler["pre_h0_3_runtime_mutation_lease"]
        self.assertEqual(lease["capacity"], 1)
        self.assertEqual(lease["holder_program"], "V0")
        self.assertEqual(lease["holder_checkpoint"], "V0_P4_REAL_RESOURCE_CONSTRUCTION")
        self.assertEqual(
            lease["state"],
            "RESERVED_FOR_V0_P4_CLOSURE_NO_ACTIVE_RUNTIME_MUTATION",
        )
        self.assertTrue(lease["implementation_complete_releases_worker"])
        self.assertTrue(lease["successor_rotation_requires_predecessor_checkpoint_acceptance"])
        self.assertTrue(lease["release_requires_main_owned_control_update"])

    def test_eco_is_explicitly_non_blocking_without_real_dependency(self) -> None:
        isolation = self.policy["research_isolation"]
        self.assertTrue(isolation["research_frontiers_are_non_blocking_by_default"])
        self.assertIn("ECO", isolation["explicitly_non_blocking_programs_for_current_p_train"])
        self.assertEqual(self.scheduler["research_isolation"]["current_explicit_non_blocker"], "ECO")
        self.assertTrue(self.scheduler["research_isolation"]["non_blocking_by_default"])
        self.assertEqual(
            self.scheduler["escalation"]["research_branch_red_without_registered_product_dependency"],
            "DO_NOT_BLOCK_V0_PRODUCT_TRAIN",
        )

    def test_project_goal_graph_exposes_same_product_order(self) -> None:
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

    def test_current_p4_closure_route_is_runtime_frozen(self) -> None:
        closure = self.policy["current_p4_closure_route"]
        self.assertEqual(closure["runtime_target"], "2a6721cdf02fa1134c59d1ab98bb7b597c66821d")
        self.assertEqual(closure["runtime_mutation"], "FROZEN")
        self.assertEqual(closure["control_repair_pr"], 127)
        self.assertEqual(closure["live_frontier_routing_repair_merged_pr"], 130)
        self.assertIn(
            "PROPOSE_AND_ACCEPT_P4_CHECKPOINT_BEFORE_ANY_P5_RUNTIME_DISPATCH",
            closure["required_next_control_steps"],
        )


if __name__ == "__main__":
    unittest.main()
