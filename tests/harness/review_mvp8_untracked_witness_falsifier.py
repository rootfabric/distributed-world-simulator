"""Adversarial Reviewer: an ignored untracked witness may not authorize events.

RED on PR #839 original HEAD: metadata exists in the working tree and is
ignored, but is NOT in HEAD. Despite being ephemeral, it authorizes an
otherwise non-ancestor Reviewer event. No product files are edited.
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
SOURCE_HEAD = "a2a8e93f065f9cee8fc8a39eb03df29be322c786"
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


if __name__ == "__main__":
    unittest.main()
