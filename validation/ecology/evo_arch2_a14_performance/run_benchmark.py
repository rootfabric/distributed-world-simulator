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
import statistics
import math
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = "res://validation/ecology/evo_arch2_a14_performance/bench_fidelity.gd"
SCALE_SCRIPT = "res://validation/ecology/evo_arch2_a14_performance/bench_scaling.gd"
PHASE_SCRIPT = "res://validation/ecology/evo_arch2_a14_performance/bench_phases.gd"
PHASE_MARKER = "ECO_A14_PHASE_SAMPLE "
PHASE_LABELS = {"lifecycle_including_global_A5", "propagule_admission", "feedback_and_seal", "runtime_validate", "spatial_create", "deep_copy", "canonical_digest"}
SCALE_MARKER = "ECO_A14_SCALE_SAMPLE "
SCALE_COUNTS = {4, 64, 128, 256}
SCALE_LABELS = {"fixture_create", "spatial_create", "spatial_serial",
                *(f"parallel_advance_{n}" for n in (1, 2, 4, 8))}
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
            *[(f"scale-{idx}", [str(binary), "--headless", "--path", str(ROOT),
                               "--script", SCALE_SCRIPT]) for idx in range(args.runs)],
            *[(f"phase-{idx}", [str(binary), "--headless", "--path", str(ROOT),
                               "--script", PHASE_SCRIPT]) for idx in range(args.runs)],
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
            if label.startswith("phase-"):
                if message.splitlines().count("ECO_A14_PHASE PASS") != 1:
                    raise RuntimeError(f"{label}:MISSING_PHASE_PASS")
                raw = [line[len(PHASE_MARKER):] for line in message.splitlines()
                       if line.startswith(PHASE_MARKER)]
                phase_samples = [json.loads(line) for line in raw]
                identities = [(s.get("founders"), s.get("label")) for s in phase_samples]
                expected = {(n, phase) for n in SCALE_COUNTS for phase in PHASE_LABELS}
                if len(identities) != len(expected) or set(identities) != expected:
                    raise RuntimeError(f"{label}:PHASE_SAMPLE_SET_MISMATCH")
                for item in phase_samples:
                    if (item.get("schema") != "dws.ecology.a14-1.phase-sample.v1"
                            or type(item.get("wall_us")) is not int or item["wall_us"] < 0
                            or not re.fullmatch(r"[0-9a-f]{64}", str(item.get("result_state_hash", "")))):
                        raise RuntimeError(f"{label}:INVALID_PHASE_SAMPLE")
                    item["iteration"] = int(label.split("-")[1])
                for founders in SCALE_COUNTS:
                    if len({item["result_state_hash"] for item in phase_samples if item["founders"] == founders}) != 1:
                        raise RuntimeError(f"{label}:PHASE_END_STATE_PARITY")
                evidence.setdefault("phase_samples", []).extend(phase_samples)
                continue
            if label.startswith("scale-"):
                if message.splitlines().count("ECO_A14_SCALE PASS") != 1:
                    raise RuntimeError(f"{label}:MISSING_SCALE_PASS")
                raw = [line[len(SCALE_MARKER):] for line in message.splitlines()
                       if line.startswith(SCALE_MARKER)]
                samples = [json.loads(line) for line in raw]
                if len(samples) != len(SCALE_COUNTS) * len(SCALE_LABELS):
                    raise RuntimeError(f"{label}:SCALE_SAMPLE_COUNT")
                for sample in samples:
                    founders, sample_label = sample.get("founders"), sample.get("label")
                    if (sample.get("schema") != "dws.ecology.a14-1.scale-sample.v1"
                            or founders not in SCALE_COUNTS or sample_label not in SCALE_LABELS
                            or not isinstance(sample.get("wall_us"), int) or sample["wall_us"] < 0
                            or not re.fullmatch(r"[0-9a-f]{64}", str(sample.get("state_hash", "")))):
                        raise RuntimeError(f"{label}:INVALID_SCALE_SAMPLE")
                identities = [(s["founders"], s["label"]) for s in samples]
                if len(set(identities)) != len(samples):
                    raise RuntimeError(f"{label}:DUPLICATE_SCALE_SAMPLE")
                for founders in SCALE_COUNTS:
                    same = [s for s in samples if s["founders"] == founders
                            and (s["label"] == "spatial_serial" or
                                 s["label"].startswith("parallel_advance_"))]
                    if len({s["state_hash"] for s in same}) != 1:
                        raise RuntimeError(f"{label}:SCALE_HASH_MISMATCH")
                for sample in samples:
                    sample["iteration"] = int(label.split("-")[1])
                evidence.setdefault("scale_samples", []).extend(samples)
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
        expected_counts = {"samples": len(LABELS), "scale_samples": len(SCALE_COUNTS) * len(SCALE_LABELS),
                           "phase_samples": len(SCALE_COUNTS) * len(PHASE_LABELS)}
        for sample_kind, per_run in expected_counts.items():
            if len(evidence.get(sample_kind, [])) != args.runs * per_run:
                raise RuntimeError("MISSING_COMPLETE_EVIDENCE:" + sample_kind)
        def describe(samples: list[dict]) -> list[dict]:
            groups: dict[tuple, list[int]] = {}
            for sample in samples:
                group = (sample.get("founders"), sample["label"])
                groups.setdefault(group, []).append(sample["wall_us"])
            out = []
            for (founders, sample_label), raw in sorted(groups.items(), key=lambda item: (item[0][0] or 0, item[0][1])):
                values = sorted(raw)
                n = len(values)
                out.append({"founders": founders, "label": sample_label, "n": n,
                            "median_us": statistics.median(values), "min_us": values[0],
                            "max_us": values[-1], "p95_nearest_rank_us": values[math.ceil(.95 * n) - 1]})
            return out
        evidence["statistics"] = {k: describe(evidence[k]) for k in expected_counts}
        evidence["statistics_note"] = "Nearest-rank p95 with n=3 equals max; NOT a stable tail estimate."
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
