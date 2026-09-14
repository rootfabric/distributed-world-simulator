#!/usr/bin/env python3
"""Run complete MVP5 composition plus unchanged MVP4/MVP3 exact regressions."""
from __future__ import annotations
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
OUT = ROOT / "artifacts/mvp5-exact"
ENGINE = os.environ["GODOT_BIN"]
ROWS = []

def run(name: str, argv: list[str], timeout: int) -> bool:
    log = OUT / (name + ".log")
    started = time.monotonic()
    with log.open("w", encoding="utf-8") as stream:
        try: code = subprocess.run(argv, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout).returncode
        except subprocess.TimeoutExpired: code = 124
    text = log.read_text(errors="replace")
    fatal = bool(re.search(r"(?im)^\s*(?:SCRIPT ERROR|ERROR):|Parse Error|Compile Error", text))
    passed = code == 0 and not fatal
    if name == "unchanged-mvp4-mvp3" and code == 0:
        # Only the existing immutable-test/baseline comparison may classify
        # historical R13 cleanup diagnostics. Require its entire command list
        # and final summary, not a name-based exception to arbitrary errors.
        previous = ROOT / "artifacts/mvp4-exact"
        command_file, summary_file = previous / "commands.json", previous / "summary.json"
        commands = json.loads(command_file.read_text()) if command_file.is_file() else []
        summary = json.loads(summary_file.read_text()) if summary_file.is_file() else {}
        allowed = {"mvp3-attestation", "baseline-attestation"}
        passed = summary.get("passed") is True and bool(commands) and all(r.get("passed") is True and (not r.get("fatal_markers") or (r.get("name") in allowed and r.get("preexisting_cleanup_baseline_confirmed") is True)) for r in commands)
    row = {"name": name, "argv": argv, "exit_code": code, "passed": passed, "fatal_markers": fatal, "timeout_seconds": timeout, "duration_seconds": time.monotonic() - started, "log_sha256": hashlib.sha256(log.read_bytes()).hexdigest()}
    ROWS.append(row)
    (OUT / "commands.json").write_text(json.dumps(ROWS, indent=2) + "\n")
    print(json.dumps(row), text[-6000:], flush=True)
    return passed

def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    prefix = [ENGINE, "--headless", "--path", str(ROOT)]
    os.environ["MVP5_FOCUSED_RESULT"] = str(OUT / "focused.json")
    if not run("import", prefix + ["--editor", "--import", "--quit"], 240): return 1
    if not run("mvp5-focused", prefix + ["--script", "res://tests/runtime/test_v0_mvp_5_exactly_once_material.gd"], 300): return 1
    if not run("mvp5-native-accounting", [sys.executable, "tests/fixtures/v0_mvp/mvp5_focused_accounting.py", "--evidence", str(OUT / "focused.json"), "--head", os.environ["EXPECTED_HEAD"], "--tree", os.environ["EXPECTED_TREE"], "--output", str(OUT / "native-accounting.json")], 30): return 1
    if not run("mvp5-graphical", [sys.executable, "tests/integration/test_v0_mvp_5_graphical_material.py", "--engine", ENGINE, "--output", str(OUT / "graphical")], 300): return 1
    predecessor_ok = run("unchanged-mvp4-mvp3", [sys.executable, "docs/control/mvp-act0-r1/validate_mvp4_exact.py"], 900)
    predecessor = ROOT / "artifacts/mvp4-exact"
    if predecessor.is_dir(): shutil.copytree(predecessor, OUT / "unchanged-mvp4-mvp3-raw")
    def read(relative: str) -> dict:
        p = OUT / relative
        return json.loads(p.read_text()) if p.is_file() else {}
    focused, accounting, graphical, previous = read("focused.json"), read("native-accounting.json"), read("graphical/manifest.json"), read("unchanged-mvp4-mvp3-raw/summary.json")
    exact = all(r.get("subject_head") == os.environ["EXPECTED_HEAD"] and r.get("subject_tree") == os.environ["EXPECTED_TREE"] for r in (focused, accounting, graphical))
    clean = not subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=no"], cwd=ROOT, text=True).strip()
    passed = predecessor_ok and all(r["passed"] for r in ROWS) and all(r.get("passed") is True for r in (focused, accounting, graphical, previous)) and exact and clean
    summary = {"passed": passed, "subject_head": os.environ["EXPECTED_HEAD"], "subject_tree": os.environ["EXPECTED_TREE"], "tracked_clean_after": clean, "focused_cases": len(focused.get("cases", [])), "native_accounting_pass": accounting.get("passed") is True, "graphical_mvp5_executed": bool(graphical), "graphical_mvp5_passed": graphical.get("passed") is True, "unchanged_mvp4_mvp3_pass": previous.get("passed") is True, "full_world_core_executed": False, "independent_verdict": False, "mvp5_predicate_verified": False, "manual_input_executed": False, "restart_executed": False}
    (OUT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    return 0 if passed else 1

if __name__ == "__main__":
    raise SystemExit(main())
