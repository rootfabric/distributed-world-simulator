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
    # The unchanged predecessor validator already classifies its immutable
    # historical cleanup baseline in its own raw command reports. Do not erase
    # or broadly suppress errors from the new MVP5 focused/graphical paths.
    passed = code == 0 and (not fatal or name == "unchanged-mvp4-mvp3")
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
    if not run("mvp5-graphical", [sys.executable, "tests/integration/test_v0_mvp_5_graphical_material.py", "--engine", ENGINE, "--output", str(OUT / "graphical")], 300): return 1
    predecessor_ok = run("unchanged-mvp4-mvp3", [sys.executable, "docs/control/mvp-act0-r1/validate_mvp4_exact.py"], 900)
    predecessor = ROOT / "artifacts/mvp4-exact"
    if predecessor.is_dir(): shutil.copytree(predecessor, OUT / "unchanged-mvp4-mvp3-raw")
    def read(relative: str) -> dict:
        p = OUT / relative
        return json.loads(p.read_text()) if p.is_file() else {}
    focused, graphical, previous = read("focused.json"), read("graphical/manifest.json"), read("unchanged-mvp4-mvp3-raw/summary.json")
    exact = all(r.get("subject_head") == os.environ["EXPECTED_HEAD"] and r.get("subject_tree") == os.environ["EXPECTED_TREE"] for r in (focused, graphical))
    clean = not subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=no"], cwd=ROOT, text=True).strip()
    passed = predecessor_ok and all(r["passed"] for r in ROWS) and all(r.get("passed") is True for r in (focused, graphical, previous)) and exact and clean
    summary = {"passed": passed, "subject_head": os.environ["EXPECTED_HEAD"], "subject_tree": os.environ["EXPECTED_TREE"], "tracked_clean_after": clean, "focused_cases": len(focused.get("cases", [])), "graphical_mvp5_executed": graphical.get("passed") is True, "unchanged_mvp4_mvp3_pass": previous.get("passed") is True, "full_world_core_executed": False, "independent_verdict": False, "mvp5_predicate_verified": False, "manual_input_executed": False, "restart_executed": False}
    (OUT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    return 0 if passed else 1

if __name__ == "__main__":
    raise SystemExit(main())
