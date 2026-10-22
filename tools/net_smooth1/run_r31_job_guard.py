#!/usr/bin/env python3
r"""Explicit opt-in Windows Job supervisor; original runner/evidence untouched.

Example: python run_r31_job_guard.py --receipt C:\new\job.json -- \
    C:\Python311\python.exe tools\net_smooth1\run_net_smooth1.py <same args>

No automatic fallback without containment. A root exit code of 0 is NOT
sufficient: Job membership must become empty naturally. Forced cleanup keeps
this attempt failed even when isolation for the next attempt is restored.
"""
from __future__ import annotations
import argparse
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import time
from win_job_guard import OwnedJob


def save_receipt(path: Path, data: dict) -> None:
    temp = path.with_suffix(path.suffix + ".tmp")
    with temp.open("w", encoding="utf-8") as stream:
        json.dump(data, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temp, path)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipt", required=True, type=Path)
    parser.add_argument("--cwd", type=Path, default=Path.cwd())
    parser.add_argument("--deadline", type=float, default=1800.0)
    parser.add_argument("--drain-grace", type=float, default=5.0)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command or not Path(command[0]).is_absolute():
        parser.error("command must start with absolute executable path, not a shell expression")
    if (not math.isfinite(args.deadline) or args.deadline <= 0
            or not math.isfinite(args.drain_grace) or args.drain_grace < 0):
        parser.error("finite positive deadline and nonnegative drain-grace required")
    receipt = args.receipt.resolve()
    log = receipt.with_suffix(receipt.suffix + ".runner.log")
    receipt.parent.mkdir(parents=True, exist_ok=True)
    # Reserve output before spawning; never overwrite old acceptance evidence.
    with receipt.open("x", encoding="utf-8") as stream:
        stream.write('{"status":"RESERVED_NOT_STARTED"}\n')
    if log.exists():
        raise FileExistsError("JOB_OUTPUT_LOG_ALREADY_EXISTS")
    started = time.monotonic()
    state = {"schema": "dws.r31.job_guard.v1", "status": "STARTING",
             "started_utc_ns": time.time_ns(), "supervisor_pid": os.getpid(),
             "root": None, "runner_exit_code": None, "job_cleanup": None,
             "errors": [], "runtime_performance_acceptance": False,
             "receipt_does_not_replace_original_manifest": True}
    job = None
    exit_code = 2
    try:
        job = OwnedJob()  # fail before any child runs if APIs unsupported
        process, identity = job.create_suspended(command, cwd=args.cwd, log=log)
        state["root"] = identity
        state["status"] = "CONTAINED_SUSPENDED"
        save_receipt(receipt, state)  # identity exists BEFORE the child executes
        process.resume()
        state["status"] = "RUNNING_IN_JOB"
        save_receipt(receipt, state)
        try:
            state["runner_exit_code"] = process.wait(args.deadline)
        except subprocess.TimeoutExpired:
            state["errors"].append("ROOT_DEADLINE_EXCEEDED")
            job.terminate()
            process.wait(10)
        state["job_cleanup"] = job.finish(args.drain_grace)
        clean = state["job_cleanup"]["acceptance"] == "CLEAN_JOB_EMPTY"
        if not clean:
            state["errors"].append(state["job_cleanup"]["acceptance"])
        if state["runner_exit_code"] != 0:
            state["errors"].append("RUNNER_EXIT_NOT_ZERO")
        state["status"] = "GUARD_CLEAN_RUNNER_ZERO_ONLY" if not state["errors"] else "GUARD_FAIL"
        exit_code = 0 if not state["errors"] else 1
    except (Exception, KeyboardInterrupt) as exc:
        # Capture query/identity/spawn faults, but never turn them into PASS.
        state["status"] = "GUARD_INCONCLUSIVE"
        state["errors"].append(type(exc).__name__ + ":" + str(exc))
        exit_code = 2
    finally:
        if job is not None:
            try:
                job.close()  # KILL_ON_JOB_CLOSE covers errors/controller stop
            except OSError as exc:
                state["errors"].append("JOB_CLOSE_FAILED:" + str(exc))
                state["status"], exit_code = "GUARD_INCONCLUSIVE", 2
        state["elapsed_s"] = round(time.monotonic() - started, 6)
        save_receipt(receipt, state)
    print(json.dumps({"status": state["status"], "receipt": str(receipt),
                      "runner_exit_code": state["runner_exit_code"], "errors": state["errors"]}))
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
