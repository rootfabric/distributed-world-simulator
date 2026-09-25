#!/usr/bin/env python3
"""Read-only exact-current-main PC0 probe for MVP6 epoch-movement diagnosis.

This probe never writes an epoch audit and never converts RED into NON_RED.  It
runs the canonical standard and directional auditors in a detached worktree of
origin/main and preserves their raw reports plus hashes outside the feature
checkout.  A separate Director action may record CONTINUE only when those raw
reports themselves prove both required NON_RED conditions.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(os.environ.get("MVP6_MAIN_PC0_OUTPUT", str(ROOT / "artifacts/mvp6-current-main-pc0"))).resolve()
WORKTREE = Path(os.environ.get("MVP6_MAIN_PC0_WORKTREE", str(OUT.parent / "mvp6-current-main-worktree"))).resolve()


def run(argv: list[str], *, cwd: Path, log: Path | None = None) -> subprocess.CompletedProcess[str]:
    if log is None:
        return subprocess.run(argv, cwd=cwd, text=True, capture_output=True, check=False)
    with log.open("w", encoding="utf-8") as stream:
        return subprocess.run(argv, cwd=cwd, text=True, stdout=stream, stderr=subprocess.STDOUT, check=False)


def git(*args: str) -> str:
    result = run(["git", *args], cwd=ROOT)
    if result.returncode != 0:
        raise RuntimeError(f"GIT_FAILED:{' '.join(args)}:{result.stderr.strip()}")
    return result.stdout.strip()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def overall(report: dict) -> str:
    for key in ("overall", "overall_health", "health"):
        value = report.get(key)
        if isinstance(value, str) and value:
            return value
    for key in ("summary", "status"):
        value = report.get(key)
        if isinstance(value, dict):
            for nested in ("overall", "overall_health", "health"):
                observed = value.get(nested)
                if isinstance(observed, str) and observed:
                    return observed
    return "UNKNOWN"


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    if any(OUT.iterdir()):
        raise RuntimeError(f"PRESERVE_EXISTING_PROBE_OUTPUT:{OUT}")

    main_sha = git("rev-parse", "origin/main^{commit}")
    expected = os.environ.get("MVP6_EXPECTED_MAIN_SHA", "").strip()
    if expected and main_sha != expected:
        raise RuntimeError(f"MAIN_MOVED_DURING_PROBE:{main_sha}:expected:{expected}")

    if WORKTREE.exists():
        raise RuntimeError(f"PROBE_WORKTREE_ALREADY_EXISTS:{WORKTREE}")
    add = run(["git", "worktree", "add", "--detach", str(WORKTREE), main_sha], cwd=ROOT)
    if add.returncode != 0:
        raise RuntimeError(f"WORKTREE_ADD_FAILED:{add.stderr.strip()}")

    try:
        actual = run(["git", "rev-parse", "HEAD"], cwd=WORKTREE)
        if actual.returncode != 0 or actual.stdout.strip() != main_sha:
            raise RuntimeError("EXACT_MAIN_WORKTREE_REQUIRED")
        status = run(["git", "status", "--porcelain", "--untracked-files=all"], cwd=WORKTREE)
        if status.returncode != 0 or status.stdout.strip():
            raise RuntimeError("MAIN_PROBE_WORKTREE_NOT_CLEAN")

        standard_log = OUT / "standard.log"
        directional_log = OUT / "directional.log"
        standard = run(
            [sys.executable, "scripts/control/project_control.py", "--no-fetch", "--no-fail-on-red"],
            cwd=WORKTREE,
            log=standard_log,
        )
        directional = run(
            [sys.executable, "scripts/control/project_control_directional_watch.py", "--no-fail-on-red"],
            cwd=WORKTREE,
            log=directional_log,
        )
        if standard.returncode != 0 or directional.returncode != 0:
            raise RuntimeError(
                f"PC0_AUDITOR_EXECUTION_FAILED:standard={standard.returncode}:directional={directional.returncode}"
            )

        source = WORKTREE / "artifacts/control"
        required = {
            "project-control-report.json": OUT / "project-control-report.json",
            "directional-watch-report.json": OUT / "directional-watch-report.json",
            "PROJECT_STATUS_RU.md": OUT / "PROJECT_STATUS_RU.md",
            "DIRECTIONAL_WATCH_STATUS_RU.md": OUT / "DIRECTIONAL_WATCH_STATUS_RU.md",
        }
        for name, target in required.items():
            current = source / name
            if not current.is_file():
                raise RuntimeError(f"PC0_REPORT_MISSING:{name}")
            shutil.copy2(current, target)

        standard_report = json.loads((OUT / "project-control-report.json").read_text(encoding="utf-8"))
        directional_report = json.loads((OUT / "directional-watch-report.json").read_text(encoding="utf-8"))
        if not isinstance(standard_report, dict) or not isinstance(directional_report, dict):
            raise RuntimeError("PC0_REPORT_OBJECT_REQUIRED")

        summary = {
            "schema": "distributed_world_simulator.mvp6_current_main_pc0_probe.v1",
            "main_sha": main_sha,
            "feature_subject_head": os.environ.get("EXPECTED_HEAD", ""),
            "standard_exit_code": standard.returncode,
            "directional_exit_code": directional.returncode,
            "standard_overall": overall(standard_report),
            "directional_overall": overall(directional_report),
            "standard_report_sha256": sha256(OUT / "project-control-report.json"),
            "directional_report_sha256": sha256(OUT / "directional-watch-report.json"),
            "standard_log_sha256": sha256(standard_log),
            "directional_log_sha256": sha256(directional_log),
            "audit_written": False,
            "continuation_claimed": False,
        }
        (OUT / "probe-summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(summary, sort_keys=True), flush=True)
        return 0
    finally:
        run(["git", "worktree", "remove", "--force", str(WORKTREE)], cwd=ROOT)
        run(["git", "worktree", "prune"], cwd=ROOT)


if __name__ == "__main__":
    raise SystemExit(main())
