#!/usr/bin/env python3
"""Exact native MVP6 slice; a pass is explicitly not whole-MVP acceptance."""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "artifacts/mvp6-exact/native"
ENGINE_HASHES = {"linux": "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7", "win32": "3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5"}
FATAL = re.compile(r"(?im)^\s*(?:SCRIPT ERROR|ERROR):|Parse Error|Compile Error")


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path: Path) -> dict:
    if not path.is_file():
        return {}
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise ValueError("EVIDENCE_OBJECT_REQUIRED:" + path.name)
    return value


def main() -> int:
    head, tree = git("rev-parse", "HEAD"), git("rev-parse", "HEAD^{tree}")
    engine = Path(os.environ["GODOT_BIN"]).resolve()
    if head != os.environ["EXPECTED_HEAD"] or tree != os.environ["EXPECTED_TREE"]:
        raise RuntimeError("EXACT_SUBJECT_MISMATCH")
    if not engine.is_file() or sha(engine) != ENGINE_HASHES.get(sys.platform):
        raise RuntimeError("EXACT_DOUBLE_ENGINE_REQUIRED")
    if git("status", "--porcelain", "--untracked-files=no"):
        raise RuntimeError("TRACKED_SOURCE_DIRTY")
    OUT.mkdir(parents=True, exist_ok=False)
    env = os.environ.copy()
    env.update(
        PYTHONUTF8="1",
        PYTHONDONTWRITEBYTECODE="1",
        BREAKPOINT_RUNTIME_DISABLED="1",
        MVP6_NATIVE_RESULT=str(OUT / "native.json"),
        MVP6_SECURITY_RESULT=str(OUT / "security.json"),
        MVP6_C17_ROUTE_RESULT=str(OUT / "c17_route.json"),
        MVP3_OWNER_HOOKS_RESULT=str(OUT / "mvp3.json"),
        MVP5_FOCUSED_RESULT=str(OUT / "mvp5.json"),
    )
    prefix = [str(engine), "--headless", "--path", str(ROOT)]
    specs = [
        ("import", prefix + ["--editor", "--import", "--quit"], 240),
        ("prediction_rollback", prefix + ["--script", "res://tests/runtime/test_v0_mvp_6_prediction_rollback.gd"], 120),
        ("security", prefix + ["--script", "res://tests/runtime/test_v0_mvp_6_native_replay_security.gd"], 120),
        ("native", prefix + ["--script", "res://tests/runtime/test_v0_mvp_6_native_item_handoff.gd"], 240),
        ("c17_route", prefix + ["--script", "res://tests/runtime/test_v0_mvp_6_authenticated_construction_authority_route.gd"], 240),
        ("mvp3", prefix + ["--script", "res://tests/runtime/test_v0_mvp3_live_owner_handoff.gd"], 240),
        ("mvp5", prefix + ["--script", "res://tests/runtime/test_v0_mvp_5_exactly_once_material.gd"], 300),
    ]
    rows: list[dict] = []
    for name, argv, timeout in specs:
        start = time.monotonic()
        log = OUT / (name + ".log")
        error = ""
        with log.open("w", encoding="utf-8") as stream:
            try:
                code = subprocess.run(argv, cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout, check=False).returncode
            except subprocess.TimeoutExpired:
                code, error = 124, "TIMEOUT"
            except OSError as exc:
                code, error = 127, str(exc)
        text = log.read_text(encoding="utf-8", errors="replace")
        matches = [line[:300] for line in text.splitlines() if FATAL.search(line)]
        row = {"name": name, "argv": argv, "exit_code": code, "error": error, "fatal_markers": matches[:8], "passed": code == 0 and not matches, "duration_seconds": time.monotonic() - start, "log_sha256": sha(log)}
        if name == "prediction_rollback":
            row["assertions"] = 77
            row["passed"] = row["passed"] and len(re.findall(r"(?m)^MVP6 prediction rollback: PASS \(77 assertions\)$", text)) == 1
        rows.append(row)
        (OUT / "commands.json").write_text(json.dumps(rows, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(row), flush=True)
        if name == "import" and not row["passed"]:
            break
    result_names = ("native", "security", "c17_route", "mvp3", "mvp5")
    results = {name: read(OUT / (name + ".json")) for name in result_names}
    checks = {"all_commands": len(rows) == len(specs) and all(r["passed"] for r in rows), "tracked_clean_after": not git("status", "--porcelain", "--untracked-files=no")}
    for name, value in results.items():
        checks[name + "_passed"] = value.get("passed") is True
        checks[name + "_exact_subject"] = value.get("subject_head") == head and value.get("subject_tree") == tree
        checks[name + "_no_failures"] = value.get("failures") == []
    native = results["native"]
    cases = native.get("cases", [])
    checks["six_actual_transfers"] = len(cases) == 6
    checks["four_nonempty_transfers"] = len([c for c in cases if c.get("nonempty") is True]) == 4
    c17 = results["c17_route"]
    checks["c17_authenticated_actor_context"] = c17.get("authenticated_actor_context_preserved") is True
    checks["c17_terminal_replay_preserved"] = c17.get("terminal_replay_preserved") is True
    checks["c17_unbound_session_rejected"] = c17.get("unbound_session_rejected") is True
    checks["c17_no_duplicate_owner"] = c17.get("canonical_owner_duplicated") is False
    checks["no_self_acceptance"] = (
        native.get("mvp6_predicate_verified") is False
        and native.get("independent_verdict") is False
        and c17.get("mvp6_predicate_verified") is False
        and c17.get("independent_verdict") is False
    )
    passed = all(checks.values())
    summary = {
        "schema": "distributed_world_simulator.mvp6_native_exact_summary.v2",
        "subject_head": head,
        "subject_tree": tree,
        "engine_sha256": sha(engine),
        "passed": passed,
        "checks": checks,
        "assertions": {n: v.get("assertions", 0) for n, v in results.items()},
        "failures": {n: v.get("failures", []) for n, v in results.items()},
        "native_carry_passed": checks["native_passed"],
        "authenticated_c17_route_passed": checks["c17_route_passed"],
        "mvp6_predicate_verified": False,
        "independent_verdict": False,
        "graphical_clients_executed": False,
        "construction_executed": False,
        "world_restart_executed": False,
        "full_world_core_executed": False,
    }
    (OUT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    manifest = {"schema": "distributed_world_simulator.mvp6_native_exact_manifest.v2", "subject_head": head, "subject_tree": tree, "engine_sha256": sha(engine), "run_id": os.environ.get("GITHUB_RUN_ID", "local"), "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT", "1"), "commands": rows, "passed": passed, "files": [{"path": p.relative_to(OUT).as_posix(), "bytes": p.stat().st_size, "sha256": sha(p)} for p in sorted(OUT.rglob("*")) if p.is_file()]}
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
