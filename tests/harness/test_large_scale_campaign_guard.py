from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
POLICY = ROOT / "config/control/harness/continuation-policy.v1.json"


class LargeScaleCampaignGuardTests(unittest.TestCase):
    def setUp(self) -> None:
        self.policy = json.loads(POLICY.read_text(encoding="utf-8"))
        self.guard = self.policy["large_scale_campaign_guard"]

    def test_scale_cases_are_durable_predicates(self) -> None:
        self.assertEqual("H0-SCALE-SHARD-2026-09-06-R1", self.policy["scale_campaign_guard_revision"])
        self.assertEqual("SCALE_SHARDED_DURABLE_CASES", self.guard["mode"])
        self.assertTrue(self.guard["required_scale_cases_are_independent_predicates"])
        self.assertTrue(self.guard["publish_case_result_before_next_case"])
        self.assertTrue(self.guard["same_source_and_runtime_identity_required_across_cases"])

    def test_timeout_never_reduces_required_scale(self) -> None:
        self.assertTrue(self.guard["required_scale_must_not_be_reduced_after_timeout"])
        self.assertTrue(self.guard["do_not_restart_prior_green_cases_after_later_timeout"])
        self.assertTrue(self.guard["profile_only_the_timed_out_case"])
        self.assertIn("KEEP_REQUIRED_SCALE_UNCHANGED", self.guard["on_case_timeout"])
        self.assertIn("CHANGE_STRATEGY_BEFORE_SECOND_RETRY", self.guard["on_case_timeout"])

    def test_exact_predecessor_reuse_is_identity_bound(self) -> None:
        reuse = self.guard["unchanged_predecessor_evidence_reuse"]
        self.assertTrue(reuse["allowed"])
        self.assertTrue(reuse["requires_blob_identity_for_runtime_and_tests"])
        self.assertTrue(reuse["must_cite_original_exact_evidence"])
        self.assertTrue(reuse["must_not_claim_reused_evidence_as_current_execution"])


if __name__ == "__main__":
    unittest.main()
