"""ACT0 compatibility tests for current-main MVP verification carriers.

The canonical ACT0 suite is reused from the current main blob. Only the fixture
lineage and the MVP-progress-specific assertions are specialized here: synthetic
authority fixtures start from the fetched canonical control main, where later MVP
progress events never existed, so append-only history is preserved without
presenting an old policy snapshot as current H0 provenance.
"""
from __future__ import annotations

from contextlib import contextmanager
import json
from pathlib import Path
import shutil
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
        """Use canonical authority plus the exact candidate Harness implementation.

        Authority JSON starts from fetched canonical main. When the candidate changes
        state_builder.py, that exact committed candidate blob is layered onto the
        synthetic feature branch in its own fixture-only commit. This prevents a
        Harness repair test from accidentally executing the older main implementation
        while leaving origin/main and all authority inputs canonical.

        Teardown is intentionally non-authorizing: the fixture directory is ephemeral
        test scratch space, so a transient filesystem cleanup race must not replace the
        already-computed Harness verdict with a false test failure.
        """
        tmp = tempfile.mkdtemp(prefix="act0-authority-")
        try:
            root = Path(tmp) / "repo"
            subprocess.run(
                [
                    "git", "clone", "--quiet", "--shared",
                    "-c", "maintenance.auto=false",
                    "-c", "gc.auto=0",
                    "-c", "gc.autoDetach=false",
                    str(ROOT), str(root),
                ],
                check=True,
            )
            control_main = git(ROOT, "rev-parse", "origin/main")
            candidate_head = git(ROOT, "rev-parse", "HEAD")
            git(root, "checkout", "--quiet", "-B", BRANCH, control_main)
            git(root, "update-ref", "refs/remotes/origin/main", control_main if adopted else BASE)

            relative = "scripts/harness/state_builder.py"
            candidate_bytes = subprocess.check_output(
                ["git", "show", f"{candidate_head}:{relative}"], cwd=ROOT
            )
            main_bytes = subprocess.check_output(
                ["git", "show", f"{control_main}:{relative}"], cwd=ROOT
            )
            if candidate_bytes != main_bytes:
                (root / relative).write_bytes(candidate_bytes)
                git(root, "add", "--", relative)
                git(
                    root,
                    "-c", "user.name=ACT0 candidate harness fixture",
                    "-c", "user.email=fixture@example.invalid",
                    "commit", "-qm", "test-only candidate Harness implementation",
                )
            yield root
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


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
