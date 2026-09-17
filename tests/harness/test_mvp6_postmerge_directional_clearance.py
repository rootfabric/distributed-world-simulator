from __future__ import annotations

import copy
import functools
import json
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/control"))
from directional_watch_clearance import resolve_critical_clearance

BASE = "a6d5eb6b287130a638ba6cf397c34e29169948c1"
CURRENT = "V0-MVP6-NX-POSTMERGE-CRITICAL-WATCH-CLEARANCE-005"
REGISTRY = "config/control/directional-watch-clearances.v1.json"
JOURNAL = "scripts/network/prediction/predicted_item_interaction_journal.gd"
M4 = "scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd"


def git(*args: str) -> str:
    p = subprocess.run(["git", *args], cwd=ROOT, text=True, capture_output=True)
    if p.returncode:
        raise AssertionError(p.stderr)
    return p.stdout.strip()


@functools.lru_cache(maxsize=None)
def blob(ref: str, path: str) -> str:
    p = subprocess.run(["git", "rev-parse", "--verify", f"{ref}:{path}"], cwd=ROOT, text=True, capture_output=True)
    return p.stdout.strip() if p.returncode == 0 else ""


@functools.lru_cache(maxsize=None)
def ancestor(base: str, head: str) -> bool:
    return subprocess.run(["git", "merge-base", "--is-ancestor", base, head], cwd=ROOT, capture_output=True).returncode == 0


