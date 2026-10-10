#!/usr/bin/env python3
"""Run the A14.1 noncanonical Godot microbenchmark and preserve immutable evidence."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = "res://validation/ecology/evo_arch2_a14_performance/bench_fidelity.gd"
MARKER = "ECO_A14_SAMPLE "
VERSION = "4.7.1.stable.double.custom_build.a13da4feb"
HASHES = {
    "Linux": "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7",
    "Windows": "3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5",
}
LABELS = {"spatial_serial", "parallel_prepare_4",
          *(f"parallel_advance_{n}" for n in (1, 2, 4, 8)),
          "plan_create", "plan_validate", "reduced_replay_4", "reduced_defer_1"}
FATAL = re.compile(r"SCRIPT ERROR|Parse Error|Failed to load script|Error compiling", re.I)

def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def git(*args: str) -> str:
    return subprocess.check_output(["git", "-C", str(ROOT), *args], text=True).strip()

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--timeout", type=int, default=900)
    args = parser.parse_args()
    if not 1 <= args.runs <= 30 or args.timeout < 30:
        parser.error("runs must be 1..30 and timeout >= 30")
    binary = args.godot.expanduser().resolve()
    stamp = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()) + f"-{os.getpid()}"
    output = ROOT / "artifacts/runtime/eco-a14-1" / stamp
    output.mkdir(parents=True, exist_ok=False)
    evidence = {
        "schema": "dws.ecology.a14-1.evidence.v1",
        "verdict": "FAIL",
        "platform": platform.platform(),
        "python": sys.version,
        "godot": str(binary),
        "runs_requested": args.runs,
        "samples": [],
        "commands": [],
        "started_utc": stamp,
    }
    exit_code = 1
    try:
        before = {"head": git("rev-parse", "HEAD"),
                  "tree": git("rev-parse", "HEAD^{tree}"),
                  "tracked_status": git("status", "--porcelain", "--untracked-files=no")}
        evidence["before"] = before
        if before["tracked_status"]:
            raise RuntimeError("TRACKED_TREE_NOT_CLEAN")
        if not binary.is_file() or platform.system() not in HASHES:
            raise RuntimeError("EXACT_BINARY_REQUIRED")
        evidence["godot_sha256"] = digest(binary.read_bytes())
        if evidence["godot_sha256"] != HASHES[platform.system()]:
            raise RuntimeError("GODOT_SHA_MISMATCH")
        version = subprocess.run([str(binary), "--version"], cwd=ROOT,
                                 capture_output=True, text=True, timeout=30)
        if version.stdout.strip() != VERSION:
            raise RuntimeError("GODOT_VERSION_MISMATCH")
        evidence["godot_version"] = VERSION
        commands = [
            ("import", [str(binary), "--headless", "--editor", "--path", str(ROOT), "--import"]),
            *[(f"bench-{idx}", [str(binary), "--headless", "--path", str(ROOT),
                               "--script", SCRIPT]) for idx in range(args.runs)],
        ]
        for label, command in commands:
            started = time.perf_counter()
            result = subprocess.run(command, cwd=ROOT, capture_output=True,
                                    timeout=args.timeout)
            elapsed = time.perf_counter() - started
            log = result.stdout + b"\n" + result.stderr
            log_path = output / (label + ".log")
            log_path.write_bytes(log)
            message = log.decode("utf-8", errors="replace")
            record = {"label": label, "command": command, "exit_code": result.returncode,
                      "wall_seconds": elapsed, "log": str(log_path.relative_to(ROOT)),
                      "log_sha256": digest(log)}
            evidence["commands"].append(record)
            if result.returncode != 0 or FATAL.search(message):
                raise RuntimeError(f"{label}:NONZERO_OR_PARSE:{result.returncode}")
            if label == "import":
                continue
            lines = [line[len(MARKER):] for line in message.splitlines()
                     if line.startswith(MARKER)]
            if message.splitlines().count("ECO_A14_BENCH PASS") != 1:
                raise RuntimeError(f"{label}:MISSING_PASS")
            parsed = [json.loads(line) for line in lines]
            labels = [row.get("label") for row in parsed]
            if len(parsed) != len(LABELS) or set(labels) != LABELS or len(set(labels)) != len(labels):
                raise RuntimeError(f"{label}:SAMPLE_SET_MISMATCH")
            for sample in parsed:
                if (sample.get("schema") != "dws.ecology.a14-1.sample.v1"
                        or not isinstance(sample.get("wall_us"), int)
                        or sample["wall_us"] < 0
                        or not re.fullmatch(r"[0-9a-f]{64}", str(sample.get("state_hash", "")))):
                    raise RuntimeError(f"{label}:INVALID_SAMPLE")
                sample["iteration"] = int(label.split("-")[1])
            evidence["samples"].extend(parsed)
        evidence["verdict"] = "PASS"
        exit_code = 0
    except Exception as exc:
        evidence["error"] = str(exc)
        print("ECO_A14_BENCH_ERROR " + str(exc), flush=True)
    finally:
        try:
            evidence["after"] = {"head": git("rev-parse", "HEAD"),
                                 "tree": git("rev-parse", "HEAD^{tree}"),
                                 "tracked_status": git("status", "--porcelain", "--untracked-files=no")}
            if (evidence["after"] != evidence.get("before")):
                evidence["verdict"] = "FAIL"
                evidence["cleanliness_error"] = "SOURCE_CHANGED"
                exit_code = 1
        except Exception as exc:
            evidence["verdict"] = "FAIL"
            evidence["cleanliness_error"] = str(exc)
            exit_code = 1
        report = output / "evidence.json"
        report.write_text(json.dumps(evidence, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        (output / "evidence.sha256").write_text(digest(report.read_bytes()) + "  evidence.json\n", encoding="ascii")
        print("ECO_A14_BENCH=" + evidence["verdict"], flush=True)
        print("ECO_A14_EVIDENCE=" + str(report), flush=True)
    return exit_code

if __name__ == "__main__":
    raise SystemExit(main())
