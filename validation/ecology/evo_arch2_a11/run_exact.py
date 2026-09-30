#!/usr/bin/env python3
"""A11 exact machine evidence. No automatic retries or test/precision fallback."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
VERSION = "4.7.1.stable.double.custom_build.a13da4feb"
BINARY_SHA = {
    "Windows": "3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5",
    "Linux": "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7",
}
TESTS = {
    "test_persistent_session.gd": "SESSION",
    "test_world_admission.gd": "WORLD",
    "test_habitat_scene.gd": "SCENE",
    "test_habitat_lifecycle.gd": "LIFECYCLE",
}
FATAL = re.compile(r"SCRIPT ERROR|Parse Error|Failed to load script|Error compiling", re.I)


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        result = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
        return result.hexdigest()


def git(*args: str) -> str:
    return subprocess.check_output(["git", "-C", str(ROOT), *args], text=True).strip()


def identity() -> dict:
    return {"head": git("rev-parse", "HEAD"), "tree": git("rev-parse", "HEAD^{tree}"),
            "tracked_status": git("status", "--porcelain", "--untracked-files=no")}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    args = parser.parse_args()
    godot = args.godot.expanduser().resolve()
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()) + f"-{os.getpid()}"
    output = ROOT / "artifacts" / "runtime" / "eco-a11" / stamp
    output.mkdir(parents=True, exist_ok=False)
    evidence = {"schema": "dws.ecology.a11.exact-evidence.v1", "platform": platform.platform(),
                "python": sys.version, "godot_path": str(godot), "commands": [], "tests": [],
                "run_id": os.getenv("GITHUB_RUN_ID", "local"),
                "run_attempt": os.getenv("GITHUB_RUN_ATTEMPT", "1"),
                "runner": os.getenv("RUNNER_NAME", platform.node()), "started_utc": stamp,
                "verdict": "IN_PROGRESS", "checks": 0, "failures": 0}
    exit_code = 1

    def execute(label: str, command: list[str], timeout: int = 900,
                allow_version_exit: bool = False) -> str:
        log = output / (label + ".log")
        record = {"label": label, "command": command, "log": str(log.relative_to(ROOT)),
                  "timeout_seconds": timeout}
        evidence["commands"].append(record)
        started = time.monotonic()
        options = {"start_new_session": True} if os.name != "nt" else {
            "creationflags": subprocess.CREATE_NEW_PROCESS_GROUP}
        timed_out = False
        with log.open("wb") as stream:
            process = subprocess.Popen(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, **options)
            record["pid"] = process.pid
            try:
                code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                # Terminate only this runner's own process tree, never all Godot.
                if os.name == "nt":
                    subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
                else:
                    os.killpg(process.pid, signal.SIGKILL)
                code = process.wait(timeout=30)
        record.update(exit_code=code, timed_out=timed_out,
                      seconds=round(time.monotonic() - started, 3), sha256=digest(log))
        text = log.read_text(encoding="utf-8", errors="replace")
        print(f"{label}: exit={code} seconds={record['seconds']} log={log}", flush=True)
        if timed_out or (code != 0 and not allow_version_exit):
            print(text[-16000:], flush=True)
            raise RuntimeError(f"{label}: {'TIMEOUT' if timed_out else 'NONZERO_EXIT'} {code}")
        return text

    def worker(phase: str, extra: list[str]) -> dict:
        result = output / ("restart-" + phase + ".json")
        command = [str(godot), "--headless", "--path", str(ROOT), "--script",
                   "res://validation/ecology/evo_arch2_a11/habitat_restart_worker.gd", "--",
                   "--phase=" + phase, "--result=" + str(result), *extra]
        text = execute("restart-" + phase, command)
        if FATAL.search(text) or text.count("EVO_ARCH2_A11_RESTART_WORKER " + phase + " PASS") != 1:
            raise RuntimeError("restart-" + phase + ": missing/invalid worker completion")
        payload = json.loads(result.read_text(encoding="utf-8"))
        if payload.get("success") is not True or payload.get("phase") != phase:
            raise RuntimeError("restart-" + phase + ": invalid result")
        return payload

    try:
        evidence["before"] = identity()
        if evidence["before"]["tracked_status"]:
            raise RuntimeError("TRACKED_SOURCE_NOT_CLEAN_BEFORE")
        system = platform.system()
        if system not in BINARY_SHA or not godot.is_file():
            raise RuntimeError("SUPPORTED_EXACT_GODOT_REQUIRED")
        evidence["godot_sha256"] = digest(godot)
        if evidence["godot_sha256"] != BINARY_SHA[system]:
            raise RuntimeError("GODOT_SHA256_MISMATCH")
        # The canonical Windows console build can return -1 for --version.
        # Record it explicitly; this exception NEVER applies to import/tests.
        version_text = execute("godot-version", [str(godot), "--version"], 30, allow_version_exit=True)
        versions = [line.strip() for line in version_text.splitlines() if line.strip()]
        if versions != [VERSION]:
            raise RuntimeError("GODOT_VERSION_MISMATCH: " + repr(versions))
        evidence["godot_version"] = VERSION
        if system == "Linux":
            evidence["meminfo"] = Path("/proc/meminfo").read_text().splitlines()[:4]
        execute("canonical-import", [str(godot), "--headless", "--editor", "--path", str(ROOT), "--import"], 600)
        discovered = sorted(path.name for path in Path(__file__).parent.glob("test_*.gd"))
        evidence["tests_discovered"] = discovered
        if discovered != sorted(TESTS):
            raise RuntimeError("A11_TEST_SET_MISMATCH")
        for name, marker in TESTS.items():
            script = "res://validation/ecology/evo_arch2_a11/" + name
            text = execute(name.removesuffix(".gd"), [str(godot), "--headless", "--path", str(ROOT), "--script", script])
            prefix = "EVO_ARCH2_A11_" + marker
            matches = re.findall(re.escape(prefix) + r" checks=(\d+) failed=(\d+)", text)
            if FATAL.search(text) or len(matches) != 1 or text.splitlines().count(prefix + " PASS") != 1:
                print(text[-16000:], flush=True)
                raise RuntimeError(name + ": FATAL_OR_MISSING_COMPLETION_MARKERS")
            checks, failures = map(int, matches[0])
            evidence["tests"].append({"name": name, "checks": checks, "failures": failures})
            evidence["checks"] += checks
            evidence["failures"] += failures
            if checks <= 0 or failures:
                raise RuntimeError(name + ": ASSERTION_FAILURE")
        baseline = worker("baseline", [])
        checkpoints = output / "checkpoints"
        checkpoints.mkdir()
        checkpoint = worker("checkpoint", ["--directory=" + str(checkpoints)])
        saved_path = Path(checkpoint["path"])
        if saved_path.parent.resolve() != checkpoints.resolve() or digest(saved_path) != checkpoint["sha256"]:
            raise RuntimeError("RESTART_RECEIPT_BINDING")
        resumed = worker("resume", ["--path=" + str(saved_path), "--sha=" + checkpoint["sha256"]])
        rejected = worker("reject", ["--path=" + str(saved_path), "--sha=" + "0" * 64])
        if len({baseline["pid"], checkpoint["pid"], resumed["pid"], rejected["pid"]}) != 4:
            raise RuntimeError("RESTART_REQUIRES_DISTINCT_PROCESSES")
        for key in ("tick", "state_hash", "field_hash", "population", "presentation", "metrics"):
            if baseline[key] != resumed[key]:
                raise RuntimeError("RESTART_DIVERGENCE:" + key)
        if baseline["tick"] != 24 or checkpoint["tick"] != 8 or not rejected.get("rejected"):
            raise RuntimeError("RESTART_TICKS_OR_NEGATIVE_CONTROL")
        evidence["restart"] = {"baseline": baseline, "checkpoint": checkpoint,
                               "resumed": resumed, "rejected": rejected, "verified": True}
        evidence["verdict"] = "PASS"
        exit_code = 0
    except Exception as exc:
        evidence["verdict"] = "FAIL"
        evidence["error"] = str(exc)
        print("ECO_A11_EXACT_ERROR " + str(exc), flush=True)
    finally:
        try:
            evidence["after"] = identity()
            before = evidence.get("before", {})
            if evidence["after"].get("tracked_status") or any(
                    evidence["after"].get(key) != before.get(key) for key in ("head", "tree")):
                evidence["verdict"] = "FAIL"
                evidence["cleanliness_error"] = "EXACT_SUBJECT_CHANGED"
                exit_code = 1
        except Exception as exc:
            evidence["verdict"] = "FAIL"
            evidence["cleanliness_error"] = str(exc)
            exit_code = 1
        evidence["files"] = [{"path": str(path.relative_to(ROOT)), "sha256": digest(path), "bytes": path.stat().st_size}
                             for path in sorted(output.rglob("*")) if path.is_file()]
        report = output / "evidence.json"
        report.write_text(json.dumps(evidence, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        (output / "evidence.sha256").write_text(digest(report) + "  evidence.json\n", encoding="ascii")
        print(f"ECO_A11_EXACT={evidence['verdict']} tests={len(evidence['tests'])}/{len(TESTS)} "
              f"checks={evidence['checks']} failures={evidence['failures']}", flush=True)
        print("ECO_A11_EVIDENCE=" + str(report), flush=True)
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
