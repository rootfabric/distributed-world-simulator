"""ACT0 compatibility tests for current-main MVP verification carriers.

The canonical ACT0 suite is reused from the current main blob.  Only the fixture
lineage and the MVP-progress-specific assertions are specialized here: synthetic
authority fixtures start from the fetched canonical control main, where later MVP
progress events never existed, so append-only history is preserved without
presenting an old policy snapshot as current H0 provenance.
"""
from __future__ import annotations

from contextlib import contextmanager
import json
from pathlib import Path
import subprocess
import tempfile

from tests.harness import mvp_act0_base as base

ROOT = base.ROOT
BASE = base.BASE
P7 = base.P7
MVP = base.MVP
BRANCH = base.BRANCH
EPOCH = base.EPOCH
WO = base.WO
H = base.H
EX = base.EX
git = base.git
read = base.read


class MVPAct0Tests(base.MVPAct0Tests):
    @contextmanager
    def fixture(self, adopted: bool):
        """Use current canonical control main, never a copied legacy policy snapshot."""
        with tempfile.TemporaryDirectory(prefix="act0-authority-") as tmp:
            root = Path(tmp) / "repo"
            subprocess.run(["git", "clone", "--quiet", "--shared", str(ROOT), str(root)], check=True)
            control_main = git(ROOT, "rev-parse", "origin/main")
            git(root, "checkout", "--quiet", "-B", BRANCH, control_main)
            git(root, "update-ref", "refs/remotes/origin/main", control_main if adopted else BASE)
            yield root

    def test_all_p7_execution_and_acceptance_blobs_are_unchanged(self):
        for path in (H + "executions/E2026-08-30-V0-P7-R1", H + "acceptance"):
            self.assertEqual("", git(ROOT, "diff", "--name-only", BASE, "HEAD", "--", path))
        for path in (
            "scripts/runtime/networked_gameplay/p7",
            "scripts/runtime/networked_gameplay/m4",
            "scripts/runtime/networked_gameplay/sm1",
            "scripts/network",
            "scripts/simulation",
            "project.godot",
            "config/architecture",
        ):
            self.assertEqual("", git(ROOT, "diff", "--name-only", BASE, "HEAD", "--", path), path)

    def test_current_mvp_work_order_snapshot_matches_latest_committed_event(self):
        order = read(EX + "/work-orders/" + WO + ".v1.json")
        directory = ROOT / EX / "events" / WO
        events = [json.loads(path.read_text(encoding="utf-8")) for path in directory.glob("*.json")]
        self.assertTrue(events)
        latest = max(events, key=lambda event: event["sequence"])
        self.assertEqual(latest["work_state"], order["state"])

    def test_preimplementation_fixture_never_deletes_future_ledger_events(self):
        with self.fixture(adopted=True) as root:
            event_dir = root / EX / "events" / WO
            self.assertFalse((event_dir / "0004-mvp1-shared-graphical-scene-implementation.v1.json").exists())
            control_main = git(ROOT, "rev-parse", "origin/main")
            deleted = git(
                root,
                "log",
                "--diff-filter=D",
                "--format=%H",
                control_main + "..HEAD",
                "--",
                EX + "/events/" + WO,
            )
            self.assertEqual("", deleted)
