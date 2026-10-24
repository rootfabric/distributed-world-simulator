"""Issue #836: exact Git proof for one external independent MVP8 Reviewer event."""
from __future__ import annotations

import copy
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

import harness.state_builder as subject
from harness.contracts import ContractValidationError, read_json

EPOCH = ROOT / "config/control/harness/executions/E2026-09-09-V0-MVP-R1"
MANIFEST = EPOCH / "external-role-event-witness.v1.json"
EVENT = EPOCH / "events/V0-MVP-R1-WO-001/0050-mvp8-repair-r2-independent-reviewer-pass.v1.json"
WORK_ORDER = EPOCH / "work-orders/V0-MVP-R1-WO-001.v1.json"


class ExternalReviewerWitnessTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.head = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True,
        ).strip()
        cls.work = read_json(WORK_ORDER)
        cls.event = read_json(EVENT)
        cls.manifest = read_json(MANIFEST)

    @classmethod
    def proof(cls, manifest=None, event=None):
        replacement = copy.deepcopy(cls.manifest if manifest is None else manifest)
        original = subject.read_json

        def read(path):
            if Path(path).resolve() == MANIFEST.resolve():
                return replacement
            return original(path)

        with mock.patch.object(subject, "read_json", side_effect=read):
            return subject._external_reviewer_witnesses(
                ROOT, EPOCH, cls.work, [EVENT],
                [cls.event if event is None else event], cls.head,
            )

    def test_source_review_is_real_and_direct_child(self):
        witnesses = self.proof()
        relative = EVENT.relative_to(ROOT).as_posix()
        self.assertEqual(list(witnesses), [relative])
        self.assertEqual(self.manifest["witnesses"][0]["reviewer_commit"], self.event["head_sha"])

    def test_old_ancestry_red_and_exact_review_green(self):
        with self.assertRaisesRegex(ContractValidationError, "EVENT_SUBJECT_NOT_ANCESTOR"):
            subject._validate_event_git_provenance(
                ROOT, [EVENT], [self.event], self.head)
        allowed = subject._validate_event_git_provenance(
            ROOT, [EVENT], [self.event], self.head, self.proof())
        self.assertEqual(len(allowed), 40)

    def test_manifest_cannot_allow_arbitrary_events(self):
        for field,value,error in (
            ("authority", "ANY_ACTOR_ALLOWED", "EXTERNAL_REVIEW_WITNESS_MANIFEST_INVALID"),
            ("project_epoch", "FOREIGN_EPOCH", "EXTERNAL_REVIEW_WITNESS_MANIFEST_INVALID"),
        ):
            with self.subTest(field=field):
                value_map = copy.deepcopy(self.manifest)
                value_map[field] = value
                with self.assertRaisesRegex(ContractValidationError, error):
                    self.proof(manifest=value_map)
        duplicate = copy.deepcopy(self.manifest)
        duplicate["witnesses"].append(duplicate["witnesses"][0])
        with self.assertRaisesRegex(ContractValidationError, "EXTERNAL_REVIEW_WITNESS_SCOPE_INVALID"):
            self.proof(manifest=duplicate)

    def test_forged_event_blob_commit_parent_and_review_blob_rejected(self):
        for key, value, code in (
            ("event_blob_sha", "0"*40, "EXTERNAL_REVIEW_WITNESS_GIT_BLOB_MISMATCH"),
            ("review_result_blob_sha", "0"*40, "EXTERNAL_REVIEW_WITNESS_GIT_BLOB_MISMATCH"),
            ("reviewer_tree", "0"*40, "EXTERNAL_REVIEW_WITNESS_EVENT_IDENTITY_INVALID"),
            ("reviewed_product_commit", "0"*40, "EXTERNAL_REVIEW_WITNESS_EVENT_IDENTITY_INVALID"),
            ("review_result_path", "config/unrelated/forged.json", "EXTERNAL_REVIEW_WITNESS_PATH_INVALID"),
            ("event_path", "../escape/file.json", "EXTERNAL_REVIEW_WITNESS_PATH_INVALID"),
        ):
            with self.subTest(key=key):
                claim = copy.deepcopy(self.manifest)
                claim["witnesses"][0][key] = value
                with self.assertRaisesRegex(ContractValidationError, code):
                    self.proof(manifest=claim)

    def test_event_actor_subject_and_type_must_match_witness(self):
        for key,value in (
            ("actor", "DIRECTOR"),
            ("event_type", "MERGE_COMPLETED"),
            ("exit_code", 7),
            ("branch", "review/some-other-branch"),
        ):
            with self.subTest(key=key):
                event = copy.deepcopy(self.event)
                event[key] = value
                with self.assertRaisesRegex(
                    ContractValidationError, "EXTERNAL_REVIEW_WITNESS_EVENT_IDENTITY_INVALID"):
                    self.proof(event=event)

    def test_review_receipt_not_replaced_by_metadata_claim(self):
        # Spoofing cannot rename a different author or justify a second
        # mutation: the witness requires a direct-child one-file Git diff,
        # main's identical Git blob, and an actual PASS review DTO.
        witness = self.manifest["witnesses"][0]
        self.assertEqual(witness["review_result_blob_sha"],
                         subprocess.check_output(
                             ["git", "rev-parse", "HEAD:"+witness["review_result_path"]],
                             cwd=ROOT, text=True).strip())
        receipt = read_json(ROOT / witness["review_result_path"])
        self.assertEqual(receipt["reviewed_head"], witness["reviewed_product_commit"])
        self.assertEqual(receipt["role"], "FRESH_INDEPENDENT_REVIEWER")
        self.assertEqual(receipt["verdict"], "PASS")
        self.assertFalse(receipt["merge_performed"])


if __name__ == "__main__":
    unittest.main()
