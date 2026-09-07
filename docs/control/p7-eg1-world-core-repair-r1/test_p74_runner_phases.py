#!/usr/bin/env python3
"""Focused phase-orchestration regression for RUN_WORLD_REGRESSION_TESTS.ps1.

Exercises the actual PowerShell foreach AST with a recording fake Godot
executor over the real canonical test manifest:

  * the P7.4 worker is invoked exactly three times in the fixed
    seed -> recover-deliver -> recover-replay order, each in a fresh native
    process, with the canonical `-- --phase=<phase>` argument form;
  * every ordinary script keeps its unchanged single generic invocation;
  * a failing phase propagates the failure and stops the suite;
  * the final main_scene_cli_all aggregate still runs after all scripts.

This is an orchestration proof only; it does not claim any runtime PASS and
does not replace the exact full world/core regression.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SOURCE_ROOT = Path(__file__).resolve().parents[3]
RUNNER = "RUN_WORLD_REGRESSION_TESTS.ps1"
P74 = "test_v0_p7_4_persistence_restart_composition"
PHASES = ("seed", "recover-deliver", "recover-replay")
ASSERTIONS = {"seed": 21, "recover-deliver": 25, "recover-replay": 17}

RECORDER = r'''#!/usr/bin/env python3
import json, os, sys
rec = os.environ["FAKE_GODOT_RECORD"]
args = sys.argv[1:]
with open(rec, "a", encoding="utf-8") as f:
    f.write(json.dumps(args) + "\n")
fail_phase = os.environ.get("FAKE_GODOT_FAIL_PHASE", "")
counts = {"seed": 21, "recover-deliver": 25, "recover-replay": 17}
phase = None
for a in args:
    if a.startswith("--phase="):
        phase = a.split("=", 1)[1]
        break
if phase is not None and phase == fail_phase:
    sys.exit(17)
if phase is not None:
    print("V0-P7.4 %s: PASS (%d assertions, 0 failures)" % (phase, counts[phase]))
sys.exit(0)
'''


def check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def run_suite(fake_root: Path, record: Path, fail_phase: str = "") -> tuple[int, list[list[str]]]:
    record.write_text("", encoding="utf-8")
    env = dict(os.environ)
    env["GODOT_BIN"] = str(fake_root / "fake-godot")
    env["FAKE_GODOT_RECORD"] = str(record)
    env["FAKE_GODOT_FAIL_PHASE"] = fail_phase
    # Same canonical invocation form as the exact validation helper: the
    # runner's atomic summary writer needs the Linux Get-Item:Force provider
    # adaptation for its dot-prefixed temporary files.
    command = ('$PSDefaultParameterValues = @{"Get-Item:Force" = $true}; '
               f'& "{fake_root / RUNNER}"; exit $LASTEXITCODE')
    proc = subprocess.run(["pwsh", "-NoProfile", "-Command", command],
                          cwd=fake_root, env=env, capture_output=True, text=True, timeout=600)
    invocations = [json.loads(line) for line in record.read_text().splitlines()]
    return proc.returncode, invocations


def main() -> int:
    tmp = Path(tempfile.mkdtemp(prefix="p74-runner-phases-"))
    try:
        fake_root = tmp / "project"
        fake_root.mkdir()
        shutil.copy2(SOURCE_ROOT / RUNNER, fake_root / RUNNER)
        shutil.copytree(SOURCE_ROOT / "tests", fake_root / "tests")
        (fake_root / "fake-godot").write_text(RECORDER, encoding="utf-8")
        (fake_root / "fake-godot").chmod(0o755)

        summary_path = fake_root / "artifacts/test-results/world-regression-summary.json"

        # Positive orchestration: full manifest through the recording executor.
        code, calls = run_suite(fake_root, tmp / "rec-positive")
        summary = json.loads(summary_path.read_text(encoding="utf-8"))
        check(code == 0, f"positive run must exit 0, got {code}")
        steps = summary["steps"]
        check(len(steps) == 330, f"expected 330 stages, got {len(steps)}")
        check(summary["passed"] is True and summary["declared_test_count"] == summary["discovered_test_count"],
              "coverage contract broke")
        check(all(s["passed"] and s["exit_code"] == 0 for s in steps), "unexpected failed stage in positive run")

        phase_calls = [(i, c) for i, c in enumerate(calls)
                       if any(a.startswith("--phase=") for a in c)]
        check(len(phase_calls) == 3, f"expected exactly 3 phase invocations, got {len(phase_calls)}")
        extracted = []
        for _, c in phase_calls:
            idx = c.index("--")
            tail = c[idx + 1:]
            check(len(tail) == 1 and tail[0].startswith("--phase="), f"unexpected phase args {tail}")
            extracted.append(tail[0].split("=", 1)[1])
        check(tuple(extracted) == PHASES, f"phase order mismatch: {extracted}")

        # Ordinary scripts keep the unchanged generic invocation: no extra
        # `--` separator beyond the three P7.4 phases (the main-scene
        # aggregate legitimately keeps its own `--` scene arguments).
        extra_sep = [c for c in calls if "--script" in c and "--" in c
                     and not any(a.startswith("--phase=") for a in c)]
        check(not extra_sep, f"ordinary invocation drifted: {extra_sep[:2]}")

        # Summary ordering, naming and target binding.
        names = [s["name"] for s in steps]
        expected = [f"{P74}[{p}]" for p in PHASES]
        for p in expected:
            check(names.count(p) == 1, f"missing unique step {p}")
        idxs = [names.index(p) for p in expected]
        check(idxs == sorted(idxs) and idxs[1] == idxs[0] + 1 and idxs[2] == idxs[1] + 1,
              f"P7.4 phases not adjacent and ordered: {idxs}")
        target = "res://tests/runtime/test_v0_p7_4_persistence_restart_composition.gd"
        check(all(steps[i]["target"] == target and steps[i]["kind"] == "headless_script" for i in idxs),
              "P7.4 step target/kind drifted")

        # Each phase is a distinct native process invocation with the script
        # path exactly once.
        for _, c in phase_calls:
            check(c.count(target) == 1, "script path not bound exactly once per phase")
            check("--headless" in c and "--path" in c and "--script" in c, "canonical godot flags missing")

        check(names[-1] == "main_scene_cli_all", "final aggregate missing")

        # Negative orchestration: a failing recover-deliver phase must stop
        # the suite with that exact stage failed.
        code_fail, calls_fail = run_suite(fake_root, tmp / "rec-negative", fail_phase="recover-deliver")
        summary_fail = json.loads(summary_path.read_text(encoding="utf-8"))
        check(code_fail != 0, "failing phase must produce nonzero suite exit")
        failed = [s for s in summary_fail["steps"] if not s["passed"]]
        check(len(failed) == 1 and failed[0]["name"] == f"{P74}[recover-deliver]"
              and failed[0]["exit_code"] == 17, f"failure not bound to the phase stage: {failed}")
        fail_phases = [c[c.index("--") + 1].split("=", 1)[1]
                       for c in calls_fail if any(a.startswith("--phase=") for a in c)]
        check(fail_phases == ["seed", "recover-deliver"], f"propagation broken: {fail_phases}")
        check(not any(c[c.index("--") + 1].split("=", 1)[1] == "recover-replay"
                      for c in calls_fail if any(a.startswith("--phase=") for a in c)),
              "suite continued past a failed phase")
        check(all(s["name"] != "main_scene_cli_all" for s in summary_fail["steps"]),
              "aggregate ran despite failure")

        print("P74_RUNNER_PHASES_ORCHESTRATION_PASS")
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
