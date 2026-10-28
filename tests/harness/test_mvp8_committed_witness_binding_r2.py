"""R2 adversarial acceptance: local witness bytes never replace durable Git authority.

Review RED on original PR #839 used a full Status in a temporary checkout
without a committed witness. This regression isolates the exact new gate
from unrelated full-CLI Git/state policy; normal full Status is still an
independent required Windows+Linux CI stage.
"""
from __future__ import annotations

from contextlib import contextmanager
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
WITNESS = ("config/control/harness/executions/E2026-09-09-V0-MVP-R1/"
           "external-role-event-witness.v1.json")
EPOCH = "config/control/harness/executions/E2026-09-09-V0-MVP-R1"
SOURCE_HEAD = subprocess.check_output(
    ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True,
).strip()


def git(*args: str, cwd: Path = ROOT) -> str:
    return subprocess.check_output(
        ["git", *args], cwd=cwd, text=True, stderr=subprocess.PIPE,
    ).strip()


@contextmanager
def disposable_named_worktree(branch_name: str):
    with tempfile.TemporaryDirectory(prefix="review-witness-r2-") as td:
        isolated = Path(td) / "repo"
        subprocess.run(
            ["git", "-C", str(ROOT), "worktree", "add", "--detach",
             str(isolated), SOURCE_HEAD],
            check=True, capture_output=True, text=True,
        )
        try:
            git("switch", "-c", branch_name, cwd=isolated)
            yield isolated
        finally:
            subprocess.run(
                ["git", "-C", str(ROOT), "worktree", "remove",
                 "--force", str(isolated)],
                check=False, capture_output=True, text=True,
            )
            subprocess.run(
                ["git", "-C", str(ROOT), "branch", "-D", branch_name],
                check=False, capture_output=True, text=True,
            )


def check_witness(root: Path) -> subprocess.CompletedProcess:
    # Direct subprocess is platform-neutral: do NOT conflate an unrelated
    # transient full Harness error with the explicit authorization guard.
    code = """
from pathlib import Path
import subprocess
import sys
from harness.contracts import ContractValidationError, read_json
from harness.state_builder import _external_reviewer_witnesses
root = Path.cwd()
epoch = root / 'config/control/harness/executions/E2026-09-09-V0-MVP-R1'
work = read_json(epoch / 'work-orders/V0-MVP-R1-WO-001.v1.json')
event = epoch / 'events/V0-MVP-R1-WO-001/0050-mvp8-repair-r2-independent-reviewer-pass.v1.json'
head = subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
try:
    result = _external_reviewer_witnesses(
        root, epoch, work, [event], [read_json(event)], head)
except ContractValidationError as exc:
    print('REVIEW_WITNESS_DENIED='+str(exc),flush=True)
    raise SystemExit(3)
print('REVIEW_WITNESS_ACCEPTED='+str(len(result)),flush=True)
"""
    env = dict(os.environ)
    env["PYTHONPATH"] = str(root / "scripts")
    return subprocess.run(
        [sys.executable, "-c", code], cwd=root, env=env,
        capture_output=True, text=True, timeout=35,
    )


class DurableWitnessMustFailClosed(unittest.TestCase):
    def test_valid_committed_one_add_witness_accepted(self):
        result = check_witness(ROOT)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertIn("REVIEW_WITNESS_ACCEPTED=1", result.stdout)

    def test_ignored_untracked_manifest_cannot_grant_event_ancestry_exception(self):
        original = (ROOT / WITNESS).read_bytes()
        with disposable_named_worktree("review-local-ignored-witness") as isolated:
            git("rm", "--", WITNESS, cwd=isolated)
            subprocess.run(
                ["git", "-c", "user.name=Adversarial Review",
                 "-c", "user.email=reviewer@example.invalid",
                 "commit", "-m", "test only: remove manifest from HEAD"],
                cwd=isolated, check=True, capture_output=True, text=True,
            )
            self.assertNotEqual(
                subprocess.run(
                    ["git","cat-file","-e","HEAD:"+WITNESS],cwd=isolated,
                    capture_output=True).returncode, 0,
            )
            (isolated / WITNESS).write_bytes(original)
            (isolated / ".gitignore").write_text("/"+WITNESS+"\n",encoding="utf-8")
            self.assertEqual(git("status","--porcelain","--",WITNESS,cwd=isolated),"")
            result = check_witness(isolated)
            print("R2_IGNORED_UNTRACKED_WITNESS="+result.stdout.strip(),flush=True)
            self.assertEqual(result.returncode,3,result.stdout+result.stderr)
            self.assertIn(
                "REVIEW_WITNESS_DENIED=EXTERNAL_REVIEW_WITNESS_MANIFEST_NOT_COMMITTED",
                result.stdout,
            )

    def test_skip_worktree_changed_bytes_must_not_authorize(self):
        with disposable_named_worktree("review-local-assume-unchanged") as isolated:
            manifest = isolated / WITNESS
            original = manifest.read_text(encoding="utf-8")
            self.assertIn('"version": 1',original)
            git("update-index","--assume-unchanged",WITNESS,cwd=isolated)
            manifest.write_text(
                original.replace('"version": 1','"version":  1'),encoding="utf-8",
            )
            self.assertEqual(git("status","--porcelain","--",WITNESS,cwd=isolated),"")
            result=check_witness(isolated)
            print("R2_ASSUME_UNCHANGED_WITNESS="+result.stdout.strip(),flush=True)
            self.assertEqual(result.returncode,3,result.stdout+result.stderr)
            self.assertIn(
                "REVIEW_WITNESS_DENIED=EXTERNAL_REVIEW_WITNESS_MANIFEST_DIRTY",
                result.stdout,
            )

    def test_committed_manifest_rewrite_must_not_reauthorize(self):
        with disposable_named_worktree("review-local-rewritten-witness") as isolated:
            manifest = isolated / WITNESS
            manifest.write_bytes(manifest.read_bytes()+b"\n")
            git("add","--",WITNESS,cwd=isolated)
            subprocess.run(
                ["git", "-c", "user.name=Adversarial Review",
                 "-c", "user.email=reviewer@example.invalid",
                 "commit", "-m", "test only: rewrite witness authority"],
                cwd=isolated,check=True,capture_output=True,text=True,
            )
            self.assertEqual(git("status","--porcelain","--",WITNESS,cwd=isolated),"")
            result=check_witness(isolated)
            print("R2_REWRITTEN_WITNESS="+result.stdout.strip(),flush=True)
            self.assertEqual(result.returncode,3,result.stdout+result.stderr)
            self.assertIn(
                "REVIEW_WITNESS_DENIED=EXTERNAL_REVIEW_WITNESS_MANIFEST_NOT_IMMUTABLE",
                result.stdout,
            )


if __name__=="__main__":
    unittest.main()
