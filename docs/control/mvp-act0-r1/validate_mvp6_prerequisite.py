#!/usr/bin/env python3
"""Reproduce the current native carry fence; never certify MVP6 product success."""
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
OUT = ROOT / "artifacts/mvp6-prerequisite"
PINNED = {
    "linux": "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7",
    "win32": "3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5",
}
FATAL = re.compile(r"(?im)^\s*(?:SCRIPT ERROR|ERROR):|Parse Error|Compile Error")


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path: Path) -> dict:
    if not path.is_file():
        return {}
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError("EVIDENCE_OBJECT_REQUIRED:" + path.name)
    return value


def main() -> int:
    engine = Path(os.environ["GODOT_BIN"]).resolve()
    if not engine.is_file() or PINNED.get(sys.platform) != digest(engine):
        raise RuntimeError("EXACT_DOUBLE_ENGINE_REQUIRED")
    head, tree = git("rev-parse", "HEAD"), git("rev-parse", "HEAD^{tree}")
    if head != os.environ["EXPECTED_HEAD"] or tree != os.environ["EXPECTED_TREE"]:
        raise RuntimeError("EXACT_SUBJECT_REQUIRED")
    if git("status", "--porcelain", "--untracked-files=no"):
        raise RuntimeError("TRACKED_CHECKOUT_DIRTY")
    if OUT.exists():
        raise RuntimeError("PRESERVE_PREVIOUS_EVIDENCE:" + str(OUT))
    OUT.mkdir(parents=True)
    env = os.environ.copy()
    env.update(
        PYTHONUTF8="1", BREAKPOINT_RUNTIME_DISABLED="1",
        MVP3_OWNER_HOOKS_RESULT=str(OUT / "unchanged-mvp3.json"),
        MVP5_FOCUSED_RESULT=str(OUT / "unchanged-mvp5.json"),
        MVP6_PREREQUISITE_RESULT=str(OUT / "diagnostic.json"),
    )
    prefix = [str(engine), "--headless", "--path", str(ROOT)]
    specs = [
        ("import", prefix + ["--editor", "--import", "--quit"], 240),
        ("unchanged-mvp3", prefix + ["--script", "res://tests/runtime/test_v0_mvp3_live_owner_handoff.gd"], 240),
        ("unchanged-mvp5", prefix + ["--script", "res://tests/runtime/test_v0_mvp_5_exactly_once_material.gd"], 300),
        ("mvp6-prerequisite", prefix + ["--script", "res://tests/runtime/test_v0_mvp_6_native_carry_prerequisite.gd"], 240),
    ]
    rows: list[dict] = []
    started = time.monotonic()
    for name, argv, timeout in specs:
        log = OUT / (name + ".log")
        begin = time.monotonic()
        error = ""
        with log.open("w", encoding="utf-8") as stream:
            try:
                code = subprocess.run(argv, cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout, check=False).returncode
            except subprocess.TimeoutExpired:
                code, error = 124, "TIMEOUT"
            except OSError as exc:
                code, error = 127, str(exc)
        text = log.read_text(encoding="utf-8", errors="replace")
        fatal = bool(FATAL.search(text))
        row = {"name": name, "argv": argv, "exit_code": code, "error": error, "fatal_markers": fatal, "passed": code == 0 and not fatal, "timeout_seconds": timeout, "duration_seconds": time.monotonic() - begin, "log_sha256": digest(log)}
        rows.append(row)
        (OUT / "commands.json").write_text(json.dumps(rows, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(row), flush=True)
        if not row["passed"]:
            print(text[-4000:], flush=True)
            break
    diagnostic = read_json(OUT / "diagnostic.json")
    predecessors = [read_json(OUT / (name + ".json")) for name in ("unchanged-mvp3", "unchanged-mvp5")]
    clean = not git("status", "--porcelain", "--untracked-files=no")
    exact = all(value.get("subject_head") == head and value.get("subject_tree") == tree for value in [diagnostic, *predecessors])
    observed = diagnostic.get("observations", {}).get("nonempty_carry", {})
    reproduced = (
        diagnostic.get("diagnostic_passed") is True
        and diagnostic.get("mvp6_nonempty_carry_passed") is False
        and diagnostic.get("mvp6_predicate_verified") is False
        and observed.get("error_code") == "MVP3_ITEM_CARRY_REQUIRES_MVP4"
        and observed.get("empty_roundtrip_positive_control") is True
        and observed.get("rejection_preserves_state") is True
        and observed.get("nonempty_transfer_succeeded") is False
    )
    passed = len(rows) == len(specs) and all(row["passed"] for row in rows) and all(p.get("passed") is True for p in predecessors) and reproduced and exact and clean
    summary = {"schema": "distributed_world_simulator.mvp6_prerequisite_summary.v1", "subject_head": head, "subject_tree": tree, "diagnostic_passed": passed, "blocker_reproduced": reproduced, "unchanged_predecessor_focused_pass": all(p.get("passed") is True for p in predecessors), "diagnostic_assertions": diagnostic.get("assertions", 0), "predecessor_assertions": [p.get("assertions", 0) for p in predecessors], "tracked_clean_after": clean, "exact_subjects": exact, "duration_seconds": time.monotonic() - started, "native_scope_amendment_required": reproduced, "mvp6_product_passed": False, "mvp6_predicate_verified": False, "independent_verdict": False, "graphical_clients_executed": False, "full_world_core_executed": False, "world_restart_executed": False}
    (OUT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    files = [{"path": path.relative_to(OUT).as_posix(), "bytes": path.stat().st_size, "sha256": digest(path)} for path in sorted(OUT.rglob("*")) if path.is_file()]
    manifest = {"schema": "distributed_world_simulator.mvp6_prerequisite_manifest.v1", "subject_head": head, "subject_tree": tree, "engine_sha256": digest(engine), "run_id": os.environ.get("GITHUB_RUN_ID", "local"), "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT", "1"), "commands": rows, "diagnostic_passed": passed, "mvp6_product_passed": False, "tracked_clean_after": clean, "files": files}
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2), flush=True)
    print("MVP6_PREREQUISITE_MANIFEST_SHA256=" + digest(OUT / "manifest.json"), flush=True)
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
