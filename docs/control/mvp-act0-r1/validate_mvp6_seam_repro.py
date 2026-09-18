#!/usr/bin/env python3
"""Preserve native gap reproduction and require seam product, derived collision and persistence rehydration."""
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
import time

ROOT = Path(__file__).resolve().parents[3]
BASE = "182d93872bfddbf52a72ab170371ebb9489690bb"
OUT = ROOT / "artifacts/mvp6-seam-repro"
WORLD_CORE_OUT = ROOT / "artifacts/mvp6-world-core"
TEST = "tests/runtime/test_v0_mvp_6_cross_authority_prerequisites.gd"
PRODUCT_TEST = "tests/runtime/test_v0_mvp_6_cross_authority_construction_seam.gd"
COLLISION_TEST = "tests/runtime/test_v0_mvp_6_cross_authority_construction_collision.gd"
PERSISTENCE_TEST = "tests/runtime/test_v0_mvp_6_cross_authority_construction_persistence.gd"
FULL_WORLD_RESULT_VALIDATOR = ROOT / "docs/control/mvp-act0-r1/validate_mvp6_full_world_core_result.py"
FULL_WORLD_TIMEOUT_SECONDS = 4500
PIN = {"linux": "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7", "win32": "3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5"}
FATAL = re.compile(r"(?im)^\s*(?:SCRIPT ERROR|ERROR):|Parse Error|Compile Error")


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def run(name: str, command: list[str], timeout: int, env: dict[str, str]) -> dict:
    start = time.monotonic()
    log = OUT / (name + ".log")
    with log.open("w", encoding="utf-8") as stream:
        try:
            code = subprocess.run(command, cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT, check=False, timeout=timeout).returncode
        except subprocess.TimeoutExpired:
            code = 124
        except OSError as exc:
            stream.write(str(exc))
            code = 127
    text = log.read_text(encoding="utf-8-sig", errors="replace")
    result = {"name": name, "command": command, "exit_code": code, "duration_seconds": round(time.monotonic() - start, 3), "fatal_markers": bool(FATAL.search(text)), "log_sha256": sha(log)}
    print(json.dumps(result), flush=True)
    if code and name not in ("drive", "closemission"):
        print(text[-4000:], flush=True)
    return result


def run_full_world_core() -> int:
    if OUT.exists() or WORLD_CORE_OUT.exists():
        raise RuntimeError("PRESERVE_EXISTING_WORLD_CORE_EVIDENCE")
    if not FULL_WORLD_RESULT_VALIDATOR.is_file():
        raise RuntimeError("MVP6_FULL_WORLD_CORE_RESULT_VALIDATOR_MISSING")
    WORLD_CORE_OUT.mkdir(parents=True)
    head, tree = git("rev-parse", "HEAD"), git("rev-parse", "HEAD^{tree}")
    env = os.environ.copy()
    env.update(
        EXPECTED_HEAD=head,
        EXPECTED_TREE=tree,
        PYTHONDONTWRITEBYTECODE="1",
        BREAKPOINT_RUNTIME_DISABLED="1",
        MVP6_SEAM_DIAGNOSTIC_RESULT=str(WORLD_CORE_OUT / "result.json"),
        MVP6_CROSS_AUTHORITY_SEAM_RESULT=str(WORLD_CORE_OUT / "product.json"),
        MVP6_DERIVED_COLLISION_RESULT=str(WORLD_CORE_OUT / "collision.json"),
        MVP6_PERSISTENCE_RESULT=str(WORLD_CORE_OUT / "persistence.json"),
    )
    command = ["pwsh", "-NoProfile", "-File", str(ROOT / "RUN_WORLD_REGRESSION_TESTS.ps1")]
    log = WORLD_CORE_OUT / "full-world-core.log"
    start = time.monotonic()
    timed_out = False
    with log.open("w", encoding="utf-8") as stream:
        try:
            code = subprocess.run(
                command,
                cwd=ROOT,
                env=env,
                stdout=stream,
                stderr=subprocess.STDOUT,
                check=False,
                timeout=FULL_WORLD_TIMEOUT_SECONDS,
            ).returncode
        except subprocess.TimeoutExpired:
            stream.write("\nMVP6_FULL_WORLD_CORE_TIMEOUT\n")
            code = 124
            timed_out = True
        except OSError as exc:
            stream.write(str(exc) + "\n")
            code = 127
    duration = round(time.monotonic() - start, 3)
    runner_summary = ROOT / "artifacts/test-results/world-regression-summary.json"
    if runner_summary.is_file():
        shutil.copy2(runner_summary, WORLD_CORE_OUT / "world-regression-summary.json")
    (WORLD_CORE_OUT / "world-exit.txt").write_text(str(code) + "\n", encoding="utf-8")
    write(
        WORLD_CORE_OUT / "execution.json",
        {
            "schema": "distributed_world_simulator.mvp6_world_core_execution_probe.v1",
            "subject_head": head,
            "subject_tree": tree,
            "command": command,
            "exit_code": code,
            "duration_seconds": duration,
            "timeout_seconds": FULL_WORLD_TIMEOUT_SECONDS,
            "timed_out": timed_out,
            "log_sha256": sha(log),
            "predicate_verified": False,
            "independent_verdict": False,
        },
    )
    print(
        json.dumps(
            {
                "name": "full-world-core",
                "command": command,
                "exit_code": code,
                "duration_seconds": duration,
                "timeout_seconds": FULL_WORLD_TIMEOUT_SECONDS,
                "timed_out": timed_out,
                "log_sha256": sha(log),
            }
        ),
        flush=True,
    )
    checked = 1
    try:
        checked = subprocess.run(
            [sys.executable, str(FULL_WORLD_RESULT_VALIDATOR)],
            cwd=ROOT,
            env=env,
            check=False,
        ).returncode
    finally:
        # Always publish raw partial evidence before the outer CI budget can
        # terminate cleanup. A timeout remains RED; this only makes the reason
        # independently inspectable instead of losing the world/core log.
        shutil.copytree(WORLD_CORE_OUT, OUT, dirs_exist_ok=True)
    return checked if checked != 0 else (0 if code == 0 else 1)


