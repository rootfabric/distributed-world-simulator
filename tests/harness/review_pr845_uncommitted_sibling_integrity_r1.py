"""Independent PR845 adversarial review: sibling local evidence has Git authority.

Exact PR845 product HEAD is read-only; this reviewer creates disposable named
worktrees with one assume-unchanged-but-dirty evidentiary input per test.
A live file may NEVER override its committed Git blob in a privileged
non-ancestor reviewer authorization path. Tests are expected RED on the
unmodified original product subject.
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

ROOT = Path(__file__).resolve().parents[2]
SOURCE = "3a8f858f85c5ff018676557650f34179d6d5f86b"
EPOCH = "config/control/harness/executions/E2026-09-09-V0-MVP-R1"
EVENT = EPOCH + "/events/V0-MVP-R1-WO-001/0050-mvp8-repair-r2-independent-reviewer-pass.v1.json"
RECEIPT = EPOCH + "/verifications/MVP8-INDEPENDENT-REVIEW-DC6E7FFF-R1.v1.json"

def git(root: Path, *args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=root, text=True,
                                   stderr=subprocess.PIPE).strip()

@contextmanager
def isolated(branch: str):
    with tempfile.TemporaryDirectory(prefix="review-pr845-sibling-") as temp:
        checkout = Path(temp) / "repo"
        subprocess.run(["git","-C",str(ROOT),"worktree","add","--detach",
                       str(checkout),SOURCE],check=True,text=True,capture_output=True)
        try:
            git(checkout,"switch","-c",branch)
            yield checkout
        finally:
            subprocess.run(["git","-C",str(ROOT),"worktree","remove","--force",
                            str(checkout)],capture_output=True)
            subprocess.run(["git","-C",str(ROOT),"branch","-D",branch],
                           capture_output=True)

def check_exact_authority(root: Path) -> subprocess.CompletedProcess:
    # Full review validation, without unrelated status/epoch/mission machinery.
    script = """
from pathlib import Path
import subprocess
from harness.contracts import read_json,ContractValidationError
from harness.state_builder import _external_reviewer_witnesses,_validate_event_git_provenance
root=Path.cwd()
epoch=root/"config/control/harness/executions/E2026-09-09-V0-MVP-R1"
work=read_json(epoch/"work-orders/V0-MVP-R1-WO-001.v1.json")
event=epoch/"events/V0-MVP-R1-WO-001/0050-mvp8-repair-r2-independent-reviewer-pass.v1.json"
head=subprocess.check_output(["git","rev-parse","HEAD"],text=True).strip()
try:
    witness=_external_reviewer_witnesses(root,epoch,work,[event],[read_json(event)],head)
    _validate_event_git_provenance(root,[event],[read_json(event)],head,witness)
except ContractValidationError as exc:
    print("REVIEW_SIBLING_DENIED="+str(exc),flush=True)
    raise SystemExit(3)
print("REVIEW_SIBLING_UNCOMMITTED_ACCEPTED=true",flush=True)
"""
    env=dict(os.environ,PYTHONPATH=str(root/"scripts"))
    return subprocess.run([sys.executable,"-c",script],cwd=root,env=env,
                          capture_output=True,text=True,timeout=45)

class LocalSiblingProofMustMatchGit(unittest.TestCase):
    def _case(self, changed: str, branch: str, field: str, value):
        with isolated(branch) as root:
            target=root/changed
            original=json.loads(target.read_text(encoding="utf-8"))
            self.assertIn(field,original)
            self.assertNotEqual(original[field],value)
            git(root,"update-index","--assume-unchanged",changed)
            original[field]=value
            target.write_text(json.dumps(original,indent=2,ensure_ascii=False)+"\n",
                              encoding="utf-8")
            head_blob=git(root,"rev-parse","HEAD:"+changed)
            live_blob=git(root,"hash-object","--no-filters","--",changed)
            self.assertNotEqual(head_blob,live_blob)
            self.assertEqual(git(root,"status","--porcelain","--",changed),"")
            result=check_exact_authority(root)
            print("REVIEW_PR845_CASE="+field,flush=True)
            print("REVIEW_PR845_HEAD_GIT_BLOB="+head_blob,flush=True)
            print("REVIEW_PR845_WORKTREE_BLOB="+live_blob,flush=True)
            print("REVIEW_PR845_STATUS_EXIT="+str(result.returncode),flush=True)
            print("REVIEW_PR845_OUTPUT="+result.stdout.strip(),flush=True)
            print("REVIEW_PR845_STDERR="+result.stderr[-400:],flush=True)
            self.assertEqual(
                result.returncode,3,
                "PROVENANCE_FAIL: uncommitted changed "+field+
                " accepted despite exact HEAD blob mismatch: "+result.stdout,
            )
            self.assertIn("REVIEW_SIBLING_DENIED=",result.stdout)

    def test_event_raw_summary_not_borne_out_by_git_cannot_authorize(self):
        self._case(
            EVENT,"review-pr845-local-event",
            "summary","UNCOMMITTED_FORGED_REVIEWER_EVENT_SUMMARY",
        )

    def test_review_receipt_source_clean_false_cannot_authorize(self):
        self._case(
            RECEIPT,"review-pr845-local-receipt",
            "source_clean_after",False,
        )

if __name__=="__main__":
    unittest.main()
