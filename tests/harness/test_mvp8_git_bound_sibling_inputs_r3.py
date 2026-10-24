"""Issue #848 R3: Git-bound Reviewer event, receipt and caller DTO.

Fresh exact subject tests for the two independently demonstrated PR #845
REVIEW_FAIL cases. Each attack runs in a disposable named Git worktree;
the subject branch and all historical records stay immutable.
"""
from __future__ import annotations

from contextlib import contextmanager
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[2]
SOURCE_HEAD = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
EPOCH = "config/control/harness/executions/E2026-09-09-V0-MVP-R1"
EVENT = EPOCH + "/events/V0-MVP-R1-WO-001/0050-mvp8-repair-r2-independent-reviewer-pass.v1.json"
RECEIPT = EPOCH + "/verifications/MVP8-INDEPENDENT-REVIEW-DC6E7FFF-R1.v1.json"
EVENT_BLOB = "b27cc80072fcb66cb217004ddad35aeb381d37a0"
RECEIPT_BLOB = "3759b7caf84ef1e49a894ae2d6b5934e676c15b5"


def git(root: Path, *args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=root, text=True, stderr=subprocess.PIPE).strip()


@contextmanager
def disposable_named_worktree(case: str):
    with tempfile.TemporaryDirectory(prefix="control-r3-") as tmp:
        checkout = Path(tmp) / "repo"
        branch = "probe-r3-" + case + "-" + uuid4().hex[:12]
        subprocess.run(
            ["git", "-C", str(ROOT), "worktree", "add", "--detach", str(checkout), SOURCE_HEAD],
            check=True, text=True, capture_output=True,
        )
        try:
            git(checkout, "switch", "-c", branch)
            yield checkout
        finally:
            subprocess.run(
                ["git", "-C", str(ROOT), "worktree", "remove", "--force", str(checkout)],
                capture_output=True, text=True,
            )
            subprocess.run(
                ["git", "-C", str(ROOT), "branch", "-D", branch],
                capture_output=True, text=True,
            )


def proof(root: Path, forge_memory_dto: bool = False) -> subprocess.CompletedProcess:
    cmd = """
from pathlib import Path
import subprocess, sys
from harness.contracts import read_json, ContractValidationError
from harness.state_builder import _external_reviewer_witnesses, _validate_event_git_provenance
root=Path.cwd()
epoch=root / 'config/control/harness/executions/E2026-09-09-V0-MVP-R1'
work=read_json(epoch / 'work-orders/V0-MVP-R1-WO-001.v1.json')
event_path=epoch / 'events/V0-MVP-R1-WO-001/0050-mvp8-repair-r2-independent-reviewer-pass.v1.json'
event=read_json(event_path)
if sys.argv[1]=='forge':
    event['summary']='IN_MEMORY_ONLY_FORGED_REVIEWER_SUMMARY'
head=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
try:
    proven=_external_reviewer_witnesses(root,epoch,work,[event_path],[event],head)
    _validate_event_git_provenance(root,[event_path],[event],head,proven)
except ContractValidationError as exc:
    print('R3_PROVENANCE_DENIED='+str(exc),flush=True)
    sys.exit(3)
print('R3_GIT_BOUND_REVIEWER_ACCEPTED=true',flush=True)
"""
    env = dict(os.environ, PYTHONPATH=str(root / "scripts"))
    return subprocess.run(
        [sys.executable, "-c", cmd, "forge" if forge_memory_dto else "normal"],
        cwd=root, env=env, capture_output=True, text=True, timeout=65,
    )


class R3SiblingAuthorityTest(unittest.TestCase):
    def test_genuine_committed_event_and_receipt_still_accepted(self):
        self.assertEqual(git(ROOT, "rev-parse", "HEAD:"+EVENT), EVENT_BLOB)
        self.assertEqual(git(ROOT, "rev-parse", "HEAD:"+RECEIPT), RECEIPT_BLOB)
        run = proof(ROOT)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertIn("R3_GIT_BOUND_REVIEWER_ACCEPTED=true", run.stdout)

    def _local_mutation(self, file: str, field: str, forged: object, case: str, error: str):
        with disposable_named_worktree(case) as root:
            path = root / file
            contents = json.loads(path.read_text(encoding="utf-8"))
            self.assertIn(field, contents)
            self.assertNotEqual(contents[field], forged)
            # Prove this is NOT visible to status but IS a different blob.
            git(root, "update-index", "--assume-unchanged", file)
            contents[field] = forged
            path.write_text(json.dumps(contents, indent=2, ensure_ascii=False)+"\n", encoding="utf-8")
            self.assertEqual(git(root, "status", "--porcelain", "--", file), "")
            original = git(root, "rev-parse", "HEAD:"+file)
            forged_blob = git(root, "hash-object", "--no-filters", "--", file)
            self.assertNotEqual(original, forged_blob)
            run = proof(root)
            print("R3_TEST_CASE="+case,flush=True)
            print("R3_HEAD_BLOB="+original,flush=True)
            print("R3_UNCOMMITTED_BLOB="+forged_blob,flush=True)
            print("R3_PROOF_OUTPUT="+run.stdout.strip(),flush=True)
            self.assertEqual(run.returncode, 3, run.stdout + run.stderr)
            self.assertIn("R3_PROVENANCE_DENIED="+error, run.stdout)

    def test_hidden_uncommitted_event_summary_rejected(self):
        self._local_mutation(
            EVENT, "summary", "UNCOMMITTED_FORGED_EVENT_SUMMARY",
            "event", "EXTERNAL_REVIEW_WITNESS_EVENT_LOCAL_BLOB_MISMATCH",
        )

    def test_hidden_uncommitted_reviewer_receipt_rejected(self):
        self._local_mutation(
            RECEIPT, "source_clean_after", False,
            "receipt", "EXTERNAL_REVIEW_WITNESS_RECEIPT_LOCAL_BLOB_MISMATCH",
        )

    def test_forged_caller_supplied_event_dto_rejected(self):
        # Disk/HEAD/event remain identical. A caller cannot substitute a
        # partially modified in-memory event dictionary after those checks.
        run = proof(ROOT, forge_memory_dto=True)
        self.assertEqual(run.returncode, 3, run.stdout + run.stderr)
        self.assertIn(
            "R3_PROVENANCE_DENIED=EXTERNAL_REVIEW_WITNESS_EVENT_DTO_MISMATCH", run.stdout
        )


if __name__ == "__main__":
    unittest.main()
