#!/usr/bin/env python3
"""Exact MVP6 full world/core gate over the unchanged canonical regression runner."""
from __future__ import annotations

import fnmatch
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
BASE = "182d93872bfddbf52a72ab170371ebb9489690bb"
OUT = ROOT / "artifacts/mvp6-seam-repro"
WORLD_SUMMARY = ROOT / "artifacts/test-results/world-regression-summary.json"
WORLD_RUNNER = "RUN_WORLD_REGRESSION_TESTS.ps1"
WORLD_TIMEOUT_SECONDS = 1500
GRAPHICAL_EVIDENCE = ROOT / "docs/control/mvp-act0-r1/MVP6_GRAPHICAL_FIVE_PROCESS_EVIDENCE_14AC9A95_R1.json"
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
# Mirror the canonical runner's marker policy exactly. Godot may emit expected
# diagnostics on stderr that begin with generic "ERROR:" even when a test is
# successful; the canonical runner deliberately does not treat those as red.
FATAL = re.compile(r"(?m)(: FAIL(?:\s|\()|SCRIPT ERROR:|Parse Error:|Compile Error:)")


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def run_world(env: dict[str, str]) -> dict:
    log = OUT / "full-world-core.log"
    started = time.monotonic()
    command = ["pwsh", "-NoProfile", "-File", str(ROOT / WORLD_RUNNER)]
    with log.open("w", encoding="utf-8") as stream:
        try:
            code = subprocess.run(
                command,
                cwd=ROOT,
                env=env,
                stdout=stream,
                stderr=subprocess.STDOUT,
                check=False,
                timeout=WORLD_TIMEOUT_SECONDS,
            ).returncode
        except subprocess.TimeoutExpired:
            stream.write("\nMVP6_FULL_WORLD_CORE_TIMEOUT\n")
            code = 124
        except OSError as exc:
            stream.write("\n" + str(exc) + "\n")
            code = 127
    text = log.read_text(encoding="utf-8-sig", errors="replace")
    row = {
        "name": "full-world-core",
        "command": command,
        "exit_code": code,
        "duration_seconds": round(time.monotonic() - started, 3),
        "timeout_seconds": WORLD_TIMEOUT_SECONDS,
        "fatal_markers": bool(FATAL.search(text)),
        "log_sha256": sha(log),
    }
    print(json.dumps(row), flush=True)
    if code:
        print(text[-12000:], flush=True)
    return row


def main() -> int:
    if OUT.exists():
        raise RuntimeError("PRESERVE_EXISTING_EVIDENCE:" + str(OUT))
    OUT.mkdir(parents=True)

    expected = os.environ.get("EXPECTED_HEAD", "")
    head = git("rev-parse", "HEAD")
    tree = git("rev-parse", "HEAD^{tree}")
    summary: dict = {
        "schema": "distributed_world_simulator.mvp6_full_world_core_execution.v1",
        "subject_head": head,
        "subject_tree": tree,
        "baseline_head": BASE,
        "run_id": os.environ.get("GITHUB_RUN_ID", "local"),
        "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT", "1"),
        "full_world_core_executed": False,
        "full_world_core_regression_pass": False,
        "manifest_coverage_pass": False,
        "mvp6_required_steps_pass": False,
        "prior_graphical_five_process_bound": False,
        "mvp6_predicate_verified": False,
        "independent_verdict": False,
        "main_merge": False,
    }
    command_row: dict = {}

    try:
        assert expected == head, "EXACT_SUBJECT_REQUIRED"
        assert not git("status", "--porcelain", "--untracked-files=no"), "TRACKED_DIRTY_BEFORE"
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

        graphical = json.loads(GRAPHICAL_EVIDENCE.read_text(encoding="utf-8"))
        graphical_head = str(graphical.get("runtime_subject", {}).get("head", ""))
        assert graphical.get("result") == "EXACT_PASS", "FIVE_PROCESS_EVIDENCE_NOT_PASS"
        assert graphical.get("artifact", {}).get("manifest_passed") is True, "FIVE_PROCESS_MANIFEST_NOT_PASS"
        assert graphical.get("artifact", {}).get("checks_failed") == 0, "FIVE_PROCESS_CHECK_FAILURE"
        assert graphical.get("processes", {}).get("unique_process_ids") == 5, "FIVE_PROCESS_PID_CONTRACT_FAILED"
        subprocess.run(["git", "merge-base", "--is-ancestor", graphical_head, head], cwd=ROOT, check=True)
        graphical_critical = {
            "scripts/runtime/networked_gameplay/mvp/v0_mvp6_graphical_client.gd",
            "scripts/runtime/networked_gameplay/mvp/v0_mvp6_guarded_gateway_process.gd",
            "scripts/runtime/networked_gameplay/mvp/v0_mvp6_guarded_authority_process.gd",
            "scripts/runtime/networked_gameplay/mvp/v0_mvp6_derived_construction_runtime_view.gd",
            "scenes/labs/mvp/v0_mvp6_live_construction.tscn",
            "tests/integration/test_v0_mvp_6_graphical_construction.py",
        }
        drift = set(git("diff", "--name-only", graphical_head, head).splitlines()) & graphical_critical
        assert not drift, "FIVE_PROCESS_CRITICAL_DRIFT:" + ",".join(sorted(drift))
        summary["prior_graphical_five_process_bound"] = True
        summary["graphical_evidence"] = {
            "runtime_subject_head": graphical_head,
            "run_id": graphical.get("exact_ci", {}).get("run_id"),
            "artifact_id": graphical.get("artifact", {}).get("id"),
            "artifact_sha256": graphical.get("artifact", {}).get("sha256"),
            "checks_total": graphical.get("artifact", {}).get("checks_total"),
            "checks_failed": graphical.get("artifact", {}).get("checks_failed"),
        }

        env = os.environ.copy()
        env.update(
            EXPECTED_HEAD=head,
            EXPECTED_TREE=tree,
            PYTHONDONTWRITEBYTECODE="1",
            BREAKPOINT_RUNTIME_DISABLED="1",
            MVP6_SEAM_DIAGNOSTIC_RESULT=str(OUT / RESULTS["diagnostic"]),
            MVP6_CROSS_AUTHORITY_SEAM_RESULT=str(OUT / RESULTS["product"]),
            MVP6_DERIVED_COLLISION_RESULT=str(OUT / RESULTS["collision"]),
            MVP6_PERSISTENCE_RESULT=str(OUT / RESULTS["persistence"]),
        )
        if WORLD_SUMMARY.exists():
            WORLD_SUMMARY.unlink()

        command_row = run_world(env)
        summary["full_world_core_executed"] = True
        assert command_row["exit_code"] == 0 and not command_row["fatal_markers"], "FULL_WORLD_CORE_PROCESS_FAILED"
        assert WORLD_SUMMARY.is_file(), "WORLD_REGRESSION_SUMMARY_MISSING"
        world = json.loads(WORLD_SUMMARY.read_text(encoding="utf-8-sig"))
        write(OUT / "world-regression-summary.json", world)

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
            and summary["prior_graphical_five_process_bound"]
            and not summary["tracked_after"]
            and summary["identity_unchanged"]
        )
        write(OUT / "commands.json", [command_row] if command_row else [])
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
            "declared": summary.get("world_regression", {}).get("declared_test_count"),
            "discovered": summary.get("world_regression", {}).get("discovered_test_count"),
            "steps": summary.get("world_regression", {}).get("step_count"),
            "manifest_sha256": sha(OUT / "manifest.json"),
            "files": len(files),
        }), flush=True)
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
