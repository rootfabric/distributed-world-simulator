from __future__ import annotations

import copy
import json
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
LEGACY_R2_PROGRAMS_AT_R3_PROMOTION = {"G", "ECO", "T", "CH", "DOCTRINE", "NX"}


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

    def _load_json(self, relative: str) -> dict:
        return json.loads((ROOT / relative).read_text(encoding="utf-8"))

    def _synthetic_r3_inputs(self):
        registry = copy.deepcopy(self._load_json("config/control/project-program-registry.v1.json"))
        policy = copy.deepcopy(self._load_json("config/control/project-control-policy.v1.json"))
        ownership = copy.deepcopy(self._load_json("config/control/architecture-ownership.v1.json"))
        registry["architecture_revision"] = R3
        policy["architecture_revision"] = R3
        ownership["architecture_revision"] = R3
        for key in LEGACY_R2_PROGRAMS_AT_R3_PROMOTION:
            registry["programs"][key]["historical_passport_architecture_revisions"] = [R2]
        return registry, policy, ownership

    def test_live_registered_r2_passports_survive_synthetic_r3_with_explicit_allowlists(self):
        registry, policy, ownership = self._synthetic_r3_inputs()
        results = []
        seen_legacy = set()
        for key, central in registry["programs"].items():
            if not isinstance(central, dict):
                continue
            branch = str(central.get("branch", ""))
            passport_path = str(central.get("passport_path", ""))
            if branch and passport_path:
                passport = pc._core.load_branch_json(pc._core.remote_ref(branch), passport_path)
                if passport and str(passport.get("architecture_revision", "")) == R2:
                    self.assertIn(key, LEGACY_R2_PROGRAMS_AT_R3_PROMOTION, (key, branch, passport_path))
                    seen_legacy.add(key)
            result = pc.audit_program(key, central, registry, policy, ownership)
            results.append(result)
            if key in LEGACY_R2_PROGRAMS_AT_R3_PROMOTION and result.get("passport_loaded"):
                self.assertFalse(
                    any(f.get("code") == "ARCHITECTURE_REVISION_MISMATCH" for f in result.get("findings", [])),
                    (key, result.get("findings")),
                )
                self.assertEqual(
                    "EXPLICIT_HISTORICAL_REVISION_ALLOWED",
                    result.get("architecture_compatibility", {}).get("mode"),
                    key,
                )

        self.assertEqual(LEGACY_R2_PROGRAMS_AT_R3_PROMOTION, seen_legacy)
        blocking_health = "GREEN"
        for result in results:
            if not result.get("blocks_global_progress", True):
                continue
            if pc.HEALTH_RANK.get(result.get("health", "GREEN"), 0) > pc.HEALTH_RANK[blocking_health]:
                blocking_health = result["health"]
        self.assertNotEqual("RED", blocking_health, [(r["program"], r["health"], r.get("findings")) for r in results])

    def test_live_g_passport_becomes_red_again_when_allowlist_is_removed(self):
        registry, policy, ownership = self._synthetic_r3_inputs()
        central = registry["programs"]["G"]
        central.pop("historical_passport_architecture_revisions", None)
        result = pc.audit_program("G", central, registry, policy, ownership)
        self.assertEqual("RED", result["health"])
        self.assertTrue(
            any(f.get("code") == "ARCHITECTURE_REVISION_MISMATCH" for f in result.get("findings", [])),
            result.get("findings"),
        )


if __name__ == "__main__":
    unittest.main()
