"""Adversarial Reviewer: an ignored untracked witness may not authorize events.

Original reviewer RED on PR #839 (recorded separately): an ignored,
untracked witness absent from HEAD authorized an event ancestry exception.
This normatively proves RED-before -> GREEN-after at the current HEAD,
and rejects a tracked-file skip-worktree mismatch and a rewritten manifest.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE_HEAD = subprocess.check_output(
    ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True,
).strip()
WITNESS = ("config/control/harness/executions/E2026-09-09-V0-MVP-R1/"
           "external-role-event-witness.v1.json")


def git(*args: str, cwd: Path = ROOT) -> str:
    return subprocess.check_output(
        ["git", *args], cwd=cwd, text=True, stderr=subprocess.PIPE,
    ).strip()


class UntrackedWitnessMustFailClosed(unittest.TestCase):
    def test_ignored_untracked_manifest_cannot_grant_event_ancestry_exception(self):
        # The test exact source itself is a detached child of the reviewed HEAD;
        # only the TEMP worktree receives a non-published commit.
        self.assertEqual(git("rev-parse", SOURCE_HEAD+"^{commit}"), SOURCE_HEAD)
        manifest_bytes = (ROOT / WITNESS).read_bytes()

        with tempfile.TemporaryDirectory(prefix="review-ignored-witness-") as temp:
            isolated = Path(temp) / "detached"
            subprocess.run(
                ["git", "-C", str(ROOT), "worktree", "add", "--detach",
                 str(isolated), SOURCE_HEAD],
                check=True, capture_output=True, text=True,
            )
            try:
                # Harness requires a named branch, not detached HEAD.
                # The temporary probe is entirely disposable and unpushed.
                subprocess.run(
                    ["git", "switch", "-c", "review-local-ignored-witness"],
                    cwd=isolated, check=True, capture_output=True, text=True,
                )
                subprocess.run(
                    ["git", "rm", "--", WITNESS], cwd=isolated,
                    check=True, capture_output=True, text=True,
                )
                subprocess.run(
                    ["git", "-c", "user.name=Adversarial Review",
                     "-c", "user.email=reviewer@example.invalid",
                     "commit", "-m", "test only: no durable witness in HEAD"],
                    cwd=isolated, check=True, capture_output=True, text=True,
                )
                self.assertNotEqual(
                    subprocess.run(
                        ["git", "cat-file", "-e", "HEAD:"+WITNESS],
                        cwd=isolated, stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                    ).returncode, 0,
                )
                candidate = isolated / WITNESS
                candidate.parent.mkdir(parents=True, exist_ok=True)
                candidate.write_bytes(manifest_bytes)
                (isolated / ".gitignore").write_text(
                    "/"+WITNESS+"\n", encoding="utf-8",
                )
                self.assertEqual(
                    git("status", "--porcelain", "--", WITNESS, cwd=isolated), "",
                    "Falsifier failed to hide the untracked witness",
                )
                env = dict(os.environ)
                env["PYTHONPATH"] = str(isolated / "scripts")
                result = subprocess.run(
                    [sys.executable, "-m", "harness.cli", "status",
                     "--root", str(isolated)],
                    cwd=isolated, env=env, capture_output=True, text=True,
                    timeout=90,
                )
                try:
                    envelope = json.loads(result.stdout.strip().splitlines()[-1])
                except Exception as exc:
                    self.fail("Missing Status JSON: "+repr(exc)+" / "+
                              result.stdout[-800:]+result.stderr[-800:])
                print("REVIEW_EXACT_SOURCE="+SOURCE_HEAD, flush=True)
                print("REVIEW_WITNESS_IN_HEAD=false", flush=True)
                print("REVIEW_WORKTREE_WITNESS_IGNORED=true", flush=True)
                print("REVIEW_STATUS_EXIT="+str(result.returncode), flush=True)
                print("REVIEW_STATUS_OK="+str(envelope.get("ok")), flush=True)
                print("REVIEW_STATUS_ERROR="+str(envelope.get("error")), flush=True)
                self.assertNotEqual(
                    result.returncode, 0,
                    "CRITICAL: ignored untracked witness authorized event #0050"
                    " without a durable Git manifest",
                )
                self.assertEqual(envelope.get("ok"), False)
                self.assertIn(
                    envelope.get("error", {}).get("detail", ""),
                    (
                        "EXTERNAL_REVIEW_WITNESS_MANIFEST_NOT_COMMITTED",
                        "EXTERNAL_REVIEW_WITNESS_MANIFEST_DIRTY",
                        "EXTERNAL_REVIEW_WITNESS_GIT_BLOB_MISMATCH",
                    ),
                )
            finally:
                subprocess.run(
                    ["git", "-C", str(ROOT), "worktree", "remove",
                     "--force", str(isolated)],
                    capture_output=True, text=True,
                )

    def test_skip_worktree_changed_bytes_cannot_authorize_provenance(self):
        # Git porcelain can also be empty for a tracked path marked
        # "assume-unchanged"; a live byte/hash compare is mandatory.
        with tempfile.TemporaryDirectory(prefix="review-skipped-witness-") as temp:
            isolated = Path(temp) / "checkout"
            subprocess.run(
                ["git", "-C", str(ROOT), "worktree", "add", "--detach",
                 str(isolated), SOURCE_HEAD],
                check=True, capture_output=True, text=True,
            )
            try:
                git("switch", "-c", "review-local-assume-unchanged", cwd=isolated)
                candidate = isolated / WITNESS
                original = candidate.read_text(encoding="utf-8")
                self.assertIn('"version": 1', original)
                git("update-index", "--assume-unchanged", WITNESS, cwd=isolated)
                candidate.write_text(
                    original.replace('"version": 1', '"version":  1'),
                    encoding="utf-8",
                )
                self.assertEqual(
                    git("status", "--porcelain", "--", WITNESS, cwd=isolated), "",
                    "Test cannot demonstrate hidden changed bytes",
                )
                env = dict(os.environ, PYTHONPATH=str(isolated / "scripts"))
                result = subprocess.run(
                    [sys.executable, "-m", "harness.cli", "status",
                     "--root", str(isolated)],
                    cwd=isolated, env=env, capture_output=True, text=True,
                    timeout=90,
                )
                report = json.loads(result.stdout.strip().splitlines()[-1])
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(
                    report["error"]["detail"],
                    "EXTERNAL_REVIEW_WITNESS_MANIFEST_DIRTY",
                )
            finally:
                subprocess.run(
                    ["git", "-C", str(ROOT), "worktree", "remove",
                     "--force", str(isolated)],
                    capture_output=True, text=True,
                )

    def test_rewritten_committed_manifest_must_fail_immutability(self):
        with tempfile.TemporaryDirectory(prefix="review-rewrite-witness-") as temp:
            isolated = Path(temp) / "checkout"
            subprocess.run(
                ["git", "-C", str(ROOT), "worktree", "add", "--detach",
                 str(isolated), SOURCE_HEAD],
                check=True, capture_output=True, text=True,
            )
            try:
                git("switch", "-c", "review-local-rewritten-witness", cwd=isolated)
                candidate = isolated / WITNESS
                candidate.write_bytes(candidate.read_bytes() + b"\n")
                git("add", "--", WITNESS, cwd=isolated)
                subprocess.run(
                    ["git", "-c", "user.name=Adversarial Review",
                     "-c", "user.email=reviewer@example.invalid",
                     "commit", "-m", "test only: rewrite trusted witness"],
                    cwd=isolated, check=True, capture_output=True, text=True,
                )
                self.assertEqual(
                    git("status", "--porcelain", "--", WITNESS, cwd=isolated), ""
                )
                env = dict(os.environ, PYTHONPATH=str(isolated / "scripts"))
                result = subprocess.run(
                    [sys.executable, "-m", "harness.cli", "status",
                     "--root", str(isolated)],
                    cwd=isolated, env=env, capture_output=True, text=True,
                    timeout=90,
                )
                report = json.loads(result.stdout.strip().splitlines()[-1])
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(
                    report["error"]["detail"],
                    "EXTERNAL_REVIEW_WITNESS_MANIFEST_NOT_IMMUTABLE",
                )
            finally:
                subprocess.run(
                    ["git", "-C", str(ROOT), "worktree", "remove",
                     "--force", str(isolated)],
                    capture_output=True, text=True,
                )



if __name__ == "__main__":
    unittest.main()
