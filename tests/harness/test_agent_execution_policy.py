from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness.agent_execution_policy import (
    AgentExecutionPolicyError,
    evaluate_execution_slice,
    load_profile_config,
    resolve_profile,
)


class AgentExecutionPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config = load_profile_config(ROOT)

    @staticmethod
    def _state(
        state_name: str = "VERIFIED",
        *,
        dirty: bool = False,
        findings: list[str] | None = None,
    ) -> dict:
        return {
            "repository": {"worktree_dirty": dirty},
            "findings": findings or [],
            "reduced_work_order": {"state": state_name},
        }

    @staticmethod
    def _continuation(
        *,
        next_actor: str = "REVIEWER",
        next_action: str = "PERSIST_FRESH_EXACT_HEAD_REVIEW",
        role_exit_allowed: bool = True,
        handoff_class: str = "ROLE_BOUNDARY",
        mission_exit_allowed: bool = False,
    ) -> dict:
        return {
            "next_actor": next_actor,
            "next_action": next_action,
            "role_exit_allowed": role_exit_allowed,
            "handoff_class": handoff_class,
            "mission_exit_allowed": mission_exit_allowed,
        }

    def test_config_is_valid_and_default_profile_exists(self) -> None:
        self.assertEqual(
            "distributed_world_simulator.agent_execution_profiles.v1",
            self.config["schema"],
        )
        self.assertIn(self.config["default_profile"], self.config["profiles"])

    def test_bounded_profile_recommends_yield_at_clean_role_boundary(self) -> None:
        result = evaluate_execution_slice(
            self._state(),
            self._continuation(),
            self.config,
            "BOUNDED_DEEP_REASONING",
        )
        self.assertTrue(result["session_yield_allowed"])
        self.assertTrue(result["session_yield_recommended"])
        self.assertTrue(result["mission_remains_open"])
        self.assertTrue(result["resume_required"])
        self.assertFalse(result["immediate_continue_required"])

    def test_long_horizon_profile_continues_at_same_clean_role_boundary(self) -> None:
        result = evaluate_execution_slice(
            self._state(),
            self._continuation(),
            self.config,
            "LONG_HORIZON_CONTINUOUS",
        )
        self.assertTrue(result["session_yield_allowed"])
        self.assertFalse(result["session_yield_recommended"])
        self.assertTrue(result["immediate_continue_required"])
        self.assertTrue(result["mission_remains_open"])

    def test_dirty_worktree_fails_closed_for_nonterminal_yield(self) -> None:
        result = evaluate_execution_slice(
            self._state(dirty=True),
            self._continuation(),
            self.config,
            "BOUNDED_DEEP_REASONING",
        )
        self.assertFalse(result["session_yield_allowed"])
        self.assertFalse(result["session_yield_recommended"])
        self.assertEqual("WORKTREE_DIRTY", result["reason"])

    def test_wrong_work_order_branch_fails_closed(self) -> None:
        result = evaluate_execution_slice(
            self._state(findings=["WORK_ORDER_BRANCH_NOT_CHECKED_OUT"]),
            self._continuation(),
            self.config,
            "BOUNDED_DEEP_REASONING",
        )
        self.assertFalse(result["session_yield_allowed"])
        self.assertEqual("WRONG_WORK_ORDER_BRANCH", result["reason"])

    def test_bounded_profile_can_yield_during_clean_verifying_state(self) -> None:
        result = evaluate_execution_slice(
            self._state("VERIFYING"),
            self._continuation(
                next_actor="VERIFIER",
                next_action="CONTINUE_VERIFICATION_UNTIL_PREDICATES_COMPLETE",
                role_exit_allowed=False,
                handoff_class="CONTINUE_SAME_ROLE",
            ),
            self.config,
            "BOUNDED_DEEP_REASONING",
        )
        self.assertTrue(result["session_yield_allowed"])
        self.assertTrue(result["session_yield_recommended"])
        self.assertTrue(result["mission_remains_open"])

    def test_external_pending_forces_yield_even_for_long_horizon_profile(self) -> None:
        result = evaluate_execution_slice(
            self._state("VERIFYING"),
            self._continuation(
                next_actor="VERIFIER",
                next_action="CONTINUE_VERIFICATION_UNTIL_PREDICATES_COMPLETE",
                role_exit_allowed=False,
                handoff_class="CONTINUE_SAME_ROLE",
            ),
            self.config,
            "LONG_HORIZON_CONTINUOUS",
            external_pending=True,
            external_ref="github-actions:34002352572",
        )
        self.assertTrue(result["session_yield_allowed"])
        self.assertTrue(result["session_yield_recommended"])
        self.assertEqual("EXTERNAL_DEPENDENCY_PENDING", result["reason"])
        self.assertEqual("github-actions:34002352572", result["external_ref"])

    def test_external_pending_does_not_override_dirty_worktree(self) -> None:
        result = evaluate_execution_slice(
            self._state("VERIFYING", dirty=True),
            self._continuation(
                next_actor="VERIFIER",
                next_action="CONTINUE_VERIFICATION_UNTIL_PREDICATES_COMPLETE",
                role_exit_allowed=False,
                handoff_class="CONTINUE_SAME_ROLE",
            ),
            self.config,
            "LONG_HORIZON_CONTINUOUS",
            external_pending=True,
        )
        self.assertFalse(result["session_yield_allowed"])
        self.assertEqual("EXTERNAL_PENDING_BUT_WORKTREE_DIRTY", result["reason"])

    def test_final_acceptance_evaluation_is_not_recommended_as_yield(self) -> None:
        result = evaluate_execution_slice(
            self._state(),
            self._continuation(
                next_actor="DIRECTOR",
                next_action="EVALUATE_CHECKPOINT_ACCEPTANCE_OR_REQUIRED_HUMAN_GATE",
            ),
            self.config,
            "BOUNDED_DEEP_REASONING",
        )
        self.assertTrue(result["session_yield_allowed"])
        self.assertFalse(result["session_yield_recommended"])
        self.assertTrue(result["immediate_continue_required"])

    def test_resume_requires_progress_before_normal_reyield(self) -> None:
        result = evaluate_execution_slice(
            self._state(),
            self._continuation(),
            self.config,
            "BOUNDED_DEEP_REASONING",
            resumed=True,
        )
        self.assertTrue(result["session_yield_allowed"])
        self.assertFalse(result["session_yield_recommended"])
        self.assertTrue(result["resume_requires_progress_before_reyield"])
        self.assertEqual(
            "RESUME_REQUIRES_PROGRESS_BEFORE_REEVALUATING_YIELD",
            result["reason"],
        )

    def test_mission_terminal_always_allows_session_exit(self) -> None:
        result = evaluate_execution_slice(
            self._state(dirty=True),
            self._continuation(mission_exit_allowed=True),
            self.config,
            "BOUNDED_DEEP_REASONING",
        )
        self.assertTrue(result["session_yield_allowed"])
        self.assertTrue(result["session_yield_recommended"])
        self.assertFalse(result["mission_remains_open"])
        self.assertFalse(result["resume_required"])

    def test_unknown_profile_fails_closed(self) -> None:
        with self.assertRaises(AgentExecutionPolicyError):
            resolve_profile(self.config, "UNKNOWN_PROFILE")


if __name__ == "__main__":
    unittest.main()
