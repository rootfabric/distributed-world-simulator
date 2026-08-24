from __future__ import annotations

import copy
import json
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "control"))

from directional_watch_clearance import resolve_critical_clearance

CLEARANCE_PATH = ROOT / "config/control/directional-watch-clearances.v1.json"
REGISTRY_PATH = ROOT / "config/control/project-program-registry.v1.json"
HISTORICAL_V0_TO_NX_CLEARANCE = "V0-P4-NX-H0-2-M4-CRITICAL-WATCH-CLEARANCE-002"
HISTORICAL_NX_TO_V0_CLEARANCE = "NX-H0-2-V0-P4-CRITICAL-WATCH-CLEARANCE-001"


def git(*args: str, check: bool = True) -> str:
    completed = subprocess.run(
        ["git", *args],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if check and completed.returncode != 0:
        raise AssertionError(completed.stderr.strip())
    return completed.stdout.strip() if completed.returncode == 0 else ""


class DirectionalWatchClearanceTests(unittest.TestCase):
    def setUp(self) -> None:
        clearance_registry = json.loads(CLEARANCE_PATH.read_text(encoding="utf-8"))
        self.project_registry = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
        self.assertEqual(
            "distributed_world_simulator.directional_watch_clearance_registry.v1",
            clearance_registry["schema"],
        )
        self.assertEqual("MAIN_OWNED_ONLY", clearance_registry["authority"])

        self.clearances = list(clearance_registry["clearances"])
        historical = [
            item for item in self.clearances if item.get("clearance_id") == HISTORICAL_V0_TO_NX_CLEARANCE
        ]
        self.assertEqual(1, len(historical), historical)
        self.clearance = historical[0]
        self.producer_ref = f"origin/{self.clearance['producer_branch']}"
        self.consumer_ref = f"origin/{self.clearance['consumer_branch']}"
        self.producer = {
            "program": self.clearance["producer_program"],
            "branch": self.clearance["producer_branch"],
            "head_sha": git("rev-parse", "--verify", self.producer_ref),
        }
        self.consumer = {
            "program": self.clearance["consumer_program"],
            "branch": self.clearance["consumer_branch"],
            "head_sha": git("rev-parse", "--verify", self.consumer_ref),
            "passport_path": self.clearance["consumer_passport_path"],
            "passport_blob_sha": git(
                "rev-parse",
                "--verify",
                f"{self.consumer_ref}:{self.clearance['consumer_passport_path']}",
            ),
        }
        self.critical_hits = list(self.clearance["critical_files"])
        self.all_hits = list(self.clearance["watched_files"])

    def blob_lookup(self, ref: str, path: str) -> str:
        return git("rev-parse", "--verify", f"{ref}:{path}", check=False)

    def ancestor_check(self, base: str, head: str) -> bool:
        completed = subprocess.run(
            ["git", "merge-base", "--is-ancestor", base, head],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )
        return completed.returncode == 0

    def _scope(self, clearance: dict) -> tuple[dict, dict, list[str], list[str], str, str]:
        producer_ref = f"origin/{clearance['producer_branch']}"
        consumer_ref = f"origin/{clearance['consumer_branch']}"
        producer = {
            "program": clearance["producer_program"],
            "branch": clearance["producer_branch"],
            "head_sha": git("rev-parse", "--verify", producer_ref),
        }
        consumer = {
            "program": clearance["consumer_program"],
            "branch": clearance["consumer_branch"],
            "head_sha": git("rev-parse", "--verify", consumer_ref),
            "passport_path": clearance["consumer_passport_path"],
            "passport_blob_sha": git(
                "rev-parse",
                "--verify",
                f"{consumer_ref}:{clearance['consumer_passport_path']}",
            ),
        }
        return (
            producer,
            consumer,
            list(clearance["critical_files"]),
            list(clearance["watched_files"]),
            producer_ref,
            consumer_ref,
        )

    def resolve(self, clearance: dict | None = None, **overrides):
        producer = copy.deepcopy(overrides.get("producer", self.producer))
        consumer = copy.deepcopy(overrides.get("consumer", self.consumer))
        critical_hits = list(overrides.get("critical_hits", self.critical_hits))
        all_hits = list(overrides.get("all_hits", self.all_hits))
        blob_lookup = overrides.get("blob_lookup", self.blob_lookup)
        ancestor_check = overrides.get("ancestor_check", self.ancestor_check)
        return resolve_critical_clearance(
            [copy.deepcopy(clearance or self.clearance)],
            producer,
            consumer,
            critical_hits,
            all_hits,
            blob_lookup,
            ancestor_check,
        )

    def test_historical_v0_p4_to_nx_clearance_still_matches_reviewed_refs_and_blobs(self):
        accepted, rejections = self.resolve()
        self.assertIsNotNone(accepted, rejections)
        self.assertEqual([], rejections)
        self.assertEqual(HISTORICAL_V0_TO_NX_CLEARANCE, accepted["clearance_id"])
        self.assertTrue(self.ancestor_check(self.clearance["reviewed_producer_head"], self.producer_ref))
        for path, expected in self.clearance["watched_file_blobs"].items():
            self.assertEqual(expected, self.blob_lookup(self.clearance["reviewed_producer_head"], path), path)
            self.assertEqual(expected, self.blob_lookup(self.producer_ref, path), path)

    def test_historical_nx_to_v0_p4_clearance_still_matches_reviewed_refs_and_blobs(self):
        matching = [
            item
            for item in self.clearances
            if item.get("clearance_id") == HISTORICAL_NX_TO_V0_CLEARANCE
        ]
        self.assertEqual(1, len(matching), matching)
        clearance = matching[0]
        producer, consumer, critical_hits, all_hits, producer_ref, _ = self._scope(clearance)
        accepted, rejections = resolve_critical_clearance(
            [copy.deepcopy(clearance)],
            producer,
            consumer,
            critical_hits,
            all_hits,
            self.blob_lookup,
            self.ancestor_check,
        )
        self.assertIsNotNone(accepted, rejections)
        self.assertEqual([], rejections)
        self.assertTrue(self.ancestor_check(clearance["reviewed_producer_head"], producer_ref))
        for path, expected in clearance["watched_file_blobs"].items():
            self.assertEqual(expected, self.blob_lookup(clearance["reviewed_producer_head"], path), path)
            self.assertEqual(expected, self.blob_lookup(producer_ref, path), path)

    def test_current_post_p6_v0_does_not_inherit_historical_p4_to_nx_clearance(self):
        current_v0_branch = self.project_registry["programs"]["V0"]["branch"]
        current_nx_branch = self.project_registry["programs"]["NX"]["branch"]
        self.assertNotEqual(self.clearance["producer_branch"], current_v0_branch)
        matching = [
            item
            for item in self.clearances
            if item.get("status") == "ACCEPTED"
            and item.get("producer_program") == "V0"
            and item.get("producer_branch") == current_v0_branch
            and item.get("consumer_program") == "NX"
            and item.get("consumer_branch") == current_nx_branch
        ]
        self.assertEqual([], matching)

    def test_current_nx_does_not_inherit_historical_nx_to_p4_clearance_for_post_p6_v0(self):
        current_v0_branch = self.project_registry["programs"]["V0"]["branch"]
        current_nx_branch = self.project_registry["programs"]["NX"]["branch"]
        matching = [
            item
            for item in self.clearances
            if item.get("status") == "ACCEPTED"
            and item.get("producer_program") == "NX"
            and item.get("producer_branch") == current_nx_branch
            and item.get("consumer_program") == "V0"
            and item.get("consumer_branch") == current_v0_branch
        ]
        self.assertEqual([], matching)

    def test_older_historical_clearance_is_retained_but_not_selected_as_p4_h0_2_clearance(self):
        historical = [
            item
            for item in self.clearances
            if item.get("clearance_id") == "V0-P4-NX-M4-CRITICAL-WATCH-CLEARANCE-001"
        ]
        self.assertEqual(1, len(historical), historical)
        self.assertNotEqual(historical[0]["consumer_branch"], self.clearance["consumer_branch"])

    def test_added_or_removed_watched_hit_fails_closed(self):
        accepted, rejections = self.resolve(
            all_hits=self.all_hits + ["scripts/network/prediction/new_runtime.gd"]
        )
        self.assertIsNone(accepted)
        self.assertEqual("WATCHED_FILE_SET_MISMATCH", rejections[0]["reason"])

    def test_reviewed_head_must_remain_producer_ancestor(self):
        accepted, rejections = self.resolve(ancestor_check=lambda _base, _head: False)
        self.assertIsNone(accepted)
        self.assertEqual("REVIEWED_HEAD_NOT_PRODUCER_ANCESTOR", rejections[0]["reason"])

    def test_consumer_head_or_passport_drift_fails_closed(self):
        consumer = copy.deepcopy(self.consumer)
        consumer["head_sha"] = "f" * 40
        accepted, rejections = self.resolve(consumer=consumer)
        self.assertIsNone(accepted)
        self.assertEqual("CONSUMER_HEAD_DRIFT", rejections[0]["reason"])

        consumer = copy.deepcopy(self.consumer)
        consumer["passport_blob_sha"] = "f" * 40
        accepted, rejections = self.resolve(consumer=consumer)
        self.assertIsNone(accepted)
        self.assertEqual("CONSUMER_PASSPORT_BLOB_DRIFT", rejections[0]["reason"])

    def test_any_reviewed_or_current_watched_blob_drift_fails_closed(self):
        target = self.all_hits[0]
        expected = self.clearance["watched_file_blobs"][target]

        def reviewed_drift(ref: str, path: str) -> str:
            if ref == self.clearance["reviewed_producer_head"] and path == target:
                return "f" * 40
            return self.blob_lookup(ref, path)

        accepted, rejections = self.resolve(blob_lookup=reviewed_drift)
        self.assertIsNone(accepted)
        self.assertEqual(f"REVIEWED_BLOB_MISMATCH:{target}", rejections[0]["reason"])

        def producer_drift(ref: str, path: str) -> str:
            if ref == self.producer_ref and path == target:
                return "f" * 40
            return self.blob_lookup(ref, path)

        accepted, rejections = self.resolve(blob_lookup=producer_drift)
        self.assertIsNone(accepted)
        self.assertEqual(f"PRODUCER_BLOB_DRIFT:{target}", rejections[0]["reason"])
        self.assertNotEqual(expected, "f" * 40)

    def test_decision_and_independent_evidence_ids_are_mandatory(self):
        candidate = copy.deepcopy(self.clearance)
        candidate["decision"] = "INTERPRET_RED_AS_PASS"
        accepted, rejections = self.resolve(candidate)
        self.assertIsNone(accepted)
        self.assertEqual("DECISION_NOT_ACCEPTED", rejections[0]["reason"])

        candidate = copy.deepcopy(self.clearance)
        candidate["verification_id"] = ""
        accepted, rejections = self.resolve(candidate)
        self.assertIsNone(accepted)
        self.assertEqual("INDEPENDENT_EVIDENCE_IDS_REQUIRED", rejections[0]["reason"])


if __name__ == "__main__":
    unittest.main()
