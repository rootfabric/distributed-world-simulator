#!/usr/bin/env python3
"""Strict R5.6.2 R1 exact-head lifecycle evidence collector (research only)."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

MARKER = "FABRIC_R562_R1_RESULT="
SCHEMA = "fabric.r56_2_r1.lifecycle.acceptance.v1"
PIN = {
    "linux": "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7",
    "windows": "3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5",
}
VERSION = "4.7.1.stable.double.custom_build.a13da4feb"
BAD = re.compile(r"SCRIPT ERROR|Parse Error|Compile Error|Invalid call|Invalid access|ERROR:", re.I)


def require(ok, message):
    if not ok:
        raise ValueError(message)


def identity(path):
    lines = path.read_text(encoding="utf-8").splitlines()
    require(len(lines) == 4 and all("=" in x for x in lines), f"{path.name}: invalid identity")
    return dict(line.split("=", 1) for line in lines)



def windows_stage_args():
    tests = "res://tests/research/fabric_bake0"
    stages = {
        "import-recovery": ["--editor", "--import", "--recovery-mode"],
        "import": ["--editor", "--import"],
        "parse-lifecycle": ["--check-only", "--script", f"{tests}/fabric_r5_6_2_r1_lifecycle_acceptance.gd"],
        **{f"lifecycle-{i}": ["--script", f"{tests}/fabric_r5_6_2_r1_lifecycle_acceptance.gd"] for i in range(1, 4)},
        "r2-regression": ["--script", f"{tests}/fabric_r5_6_1_r2_dynamic_aggregate_acceptance.gd"],
        "com-recovery-regression": ["--script", f"{tests}/fabric_r5_6_1_r2_com_recovery_acceptance.gd"],
        "r1-regression": ["--script", f"{tests}/fabric_r5_6_1_canonical_delta_acceptance.gd"],
        "bridge4-regression": ["--quit-after", "2", "--script", "res://tests/research/fabric1/fabric_bridge4_canonical_world_acceptance.gd"],
    }
    return stages


def validate_windows_launches(root):
    """Independently reject missing/altered CLI intent and false process PASS.

    These local receipts are evidence, not authenticated OS attestation.
    Exact runtime still requires the pinned binary and independent execution.
    """
    common_identity = None
    command_fields = {"schema", "stage", "executable", "working_directory", "argv", "timeout_seconds"}
    process_fields = {"schema", "stage", "started", "exit_code", "timed_out", "gameplay_detected", "verdict"}
    for stage, gate_args in windows_stage_args().items():
        command = json.loads((root / f"{stage}.argv.json").read_text(encoding="utf-8"))
        outcome = json.loads((root / f"{stage}.process.json").read_text(encoding="utf-8"))
        require(type(command) is dict and set(command) == command_fields, f"{stage}: INVALID_LAUNCH_FIELDS")
        require(command["schema"] == "fabric.r562.windows_launch.v1" and command["stage"] == stage,
                f"{stage}: INVALID_LAUNCH_SCHEMA")
        executable, cwd = command["executable"], command["working_directory"]
        require(type(executable) is str and bool(executable) and type(cwd) is str and bool(cwd),
                f"{stage}: INVALID_LAUNCH_IDENTITY")
        current_identity = (executable, cwd)
        if common_identity is None:
            common_identity = current_identity
        require(current_identity == common_identity, f"{stage}: LAUNCH_IDENTITY_DRIFT")
        require(command["argv"] == ["--headless", "--path", cwd] + gate_args,
                f"{stage}: GODOT_STAGE_ARGV_MISMATCH")
        require(type(command["timeout_seconds"]) is int and 1 <= command["timeout_seconds"] <= 1800,
                f"{stage}: INVALID_TIMEOUT")
        require(type(outcome) is dict and set(outcome) == process_fields, f"{stage}: INVALID_PROCESS_FIELDS")
        require(outcome["schema"] == "fabric.r562.windows_process.v1" and outcome["stage"] == stage,
                f"{stage}: INVALID_PROCESS_SCHEMA")
        require(outcome["started"] is True and outcome["timed_out"] is False
                and outcome["gameplay_detected"] is False and type(outcome["exit_code"]) is int
                and outcome["exit_code"] == 0 and outcome["verdict"] == "PASS",
                f"{stage}: PROCESS_NOT_CLEAN_PASS")
        # Read bytes: newline translation must not hide differences on Windows.
        combined = (root / f"{stage}.log").read_bytes()
        require(combined == (root / f"{stage}.stdout.log").read_bytes()
                + (root / f"{stage}.stderr.log").read_bytes(), f"{stage}: RAW_STREAM_MISMATCH")
        require(not BAD.search(combined.decode("utf-8")), f"{stage}: RUNTIME_ERROR")
        if stage in ("import", "import-recovery"):
            require(not re.search(r"listen-host|user://worlds/|terrain_streaming_summary|spectator_predictive_stream",
                                  combined.decode("utf-8"), re.I), f"{stage}: IMPORT_GAMEPLAY_SIDE_EFFECT")
    return len(windows_stage_args())

def run(args):
    root = Path(args.root).resolve()
    require(root.is_dir(), "EVIDENCE_DIR_MISSING")
    before = identity(root / "identity-before.txt")
    after = identity(root / "identity-after.txt")
    require(before == after, "IDENTITY_BEFORE_AFTER_DRIFT")
    require(before.get("HEAD") == args.expected_head, "HEAD_DRIFT")
    require(before.get("TREE") == args.expected_tree, "TREE_DRIFT")
    require(before.get("GODOT_VERSION") == VERSION, "GODOT_VERSION_MISMATCH")
    require(before.get("GODOT_SHA256") == PIN[args.platform], "GODOT_SHA_MISMATCH")
    actual = []
    for i in range(1, 4):
        path = root / f"lifecycle-{i}.log"
        lines = path.read_text(encoding="utf-8").splitlines()
        require(not BAD.search("\n".join(lines)), f"{path.name}: Godot runtime error")
        matches = [line[len(MARKER):] for line in lines if line.startswith(MARKER)]
        require(len(matches) == 1, f"{path.name}: missing or duplicate result marker")
        data = json.loads(matches[0])
        require(data.get("schema") == SCHEMA, "INVALID_RESULT_SCHEMA")
        require(data.get("failures") == [], "LIFECYCLE_FAILURES")
        require(data.get("committed_events") == 10, "MIXED_EVENTS_MISSING")
        require(data.get("cold_restarts") == 30, "COLD_RECOVERY_WINDOWS_MISSING")
        require(data.get("disk_roundtrips") == 42, "PROCESS_CRASH_DISK_ROUNDTRIPS_MISSING")
        require(data.get("full_oracle_queries", 0) >= 14, "FULL_ORACLES_MISSING")
        require(data.get("negative_rejections", 0) >= 60, "FAIL_CLOSED_MATRIX_MISSING")
        require(data.get("checks", 0) >= 200, "ACCEPTANCE_COVERAGE_TOO_LOW")
        actual.append(matches[0].encode("utf-8"))
    require(actual[0] == actual[1] == actual[2], "R1_NONDETERMINISTIC_RESULT")
    mandatory = ["import-recovery.log", "import.log", "parse-lifecycle.log", "r2-regression.log",
                 "com-recovery-regression.log", "r1-regression.log", "bridge4-regression.log"]
    for name in mandatory:
        data = (root / name).read_text(encoding="utf-8")
        require(not BAD.search(data), f"{name}: error output")
    isolation = (root / "isolation.txt").read_text(encoding="utf-8").splitlines()
    require(isolation == ["RECEIPTS_IN_SANDBOX=42", "LIVE_WORLD_LOGS=0"],
            "USER_DATA_ISOLATION_NOT_PROVEN")
    launch_count = validate_windows_launches(root) if args.platform == "windows" else None
    report = {
        "schema": "fabric.r56_2_r1.exact_evidence.v2",
        "windows_launches_verified": launch_count,
        "head": before["HEAD"], "tree": before["TREE"],
        "engine": VERSION, "engine_sha256": before["GODOT_SHA256"],
        "acceptance": json.loads(actual[0]),
        "deterministic_result_sha256": hashlib.sha256(actual[0]).hexdigest(),
        "gates": {"lifecycle_triple": "PASS", "inherited_regressions": "PASS",
                  "identity_exact": "PASS", "cold_import_twice": "PASS",
                  "user_data_isolation": "PASS"},
        "scope": "PROCESS_RESTART_ONLY_NOT_DISTRIBUTED_EXACTLY_ONCE",
    }
    (root / "evidence.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n",
                                         encoding="utf-8")
    print("FABRIC_R562_R1_COLLECTOR=PASS")
    print(json.dumps(report, sort_keys=True))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--expected-head", required=True)
    ap.add_argument("--expected-tree", required=True)
    ap.add_argument("--platform", choices=PIN, required=True)
    try:
        run(ap.parse_args())
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as exc:
        print("FABRIC_R562_R1_COLLECTOR=FAIL " + str(exc), file=sys.stderr)
        sys.exit(1)
