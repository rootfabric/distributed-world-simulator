from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def _git_head() -> str:
    try:
        return subprocess.check_output(
            ["git", "rev-parse", "HEAD"],
            cwd=ROOT,
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (OSError, subprocess.CalledProcessError):
        return "UNKNOWN"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", default="")
    args = parser.parse_args()

    command = [
        sys.executable,
        "-m",
        "unittest",
        "discover",
        "-s",
        str(ROOT / "tests" / "research" / "seamless" / "i1"),
        "-p",
        "test_*.py",
        "-v",
    ]
    completed = subprocess.run(command, cwd=ROOT, text=True)
    report = {
        "schema": "distributed_world_simulator.sm1_i1_runner_report.v1",
        "checkpoint": "SM1-I1-A",
        "status": "RESEARCH_ONLY_NOT_PRODUCTION_ACCEPTANCE",
        "code_sha": _git_head(),
        "test_command": command,
        "exit_code": completed.returncode,
        "result": "PASS" if completed.returncode == 0 else "FAIL",
    }
    print(json.dumps(report, sort_keys=True))
    if args.report:
        target = Path(args.report)
        if not target.is_absolute():
            target = ROOT / target
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(
            json.dumps(report, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
    return completed.returncode


if __name__ == "__main__":
    raise SystemExit(main())
