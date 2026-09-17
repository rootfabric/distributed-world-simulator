#!/usr/bin/env python3
"""Validate an already-completed canonical full world/core run for MVP6.

Execution is deliberately outside this checker so the unchanged canonical
RUN_WORLD_REGRESSION_TESTS.ps1 can consume the workflow's bounded job budget.
Exact world/core evidence is valid only when the SAME workflow run supplies the
raw five-process graphical manifest for the SAME HEAD/TREE.
"""
from __future__ import annotations

import fnmatch
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
BASE = "182d93872bfddbf52a72ab170371ebb9489690bb"
OUT = ROOT / "artifacts/mvp6-world-core"
WORLD_SUMMARY = ROOT / "artifacts/test-results/world-regression-summary.json"
WORLD_RUNNER = "RUN_WORLD_REGRESSION_TESTS.ps1"
GRAPHICAL_MANIFEST_ENV = "MVP6_GRAPHICAL_MANIFEST"
TESTS = {
    "diagnostic": "res://tests/runtime/test_v0_mvp_6_cross_authority_prerequisites.gd",
    "product": "res://tests/runtime/test_v0_mvp_6_cross_authority_construction_seam.gd",
    "collision": "res://tests/runtime/test_v0_mvp_6_cross_authority_construction_collision.gd",
    "persistence": "res://tests/runtime/test_v0_mvp_6_cross_authority_construction_persistence.gd",
}
RESULTS = {
    "diagnostic": "result.json",
    "product": "product.json",
    "collision": "collision.json",
    "persistence": "persistence.json",
}
PIN = {
    "linux": "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7",
    "win32": "3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5",
}
FATAL = re.compile(r"(?m)(: FAIL(?:\s|\()|SCRIPT ERROR:|Parse Error:|Compile Error:)")


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def exact_graphical_manifest(head: str, tree: str) -> tuple[Path, dict]:
    raw = os.environ.get(GRAPHICAL_MANIFEST_ENV, "").strip()
    assert raw, "SAME_HEAD_GRAPHICAL_MANIFEST_PATH_REQUIRED"
    path = Path(raw).resolve()
    assert path.is_file(), "SAME_HEAD_GRAPHICAL_MANIFEST_MISSING"
    value = json.loads(path.read_text(encoding="utf-8"))
    assert value.get("schema") == "distributed_world_simulator.mvp6_graphical_construction_manifest.v1", "GRAPHICAL_MANIFEST_SCHEMA_INVALID"
    assert value.get("subject_head") == head, "GRAPHICAL_HEAD_MISMATCH"
    assert value.get("subject_tree") == tree, "GRAPHICAL_TREE_MISMATCH"
    assert value.get("passed") is True, "GRAPHICAL_MANIFEST_NOT_PASS"
    assert value.get("five_process_graphical_executed") is True, "FIVE_PROCESS_GRAPHICAL_NOT_EXECUTED"
    assert value.get("mvp6_predicate_verified") is False and value.get("independent_verdict") is False, "GRAPHICAL_GATE_MUST_NOT_SELF_ACCEPT"
    checks = value.get("checks")
    assert isinstance(checks, dict) and checks and all(v is True for v in checks.values()), "GRAPHICAL_CHECK_FAILURE"
    assert checks.get("mvp6:five_distinct_processes") is True, "FIVE_PROCESS_PID_CONTRACT_FAILED"
    roles = {str(row.get("role", "")) for row in value.get("commands", []) if isinstance(row, dict)}
    assert roles == {"authority/a", "authority/b", "gateway", "client/a", "client/b"}, "FIVE_PROCESS_ROLE_SET_INVALID"
    return path, value


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    expected = os.environ.get("EXPECTED_HEAD", "")
    head = git("rev-parse", "HEAD")
    tree = git("rev-parse", "HEAD^{tree}")
    summary: dict = {
        "schema": "distributed_world_simulator.mvp6_full_world_core_execution.v3",
        "subject_head": head,
        "subject_tree": tree,
        "baseline_head": BASE,
        "run_id": os.environ.get("GITHUB_RUN_ID", "local"),
        "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT", "1"),
        "full_world_core_executed": False,
        "full_world_core_regression_pass": False,
        "manifest_coverage_pass": False,
        "mvp6_required_steps_pass": False,
        "same_head_graphical_five_process_bound": False,
        "mvp6_predicate_verified": False,
        "independent_verdict": False,
        "main_merge": False,
    }
    try:
        assert expected == head, "EXACT_SUBJECT_REQUIRED"
        subprocess.run(["git", "merge-base", "--is-ancestor", BASE, head], cwd=ROOT, check=True)

        wo_path = ROOT / "config/control/harness/executions/E2026-09-09-V0-MVP-R1/work-orders/V0-MVP-R1-WO-001.v1.json"
        wo = json.loads(wo_path.read_text(encoding="utf-8"))
        assert wo["state"] == "IN_PROGRESS", "WORK_ORDER_NOT_ACTIVE"
        assert "FULL_WORLD_CORE_REGRESSION_PASS" in wo["required_predicates"], "WORLD_CORE_PREDICATE_NOT_REQUIRED"
        changed = git("diff", "--name-only", BASE, head).splitlines()
        for path in changed:
            assert any(fnmatch.fnmatchcase(path, pattern) for pattern in wo["allowed_paths"]), "OUTSIDE_ALLOWED:" + path
            assert not any(fnmatch.fnmatchcase(path, pattern) for pattern in wo["forbidden_paths"]), "FORBIDDEN:" + path
        assert WORLD_RUNNER not in changed, "CANONICAL_WORLD_RUNNER_MUST_REMAIN_UNCHANGED"
        subprocess.run(["git", "diff", "--check", BASE, head], cwd=ROOT, check=True)

        engine = Path(os.environ["GODOT_BIN"]).resolve()
        assert engine.is_file(), "GODOT_BIN_NOT_FOUND"
        engine_sha = sha(engine)
        assert engine_sha == PIN.get(sys.platform), "CANONICAL_DOUBLE_GODOT_REQUIRED"
        summary["engine_sha256"] = engine_sha
        summary["world_runner_blob"] = git("rev-parse", head + ":" + WORLD_RUNNER)

        graphical_path, graphical = exact_graphical_manifest(head, tree)
        summary["same_head_graphical_five_process_bound"] = True
        summary["graphical_evidence"] = {
            "manifest_path": str(graphical_path),
            "manifest_sha256": sha(graphical_path),
            "subject_head": graphical.get("subject_head"),
            "subject_tree": graphical.get("subject_tree"),
            "run_id": graphical.get("run_id"),
            "check_count": len(graphical.get("checks", {})),
            "negative_controls": list(graphical.get("negative_controls", [])),
        }

        exit_path = OUT / "world-exit.txt"
        assert exit_path.is_file(), "WORLD_EXIT_EVIDENCE_MISSING"
        world_exit = int(exit_path.read_text(encoding="utf-8").strip())
        summary["world_exit_code"] = world_exit
        summary["full_world_core_executed"] = True
        assert world_exit == 0, "FULL_WORLD_CORE_PROCESS_FAILED"

        log_path = OUT / "full-world-core.log"
        assert log_path.is_file(), "WORLD_LOG_MISSING"
        log_text = log_path.read_text(encoding="utf-8-sig", errors="replace")
        summary["world_log_sha256"] = sha(log_path)
        assert not FATAL.search(log_text), "FULL_WORLD_CORE_FATAL_MARKER"

        assert WORLD_SUMMARY.is_file(), "WORLD_REGRESSION_SUMMARY_MISSING"
        world = json.loads(WORLD_SUMMARY.read_text(encoding="utf-8-sig"))
        shutil.copyfile(WORLD_SUMMARY, OUT / "world-regression-summary.json")
        steps = world.get("steps", [])
        assert world.get("passed") is True, "WORLD_REGRESSION_SUMMARY_RED"
        declared = int(world.get("declared_test_count", -1))
        discovered = int(world.get("discovered_test_count", -2))
        assert declared > 0 and declared == discovered, "WORLD_DISCOVERY_PARITY_FAILED"
        assert steps and all(int(row.get("exit_code", 1)) == 0 and row.get("passed") is True for row in steps), "WORLD_STEP_RED"
        coverage = [row for row in steps if row.get("name") == "test_manifest_coverage"]
        assert len(coverage) == 1 and coverage[0].get("passed") is True, "WORLD_MANIFEST_COVERAGE_FAILED"
        summary["manifest_coverage_pass"] = True

        required_step_evidence: dict[str, dict] = {}
        for name, target in TESTS.items():
            matches = [row for row in steps if row.get("target") == target]
            assert matches, "MVP6_WORLD_STEP_MISSING:" + name
            assert all(row.get("passed") is True and int(row.get("exit_code", 1)) == 0 for row in matches), "MVP6_WORLD_STEP_RED:" + name
            required_step_evidence[name] = {
                "target": target,
                "step_names": [row.get("name") for row in matches],
                "durations_seconds": [row.get("duration_seconds") for row in matches],
            }
        summary["mvp6_required_steps"] = required_step_evidence
        summary["mvp6_required_steps_pass"] = True

        focused: dict[str, dict] = {}
        for name, filename in RESULTS.items():
            path = OUT / filename
            assert path.is_file(), "MVP6_RESULT_MISSING:" + name
            value = json.loads(path.read_text(encoding="utf-8"))
            assert value.get("subject_head") == head and value.get("subject_tree") == tree, "MVP6_RESULT_SUBJECT_MISMATCH:" + name
            if name == "diagnostic":
                assert value.get("diagnostic_passed") is True and value.get("failures") == [], "MVP6_DIAGNOSTIC_RED"
            else:
                assert value.get("passed") is True and value.get("failures") == [], "MVP6_FOCUSED_RESULT_RED:" + name
            focused[name] = {k: v for k, v in value.items() if k not in ("observations", "product", "collision", "persistence")}
        summary["focused_results"] = focused
        summary["world_regression"] = {
            "schema": world.get("schema"),
            "checkpoint": world.get("checkpoint"),
            "declared_test_count": declared,
            "discovered_test_count": discovered,
            "step_count": len(steps),
            "summary_sha256": sha(WORLD_SUMMARY),
            "all_steps_green": True,
        }
        summary["full_world_core_regression_pass"] = True
    except Exception as exc:
        summary["error"] = type(exc).__name__ + ": " + str(exc)
        print(summary["error"], flush=True)
    finally:
        summary["tracked_after"] = git("status", "--porcelain", "--untracked-files=no")
        summary["identity_unchanged"] = git("rev-parse", "HEAD") == head and git("rev-parse", "HEAD^{tree}") == tree
        summary["passed"] = (
            summary["full_world_core_regression_pass"]
            and summary["manifest_coverage_pass"]
            and summary["mvp6_required_steps_pass"]
            and summary["same_head_graphical_five_process_bound"]
            and not summary["tracked_after"]
            and summary["identity_unchanged"]
        )
        write(OUT / "summary.json", summary)
        files = [
            {"path": path.relative_to(OUT).as_posix(), "bytes": path.stat().st_size, "sha256": sha(path)}
            for path in sorted(OUT.rglob("*"))
            if path.is_file() and path.name != "manifest.json"
        ]
        write(OUT / "manifest.json", {**summary, "files": files})
        print(json.dumps({
            "head": head,
            "tree": tree,
            "passed": summary["passed"],
            "full_world_core_regression_pass": summary["full_world_core_regression_pass"],
            "same_head_graphical": summary["same_head_graphical_five_process_bound"],
            "declared": summary.get("world_regression", {}).get("declared_test_count"),
            "discovered": summary.get("world_regression", {}).get("discovered_test_count"),
            "steps": summary.get("world_regression", {}).get("step_count"),
            "manifest_sha256": sha(OUT / "manifest.json"),
            "files": len(files),
        }), flush=True)
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
