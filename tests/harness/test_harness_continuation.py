from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from harness.continuation import build_continuation

POLICY = {
    "review_evidence_sinks": {
        "default_harness_work_order": "EXECUTION_LEDGER",
        "github_pr_gate": "GITHUB_PR_REVIEW",
        "chat": "FORBIDDEN_AS_AUTHORITY",
    },
    "self_closing_execution": {
        "max_same_defect_fix_required_events_before_takeover": 3,
        "same_role_recoverable_findings": ["REPAIR_MAP_REQUIRED"],
    },
}


def state() -> dict:
    return {
        "active_work_order": {
            "work_order_id": "WO-1",
            "goal_checkpoint": "CP-1",
            "review_required": True,
        },
        "reduced_work_order": {"state": "IMPLEMENTED"},
        "review": {
            "post_build_state": "MISSING",
            "review_target_head_sha": "a" * 40,
        },
        "repository": {"implementation_head_sha": "a" * 40},
        "human_attention": {"open_items": []},
        "findings": [],
        "checkpoint_blockers": [
            "POST_BUILD_REVIEW_NOT_FRESH_PASS",
            "EVIDENCE_MAP_MISSING",
        ],
        "checkpoint_proposal_blocked": True,
        "repair": {
            "same_defect_fix_required_count": 0,
            "escalation_required": False,
        },
    }


