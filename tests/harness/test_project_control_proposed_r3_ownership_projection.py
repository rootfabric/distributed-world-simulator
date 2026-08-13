from __future__ import annotations

import copy
import json
import os
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "control"))

import project_control as pc
import project_control_directional_watch as directional

R2 = "GLOBAL-P0-2026-08-10-R2"
R3 = "GLOBAL-P0-2026-08-12-R3-REFRESH-R1"
FROZEN_R3_TARGET = "595263c4c925c122a09876cb29b87f5ca5fef1d2"
FROZEN_R3_OWNERSHIP_PATH = "config/control/architecture-ownership-r3-candidate.v1.json"
FROZEN_R3_OWNERSHIP_BLOB = "ad2aaac2c5f942b9748b5cf391038a7ce122d073"
LEGACY_PROGRAMS = ("G", "ECO", "T", "CH", "DOCTRINE", "NX")
T_TRANSITIONS = [
    {
        "program": "T",
        "architecture_revision": R2,
        "foundation": "WORLD_QUERY_FABRIC",
        "historical_owner": "P1_FUTURE",
        "canonical_owner": "WQ",
    },
    {
        "program": "T",
        "architecture_revision": R2,
        "foundation": "WORLD_TRANSACTION_MODEL",
        "historical_owner": "P0",
        "canonical_owner": "WT",
    },
]


