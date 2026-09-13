#!/usr/bin/env python3
"""Exact MVP4 execution; CI evidence is not an independent or manual verdict."""
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
OUT = ROOT / "artifacts/mvp4-exact"
ENGINE = os.environ["GODOT_BIN"]
BASELINE = "f1d453fb2af49231c30bdc5cbe415ad199394446"
ROWS: list[dict] = []
# Only these exact existing R13 cleanup diagnostics can be classified against
# a new execution of the immutable baseline. Every other ERROR remains fatal.
CLEANUP = re.compile(r"(?m)^(?:WARNING: \d+ ObjectDB instances were leaked at exit[^\n]*|ERROR: \d+ resources still in use at exit[^\n]*)$")
FATAL = re.compile(r"(?im)^\s*(?:SCRIPT ERROR|ERROR):|Parse Error|Compile Error|: FAIL(?:\s|\()")


def run(name: str, args: list[str], timeout: int = 240) -> dict:
    path = OUT / (name + ".log")
    start = time.monotonic()
    code, timed_out = 124, False
    with path.open("w", encoding="utf-8") as log:
        try: code = subprocess.run(args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=timeout, check=False).returncode
        except subprocess.TimeoutExpired: timed_out = True
    text = path.read_text(errors="replace")
    row = {"name": name, "argv": args, "exit_code": code, "timeout_seconds": timeout, "timed_out": timed_out, "fatal_markers": bool(FATAL.search(text)), "passed": code == 0 and not timed_out and not FATAL.search(text), "cleanup_diagnostics": CLEANUP.findall(text), "log_sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "duration_seconds": round(time.monotonic() - start, 3)}
    ROWS.append(row)
    save()
    print(name, json.dumps(row), text[-4000:], flush=True)
    return row


def save() -> None:
    (OUT / "commands.json").write_text(json.dumps(ROWS, indent=2) + "\n")


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    prefix = [ENGINE, "--headless", "--path", str(ROOT)]
    os.environ["MVP4_FOCUSED_RESULT"] = str(OUT / "focused.json")
    if not run("import", prefix + ["--editor", "--import", "--quit"], 180)["passed"]: return 1
    run("mvp4-focused", prefix + ["--script", "res://tests/runtime/test_v0_mvp_4_shared_canonical_dig.gd"])
    current = run("mvp3-attestation", prefix + ["--script", "res://tests/runtime/test_v0_mvp3_source_attestation_roundtrip.gd"])
    if current["cleanup_diagnostics"]:
        baseline_root = Path(os.environ["RUNNER_TEMP"]) / "mvp4-r13-baseline"
        subprocess.run(["git", "worktree", "add", "--detach", str(baseline_root), BASELINE], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
        baseline_import = run("baseline-import", [ENGINE, "--headless", "--path", str(baseline_root), "--editor", "--import", "--quit"], 180)
        baseline = run("baseline-attestation", [ENGINE, "--headless", "--path", str(baseline_root), "--script", "res://tests/runtime/test_v0_mvp3_source_attestation_roundtrip.gd"])
        source = "tests/runtime/test_v0_mvp3_source_attestation_roundtrip.gd"
        unchanged = (ROOT / source).read_bytes() == (baseline_root / source).read_bytes()
        matching = unchanged and baseline_import["passed"] and baseline["cleanup_diagnostics"] == current["cleanup_diagnostics"]
        for row in (current, baseline):
            text = (OUT / (row["name"] + ".log")).read_text(errors="replace")
            successful = "MVP3_SOURCE_ATTESTATION_ROUNDTRIP assertions=86 failures=0 passed=true" in text
            classified = matching and row["exit_code"] == 0 and not row["timed_out"] and successful and not FATAL.search(CLEANUP.sub("", text))
            row["preexisting_cleanup_baseline_confirmed"] = classified
            row["passed"] = bool(classified)
        (OUT / "baseline-cleanup-classification.json").write_text(json.dumps({"baseline_head": BASELINE, "test_bytes_unchanged": unchanged, "diagnostics_identical": matching, "baseline_diagnostics": baseline["cleanup_diagnostics"], "candidate_diagnostics": current["cleanup_diagnostics"], "cleanup_issue_resolved": False, "note": "Historical cleanup warning is retained in raw logs; neither assertions nor diagnostics are deleted."}, indent=2) + "\n")
        save()
    for name, path in [("mvp3-live-owner", "tests/runtime/test_v0_mvp3_live_owner_handoff.gd"), ("mvp3-fixed-input", "tests/runtime/test_v0_mvp3_fixed_tick_input_contract.gd"), ("sm1-carry", "tests/network/test_v0_sm1_player_carry_and_gateway_pivot.gd")]:
        run(name, prefix + ["--script", "res://" + path])
    run("mvp4-five-process", [sys.executable, "tests/integration/test_v0_mvp_4_graphical_shared_dig.py", "--engine", ENGINE, "--output", str(OUT / "graphical")], 300)
    run("mvp3-native-process", [sys.executable, "tests/integration/test_v0_mvp3_native_process_roundtrip.py", "--engine", ENGINE, "--output", str(OUT / "mvp3-native")], 240)
    run("mvp3-graphical-process", [sys.executable, "tests/integration/test_v0_mvp3_graphical_process_roundtrip.py", "--engine", ENGINE, "--output", str(OUT / "mvp3-graphical")], 300)
    focused = json.loads((OUT / "focused.json").read_text()) if (OUT / "focused.json").is_file() else {}
    graphical = json.loads((OUT / "graphical/manifest.json").read_text()) if (OUT / "graphical/manifest.json").is_file() else {}
    exact = focused.get("subject_head") == os.environ["EXPECTED_HEAD"] and focused.get("subject_tree") == os.environ["EXPECTED_TREE"] and graphical.get("subject_head") == os.environ["EXPECTED_HEAD"] and graphical.get("subject_tree") == os.environ["EXPECTED_TREE"]
    clean = not subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=no"], cwd=ROOT, text=True).strip()
    passed = all(row["passed"] for row in ROWS) and focused.get("passed") is True and graphical.get("passed") is True and exact and clean
    (OUT / "summary.json").write_text(json.dumps({"passed": passed, "exact_subject": exact, "tracked_clean_after": clean, "independent_verdict": False, "manual_input_executed": False, "mvp4_predicate_verified": False, "full_world_core_executed": False}, indent=2) + "\n")
    return 0 if passed else 1

if __name__ == "__main__":
    raise SystemExit(main())
