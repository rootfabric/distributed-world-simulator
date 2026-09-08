#!/usr/bin/env python3
"""Capture canonical controller readouts without dispatch or acceptance writes."""
import json
from pathlib import Path
import subprocess
import sys

from validate_candidate import digest, identity, write_json


def main() -> int:
    root = Path.cwd()
    out = root / "artifacts/p7-eg1-repair-control"
    out.mkdir(parents=True, exist_ok=True)
    before = identity(root)
    records = []
    try:
        for mode in ("Overview", "CheckConsistency", "Drive", "CloseRole", "CloseMission"):
            command = ["pwsh", "-NoProfile", "-File", "./CONTROL_DEVELOPMENT.ps1", f"-{mode}"]
            with (out / f"{mode}.log").open("wb") as log:
                result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=120, check=False)
            allowed = (0, 7) if mode == "CloseRole" else (0, 8) if mode == "CloseMission" else (0,)
            records.append({"mode": mode, "command": command, "exit_code": result.returncode,
                            "expected_readout_exit": result.returncode in allowed,
                            "log_sha256": digest(out / f"{mode}.log")})
            print(f"CONTROL_{mode}: exit={result.returncode}", flush=True)
    finally:
        after = identity(root)
        write_json(out / "observations.json", {
            "classification": "READ_ONLY_CONTROLLER_OBSERVATIONS_NOT_ACCEPTANCE",
            "before": before, "after": after, "commands": records,
            "canonical_acceptance_written": False,
        })
    complete = len(records) == 5 and all(row["expected_readout_exit"] for row in records)
    return 0 if complete and before == after and not after["tracked_status"] else 1


if __name__ == "__main__":
    sys.exit(main())
