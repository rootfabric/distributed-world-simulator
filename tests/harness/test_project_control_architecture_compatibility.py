from __future__ import annotations

import copy
import json
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "control"))

import project_control as pc


R2 = "GLOBAL-P0-2026-08-10-R2"
R3 = "GLOBAL-P0-2026-08-12-R3-REFRESH-R1"
PROGRAM = "G"
BRANCH = "feature/g8-geomorphology"
PASSPORT_PATH = "config/control/branches/feature__g8-geomorphology.v1.json"
HEAD = "1" * 40
BLOB = "2" * 40
MOVED_HEAD = "3" * 40
OTHER_BLOB = "4" * 40
POLICY = {
    "passport_architecture_compatibility": {
        "mode": "EXPLICIT_PER_PROGRAM_HISTORICAL_ALLOWLIST",
        "central_registry_field": "historical_passport_architecture_revisions",
        "historical_identity_registry_field": "historical_passport_identities",
        "historical_identity_required_for_mismatch": True,
        "historical_identity_required_fields": [
            "program",
            "branch",
            "passport_path",
            "architecture_revision",
            "pinned_head_sha",
            "passport_blob_sha",
        ],
        "new_or_refreshed_post_promotion_frontiers_must_use_canonical_revision": True,
    }
}
LEGACY_R2_PROGRAMS_AT_R3_PROMOTION = {"G", "ECO", "T", "CH", "DOCTRINE", "NX"}


