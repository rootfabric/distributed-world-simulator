from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
POLICY = ROOT / "config/control/harness/continuation-policy.v1.json"


class SessionStallGuardTests(unittest.TestCase):
    def setUp(self) -> None:
        self.policy = json.loads(POLICY.read_text(encoding="utf-8"))
        self.guard = self.policy["session_stall_guard"]

    def test_bounded_durable_slice_contract(self) -> None:
        self.assertEqual("H0-STALL-GUARD-2026-09-06-R1", self.policy["session_stall_guard_revision"])
        self.assertEqual("BOUNDED_DURABLE_SLICES", self.guard["mode"])
        self.assertEqual(0, self.guard["max_completed_predicates_kept_only_in_ephemeral_workspace"])
        self.assertTrue(self.guard["publish_after_each_completed_predicate"])
        self.assertTrue(self.guard["require_resume_record_before_long_followup"])
        self.assertTrue(self.guard["split_long_validation_by_runner_or_predicate"])

    def test_retry_loop_must_switch_strategy(self) -> None:
        self.assertEqual(2, self.guard["max_same_strategy_failures_before_strategy_switch"])
        self.assertTrue(self.guard["do_not_repeat_identical_observation_cycle"])
        self.assertIn("CHANGE_STRATEGY_OR_REPAIR_ROOT_CAUSE", self.guard["on_repeated_failure"])
        self.assertIn("DO_NOT_REPEAT_THE_SAME_TOOL_OR_TRANSPORT_LOOP", self.guard["on_repeated_failure"])

    def test_wait_and_workspace_loss_are_fail_forward(self) -> None:
        self.assertTrue(self.guard["do_not_wait_for_queued_ci_when_exact_local_runtime_is_available"])
        self.assertTrue(self.guard["do_not_create_background_wait_loops"])
        self.assertEqual(
            [
                "READ_LIVE_REMOTE_HEAD_ONCE",
                "REHYDRATE_FROM_DURABLE_GIT_STATE",
                "VERIFY_RUNTIME_IDENTITY",
                "RESUME_FROM_LAST_PUBLISHED_PREDICATE",
            ],
            self.guard["on_workspace_loss"],
        )
        self.assertEqual(
            ["DURABLE_PROGRESS", "STRATEGY_SWITCH_RECORDED", "HARD_BLOCK_PROVEN"],
            self.guard["slice_exit_requires_one_of"],
        )


if __name__ == "__main__":
    unittest.main()
