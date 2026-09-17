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
HIST_V0_NX = "V0-P4-NX-H0-2-M4-CRITICAL-WATCH-CLEARANCE-002"
HIST_NX_V0 = "NX-H0-2-V0-P4-CRITICAL-WATCH-CLEARANCE-001"
CURRENT = "V0-MVP6-NX-H0-2-M4-JOURNAL-CRITICAL-WATCH-CLEARANCE-004"
BASELINE = "d9706b157e84c653a753cc54243ce6651d53319c"
M4 = "scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd"
JOURNAL = "scripts/network/prediction/predicted_item_interaction_journal.gd"


def git(*args: str, check: bool = True) -> str:
    p = subprocess.run(["git", *args], cwd=ROOT, text=True, capture_output=True, check=False)
    if check and p.returncode != 0:
        raise AssertionError(p.stderr.strip())
    return p.stdout.strip() if p.returncode == 0 else ""


def ancestor(base: str, head: str) -> bool:
    return subprocess.run(
        ["git", "merge-base", "--is-ancestor", base, head],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    ).returncode == 0


def blob(ref: str, path: str) -> str:
    return git("rev-parse", "--verify", f"{ref}:{path}", check=False)


def main_without_baseline(base: str, head: str) -> bool:
    if base == BASELINE and head == "origin/main":
        return False
    return ancestor(base, head)


