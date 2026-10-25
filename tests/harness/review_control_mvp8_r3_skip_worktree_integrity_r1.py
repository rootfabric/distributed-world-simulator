"""Fresh adversarial evidence-only review of PR855 R3 Git-byte integrity.

Never edits product HEAD. Tests novel skip-worktree and semantic-no-op
on-disk manipulations not in the R3 normative tests. An event or receipt
with bytes different from HEAD must be rejected even if status is clean.
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

ROOT=Path(__file__).resolve().parents[2]
PRODUCT_HEAD="7510aa4ff81e6d3a13bbfa0872b6f60bfb547621"
PRODUCT_TREE="5003355e504c620c7f4bb0413bda6d4f36b9fd8d"
EPOCH="config/control/harness/executions/E2026-09-09-V0-MVP-R1"
EVENT=EPOCH+"/events/V0-MVP-R1-WO-001/0050-mvp8-repair-r2-independent-reviewer-pass.v1.json"
REVIEW=EPOCH+"/verifications/MVP8-INDEPENDENT-REVIEW-DC6E7FFF-R1.v1.json"


def git(root: Path,*args: str)->str:
    return subprocess.check_output(["git",*args],cwd=root,text=True,
                                   stderr=subprocess.PIPE).strip()


@contextmanager
def fresh_named_worktree(label: str):
    with tempfile.TemporaryDirectory(prefix="r3-new-review-") as tmp:
        target=Path(tmp)/"repo"
        branch="r3-critic-"+label+"-"+uuid4().hex[:12]
        subprocess.run(["git","-C",str(ROOT),"worktree","add","--detach",
                        str(target),PRODUCT_HEAD],check=True,capture_output=True,text=True)
        try:
            git(target,"switch","-c",branch)
            assert git(target,"rev-parse","HEAD")==PRODUCT_HEAD
            assert git(target,"rev-parse","HEAD^{tree}")==PRODUCT_TREE
            yield target
        finally:
            subprocess.run(["git","-C",str(ROOT),"worktree","remove","--force",
                            str(target)],capture_output=True)
            subprocess.run(["git","-C",str(ROOT),"branch","-D",branch],
                           capture_output=True)


def prove(root:Path):
    # This is the production trust-boundary function, not a simplified mock.
    script=StringLiteral = """
from pathlib import Path
import subprocess,sys
from harness.contracts import read_json,ContractValidationError
from harness.state_builder import _external_reviewer_witnesses,_validate_event_git_provenance
root=Path.cwd()
ep=root/'config/control/harness/executions/E2026-09-09-V0-MVP-R1'
wo=read_json(ep/'work-orders/V0-MVP-R1-WO-001.v1.json')
eventpath=ep/'events/V0-MVP-R1-WO-001/0050-mvp8-repair-r2-independent-reviewer-pass.v1.json'
event=read_json(eventpath)
head=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
try:
    witness=_external_reviewer_witnesses(root,ep,wo,[eventpath],[event],head)
    _validate_event_git_provenance(root,[eventpath],[event],head,witness)
except ContractValidationError as exc:
    print('R3_REVIEW_PROOF_DENIED='+str(exc),flush=True)
    sys.exit(3)
print('R3_REVIEW_PROOF_ACCEPTED=true',flush=True)
"""
    env=dict(os.environ,PYTHONPATH=str(root/"scripts"))
    return subprocess.run([sys.executable,"-c",script],cwd=root,env=env,
                          capture_output=True,text=True,timeout=90)


class NovelGitByteReview(unittest.TestCase):
    def _attack(self,rel:str,label:str,error:str,field:str|None=None,value=None,whitespace=False):
        with fresh_named_worktree(label) as root:
            old=git(root,"rev-parse","HEAD:"+rel)
            target=root/rel
            original=target.read_bytes()
            git(root,"update-index","--skip-worktree",rel)
            if whitespace:
                # Preserves *all parsed fields*, changes just raw bytes.
                target.write_bytes(original+b"\n")
                self.assertEqual(json.loads(target.read_bytes()),
                                 json.loads(original))
            else:
                dto=json.loads(original)
                self.assertIn(field,dto)
                self.assertNotEqual(dto[field],value)
                dto[field]=value
                target.write_text(json.dumps(dto,ensure_ascii=False,indent=2)+"\n",
                                  encoding="utf-8")
            live=git(root,"hash-object","--no-filters","--",rel)
            self.assertNotEqual(old,live)
            status=git(root,"status","--porcelain","--",rel)
            self.assertEqual(status,"","Skip-worktree did not mask the edit")
            out=prove(root)
            print("NOVEL_R3_REVIEW_CASE="+label,flush=True)
            print("NOVEL_R3_REVIEW_HEAD_BLOB="+old,flush=True)
            print("NOVEL_R3_REVIEW_LIVE_BLOB="+live,flush=True)
            print("NOVEL_R3_REVIEW_RESULT="+out.stdout.strip(),flush=True)
            self.assertEqual(out.returncode,3,out.stdout+out.stderr)
            self.assertIn("R3_REVIEW_PROOF_DENIED="+error,out.stdout)

    def test_positive_control_original_exact_git_bytes(self):
        with fresh_named_worktree("positive") as root:
            out=prove(root)
            self.assertEqual(out.returncode,0,out.stdout+out.stderr)
            self.assertIn("R3_REVIEW_PROOF_ACCEPTED=true",out.stdout)

    def test_skip_worktree_event_sha_mismatch_refused(self):
        self._attack(EVENT,"skip-event",
                     "EXTERNAL_REVIEW_WITNESS_EVENT_LOCAL_BLOB_MISMATCH",
                     field="summary",value="REVIEW_FORGED_LOCAL_EVENT")

    def test_skip_worktree_reviewer_receipt_sha_mismatch_refused(self):
        self._attack(REVIEW,"skip-review",
                     "EXTERNAL_REVIEW_WITNESS_RECEIPT_LOCAL_BLOB_MISMATCH",
                     field="source_clean_after",value=False)

    def test_parse_equivalent_but_byte_different_receipt_refused(self):
        self._attack(REVIEW,"same-dto-newline",
                     "EXTERNAL_REVIEW_WITNESS_RECEIPT_LOCAL_BLOB_MISMATCH",
                     whitespace=True)


if __name__=="__main__":
    unittest.main()
