from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness.continuation import build_continuation


def current_policy() -> dict:
    return json.loads(
        (ROOT / "config/control/harness/continuation-policy.v1.json").read_text(encoding="utf-8")
    )


def blocked_state(proof: dict) -> dict:
    return {
        "active_work_order": {
            "work_order_id": "AUTONOMY-RUNTIME-TEST",
            "goal_checkpoint": "V0_P5_EQUIPMENT_TOOLS",
            "work_order_type": "CONTROL",
            "review_required": False,
        },
        "reduced_work_order": {"state": "BLOCKED", "work_order_id": "AUTONOMY-RUNTIME-TEST"},
        "review": {"post_build_state": "PASS"},
        "repository": {"implementation_head_sha": "a" * 40},
        "checkpoint_blockers": [],
        "findings": [],
        "repair": {"same_defect_fix_required_count": 0},
        "human_attention": {"open_items": []},
        "checkpoint_acceptance": None,
        "hard_block_proof": proof,
    }


class AutonomousRuntimeRoutingTests(unittest.TestCase):
    def complete_proof(self) -> dict:
        return {
            "proven_non_automatable": True,
            "required_capability_mandatory": True,
            "automation_fallbacks_exhausted": True,
            "scope_preserving_recovery_exhausted": True,
            "proof_evidence_path": "docs/control/evidence/HARD-BLOCK-001.v1.json",
            "resume_condition": "REQUIRED_EXTERNAL_CAPABILITY_AVAILABLE",
        }

    def test_current_policy_rejects_legacy_flag_only(self) -> None:
        result = build_continuation(
            blocked_state({"proven_non_automatable": True, "resume_condition": "SOMETHING_CHANGED"}),
            current_policy(),
        )
        self.assertFalse(result["hard_blocked"])
        self.assertFalse(result["mission_exit_allowed"])
        self.assertEqual("DIAGNOSE_BLOCKER_AND_ROUTE_AUTOMATABLE_RECOVERY", result["next_action"])

    def test_current_policy_requires_every_declared_proof_clause(self) -> None:
        proof = self.complete_proof()
        for field in (
            "required_capability_mandatory",
            "automation_fallbacks_exhausted",
            "scope_preserving_recovery_exhausted",
            "proof_evidence_path",
            "resume_condition",
        ):
            with self.subTest(field=field):
                candidate = dict(proof)
                candidate.pop(field)
                result = build_continuation(blocked_state(candidate), current_policy())
                self.assertFalse(result["hard_blocked"], result)
                self.assertFalse(result["mission_exit_allowed"], result)

    def test_current_policy_accepts_only_exhaustive_durable_proof(self) -> None:
        result = build_continuation(blocked_state(self.complete_proof()), current_policy())
        self.assertTrue(result["hard_blocked"])
        self.assertTrue(result["mission_exit_allowed"])
        self.assertEqual("SYSTEM_BLOCKED", result["handoff_class"])

    def test_unknown_policy_requirement_fails_closed(self) -> None:
        policy = current_policy()
        policy["autonomous_execution"]["hard_block_requires"].append("FUTURE_REQUIREMENT")
        result = build_continuation(blocked_state(self.complete_proof()), policy)
        self.assertFalse(result["hard_blocked"])
        self.assertFalse(result["mission_exit_allowed"])


if __name__ == "__main__":
    unittest.main()