def main() -> int:
    commit_message = git("log", "-1", "--pretty=%B")
    if "[mvp6-world-core]" in commit_message:
        return run_full_world_core()

    if OUT.exists():
        raise RuntimeError("PRESERVE_EXISTING_EVIDENCE:" + str(OUT))
    OUT.mkdir(parents=True)
    expected = os.environ.get("EXPECTED_HEAD", "")
    head, tree = git("rev-parse", "HEAD"), git("rev-parse", "HEAD^{tree}")
    env = os.environ.copy()
    env.update(
        EXPECTED_HEAD=head,
        EXPECTED_TREE=tree,
        PYTHONDONTWRITEBYTECODE="1",
        BREAKPOINT_RUNTIME_DISABLED="1",
        MVP6_SEAM_DIAGNOSTIC_RESULT=str(OUT / "result.json"),
        MVP6_CROSS_AUTHORITY_SEAM_RESULT=str(OUT / "product.json"),
        MVP6_DERIVED_COLLISION_RESULT=str(OUT / "collision.json"),
        MVP6_PERSISTENCE_RESULT=str(OUT / "persistence.json"),
    )
    summary: dict = {
        "schema": "distributed_world_simulator.mvp6_seam_repro_execution.v4",
        "subject_head": head,
        "subject_tree": tree,
        "baseline_head": BASE,
        "run_id": env.get("GITHUB_RUN_ID", "local"),
        "run_attempt": env.get("GITHUB_RUN_ATTEMPT", "1"),
        "diagnostic_passed": False,
        "product_test_passed": False,
        "collision_test_passed": False,
        "persistence_test_passed": False,
        "mvp6_cross_authority_construction_seam_verified": False,
        "mvp6_predicate_verified": False,
        "independent_verdict": False,
        "main_merge": False,
        "full_world_core_executed": False,
        "graphical_five_process_executed": False,
        "full_process_restart_executed": False,
    }
    rows: list[dict] = []
    try:
        assert expected == head, "EXACT_SUBJECT_REQUIRED"
        assert not git("status", "--porcelain", "--untracked-files=no"), "TRACKED_DIRTY_BEFORE"
        subprocess.run(["git", "merge-base", "--is-ancestor", BASE, head], cwd=ROOT, check=True)
        subprocess.run([
            "git", "diff", "--check", BASE, head, "--",
            ".github/workflows", "scripts/runtime/networked_gameplay", "scripts/network/prediction",
            "tests/runtime", "tests/integration", "config/control/harness", "scenes/labs/mvp",
            "RUN_V0_MVP_JOURNAL_ROLLBACK.ps1",
        ], cwd=ROOT, check=True)
        wo = json.loads((ROOT / "config/control/harness/executions/E2026-09-09-V0-MVP-R1/work-orders/V0-MVP-R1-WO-001.v1.json").read_text(encoding="utf-8"))
        assert wo["state"] == "IN_PROGRESS" and "MVP6_CROSS_AUTHORITY_CONSTRUCTION_SEAM" in wo["required_predicates"]
        for path in git("diff", "--name-only", BASE, head).splitlines():
            assert any(fnmatch.fnmatchcase(path, p) for p in wo["allowed_paths"]), "OUTSIDE_ALLOWED:" + path
            assert not any(fnmatch.fnmatchcase(path, p) for p in wo["forbidden_paths"]), "FORBIDDEN:" + path
        engine = Path(env["GODOT_BIN"]).resolve()
        summary["engine_sha256"] = sha(engine)
        assert summary["engine_sha256"] == PIN.get(sys.platform), "CANONICAL_DOUBLE_GODOT_REQUIRED"
        summary["diagnostic_test_blob"] = git("rev-parse", head + ":" + TEST)
        summary["product_test_blob"] = git("rev-parse", head + ":" + PRODUCT_TEST)
        summary["collision_test_blob"] = git("rev-parse", head + ":" + COLLISION_TEST)
        summary["persistence_test_blob"] = git("rev-parse", head + ":" + PERSISTENCE_TEST)
        prefix = [str(engine), "--headless", "--path", str(ROOT)]
        imported = run("import", prefix + ["--editor", "--import", "--quit"], 240, env)
        rows.append(imported)
        assert imported["exit_code"] == 0 and not imported["fatal_markers"], "FRESH_IMPORT_FAILED"

        tested = run("seam-prerequisite", prefix + ["--script", "res://" + TEST], 240, env)
        rows.append(tested)
        result_path = OUT / "result.json"
        result = json.loads(result_path.read_text(encoding="utf-8")) if result_path.is_file() else {}
        summary["diagnostic_result"] = {k: v for k, v in result.items() if k != "observations"}
        assert tested["exit_code"] == 0 and not tested["fatal_markers"], "NATIVE_DIAGNOSTIC_FAILED"
        assert result.get("subject_head") == head and result.get("subject_tree") == tree, "DIAGNOSTIC_SUBJECT_MISMATCH"
        assert result.get("diagnostic_passed") is True and result.get("failures") == [], "EXPECTED_GAPS_NOT_BOTH_PROVEN"
        assert result.get("mvp6_predicate_verified") is False and result.get("live_five_process_executed") is False, "DIAGNOSTIC_MUST_NOT_ACCEPT_MVP6"
        summary["diagnostic_passed"] = True

        product_row = run("seam-product", prefix + ["--script", "res://" + PRODUCT_TEST], 480, env)
        rows.append(product_row)
        product_path = OUT / "product.json"
        product = json.loads(product_path.read_text(encoding="utf-8")) if product_path.is_file() else {}
        summary["product_result"] = {k: v for k, v in product.items() if k != "product"}
        assert product_row["exit_code"] == 0 and not product_row["fatal_markers"], "SEAM_PRODUCT_TEST_FAILED"
        assert product.get("subject_head") == head and product.get("subject_tree") == tree, "PRODUCT_SUBJECT_MISMATCH"
        assert product.get("passed") is True and product.get("failures") == [], "SEAM_PRODUCT_NOT_GREEN"
        assert product.get("base_part_count") == 100 and product.get("add_part_count") == 101 and product.get("remove_part_count") == 100, "SEAM_SCALE_CONTRACT_FAILED"
        for field in (
            "single_writer_c17_executed", "east_read_replica_executed", "cross_authority_add_executed",
            "cross_authority_remove_executed", "add_remove_replay_executed", "wrong_epoch_negative_executed",
            "nonempty_player_seam_carry_executed",
        ):
            assert product.get(field) is True, "SEAM_PRODUCT_FIELD_FALSE:" + field
        assert product.get("graphical_five_process_executed") is False and product.get("derived_collision_executed") is False, "NATIVE_PRODUCT_MUST_NOT_OVERCLAIM_GRAPHICS"
        assert product.get("mvp6_cross_authority_construction_seam_verified") is False and product.get("mvp6_predicate_verified") is False, "NATIVE_PRODUCT_MUST_NOT_SELF_ACCEPT"
        summary["product_test_passed"] = True

        collision_row = run("seam-collision", prefix + ["--script", "res://" + COLLISION_TEST], 600, env)
        rows.append(collision_row)
        collision_path = OUT / "collision.json"
        collision = json.loads(collision_path.read_text(encoding="utf-8")) if collision_path.is_file() else {}
        summary["collision_result"] = {k: v for k, v in collision.items() if k != "collision"}
        assert collision_row["exit_code"] == 0 and not collision_row["fatal_markers"], "SEAM_COLLISION_TEST_FAILED"
        assert collision.get("subject_head") == head and collision.get("subject_tree") == tree, "COLLISION_SUBJECT_MISMATCH"
        assert collision.get("passed") is True and collision.get("failures") == [], "SEAM_COLLISION_NOT_GREEN"
        for field in (
            "cross_authority_seam_executed", "derived_presentation_executed", "derived_collision_executed",
            "physics_server_hit_executed", "removed_leaf_collision_absent",
        ):
            assert collision.get(field) is True, "SEAM_COLLISION_FIELD_FALSE:" + field
        assert collision.get("graphical_five_process_executed") is False, "COLLISION_GATE_MUST_NOT_OVERCLAIM_FIVE_PROCESS"
        assert collision.get("mvp6_cross_authority_construction_seam_verified") is False and collision.get("mvp6_predicate_verified") is False, "COLLISION_GATE_MUST_NOT_SELF_ACCEPT"
        summary["collision_test_passed"] = True

        persistence_row = run("seam-persistence", prefix + ["--script", "res://" + PERSISTENCE_TEST], 720, env)
        rows.append(persistence_row)
        persistence_path = OUT / "persistence.json"
        persistence = json.loads(persistence_path.read_text(encoding="utf-8")) if persistence_path.is_file() else {}
        summary["persistence_result"] = {k: v for k, v in persistence.items() if k != "persistence"}
        assert persistence_row["exit_code"] == 0 and not persistence_row["fatal_markers"], "SEAM_PERSISTENCE_TEST_FAILED"
        assert persistence.get("subject_head") == head and persistence.get("subject_tree") == tree, "PERSISTENCE_SUBJECT_MISMATCH"
        assert persistence.get("passed") is True and persistence.get("failures") == [], "SEAM_PERSISTENCE_NOT_GREEN"
        for field in (
            "serialization_executed", "rehydration_executed", "item_identity_preserved",
            "construction_identity_preserved", "authority_mapping_preserved", "relationships_preserved",
            "collision_rehydrated", "removed_collision_stays_absent",
        ):
            assert persistence.get(field) is True, "SEAM_PERSISTENCE_FIELD_FALSE:" + field
        assert persistence.get("full_process_restart_executed") is False and persistence.get("mvp7_restart_claimed") is False, "MVP6_PERSISTENCE_MUST_NOT_CLAIM_MVP7_RESTART"
        assert persistence.get("mvp6_cross_authority_construction_seam_verified") is False and persistence.get("mvp6_predicate_verified") is False and persistence.get("independent_verdict") is False, "PERSISTENCE_GATE_MUST_NOT_SELF_ACCEPT"
        summary["persistence_test_passed"] = True
    except Exception as exc:
        summary["error"] = type(exc).__name__ + ": " + str(exc)
        print(summary["error"], flush=True)
    finally:
        controller = []
        for mode in ("Drive", "CloseMission"):
            name = mode.lower()
            row = run(name, ["pwsh", "-NoProfile", "-File", str(ROOT / "CONTROL_DEVELOPMENT.ps1"), "-" + mode, "-Checkpoint", "V0_PLAYABLE_SEAMLESS_PLANET_COMPOSITION_ACCEPTANCE"], 180, env)
            rows.append(row)
            text = (OUT / (name + ".log")).read_text(encoding="utf-8-sig", errors="replace")
            documents = []
            for line in text.splitlines():
                if line.startswith("{"):
                    try: documents.append(json.loads(line))
                    except json.JSONDecodeError: pass
            write(OUT / (name + ".json"), documents)
            controller.append({"mode": mode, "exit_code": row["exit_code"], "json_documents": len(documents)})
        summary["controller"] = controller
        summary["tracked_after"] = git("status", "--porcelain", "--untracked-files=no")
        summary["identity_unchanged"] = git("rev-parse", "HEAD") == head and git("rev-parse", "HEAD^{tree}") == tree
        summary["passed"] = summary["diagnostic_passed"] and summary["product_test_passed"] and summary["collision_test_passed"] and summary["persistence_test_passed"] and not summary["tracked_after"] and summary["identity_unchanged"]
        write(OUT / "commands.json", rows)
        write(OUT / "summary.json", summary)
        files = [{"path": p.relative_to(OUT).as_posix(), "bytes": p.stat().st_size, "sha256": sha(p)} for p in sorted(OUT.rglob("*")) if p.is_file() and p.name != "manifest.json"]
        write(OUT / "manifest.json", {**summary, "files": files})
        print(json.dumps({"head": head, "tree": tree, "passed": summary["passed"], "diagnostic_passed": summary["diagnostic_passed"], "product_test_passed": summary["product_test_passed"], "collision_test_passed": summary["collision_test_passed"], "persistence_test_passed": summary["persistence_test_passed"], "manifest_sha256": sha(OUT / "manifest.json"), "files": len(files)}), flush=True)
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