class HarnessContinuationTests(unittest.TestCase):
    def test_missing_review_is_role_boundary_not_human_stop(self):
        result = build_continuation(state(), POLICY)
        self.assertEqual("ROLE_BOUNDARY", result["handoff_class"])
        self.assertEqual("REVIEWER", result["next_actor"])
        self.assertFalse(result["human_decision_required"])
        self.assertFalse(result["mission_complete"])
        self.assertTrue(result["session_exit_allowed"])

    def test_chat_only_pass_does_not_authorize_transition(self):
        value = state()
        value["chat_review_verdict"] = "PASS"
        result = build_continuation(value, POLICY)
        self.assertEqual("REVIEWER", result["next_actor"])
        self.assertIn("DURABLE_REVIEW_PASS", result["resume_condition"])

    def test_pr_handoff_can_require_github_review_sink(self):
        value = state()
        value["active_work_order"]["handoff"] = {
            "review_evidence_sink": "GITHUB_PR_REVIEW"
        }
        self.assertEqual(
            "GITHUB_PR_REVIEW",
            build_continuation(value, POLICY)["evidence_sink"],
        )

    def test_stale_review_routes_back_to_reviewer(self):
        value = state()
        value["review"]["post_build_state"] = "STALE"
        self.assertEqual("REVIEWER", build_continuation(value, POLICY)["next_actor"])

    def test_review_fail_routes_to_implementer_not_reviewer(self):
        value = state()
        value["review"]["post_build_state"] = "FAIL"
        result = build_continuation(value, POLICY)
        self.assertEqual("ROLE_BOUNDARY", result["handoff_class"])
        self.assertEqual("IMPLEMENTER", result["next_actor"])
        self.assertEqual(
            "CONSUME_REVIEW_FINDINGS_AND_EXECUTE_REPAIR_CLOSURE_LOOP",
            result["next_action"],
        )

    def test_insufficient_evidence_routes_to_exact_gap_ownership(self):
        value = state()
        value["review"]["post_build_state"] = "INSUFFICIENT_EVIDENCE"
        result = build_continuation(value, POLICY)
        self.assertEqual("DIRECTOR", result["next_actor"])
        self.assertEqual(
            "ROUTE_EXACT_EVIDENCE_GAPS_TO_OWNING_ROLE",
            result["next_action"],
        )

    def test_fix_required_without_repair_map_continues_same_role(self):
        value = state()
        value["reduced_work_order"]["state"] = "FIX_REQUIRED"
        value["findings"] = ["REPAIR_MAP_REQUIRED"]
        result = build_continuation(value, POLICY)
        self.assertEqual("CONTINUE_SAME_ROLE", result["handoff_class"])
        self.assertEqual("IMPLEMENTER", result["next_actor"])
        self.assertEqual("EXECUTE_REPAIR_TEST_CLOSURE_LOOP", result["next_action"])
        self.assertFalse(result["session_exit_allowed"])
        self.assertTrue(result["closure_loop_required"])

    def test_fix_required_with_repair_map_still_continues_same_role(self):
        value = state()
        value["reduced_work_order"]["state"] = "FIX_REQUIRED"
        result = build_continuation(value, POLICY)
        self.assertEqual("CONTINUE_SAME_ROLE", result["handoff_class"])
        self.assertFalse(result["session_exit_allowed"])

    def test_same_defect_takeover_threshold_routes_to_director(self):
        value = state()
        value["reduced_work_order"]["state"] = "FIX_REQUIRED"
        value["repair"]["same_defect_fix_required_count"] = 3
        result = build_continuation(value, POLICY)
        self.assertEqual("ROLE_BOUNDARY", result["handoff_class"])
        self.assertEqual("DIRECTOR", result["next_actor"])
        self.assertEqual(
            "ESCALATE_REPEATED_DEFECT_FOR_TAKEOVER",
            result["next_action"],
        )
        self.assertTrue(result["session_exit_allowed"])

    def test_review_pass_then_missing_evidence_routes_to_director(self):
        value = state()
        value["review"]["post_build_state"] = "PASS"
        value["checkpoint_blockers"] = ["EVIDENCE_MAP_MISSING"]
        result = build_continuation(value, POLICY)
        self.assertEqual("DIRECTOR", result["next_actor"])
        self.assertEqual(
            "INGEST_DURABLE_REVIEW_AND_REFRESH_EVIDENCE_MAP",
            result["next_action"],
        )

    def test_missing_predicates_route_to_verifier(self):
        value = state()
        value["review"]["post_build_state"] = "PASS"
        value["checkpoint_blockers"] = ["REQUIRED_PREDICATES_INCOMPLETE"]
        self.assertEqual("VERIFIER", build_continuation(value, POLICY)["next_actor"])

    def test_blocking_human_attention_is_real_human_gate(self):
        value = state()
        value["human_attention"]["open_items"] = [{"blocking": True}]
        result = build_continuation(value, POLICY)
        self.assertEqual("HUMAN_DECISION_REQUIRED", result["handoff_class"])
        self.assertEqual("HUMAN", result["next_actor"])
        self.assertTrue(result["session_exit_allowed"])

    def test_system_finding_routes_to_director_and_keeps_mission_open(self):
        value = state()
        value["findings"] = ["MAIN_MOVED_REVIEW_REQUIRED"]
        result = build_continuation(value, POLICY)
        self.assertEqual("SYSTEM_BLOCKED", result["handoff_class"])
        self.assertEqual("DIRECTOR", result["next_actor"])
        self.assertFalse(result["mission_complete"])

    def test_blocked_state_is_not_same_role_autorepair(self):
        value = state()
        value["reduced_work_order"]["state"] = "BLOCKED"
        result = build_continuation(value, POLICY)
        self.assertEqual("SYSTEM_BLOCKED", result["handoff_class"])
        self.assertEqual("DIRECTOR", result["next_actor"])
        self.assertTrue(result["session_exit_allowed"])

    def test_ready_local_work_routes_to_director_not_mission_complete(self):
        value = state()
        value["review"]["post_build_state"] = "PASS"
        value["checkpoint_blockers"] = []
        value["checkpoint_proposal_blocked"] = False
        result = build_continuation(value, POLICY)
        self.assertEqual("DIRECTOR", result["next_actor"])
        self.assertFalse(result["mission_complete"])

    def test_declared_parent_mission_survives_role_boundary(self):
        value = state()
        value["active_work_order"]["mission"] = {
            "mission_id": "MISSION-ROOT",
            "objective": "Restore main and resume P4",
            "parent_mission_id": "PROJECT-V0",
            "completion_condition": "MAIN_NON_RED_AND_P4_RESUMED",
        }
        result = build_continuation(value, POLICY)
        self.assertEqual("MISSION-ROOT", result["mission_id"])
        self.assertEqual("PROJECT-V0", result["parent_mission_id"])


if __name__ == "__main__":
    unittest.main()