class ProposedR3OwnershipProjectionTests(unittest.TestCase):
    def _load_local_json(self, path: str) -> dict:
        return json.loads((ROOT / path).read_text(encoding="utf-8"))

    def _load_git_json(self, ref: str, path: str) -> dict:
        raw = pc._core.git("show", f"{ref}:{path}", allow_fail=True)
        self.assertTrue(raw, (ref, path))
        value = json.loads(raw)
        self.assertIsInstance(value, dict)
        return value

    def _projection(self) -> tuple[dict, dict, dict, dict[str, dict[str, str]]]:
        if os.environ.get("GITHUB_ACTIONS") != "true":
            self.skipTest("live proposed-R3 projection requires GitHub Actions with all remote refs fetched")

        registry = copy.deepcopy(self._load_local_json("config/control/project-program-registry.v1.json"))
        policy = copy.deepcopy(self._load_local_json("config/control/project-control-policy.v1.json"))

        ownership_blob = pc._core.git("rev-parse", f"{FROZEN_R3_TARGET}:{FROZEN_R3_OWNERSHIP_PATH}", allow_fail=True)
        self.assertEqual(FROZEN_R3_OWNERSHIP_BLOB, ownership_blob)
        frozen_ownership = self._load_git_json(FROZEN_R3_TARGET, FROZEN_R3_OWNERSHIP_PATH)
        self.assertEqual(R3, frozen_ownership.get("architecture_revision"))

        identities: dict[str, dict[str, str]] = {}
        if registry.get("registry_generation") == 78 and registry.get("architecture_revision") == R2:
            ownership = frozen_ownership
            registry["registry_generation"] = 79
            registry["architecture_revision"] = R3
            policy["architecture_revision"] = R3
            for key in LEGACY_PROGRAMS:
                central = registry["programs"][key]
                branch = str(central["branch"])
                passport_path = str(central["passport_path"])
                branch_ref = pc._core.remote_ref(branch)
                passport = pc._core.load_branch_json(branch_ref, passport_path)
                self.assertIsNotNone(passport, (key, branch, passport_path))
                self.assertEqual(R2, passport.get("architecture_revision"), key)
                head = pc._core.git("rev-parse", branch_ref, allow_fail=True)
                blob = pc._core.git("rev-parse", f"{branch_ref}:{passport_path}", allow_fail=True)
                identity = {"program": key, "branch": branch, "passport_path": passport_path, "architecture_revision": R2, "pinned_head_sha": head, "passport_blob_sha": blob}
                central["historical_passport_architecture_revisions"] = [R2]
                central["historical_passport_identities"] = [identity]
                central.pop("historical_passport_ownership_transitions", None)
                identities[key] = identity
            registry["programs"]["T"]["historical_passport_ownership_transitions"] = copy.deepcopy(T_TRANSITIONS)
            return registry, policy, ownership, identities

        self.assertEqual(79, registry.get("registry_generation"))
        self.assertEqual(R3, registry.get("architecture_revision"))
        self.assertEqual(R3, policy.get("architecture_revision"))
        ownership = self._load_local_json("config/control/architecture-ownership.v1.json")
        self.assertEqual(R3, ownership.get("architecture_revision"))
        self.assertEqual(frozen_ownership.get("foundations"), ownership.get("foundations"))
        for key in LEGACY_PROGRAMS:
            central = registry["programs"][key]
            records = central.get("historical_passport_identities", [])
            self.assertEqual(1, len(records), key)
            identity = records[0]
            self.assertEqual(key, identity.get("program"), key)
            self.assertEqual(central.get("branch"), identity.get("branch"), key)
            self.assertEqual(central.get("passport_path"), identity.get("passport_path"), key)
            self.assertEqual(R2, identity.get("architecture_revision"), key)
            self.assertRegex(str(identity.get("pinned_head_sha", "")), r"^[0-9a-f]{40}$", key)
            self.assertRegex(str(identity.get("passport_blob_sha", "")), r"^[0-9a-f]{40}$", key)
            self.assertEqual([R2], central.get("historical_passport_architecture_revisions"), key)
            identities[key] = identity
        self.assertEqual(T_TRANSITIONS, registry["programs"]["T"].get("historical_passport_ownership_transitions"))
        return registry, policy, ownership, identities

    @staticmethod
    def _standard_overall(programs: list[dict]) -> str:
        overall = "GREEN"
        for program in programs:
            if not bool(program.get("blocks_global_progress", True)):
                continue
            health = str(program.get("health", "GREEN"))
            if pc.HEALTH_RANK.get(health, 0) > pc.HEALTH_RANK[overall]:
                overall = health
        return overall

    @staticmethod
    def _directional_overall(registry: dict, policy: dict) -> str:
        scopes = [
            scope
            for key, central in dict(registry.get("programs", {})).items()
            if isinstance(central, dict)
            for scope in [directional.program_scope(key, central, policy)]
            if scope is not None
        ]
        directional_policy = dict(policy.get("directional_watch_policy", {}))
        watched_level = str(directional_policy.get("watched_hit_health", "YELLOW"))
        critical_level = str(directional_policy.get("critical_hit_health", "RED"))
        if watched_level not in directional.HEALTH_RANK or critical_level not in directional.HEALTH_RANK:
            raise AssertionError("invalid directional health policy")

        overall = "GREEN"
        for producer in scopes:
            if not producer["producer_enabled"] or not producer["changed_files"]:
                continue
            producer_files = list(producer["changed_files"])
            for consumer in scopes:
                if producer["program"] == consumer["program"]:
                    continue
                critical_hits = [
                    path
                    for path in producer_files
                    if directional.matches_any(path, list(consumer["critical_watched_paths"]))
                ]
                critical_set = set(critical_hits)
                watched_hits = [
                    path
                    for path in producer_files
                    if path not in critical_set
                    and directional.matches_any(path, list(consumer["watched_paths"]))
                ]
                if not bool(consumer.get("blocks_global_progress", True)):
                    continue
                if critical_hits and directional.HEALTH_RANK[critical_level] > directional.HEALTH_RANK[overall]:
                    overall = critical_level
                if watched_hits and directional.HEALTH_RANK[watched_level] > directional.HEALTH_RANK[overall]:
                    overall = watched_level
        return overall

    def _audit_t(self, registry: dict, policy: dict, ownership: dict) -> dict:
        central = registry["programs"]["T"]
        return pc.audit_program("T", central, registry, policy, ownership)

    def test_live_proposed_r3_standard_and_directional_are_non_red(self):
        registry, policy, ownership, identities = self._projection()
        programs = [
            pc.audit_program(key, central, registry, policy, ownership)
            for key, central in dict(registry.get("programs", {})).items()
            if isinstance(central, dict)
        ]
        pc.apply_cross_branch_overlap(programs, policy)
        standard = self._standard_overall(programs)
        directional_health = self._directional_overall(registry, policy)

        self.assertNotEqual("RED", standard, [(p["program"], p["health"], p.get("findings")) for p in programs])
        self.assertNotEqual("RED", directional_health)
        self.assertEqual(79, registry["registry_generation"])
        self.assertEqual(R3, registry["architecture_revision"])
        self.assertEqual(set(LEGACY_PROGRAMS), set(identities))

        t = next(program for program in programs if program["program"] == "T")
        self.assertNotEqual("RED", t["health"], t)
        self.assertEqual(
            "EXPLICIT_HISTORICAL_IDENTITY_ALLOWED",
            t.get("architecture_compatibility", {}).get("mode"),
        )
        self.assertEqual(
            1,
            t.get("architecture_compatibility", {}).get("matching_historical_identities"),
        )
        self.assertEqual(
            [
                {
                    "foundation": "WORLD_QUERY_FABRIC",
                    "historical_owner": "P1_FUTURE",
                    "canonical_owner": "WQ",
                },
                {
                    "foundation": "WORLD_TRANSACTION_MODEL",
                    "historical_owner": "P0",
                    "canonical_owner": "WT",
                },
            ],
            t.get("ownership_compatibility", {}).get("authorized_conflicts"),
        )
        self.assertFalse(
            any(
                finding.get("code") == "FOUNDATION_OWNERSHIP_CONFLICT"
                and (
                    "WORLD_QUERY_FABRIC" in str(finding.get("detail", ""))
                    or "WORLD_TRANSACTION_MODEL" in str(finding.get("detail", ""))
                )
                for finding in t.get("findings", [])
                if isinstance(finding, dict)
            ),
            t,
        )

        blocking_red = [
            program["program"]
            for program in programs
            if program.get("blocks_global_progress", True) and program.get("health") == "RED"
        ]
        self.assertEqual([], blocking_red)
        eco = next(program for program in programs if program["program"] == "ECO")
        if eco.get("health") == "RED":
            self.assertFalse(eco.get("blocks_global_progress", True))

    def test_live_proposed_r3_negative_ownership_mutations_fail_closed(self):
        registry, policy, ownership, _ = self._projection()

        with self.subTest("remove one T transition"):
            mutated = copy.deepcopy(registry)
            mutated["programs"]["T"]["historical_passport_ownership_transitions"] = [
                copy.deepcopy(T_TRANSITIONS[0])
            ]
            result = self._audit_t(mutated, policy, ownership)
            self.assertEqual("RED", result["health"], result)
            self.assertTrue(
                any(
                    finding.get("code") == "FOUNDATION_OWNERSHIP_CONFLICT"
                    and "WORLD_TRANSACTION_MODEL" in str(finding.get("detail", ""))
                    for finding in result.get("findings", [])
                    if isinstance(finding, dict)
                )
            )

        with self.subTest("change one target R3 owner"):
            mutated_ownership = copy.deepcopy(ownership)
            mutated_ownership["foundations"]["WORLD_QUERY_FABRIC"]["owner"] = "WQ_CHANGED"
            result = self._audit_t(registry, policy, mutated_ownership)
            self.assertEqual("RED", result["health"], result)

        with self.subTest("duplicate one T transition"):
            mutated = copy.deepcopy(registry)
            mutated["programs"]["T"]["historical_passport_ownership_transitions"] = [
                copy.deepcopy(T_TRANSITIONS[0]),
                copy.deepcopy(T_TRANSITIONS[0]),
                copy.deepcopy(T_TRANSITIONS[1]),
            ]
            result = self._audit_t(mutated, policy, ownership)
            self.assertEqual("RED", result["health"], result)
            self.assertEqual(
                "OWNERSHIP_TRANSITION_AMBIGUOUS",
                result.get("ownership_compatibility", {}).get("reason"),
            )

        with self.subTest("refreshed T identity"):
            mutated = copy.deepcopy(registry)
            mutated["programs"]["T"]["historical_passport_identities"][0]["pinned_head_sha"] = "f" * 40
            result = self._audit_t(mutated, policy, ownership)
            self.assertEqual("RED", result["health"], result)
            self.assertNotEqual(
                "EXPLICIT_HISTORICAL_IDENTITY_ALLOWED",
                result.get("architecture_compatibility", {}).get("mode"),
            )
            self.assertNotIn("ownership_compatibility", result)


if __name__ == "__main__":
    unittest.main()
