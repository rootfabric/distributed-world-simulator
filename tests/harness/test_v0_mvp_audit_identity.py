"""Real CLI audit-identity regressions; all authority changes are isolated fixtures."""
from __future__ import annotations

import json
from pathlib import Path
import unittest

from tests.harness import test_v0_mvp_epoch_resume as resume

EX = resume.EX


class MVPAuditIdentityTests(unittest.TestCase):
    fixture = resume.MVPEpochResumeTests.fixture
    cli = resume.MVPEpochResumeTests.cli
    append_audit = resume.MVPEpochResumeTests.append_audit
    append_progress = resume.MVPEpochResumeTests.append_progress

    def setUp(self):
        resume.MVPEpochResumeTests.setUp(self)

    def completed_audit(self, root: Path, *, changes=None, missing=()):
        first = self.append_audit(root)
        for kind, state in (("IMPLEMENTATION_COMMITTED", "IMPLEMENTED"),
                            ("VERIFICATION_STARTED", "VERIFYING"),
                            ("PREDICATE_VERIFIED", "VERIFIED")):
            self.append_progress(root, kind, state)
        audit = json.loads((root / first).read_text())
        audit.update(changes or {})
        for key in missing:
            audit.pop(key, None)
        relative = EX + "/audits/completed-identity-test.v1.json"
        (root / relative).write_text(json.dumps(audit) + "\n", encoding="utf-8")
        self.append_progress(root, "AUDIT_COMPLETED", "AUDITED", [relative])

    def test_foreign_completed_order_is_rejected(self):
        with self.fixture(adopted=True) as root:
            self.completed_audit(root, changes={"work_order_id": "FOREIGN-WORK-ORDER"})
            code, result = self.cli(root, "drive")
            self.assertEqual(3, code, result)
            self.assertIn("MVP_RESUME_AUDIT_IDENTITY_MISMATCH", result["error"]["detail"])

    def test_foreign_completed_epoch_is_rejected(self):
        with self.fixture(adopted=True) as root:
            self.completed_audit(root, changes={"project_epoch": "E-FOREIGN"})
            code, result = self.cli(root, "drive")
            self.assertEqual(3, code, result)
            self.assertIn("MVP_RESUME_AUDIT_IDENTITY_MISMATCH", result["error"]["detail"])

    def test_missing_completed_identity_is_rejected(self):
        for key in ("project_epoch", "work_order_id", "base_sha"):
            with self.subTest(key=key), self.fixture(adopted=True) as root:
                self.completed_audit(root, missing=(key,))
                code, result = self.cli(root, "drive")
                self.assertEqual(3, code, result)
                self.assertIn("MVP_RESUME_AUDIT_IDENTITY_MISMATCH", result["error"]["detail"])

    def test_valid_completed_audit_keeps_main_distinct_from_implementation(self):
        with self.fixture(adopted=True) as root:
            canonical_main = resume.git(root, "rev-parse", "origin/main")
            self.completed_audit(root)
            directory = root / EX / "events" / resume.WO
            latest = max((json.loads(p.read_text()) for p in directory.glob("*.json")), key=lambda e: e["sequence"])
            self.assertNotEqual(canonical_main, latest["head_sha"])
            code, result = self.cli(root, "drive")
            self.assertEqual(0, code, result)
            self.assertEqual("MAIN_MOVED_AUDIT_CONTINUE", result["epoch"]["validation"]["status"])
            self.assertEqual("CONTINUE", result["epoch"]["validation"]["action"])
            self.assertEqual("AUDITED", result["reduced_work_order"]["state"])
            self.assertEqual([], result["reduced_work_order"]["completed_predicates"])
            self.assertFalse(result["next"]["mission_complete"])
            close_code, closed = self.cli(root, "close-mission")
            self.assertEqual(8, close_code, closed)


if __name__ == "__main__":
    unittest.main()