class DirectionalWatchClearanceTests(unittest.TestCase):
    def setUp(self) -> None:
        registry = json.loads(CLEARANCE_PATH.read_text(encoding="utf-8"))
        self.project = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))
        self.assertEqual("distributed_world_simulator.directional_watch_clearance_registry.v1", registry["schema"])
        self.assertEqual("MAIN_OWNED_ONLY", registry["authority"])
        self.clearances = list(registry["clearances"])

    def one(self, clearance_id: str) -> dict:
        rows = [x for x in self.clearances if x.get("clearance_id") == clearance_id]
        self.assertEqual(1, len(rows), rows)
        return rows[0]

    def scope(self, c: dict) -> tuple[dict, dict, list[str], list[str]]:
        consumer = {
            "program": c["consumer_program"],
            "branch": c["consumer_branch"],
            "head_sha": c["consumer_head_sha"],
            "passport_path": c["consumer_passport_path"],
            "passport_blob_sha": blob(c["consumer_head_sha"], c["consumer_passport_path"]),
        }
        self.assertEqual(c["consumer_passport_blob_sha"], consumer["passport_blob_sha"])
        producer = {
            "program": c["producer_program"],
            "branch": c["producer_branch"],
            "head_sha": c["reviewed_producer_head"],
        }
        return producer, consumer, list(c["critical_files"]), list(c["watched_files"])

    def resolve(self, c: dict, *, producer=None, consumer=None, critical=None, watched=None, blob_lookup=blob, ancestor_check=ancestor):
        p, q, crit, hits = self.scope(c)
        return resolve_critical_clearance(
            [copy.deepcopy(c)],
            copy.deepcopy(producer or p),
            copy.deepcopy(consumer or q),
            list(critical if critical is not None else crit),
            list(watched if watched is not None else hits),
            blob_lookup,
            ancestor_check,
        )

    def test_historical_v0_to_nx_replays(self):
        accepted, rejected = self.resolve(self.one(HIST_V0_NX))
        self.assertIsNotNone(accepted, rejected)
        self.assertEqual([], rejected)

    def test_historical_nx_to_v0_replays(self):
        accepted, rejected = self.resolve(self.one(HIST_NX_V0))
        self.assertIsNotNone(accepted, rejected)
        self.assertEqual([], rejected)

    def test_current_scope_and_evidence_are_exact(self):
        c = self.one(CURRENT)
        v0 = self.project["programs"]["V0"]["branch"]
        nx = self.project["programs"]["NX"]["branch"]
        rows = [
            x for x in self.clearances
            if x.get("status") == "ACCEPTED"
            and x.get("producer_program") == "V0"
            and x.get("producer_branch") == v0
            and x.get("consumer_program") == "NX"
            and x.get("consumer_branch") == nx
        ]
        self.assertEqual([CURRENT], [x["clearance_id"] for x in rows])
        self.assertEqual(BASELINE, c["required_main_ancestor"])
        self.assertTrue(ancestor(BASELINE, "origin/main"))
        self.assertEqual([M4], c["critical_files"])
        self.assertEqual(sorted([JOURNAL, M4]), sorted(c["watched_files"]))
        self.assertEqual("MVP6-JOURNAL-73B88181-REVIEW-R1", c["review_id"])
        self.assertEqual("MVP6-JOURNAL-FEATURE-VERIFIER-R1", c["verification_id"])
        self.assertTrue(ancestor(c["reviewed_producer_head"], f"origin/{v0}"))
        for path, expected in c["watched_file_blobs"].items():
            self.assertEqual(expected, blob(c["reviewed_producer_head"], path), path)
            self.assertEqual(expected, blob(f"origin/{v0}", path), path)

    def test_current_requires_canonical_baseline(self):
        c = self.one(CURRENT)
        accepted, rejected = self.resolve(c)
        self.assertIsNotNone(accepted, rejected)
        self.assertEqual([], rejected)
        self.assertEqual(CURRENT, accepted["clearance_id"])

        accepted, rejected = self.resolve(c, ancestor_check=main_without_baseline)
        self.assertIsNone(accepted)
        self.assertEqual("REQUIRED_MAIN_ANCESTOR_NOT_CANONICAL", rejected[0]["reason"])

    def test_current_required_main_ancestor_must_be_full_sha(self):
        c = copy.deepcopy(self.one(CURRENT))
        c["required_main_ancestor"] = "d9706b1"
        accepted, rejected = self.resolve(c)
        self.assertIsNone(accepted)
        self.assertEqual("REQUIRED_MAIN_ANCESTOR_INVALID", rejected[0]["reason"])

    def test_current_hitset_drift_fails_closed_after_baseline(self):
        c = self.one(CURRENT)
        p, q, critical, watched = self.scope(c)
        for altered in ([x for x in watched if x != JOURNAL], watched + ["scripts/network/prediction/new_runtime.gd"]):
            accepted, rejected = resolve_critical_clearance(
                [copy.deepcopy(c)], p, q, critical, altered, blob, ancestor
            )
            self.assertIsNone(accepted)
            self.assertEqual("WATCHED_FILE_SET_MISMATCH", rejected[0]["reason"])

    def test_current_either_live_blob_drift_fails_closed_after_baseline(self):
        c = self.one(CURRENT)
        p, q, critical, watched = self.scope(c)
        for target in (JOURNAL, M4):
            def drift(ref: str, path: str, target_path: str = target) -> str:
                if ref == f"origin/{p['branch']}" and path == target_path:
                    return "f" * 40
                return blob(ref, path)
            accepted, rejected = resolve_critical_clearance(
                [copy.deepcopy(c)], p, q, critical, watched, drift, ancestor
            )
            self.assertIsNone(accepted)
            self.assertEqual(f"PRODUCER_BLOB_DRIFT:{target}", rejected[0]["reason"])

    def test_current_reviewed_blob_drift_fails_closed_after_baseline(self):
        c = self.one(CURRENT)
        p, q, critical, watched = self.scope(c)
        def drift(ref: str, path: str) -> str:
            if ref == c["reviewed_producer_head"] and path == JOURNAL:
                return "f" * 40
            return blob(ref, path)
        accepted, rejected = resolve_critical_clearance(
            [copy.deepcopy(c)], p, q, critical, watched, drift, ancestor
        )
        self.assertIsNone(accepted)
        self.assertEqual(f"REVIEWED_BLOB_MISMATCH:{JOURNAL}", rejected[0]["reason"])

    def test_current_producer_ancestry_drift_fails_closed_after_baseline(self):
        c = self.one(CURRENT)
        p, q, critical, watched = self.scope(c)
        def producer_drift(base: str, head: str) -> bool:
            if base == c["reviewed_producer_head"] and head == f"origin/{p['branch']}":
                return False
            return ancestor(base, head)
        accepted, rejected = resolve_critical_clearance(
            [copy.deepcopy(c)], p, q, critical, watched, blob, producer_drift
        )
        self.assertIsNone(accepted)
        self.assertEqual("REVIEWED_HEAD_NOT_PRODUCER_ANCESTOR", rejected[0]["reason"])

    def test_current_consumer_identity_drift_fails_closed_after_baseline(self):
        c = self.one(CURRENT)
        p, q, critical, watched = self.scope(c)
        for field in ("head_sha", "passport_blob_sha"):
            changed = copy.deepcopy(q)
            changed[field] = "f" * 40
            accepted, rejected = resolve_critical_clearance(
                [copy.deepcopy(c)], p, changed, critical, watched, blob, ancestor
            )
            self.assertIsNone(accepted)
            expected = "CONSUMER_HEAD_DRIFT" if field == "head_sha" else "CONSUMER_PASSPORT_BLOB_DRIFT"
            self.assertEqual(expected, rejected[0]["reason"])

    def test_current_decision_and_evidence_ids_are_mandatory(self):
        c = self.one(CURRENT)
        p, q, critical, watched = self.scope(c)
        bad = copy.deepcopy(c)
        bad["decision"] = "UNSUPPORTED"
        accepted, rejected = resolve_critical_clearance([bad], p, q, critical, watched, blob, ancestor)
        self.assertIsNone(accepted)
        self.assertEqual("DECISION_NOT_ACCEPTED", rejected[0]["reason"])
        bad = copy.deepcopy(c)
        bad["verification_id"] = ""
        accepted, rejected = resolve_critical_clearance([bad], p, q, critical, watched, blob, ancestor)
        self.assertIsNone(accepted)
        self.assertEqual("INDEPENDENT_EVIDENCE_IDS_REQUIRED", rejected[0]["reason"])

    def test_current_nx_has_no_reverse_post_p6_clearance(self):
        v0 = self.project["programs"]["V0"]["branch"]
        nx = self.project["programs"]["NX"]["branch"]
        rows = [
            x for x in self.clearances
            if x.get("status") == "ACCEPTED"
            and x.get("producer_program") == "NX"
            and x.get("producer_branch") == nx
            and x.get("consumer_program") == "V0"
            and x.get("consumer_branch") == v0
        ]
        self.assertEqual([], rows)


if __name__ == "__main__":
    unittest.main()
