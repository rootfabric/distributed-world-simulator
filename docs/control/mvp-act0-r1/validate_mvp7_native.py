#!/usr/bin/env python3
"""Exact native recovery prerequisites. Never marks the whole MVP7 accepted."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
PINNED_LINUX = "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def require(ok: bool, reason: str) -> None:
    if not ok:
        raise RuntimeError(reason)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    engine, out = args.engine.resolve(), args.output.resolve()
    require(engine.is_file() and sys.platform == "linux" and digest(engine) == PINNED_LINUX, "PINNED_LINUX_DOUBLE_REQUIRED")
    require(not out.exists(), "DO_NOT_OVERWRITE_EVIDENCE")
    require(not git("status", "--porcelain", "--untracked-files=no"), "TRACKED_CHECKOUT_DIRTY")
    head, tree = git("rev-parse", "HEAD"), git("rev-parse", "HEAD^{tree}")
    require(head == os.environ.get("EXPECTED_HEAD", head), "EXACT_HEAD_MISMATCH")
    out.mkdir(parents=True)
    env = os.environ.copy()
    env.update(EXPECTED_HEAD=head, EXPECTED_TREE=tree, BREAKPOINT_RUNTIME_DISABLED="1", GODOT_SILENCE_ROOT_WARNING="1", PYTHONDONTWRITEBYTECODE="1", MVP7_NATIVE_ROOT=str(out / "native-checkpoints"), MVP7_WORLD_ROOT=str(out / "world-checkpoints"), XDG_DATA_HOME=str(out / "profile"), XDG_CONFIG_HOME=str(out / "config"), XDG_CACHE_HOME=str(out / "cache"))
    commands: list[dict] = []
    reports: dict = {}
    world_reports: dict = {}
    construction_reports: dict = {}
    passed = False
    error = ""

    def execute(label: str, argv: list[str], timeout: int, overrides: dict | None = None) -> None:
        path = out / (label + ".log")
        with path.open("w", encoding="utf-8") as stream:
            try:
                code = subprocess.run(argv, cwd=ROOT, env=env | (overrides or {}), stdout=stream, stderr=subprocess.STDOUT, timeout=timeout, check=False).returncode
            except subprocess.TimeoutExpired:
                code = 124
        commands.append({"label": label, "argv": argv, "exit_code": code})
        print("MVP7_COMMAND", label, "exit", code, flush=True)
        require(code == 0, label + ":EXIT_" + str(code))
        log = path.read_text(encoding="utf-8", errors="replace")
        require("Parse Error:" not in log and "SCRIPT ERROR:" not in log, label + ":GODOT_SCRIPT_ERROR")

    def check_report(target: Path, mode: str, minimum: int) -> dict:
        require(target.is_file(), mode + ":MISSING_RESULT")
        report = json.loads(target.read_text(encoding="utf-8"))
        require(report["passed"] is True and report["failures"] == [] and report["assertions"] >= minimum, mode + ":FAILED_OR_INCOMPLETE")
        require(report["subject_head"] == head and report["mode"] == mode, mode + ":SOURCE_BINDING")
        require(report["mvp7_predicate_verified"] is False, "NO_FALSE_WORLD_CLOSURE")
        return report

    try:
        execute("import", [str(engine), "--headless", "--editor", "--path", str(ROOT), "--import"], 300)
        for mode in ("produce", "recover1", "recover2"):
            target = out / (mode + ".json")
            execute(mode, [str(engine), "--headless", "--path", str(ROOT), "--script", "res://tests/runtime/test_v0_mvp_7_quiescent_recovery.gd"], 120, {"MVP7_NATIVE_MODE": mode, "MVP7_NATIVE_RESULT": str(target)})
            report = check_report(target, mode, 21)
            require(report["graphical_world_predicate_executed"] is False, "NO_FALSE_GRAPHICAL_CLOSURE")
            reports[mode] = report
        require(len({r["process_id"] for r in reports.values()}) == 3, "THREE_DISTINCT_NATIVE_PROCESS_IDS_REQUIRED")
        for previous, current in (("produce", "recover1"), ("recover1", "recover2")):
            a, b = reports[previous]["evidence"], reports[current]["evidence"]
            for field in ("checkpoint_checksum", "durable_checksum", "replay_checksum", "item_graph_checksum"):
                require(a[field] == b["recovered_" + field], previous + "->" + current + ":" + field)
        for mode in ("produce", "recover1", "recover2"):
            target = out / ("world-" + mode + ".json")
            execute("world-" + mode, [str(engine), "--headless", "--path", str(ROOT), "--script", "res://tests/runtime/test_v0_mvp_7_matter_restart.gd"], 180, {"MVP7_WORLD_MODE": mode, "MVP7_WORLD_RESULT": str(target)})
            report = check_report(target, mode, 35)
            require(report["enet_reconnect_executed"] is False and report["construction_recovery_executed"] is False, "NO_FALSE_LIVE_WORLD_CLOSURE")
            world_reports[mode] = report
        require(len({r["process_id"] for r in world_reports.values()}) == 3, "THREE_DISTINCT_WORLD_PROCESS_IDS_REQUIRED")
        for previous, current in (("produce", "recover1"), ("recover1", "recover2")):
            a, b = world_reports[previous], world_reports[current]
            for field in ("checkpoint_checksum", "item_graph_checksum", "store_hash", "state_hash"):
                require(a[field] == b["recovered_" + field], "world:" + previous + "->" + current + ":" + field)
        for mode in ("produce", "recover1", "recover2"):
            target = out / ("construction-" + mode + ".json")
            execute("construction-" + mode, [str(engine), "--headless", "--path", str(ROOT), "--script", "res://tests/runtime/test_v0_mvp_7_construction_restart.gd"], 240, {"MVP7_CONSTRUCTION_MODE": mode, "MVP7_CONSTRUCTION_ROOT": str(out / "construction-restart"), "MVP7_CONSTRUCTION_RESULT": str(target)})
            report = check_report(target, mode, 18)
            require(report["enet_reconnect_executed"] is False and report["graphical_five_process_executed"] is False, "NO_FALSE_ENET_OR_GRAPHICAL_CLOSURE")
            if mode != "produce":
                require(report["construction_recovery_executed"] is True and report["collision_recovery_executed"] is True, mode + ":CONSTRUCTION_COLLISION_RECOVERY_REQUIRED")
            construction_reports[mode] = report
        require(len({r["process_id"] for r in construction_reports.values()}) == 3, "THREE_DISTINCT_CONSTRUCTION_PROCESS_IDS_REQUIRED")
        produced_construction = construction_reports["produce"]["evidence"]
        for mode in ("recover1", "recover2"):
            recovered_construction = construction_reports[mode]["evidence"]
            for field in ("item_graph_checksum", "construction_checksum"):
                require(produced_construction[field] == recovered_construction[field], "construction:produce->" + mode + ":" + field)
            require(recovered_construction["collision_part_count"] == 100 and recovered_construction["boundary_hits"] > 0 and recovered_construction["removed_leaf_hits"] == 0, mode + ":COLLISION_CONTINUITY")
        for label, script in (
            ("regression-mvp3", "tests/runtime/test_v0_mvp3_live_owner_handoff.gd"),
            ("regression-mvp5", "tests/runtime/test_v0_mvp_5_exactly_once_material.gd"),
            ("regression-mvp6-persistence", "tests/runtime/test_v0_mvp_6_cross_authority_construction_persistence.gd"),
        ):
            execute(label, [str(engine), "--headless", "--path", str(ROOT), "--script", "res://" + script], 180)
        require(not git("status", "--porcelain", "--untracked-files=no"), "TRACKED_SOURCE_CHANGED")
        passed = True
    except (RuntimeError, OSError, ValueError, KeyError, subprocess.SubprocessError) as exc:
        error = str(exc)
        print("MVP7_NATIVE_VALIDATION_ERROR", error, flush=True)
    finally:
        (out / "commands.json").write_text(json.dumps(commands, indent=2) + "\n", encoding="utf-8")
        files = [{"path": p.relative_to(out).as_posix(), "bytes": p.stat().st_size, "sha256": digest(p)} for p in sorted(out.rglob("*")) if p.is_file() and p.name not in {"manifest.json", "summary.json"}]
        summary = {"schema": "distributed_world_simulator.mvp7_native_ci_summary.v1", "subject_head": head, "subject_tree": tree, "engine_sha256": digest(engine), "passed": passed, "error": error, "process_ids": {m: r["process_id"] for m, r in reports.items()}, "world_process_ids": {m: r["process_id"] for m, r in world_reports.items()}, "construction_process_ids": {m: r["process_id"] for m, r in construction_reports.items()}, "assertions": sum(r["assertions"] for r in reports.values()) + sum(r["assertions"] for r in world_reports.values()) + sum(r["assertions"] for r in construction_reports.values()), "tracked_after": git("status", "--porcelain", "--untracked-files=no"), "mvp7_predicate_verified": False, "independent_verdict": False, "scope": "NATIVE_GAMEPLAY_MW5_AND_CONSTRUCTION_PROCESS_RESTART_PREREQUISITES"}
        (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
        (out / "manifest.json").write_text(json.dumps({"summary": summary, "files": files, "commands": commands}, indent=2) + "\n", encoding="utf-8")
        print("MVP7_NATIVE_SUMMARY", json.dumps(summary), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