class ProjectControlArchitectureCompatibilityTests(unittest.TestCase):
    def _identity(
        self,
        *,
        program: str = PROGRAM,
        branch: str = BRANCH,
        passport_path: str = PASSPORT_PATH,
        architecture_revision: str = R2,
        pinned_head_sha: str = HEAD,
        passport_blob_sha: str = BLOB,
    ) -> dict:
        return {
            "program": program,
            "branch": branch,
            "passport_path": passport_path,
            "architecture_revision": architecture_revision,
            "pinned_head_sha": pinned_head_sha,
            "passport_blob_sha": passport_blob_sha,
        }

    def _central(self, *, identities=None) -> dict:
        return {
            "program": PROGRAM,
            "branch": BRANCH,
            "passport_path": PASSPORT_PATH,
            "historical_passport_architecture_revisions": [R2],
            "historical_passport_identities": (
                [self._identity()] if identities is None else identities
            ),
        }

    def _passport(self, *, program: str = PROGRAM, branch: str = BRANCH, revision: str = R2) -> dict:
        return {
            "program": program,
            "branch": branch,
            "architecture_revision": revision,
        }

    def _decision(
        self,
        *,
        central=None,
        registry=None,
        passport=None,
        policy=None,
        audited_program: str = PROGRAM,
        observed_branch: str = BRANCH,
        observed_passport_path: str = PASSPORT_PATH,
        observed_head_sha: str = HEAD,
        observed_passport_blob_sha: str = BLOB,
    ) -> dict:
        return pc.evaluate_passport_architecture_compatibility(
            self._central() if central is None else central,
            {"architecture_revision": R3} if registry is None else registry,
            self._passport() if passport is None else passport,
            POLICY if policy is None else policy,
            audited_program=audited_program,
            observed_branch=observed_branch,
            observed_passport_path=observed_passport_path,
            observed_head_sha=observed_head_sha,
            observed_passport_blob_sha=observed_passport_blob_sha,
        )

    def _audit_mocked(
        self,
        *,
        central=None,
        passport=None,
        policy=None,
        observed_head_sha: str = HEAD,
        observed_passport_blob_sha: str = BLOB,
        extra_findings=None,
    ) -> dict:
        central = self._central() if central is None else central
        passport = self._passport() if passport is None else passport
        findings = [
            {
                "level": "RED",
                "code": "ARCHITECTURE_REVISION_MISMATCH",
                "detail": f"passport={R2} main={R3}",
            }
        ]
        findings.extend(extra_findings or [])
        original_result = {
            "program": PROGRAM,
            "branch": BRANCH,
            "passport_loaded": True,
            "health_declared": "GREEN",
            "health": "RED",
            "findings": findings,
        }

        def fake_git(*args: str, allow_fail: bool = False) -> str:
            if args == ("rev-parse", f"origin/{BRANCH}"):
                return observed_head_sha
            if args == ("rev-parse", f"origin/{BRANCH}:{PASSPORT_PATH}"):
                return observed_passport_blob_sha
            return ""

        with (
            patch.object(pc, "_ORIGINAL_AUDIT_PROGRAM", return_value=copy.deepcopy(original_result)),
            patch.object(pc._core, "load_branch_json", return_value=copy.deepcopy(passport)),
            patch.object(pc._core, "git", side_effect=fake_git),
        ):
            return pc.audit_program(
                PROGRAM,
                copy.deepcopy(central),
                {"architecture_revision": R3},
                copy.deepcopy(POLICY if policy is None else policy),
                {},
            )

    def assert_architecture_mismatch_red(self, result: dict) -> None:
        self.assertEqual("RED", result["health"], result)
        self.assertTrue(
            any(
                isinstance(finding, dict)
                and finding.get("code") == "ARCHITECTURE_REVISION_MISMATCH"
                and finding.get("level") == "RED"
                for finding in result.get("findings", [])
            ),
            result,
        )

    # A
    def test_a_exact_canonical_match_still_succeeds(self):
        decision = self._decision(
            central={},
            registry={"architecture_revision": R2},
            passport={"architecture_revision": R2},
            policy={},
            audited_program="",
            observed_branch="",
            observed_passport_path="",
            observed_head_sha="",
            observed_passport_blob_sha="",
        )
        self.assertTrue(decision["compatible"])
        self.assertEqual("EXACT_CANONICAL_REVISION", decision["mode"])

    # B
    def test_b_mismatch_without_compatibility_policy_fails_closed(self):
        decision = self._decision(policy={})
        self.assertFalse(decision["compatible"])
        self.assertEqual("STRICT_MISMATCH_POLICY_NOT_ENABLED", decision["mode"])

    # C
    def test_c_missing_central_registry_field_fails_closed(self):
        policy = copy.deepcopy(POLICY)
        policy["passport_architecture_compatibility"].pop("central_registry_field")
        decision = self._decision(policy=policy)
        self.assertFalse(decision["compatible"])
        self.assertEqual("STRICT_MISMATCH_REVISION_POLICY_FIELD_INVALID", decision["mode"])

    # D
    def test_d_empty_central_registry_field_fails_closed(self):
        policy = copy.deepcopy(POLICY)
        policy["passport_architecture_compatibility"]["central_registry_field"] = ""
        self.assertFalse(self._decision(policy=policy)["compatible"])

    # E
    def test_e_wrong_or_non_string_central_registry_field_fails_closed(self):
        for value in ("legacy_revisions", None, 7, ["historical_passport_architecture_revisions"]):
            with self.subTest(value=value):
                policy = copy.deepcopy(POLICY)
                policy["passport_architecture_compatibility"]["central_registry_field"] = value
                self.assertFalse(self._decision(policy=policy)["compatible"])

    # F
    def test_f_missing_historical_identity_registry_field_fails_closed(self):
        policy = copy.deepcopy(POLICY)
        policy["passport_architecture_compatibility"].pop("historical_identity_registry_field")
        decision = self._decision(policy=policy)
        self.assertFalse(decision["compatible"])
        self.assertEqual("STRICT_MISMATCH_IDENTITY_POLICY_FIELD_INVALID", decision["mode"])

    # G
    def test_g_wrong_or_non_string_identity_field_literal_fails_closed(self):
        for value in ("passport_history", "", None, 9):
            with self.subTest(value=value):
                policy = copy.deepcopy(POLICY)
                policy["passport_architecture_compatibility"]["historical_identity_registry_field"] = value
                self.assertFalse(self._decision(policy=policy)["compatible"])

    # H
    def test_h_revision_allowlist_without_identity_list_fails_closed(self):
        central = self._central()
        central.pop("historical_passport_identities")
        decision = self._decision(central=central)
        self.assertFalse(decision["compatible"])
        self.assertEqual("STRICT_MISMATCH_MALFORMED_IDENTITY_LIST", decision["mode"])

    # I
    def test_i_revision_allowlist_plus_exact_immutable_identity_succeeds(self):
        decision = self._decision()
        self.assertTrue(decision["compatible"])
        self.assertEqual("EXPLICIT_HISTORICAL_IDENTITY_ALLOWED", decision["mode"])
        self.assertEqual(1, decision["matching_historical_identities"])

    # J
    def test_j_wrong_program_identity_fails_closed(self):
        central = self._central(identities=[self._identity(program="OTHER")])
        self.assertFalse(self._decision(central=central)["compatible"])

    # K
    def test_k_wrong_branch_identity_fails_closed(self):
        central = self._central(identities=[self._identity(branch="feature/other")])
        self.assertFalse(self._decision(central=central)["compatible"])

    # L
    def test_l_wrong_passport_path_identity_fails_closed(self):
        central = self._central(
            identities=[self._identity(passport_path="config/control/branches/other.json")]
        )
        self.assertFalse(self._decision(central=central)["compatible"])

    # M
    def test_m_wrong_historical_architecture_revision_identity_fails_closed(self):
        central = self._central(identities=[self._identity(architecture_revision="R1")])
        self.assertFalse(self._decision(central=central)["compatible"])

    # N
    def test_n_wrong_pinned_head_fails_closed(self):
        central = self._central(identities=[self._identity(pinned_head_sha=MOVED_HEAD)])
        self.assertFalse(self._decision(central=central)["compatible"])

    # O
    def test_o_wrong_passport_blob_fails_closed(self):
        central = self._central(identities=[self._identity(passport_blob_sha=OTHER_BLOB)])
        self.assertFalse(self._decision(central=central)["compatible"])

    # P
    def test_p_malformed_pinned_sha_fails_closed(self):
        central = self._central(identities=[self._identity(pinned_head_sha="1234")])
        decision = self._decision(central=central)
        self.assertFalse(decision["compatible"])
        self.assertEqual("STRICT_MISMATCH_MALFORMED_IDENTITY_SHA", decision["mode"])

    # Q
    def test_q_malformed_blob_sha_fails_closed(self):
        central = self._central(identities=[self._identity(passport_blob_sha="not-a-sha")])
        self.assertFalse(self._decision(central=central)["compatible"])

    # R
    def test_r_malformed_identity_list_or_record_fails_closed(self):
        cases = [
            "not-a-list",
            [self._identity(), "not-an-object"],
            [{key: value for key, value in self._identity().items() if key != "passport_blob_sha"}],
        ]
        for identities in cases:
            with self.subTest(identities=identities):
                central = self._central(identities=identities)
                self.assertFalse(self._decision(central=central)["compatible"])

    # S
    def test_s_copied_r2_allowlist_to_different_identity_fails_closed(self):
        copied_old_identity = self._identity(
            branch="feature/old-frontier",
            passport_path="config/control/branches/old-frontier.json",
            pinned_head_sha="5" * 40,
            passport_blob_sha="6" * 40,
        )
        central = self._central(identities=[copied_old_identity])
        decision = self._decision(central=central)
        self.assertFalse(decision["compatible"])
        self.assertEqual("STRICT_MISMATCH_HISTORICAL_IDENTITY_NOT_PINNED", decision["mode"])

    # T
    def test_t_new_or_refreshed_r2_frontier_with_copied_allowlist_stays_red(self):
        result = self._audit_mocked(observed_head_sha=MOVED_HEAD)
        self.assert_architecture_mismatch_red(result)

    # U
    def test_u_same_historical_branch_moved_after_pinned_identity_fails_closed(self):
        decision = self._decision(observed_head_sha=MOVED_HEAD)
        self.assertFalse(decision["compatible"])
        self.assertEqual("STRICT_MISMATCH_HISTORICAL_IDENTITY_NOT_PINNED", decision["mode"])

    # V
    def test_v_other_existing_red_finding_remains_red(self):
        result = self._audit_mocked(
            extra_findings=[{"level": "RED", "code": "OTHER_RED", "detail": "still blocking"}]
        )
        self.assertEqual("RED", result["health"])
        self.assertTrue(any(f.get("code") == "OTHER_RED" for f in result["findings"]))
        self.assertFalse(
            any(f.get("code") == "ARCHITECTURE_REVISION_MISMATCH" for f in result["findings"])
        )

    # W
    def test_w_remaining_existing_yellow_remains_yellow(self):
        result = self._audit_mocked(
            extra_findings=[{"level": "YELLOW", "code": "OTHER_YELLOW", "detail": "review"}]
        )
        self.assertEqual("YELLOW", result["health"])
        self.assertTrue(any(f.get("code") == "OTHER_YELLOW" for f in result["findings"]))

    def _load_json(self, relative: str) -> dict:
        return json.loads((ROOT / relative).read_text(encoding="utf-8"))

    def _live_refs_available(self, registry: dict) -> bool:
        for key in LEGACY_R2_PROGRAMS_AT_R3_PROMOTION:
            central = registry["programs"].get(key, {})
            branch = str(central.get("branch", ""))
            path = str(central.get("passport_path", ""))
            if not branch or not path or not pc._core.ref_exists(pc._core.remote_ref(branch)):
                return False
            if not pc._core.git(
                "rev-parse", f"{pc._core.remote_ref(branch)}:{path}", allow_fail=True
            ):
                return False
        return True

    def _synthetic_fallback_six(self):
        registry = {
            "architecture_revision": R3,
            "programs": {},
        }
        passports = {}
        for index, key in enumerate(sorted(LEGACY_R2_PROGRAMS_AT_R3_PROMOTION), 1):
            branch = f"feature/{key.lower()}-historical"
            path = f"config/control/branches/{key.lower()}-historical.json"
            head = f"{index:x}" * 40
            blob = f"{index + 6:x}" * 40
            registry["programs"][key] = {
                "program": key,
                "branch": branch,
                "passport_path": path,
                "historical_passport_architecture_revisions": [R2],
                "historical_passport_identities": [
                    {
                        "program": key,
                        "branch": branch,
                        "passport_path": path,
                        "architecture_revision": R2,
                        "pinned_head_sha": head,
                        "passport_blob_sha": blob,
                    }
                ],
            }
            passports[key] = (
                {"program": key, "branch": branch, "architecture_revision": R2},
                head,
                blob,
            )
        return registry, passports

    def _synthetic_r3_inputs(self):
        registry_path = ROOT / "config/control/project-program-registry.v1.json"
        policy_path = ROOT / "config/control/project-control-policy.v1.json"
        ownership_path = ROOT / "config/control/architecture-ownership.v1.json"
        if not (registry_path.exists() and policy_path.exists() and ownership_path.exists()):
            return None

        registry = copy.deepcopy(self._load_json("config/control/project-program-registry.v1.json"))
        if not self._live_refs_available(registry):
            if os.environ.get("GITHUB_ACTIONS") == "true":
                self.fail("GitHub Actions must fetch all historical branch refs for the live R3 regression")
            return None

        policy = copy.deepcopy(self._load_json("config/control/project-control-policy.v1.json"))
        ownership = copy.deepcopy(self._load_json("config/control/architecture-ownership.v1.json"))
        registry["architecture_revision"] = R3
        policy["architecture_revision"] = R3
        ownership["architecture_revision"] = R3

        seen = set()
        for key in LEGACY_R2_PROGRAMS_AT_R3_PROMOTION:
            central = registry["programs"][key]
            branch = str(central["branch"])
            path = str(central["passport_path"])
            branch_ref = pc._core.remote_ref(branch)
            passport = pc._core.load_branch_json(branch_ref, path)
            self.assertIsNotNone(passport, (key, branch, path))
            self.assertEqual(R2, passport.get("architecture_revision"), key)
            head = pc._core.git("rev-parse", branch_ref, allow_fail=True)
            blob = pc._core.git("rev-parse", f"{branch_ref}:{path}", allow_fail=True)
            self.assertRegex(head, r"^[0-9a-f]{40}$")
            self.assertRegex(blob, r"^[0-9a-f]{40}$")
            central["historical_passport_architecture_revisions"] = [R2]
            central["historical_passport_identities"] = [
                {
                    "program": key,
                    "branch": branch,
                    "passport_path": path,
                    "architecture_revision": R2,
                    "pinned_head_sha": head,
                    "passport_blob_sha": blob,
                }
            ]
            seen.add(key)
        self.assertEqual(LEGACY_R2_PROGRAMS_AT_R3_PROMOTION, seen)
        return registry, policy, ownership

    # X
    def test_x_six_historical_r2_passports_require_revision_and_exact_identity(self):
        live = self._synthetic_r3_inputs()
        if live is None:
            registry, passports = self._synthetic_fallback_six()
            for key, central in registry["programs"].items():
                passport, head, blob = passports[key]
                decision = pc.evaluate_passport_architecture_compatibility(
                    central,
                    registry,
                    passport,
                    POLICY,
                    audited_program=key,
                    observed_branch=central["branch"],
                    observed_passport_path=central["passport_path"],
                    observed_head_sha=head,
                    observed_passport_blob_sha=blob,
                )
                self.assertTrue(decision["compatible"], (key, decision))
            self.assertEqual(LEGACY_R2_PROGRAMS_AT_R3_PROMOTION, set(registry["programs"]))
            return

        registry, policy, ownership = live
        results = []
        seen_legacy = set()
        for key, central in registry["programs"].items():
            if not isinstance(central, dict):
                continue
            branch = str(central.get("branch", ""))
            passport_path = str(central.get("passport_path", ""))
            if branch and passport_path:
                passport = pc._core.load_branch_json(pc._core.remote_ref(branch), passport_path)
                if passport and passport.get("architecture_revision") == R2:
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
                    "EXPLICIT_HISTORICAL_IDENTITY_ALLOWED",
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
        self.assertNotEqual(
            "RED",
            blocking_health,
            [(r["program"], r["health"], r.get("findings")) for r in results],
        )

    def _live_or_mocked_g_result(self, mutator):
        live = self._synthetic_r3_inputs()
        if live is None:
            central = self._central()
            mutator(central)
            return self._audit_mocked(central=central)
        registry, policy, ownership = live
        central = registry["programs"]["G"]
        mutator(central)
        return pc.audit_program("G", central, registry, policy, ownership)

    # Y
    def test_y_remove_g_revision_allowlist_restores_red(self):
        def mutate(central):
            central.pop("historical_passport_architecture_revisions", None)

        result = self._live_or_mocked_g_result(mutate)
        self.assert_architecture_mismatch_red(result)

    # Z
    def test_z_alter_only_g_pinned_head_restores_red(self):
        def mutate(central):
            central["historical_passport_identities"][0]["pinned_head_sha"] = "a" * 40

        result = self._live_or_mocked_g_result(mutate)
        self.assert_architecture_mismatch_red(result)

    # AA
    def test_aa_alter_only_g_passport_blob_restores_red(self):
        def mutate(central):
            central["historical_passport_identities"][0]["passport_blob_sha"] = "b" * 40

        result = self._live_or_mocked_g_result(mutate)
        self.assert_architecture_mismatch_red(result)


if __name__ == "__main__":
    unittest.main()
