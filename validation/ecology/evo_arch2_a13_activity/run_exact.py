#!/usr/bin/env python3
"""ECO ARCH2 A13 active/sleeping cadence exact evidence."""
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
TESTS = {"test_activity_cadence.gd": "ACTIVITY"}
FATAL = re.compile(r"SCRIPT ERROR|Parse Error|Failed to load script|Error compiling", re.I)

def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def git(*args: str) -> str:
    return subprocess.check_output(["git", "-C", str(ROOT), *args], text=True).strip()

def identity() -> dict:
    return {
        "head": git("rev-parse", "HEAD"),
        "tree": git("rev-parse", "HEAD^{tree}"),
        "tracked_status": git("status", "--porcelain", "--untracked-files=no"),
    }

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    args = parser.parse_args()
    godot = args.godot.expanduser().resolve()

    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()) + f"-{os.getpid()}"
    output = ROOT / "artifacts" / "runtime" / "eco-a13-activity" / stamp
    output.mkdir(parents=True, exist_ok=False)
    evidence = {
        "schema": "dws.ecology.a13-activity.exact-evidence.v1",
        "platform": platform.platform(),
        "python": sys.version,
        "godot_path": str(godot),
        "commands": [],
        "tests": [],
        "started_utc": stamp,
        "verdict": "IN_PROGRESS",
        "checks": 0,
        "failures": 0,
    }
    exit_code = 1

    def execute(label: str, command: list[str], timeout: int = 2400, allow_version_exit: bool = False) -> str:
        log = output / (label + ".log")
        record = {
            "label": label,
            "command": command,
            "log": str(log.relative_to(ROOT)),
            "timeout_seconds": timeout,
        }
        evidence["commands"].append(record)
        opts = {"start_new_session": True} if os.name != "nt" else {"creationflags": subprocess.CREATE_NEW_PROCESS_GROUP}
        started = time.monotonic()
        timed_out = False
        with log.open("wb") as stream:
            process = subprocess.Popen(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, **opts)
            record["pid"] = process.pid
            try:
                code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                if os.name == "nt":
                    subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
                else:
                    os.killpg(process.pid, signal.SIGKILL)
                code = process.wait(timeout=30)
        record.update(
            exit_code=code,
            timed_out=timed_out,
            seconds=round(time.monotonic() - started, 3),
            sha256=digest(log),
        )
        text = log.read_text(encoding="utf-8", errors="replace")
        print(f"{label}: exit={code} seconds={record['seconds']} log={log}", flush=True)
        if timed_out or (code != 0 and not allow_version_exit):
            print(text[-24000:], flush=True)
            raise RuntimeError(f"{label}: {'TIMEOUT' if timed_out else 'NONZERO_EXIT'} {code}")
        return text

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

        versions = [line.strip() for line in execute(
            "godot-version", [str(godot), "--version"], 30, True
        ).splitlines() if line.strip()]
        if versions != [VERSION]:
            raise RuntimeError("GODOT_VERSION_MISMATCH:" + repr(versions))
        evidence["godot_version"] = VERSION

        execute("canonical-import", [str(godot), "--headless", "--editor", "--path", str(ROOT), "--import"], 600)

        discovered = sorted(path.name for path in Path(__file__).parent.glob("test_*.gd"))
        if discovered != sorted(TESTS):
            raise RuntimeError("A13_ACTIVITY_TEST_SET_MISMATCH:" + repr(discovered))

        for name, marker in TESTS.items():
            text = execute(
                name.removesuffix(".gd"),
                [str(godot), "--headless", "--path", str(ROOT), "--script",
                 "res://validation/ecology/evo_arch2_a13_activity/" + name],
            )
            prefix = "EVO_ARCH2_A13_" + marker
            matches = re.findall(re.escape(prefix) + r" checks=(\d+) failed=(\d+)", text)
            if FATAL.search(text) or len(matches) != 1 or text.splitlines().count(prefix + " PASS") != 1:
                print(text[-24000:], flush=True)
                raise RuntimeError(name + ":FATAL_OR_MISSING_COMPLETION_MARKERS")
            checks, failures = map(int, matches[0])
            evidence["tests"].append({"name": name, "checks": checks, "failures": failures})
            evidence["checks"] += checks
            evidence["failures"] += failures
            if checks < 50 or failures:
                raise RuntimeError(name + ":ASSERTION_FAILURE")

        evidence["verdict"] = "PASS"
        exit_code = 0
    except Exception as exc:
        evidence["verdict"] = "FAIL"
        evidence["error"] = str(exc)
        print("ECO_A13_ACTIVITY_EXACT_ERROR " + str(exc), flush=True)
    finally:
        try:
            evidence["after"] = identity()
            before = evidence.get("before", {})
            if evidence["after"].get("tracked_status") or any(
                evidence["after"].get(key) != before.get(key) for key in ("head", "tree")
            ):
                evidence["verdict"] = "FAIL"
                evidence["cleanliness_error"] = "EXACT_SUBJECT_CHANGED"
                exit_code = 1
        except Exception as exc:
            evidence["verdict"] = "FAIL"
            evidence["cleanliness_error"] = str(exc)
            exit_code = 1

        report = output / "evidence.json"
        report.write_text(json.dumps(evidence, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        (output / "evidence.sha256").write_text(digest(report) + "  evidence.json\n", encoding="ascii")
        print(
            f"ECO_A13_ACTIVITY_EXACT={evidence['verdict']} "
            f"tests={len(evidence['tests'])}/{len(TESTS)} "
            f"checks={evidence['checks']} failures={evidence['failures']}",
            flush=True,
        )
        print("ECO_A13_ACTIVITY_EVIDENCE=" + str(report), flush=True)

    return exit_code

if __name__ == "__main__":
    raise SystemExit(main())