class MVP6PostmergeClearanceTests(unittest.TestCase):
    def setUp(self):
        self.registry = json.loads((ROOT / REGISTRY).read_text(encoding="utf-8"))
        rows = [r for r in self.registry["clearances"] if r["clearance_id"] == CURRENT]
        self.assertEqual(1, len(rows))
        self.c = copy.deepcopy(rows[0])
        self.p = {"program": "V0", "branch": self.c["producer_branch"], "head_sha": git("rev-parse", "origin/" + self.c["producer_branch"])}
        self.q = {"program": "NX", "branch": self.c["consumer_branch"], "head_sha": git("rev-parse", "origin/" + self.c["consumer_branch"]), "passport_path": self.c["consumer_passport_path"], "passport_blob_sha": blob("origin/" + self.c["consumer_branch"], self.c["consumer_passport_path"])}

    def resolve(self, record=None, producer=None, consumer=None, critical=None, watched=None, lookup=blob, ancestry=ancestor):
        return resolve_critical_clearance(
            [self.c if record is None else record],
            self.p if producer is None else producer,
            self.q if consumer is None else consumer,
            [M4] if critical is None else critical,
            [JOURNAL, M4] if watched is None else watched,
            lookup, ancestry,
        )

    def rejected(self, expected, **kwargs):
        accepted, rejected = self.resolve(**kwargs)
        self.assertIsNone(accepted)
        self.assertEqual([expected], [r["reason"] for r in rejected])

    def test_real_merged_main_and_exact_live_dependencies_pass(self):
        self.assertEqual(BASE, self.c["required_main_ancestor"])
        self.assertTrue(ancestor(BASE, "origin/main"))
        self.assertEqual({JOURNAL: "abdf0c0a335f4e2c968933156fb17f94a7b45bd1"}, self.c["required_main_file_blobs"])
        self.assertEqual("1a56fe0e845c941f14ce7b9296ee939e9d0ca8bc", self.q["head_sha"])
        self.assertEqual("c3af1974228c9ee5c34bf4d54c72896c99fc4d1a", self.q["passport_blob_sha"])
        self.assertEqual("73b8818184c93986e3313f35f9f4548c608e47e6", self.c["reviewed_producer_head"])
        self.assertEqual("MVP6-JOURNAL-73B88181-REVIEW-R1", self.c["review_id"])
        self.assertEqual("MVP6-JOURNAL-FEATURE-VERIFIER-R1", self.c["verification_id"])
        accepted, rejected = self.resolve()
        self.assertEqual([], rejected)
        self.assertEqual(CURRENT, accepted["clearance_id"])

    def test_historical_records_unchanged_and_one_new_record(self):
        original = json.loads(git("show", BASE + ":" + REGISTRY))
        self.assertEqual(original["clearances"], self.registry["clearances"][:-1])
        self.assertEqual(len(original["clearances"]) + 1, len(self.registry["clearances"]))
        self.assertEqual("MAIN_OWNED_ONLY", self.registry["authority"])
        self.assertNotIn("6b147d0300529a6b40568b4de0817d5cc7f95fdb", json.dumps(self.c))

    def test_unmerged_pr643_cannot_satisfy_the_actual_pr646_prerequisite(self):
        self.rejected("REQUIRED_MAIN_ANCESTOR_NOT_CANONICAL", ancestry=lambda a, b: False if (a, b) == (BASE, "origin/main") else ancestor(a, b))

    def test_malformed_main_ancestor_fails_closed(self):
        for value in (None, "", "a6d5eb6", "z" * 40, "F" * 40, 12, []):
            with self.subTest(value=value):
                c = copy.deepcopy(self.c); c["required_main_ancestor"] = value
                self.rejected("REQUIRED_MAIN_ANCESTOR_INVALID", record=c)

    def test_missing_main_ancestor_fails_closed(self):
        c = copy.deepcopy(self.c); del c["required_main_ancestor"]
        self.rejected("REQUIRED_MAIN_ANCESTOR_INVALID", record=c)

    def test_missing_or_empty_main_blob_fence_fails_closed(self):
        c = copy.deepcopy(self.c); del c["required_main_file_blobs"]
        self.rejected("REQUIRED_MAIN_BLOB_FENCE_REQUIRED", record=c)
        for value in (None, {}, [], ""):
            with self.subTest(value=value):
                c = copy.deepcopy(self.c); c["required_main_file_blobs"] = value
                self.rejected("REQUIRED_MAIN_BLOB_FENCE_REQUIRED", record=c)

    def test_malformed_main_blob_fence_fails_closed(self):
        for value in ({JOURNAL: "z" * 40}, {JOURNAL: None}, {"../secret": "f" * 40}, {"/absolute": "f" * 40}, {"a//b": "f" * 40}, {"x:y": "f" * 40}, {"a\\b": "f" * 40}, {7: "f" * 40}):
            with self.subTest(value=value):
                c = copy.deepcopy(self.c); c["required_main_file_blobs"] = value
                self.rejected("REQUIRED_MAIN_BLOB_FENCE_INVALID", record=c)

    def test_reverted_main_journal_rejected_even_with_merge_ancestry(self):
        self.assertTrue(ancestor(BASE, "origin/main"))
        self.rejected("REQUIRED_MAIN_BLOB_DRIFT:" + JOURNAL, lookup=lambda r, p: "f" * 40 if (r, p) == ("origin/main", JOURNAL) else blob(r, p))

    def test_missing_main_journal_rejected(self):
        self.rejected("REQUIRED_MAIN_BLOB_DRIFT:" + JOURNAL, lookup=lambda r, p: "" if (r, p) == ("origin/main", JOURNAL) else blob(r, p))

    def test_prerequisite_commit_must_contain_bound_journal(self):
        self.rejected("REQUIRED_MAIN_BASELINE_BLOB_MISMATCH:" + JOURNAL, lookup=lambda r, p: "f" * 40 if (r, p) == (BASE, JOURNAL) else blob(r, p))

    def test_critical_set_added_or_removed_is_rejected(self):
        for hits in ([], [M4, JOURNAL]):
            with self.subTest(hits=hits):
                self.rejected("CRITICAL_FILE_SET_MISMATCH", critical=hits)

    def test_watched_set_added_or_removed_is_rejected(self):
        for hits in ([M4], [JOURNAL], [JOURNAL, M4, "scripts/network/new.gd"]):
            with self.subTest(hits=hits):
                self.rejected("WATCHED_FILE_SET_MISMATCH", watched=hits)

    def test_current_producer_blob_drift_each_path(self):
        for path in (JOURNAL, M4):
            with self.subTest(path=path):
                self.rejected("PRODUCER_BLOB_DRIFT:" + path, lookup=lambda r, p: "f" * 40 if (r, p) == ("origin/" + self.p["branch"], path) else blob(r, p))

    def test_reviewed_producer_blob_drift_each_path(self):
        for path in (JOURNAL, M4):
            with self.subTest(path=path):
                self.rejected("REVIEWED_BLOB_MISMATCH:" + path, lookup=lambda r, p: "f" * 40 if (r, p) == (self.c["reviewed_producer_head"], path) else blob(r, p))

    def test_reviewed_producer_must_remain_ancestor(self):
        pair = (self.c["reviewed_producer_head"], "origin/" + self.p["branch"])
        self.rejected("REVIEWED_HEAD_NOT_PRODUCER_ANCESTOR", ancestry=lambda a, b: False if (a, b) == pair else ancestor(a, b))

    def test_consumer_identity_drift(self):
        for field, reason in (("head_sha", "CONSUMER_HEAD_DRIFT"), ("passport_blob_sha", "CONSUMER_PASSPORT_BLOB_DRIFT"), ("passport_path", "CONSUMER_PASSPORT_PATH_DRIFT")):
            with self.subTest(field=field):
                q = dict(self.q); q[field] = "f" * 40
                self.rejected(reason, consumer=q)

    def test_other_producer_or_consumer_branch_never_inherits_clearance(self):
        for which in ("producer", "consumer"):
            changed = dict(self.p if which == "producer" else self.q, branch="feature/unreviewed")
            accepted, rejected = self.resolve(**{which: changed})
            self.assertIsNone(accepted)
            self.assertEqual([], rejected)

    def test_missing_evidence_or_unaccepted_decision(self):
        for field, value, reason in (("review_id", "", "INDEPENDENT_EVIDENCE_IDS_REQUIRED"), ("verification_id", "", "INDEPENDENT_EVIDENCE_IDS_REQUIRED"), ("status", "PROPOSED", "STATUS_NOT_ACCEPTED"), ("decision", "INTERPRET_RED_AS_PASS", "DECISION_NOT_ACCEPTED")):
            with self.subTest(field=field):
                c = copy.deepcopy(self.c); c[field] = value
                self.rejected(reason, record=c)

    def test_incomplete_producer_blob_fence_rejected(self):
        c = copy.deepcopy(self.c); del c["watched_file_blobs"][JOURNAL]
        self.rejected("WATCHED_BLOB_FENCE_INCOMPLETE", record=c)


if __name__ == "__main__":
    unittest.main()
