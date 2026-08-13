from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "control"))

import project_control as pc


R2 = "GLOBAL-P0-2026-08-10-R2"
R3 = "GLOBAL-P0-2026-08-12-R3-REFRESH-R1"
POLICY = {
    "passport_architecture_compatibility": {
        "mode": "EXPLICIT_PER_PROGRAM_HISTORICAL_ALLOWLIST",
        "central_registry_field": "historical_passport_architecture_revisions",
    }
}


class ProjectControlArchitectureCompatibilityTests(unittest.TestCase):
    def test_exact_revision_passes_without_exception_policy(self):
        decision = pc.evaluate_passport_architecture_compatibility(
            {}, {"architecture_revision": R2}, {"architecture_revision": R2}, {}
        )
        self.assertTrue(decision["compatible"])
        self.assertEqual("EXACT_CANONICAL_REVISION", decision["mode"])

    def test_mismatch_stays_fail_closed_when_policy_not_enabled(self):
        decision = pc.evaluate_passport_architecture_compatibility(
            {"historical_passport_architecture_revisions": [R2]},
            {"architecture_revision": R3},
            {"architecture_revision": R2},
            {},
        )
        self.assertFalse(decision["compatible"])
        self.assertEqual("STRICT_MISMATCH_POLICY_NOT_ENABLED", decision["mode"])

    def test_explicit_historical_allowlist_accepts_exact_old_revision(self):
        decision = pc.evaluate_passport_architecture_compatibility(
            {"historical_passport_architecture_revisions": [R2]},
            {"architecture_revision": R3},
            {"architecture_revision": R2},
            POLICY,
        )
        self.assertTrue(decision["compatible"])
        self.assertEqual("EXPLICIT_HISTORICAL_REVISION_ALLOWED", decision["mode"])

    def test_unlisted_historical_revision_remains_blocking(self):
        decision = pc.evaluate_passport_architecture_compatibility(
            {"historical_passport_architecture_revisions": []},
            {"architecture_revision": R3},
            {"architecture_revision": R2},
            POLICY,
        )
        self.assertFalse(decision["compatible"])
        self.assertEqual("STRICT_MISMATCH_NOT_ALLOWLISTED", decision["mode"])

    def test_malformed_allowlist_fails_closed(self):
        decision = pc.evaluate_passport_architecture_compatibility(
            {"historical_passport_architecture_revisions": R2},
            {"architecture_revision": R3},
            {"architecture_revision": R2},
            POLICY,
        )
        self.assertFalse(decision["compatible"])
        self.assertEqual("STRICT_MISMATCH_MALFORMED_ALLOWLIST", decision["mode"])

    def test_health_recompute_never_hides_other_red_finding(self):
        result = {
            "health_declared": "GREEN",
            "health": "RED",
            "findings": [
                {"level": "RED", "code": "OTHER_RED", "detail": "still blocking"},
            ],
        }
        pc._recompute_health(result)
        self.assertEqual("RED", result["health"])

    def test_health_recompute_drops_to_remaining_yellow_after_compatibility(self):
        result = {
            "health_declared": "GREEN",
            "health": "RED",
            "findings": [
                {"level": "YELLOW", "code": "OTHER_YELLOW", "detail": "review"},
            ],
        }
        pc._recompute_health(result)
        self.assertEqual("YELLOW", result["health"])


if __name__ == "__main__":
    unittest.main()
