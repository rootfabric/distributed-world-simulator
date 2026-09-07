#!/usr/bin/env python3
"""Read-only exact-candidate validation; never emits an independent verdict."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time

BASE = "c14c37cce4930a8b5132d5d5fdfab3a5dfa82f5f"
ENGINE_SHA = "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"
DOCS = "docs/control/p7-eg1-world-core-repair-r1/"
PORT = "scripts/network/transports/v2/enet_multi_peer_transport_port.gd"
EG1 = "tests/network/test_eg1_gateway_processes.gd"
FATAL = re.compile(r"SCRIPT ERROR:|Parse Error:|Compile Error:|Failed to instantiate an autoload|Failed to load script")
P7_LEAVES = {
    "v0-p7-5-two-client-convergence": {
        "m7-aggregate-replica": 5, "mw6": 130, "mw7": 114, "p5-mining-tool": 36,
        "p5-two-client": 47, "p7-1-authority": 88, "p7-1-tool-to-mw4": 30,
        "p7-2-bubble": 53, "p7-2-seam": 50, "p7-3-material-delivery": 116,
        "p7-4-recover-deliver": 25, "p7-4-recover-replay": 17, "p7-4-seed": 21,
        "p7-5-two-client": 85, "rl2": 153, "rl3": 175,
    },
    "v0-p7-7-graphical-digging": {
        "mw10-c0-physical-output": 30, "mw10-c1-durability": 60,
        "mw10-process-recovery": 53, "mw10-transactions": 201, "mw4": 187,
        "p7-6-seam-composition": 106, "p7-7-a-playground": 20,
        "p7-7-b-seam-near": 20, "p7-7-c2-delivery": 42, "p7-7-c3-true-ab": 61,
        "p7-7-d-reservation-conflict": 31, "p7-7-e-actor-handoff": 24,
        "p7-7-graphical-slice": 52,
    },
}

P7_SUMMARY_PREFIXES = {'m7-aggregate-replica': 'M7 aggregate replica compatibility',
 'mw10-c0-physical-output': 'MW10 canonical physical output',
 'mw10-c1-durability': 'MW10 physical output durability',
 'mw10-process-recovery': 'MW10 cross-region Matter processes',
 'mw10-transactions': 'MW10 cross-region Matter transactions',
 'mw4': 'MW4 matter mutations',
 'mw6': 'MW6 matter network authority',
 'mw7': 'MW7 matter interest replication',
 'p5-mining-tool': 'V0-P5 mining tool gate',
 'p5-two-client': 'V0-P5 two-client replication/reconnect',
 'p7-1-authority': 'V0-P7.1 authority gate',
 'p7-1-tool-to-mw4': 'V0-P7.1 Tool->MW4 integration',
 'p7-2-bubble': 'V0-P7.2 lunar Matter bubble',
 'p7-2-seam': 'V0-P7.2 lunar surface seam',
 'p7-3-material-delivery': 'V0-P7.3 material batch to Item Graph',
 'p7-4-recover-deliver': 'V0-P7.4 recover-deliver',
 'p7-4-recover-replay': 'V0-P7.4 recover-replay',
 'p7-4-seed': 'V0-P7.4 seed',
 'p7-5-two-client': 'V0-P7.5 two-client convergence',
 'p7-6-seam-composition': 'V0-P7.6 seam + multi-region composition',
 'p7-7-a-playground': 'V0-P7.7-A Digging Playground',
 'p7-7-b-seam-near': 'V0-P7.7-B seam-near single-region',
 'p7-7-c2-delivery': 'V0-P7.7-C2 MW10 physical output to P7.3',
 'p7-7-c3-true-ab': 'V0-P7.7-C3 true A+B end-to-end',
 'p7-7-d-reservation-conflict': 'V0-P7.7-D MW10 reservation conflict',
 'p7-7-e-actor-handoff': 'V0-P7.7-E actor handoff no false MW10',
 'p7-7-graphical-slice': 'V0-P7.7 graphical digging slice',
 'rl2': 'RL2 Matter multiresolution meshing',
 'rl3': 'RL3 representation-aware network streaming'}


def git(*args: str, cwd: Path | None = None) -> str:
    return subprocess.check_output(["git", *args], cwd=cwd, text=True).strip()


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def run(root: Path, out: Path, name: str, command: list[str], timeout: int,
        expected: int = 0, cwd: Path | None = None) -> None:
    working = cwd or root
    started = time.time()
    record = {"command": command, "cwd": str(working), "expected_exit": expected,
              "timeout_seconds": timeout, "started_unix": started}
    write_json(out / f"{name}.command.json", record)
    with (out / f"{name}.log").open("wb") as log:
        process = subprocess.Popen(command, cwd=working, stdout=log, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
            code = 124
            log.write(b"\nVALIDATOR_PROCESS_GROUP_TIMEOUT\n")
    text = (out / f"{name}.log").read_text(encoding="utf-8", errors="replace")
    record.update(exit_code=code, elapsed_seconds=round(time.time() - started, 3),
                  fatal_matches=FATAL.findall(text), log_sha256=digest(out / f"{name}.log"))
    write_json(out / f"{name}.result.json", record)
    print(f"{name}: exit={code} expected={expected} fatal={len(record['fatal_matches'])}", flush=True)
    require(code == expected and not record["fatal_matches"], f"FAILED_STEP:{name}; see complete log")


def identity(root: Path) -> dict:
    return {"head": git("rev-parse", "HEAD", cwd=root),
            "tree": git("rev-parse", "HEAD^{tree}", cwd=root),
            "tracked_status": git("status", "--porcelain", "--untracked-files=no", cwd=root)}


def check_source(root: Path) -> None:
    changed = git("diff", "--name-only", BASE, "HEAD", cwd=root).splitlines()
    allowed = {PORT, EG1, ".github/workflows/p7-eg1-world-core-repair.yml"}
    require(all(path in allowed or path.startswith(DOCS) for path in changed), "WORK_ORDER_SCOPE_DRIFT")
    original = subprocess.check_output(["git", "show", f"{BASE}:{PORT}"], cwd=root).decode()
    current = (root / PORT).read_text(encoding="utf-8")
    patch = ("\t# Godot a13da4feb passes the channel count as incoming bandwidth.\n"
             "\t# Restore this endpoint's unlimited defaults before any client handshake;\n"
             "\t# do not alter channel binding, delivery modes or adaptive RTT throttling.\n"
             "\t_peer.host.bandwidth_limit(0, 0)\n")
    require(current.count(patch) == 1 and current.replace(patch, "") == original, "NON_MINIMAL_ADAPTER_DIFF")
    test = (root / EG1).read_text(encoding="utf-8")
    begin = "\t# Run only after all original worker assertions and cleanup: no timing change\n"
    end = "\tprint(JSON.stringify(bandwidth))\n"
    require(test.count(begin) == 1 and test.count(end) == 1, "ADDITIVE_EG1_HOOK_MISSING")
    first, rest = test.split(begin)
    _, last = rest.split(end)
    original_test = subprocess.check_output(["git", "show", f"{BASE}:{EG1}"], cwd=root).decode()
    require(first.endswith("func _finish() -> void:\n\t_cleanup()\n") and first + last == original_test,
            "ORIGINAL_EG1_SCENARIO_CHANGED")
    git("diff", "--check", cwd=root)


def probe_campaign(root: Path, out: Path, engine: str) -> None:
    baseline = Path(os.environ["RUNNER_TEMP"]) / f"p7-baseline-{os.environ['GITHUB_RUN_ID']}"
    require(not baseline.exists(), "BASELINE_DIRECTORY_ALREADY_EXISTS")
    git("worktree", "add", "--detach", str(baseline), BASE, cwd=root)
    before = identity(baseline)
    write_json(out / "baseline-preflight.json", before)
    runner = str(root / DOCS / "probes/run_bandwidth_probe.gd")
    run(root, out, "baseline-import", [engine, "--headless", "--editor", "--path", str(baseline), "--import"], 180)
    run(root, out, "baseline-probe", [engine, "--headless", "--path", str(baseline), "--script", runner,
        "--", f"--output={out / 'baseline-probe.json'}"], 30, expected=1)
    report = json.loads((out / "baseline-probe.json").read_text())
    require(report["passed"] is False and len(report["cases"]) == 2, "BASELINE_NEGATIVE_CONTROL_MISSING")
    for case in report["cases"]:
        require(case["statistics_before_input"]["limit"] == 1 and case["statistics_before_input"]["deceleration"] == 2
                and case["reliable_valid"] and case["reliable_enqueue"] == [0, 0, 0]
                and case["input_enqueue"] == 0 and case["input_received"] is False, "BASELINE_FAILURE_NOT_BANDWIDTH")
    after = identity(baseline)
    write_json(out / "baseline-postflight.json", after)
    require(before == after and not after["tracked_status"], "BASELINE_MUTATED")
    run(root, out, "candidate-probe", [engine, "--headless", "--path", str(root), "--script", runner,
        "--", f"--output={out / 'candidate-probe.json'}"], 30)
    positive = json.loads((out / "candidate-probe.json").read_text())
    require(positive["passed"] is True and len(positive["cases"]) == 2, "CANDIDATE_POSITIVE_CONTROL_MISSING")
    for case in positive["cases"]:
        require(case["passed"] is True and case["statistics_before_input"]["limit"] == 32
                and case["statistics_before_input"]["deceleration"] == 2
                and case["reliable_valid"] and case["input_received"], "CANDIDATE_BANDWIDTH_NOT_RESTORED")
    for attempt in range(1, 6):
        name = f"eg1-{attempt}"
        run(root, out, name, [engine, "--headless", "--path", str(root), "--script", f"res://{EG1}"], 90)
        reports = []
        for line in (out / f"{name}.log").read_text().splitlines():
            if line.startswith("{"):
                value = json.loads(line)
                if value.get("test") == "eg1_gateway_processes_l2":
                    reports.append(value)
        require(len(reports) == 1 and reports[0]["verdict"] == "PASS" and not reports[0]["failures"]
                and reports[0]["assertions"] == 36, "EG1_ORIGINAL_PLUS_ADDITIVE_ASSERTIONS_NOT_PROVEN")
    siblings = ["test_t1_multi_peer_transport_contracts.gd", "test_t1_multi_peer_transport_processes.gd",
                "test_nx2_realtime_traffic_separation.gd"]
    siblings += [p.name for p in sorted((root / "tests/network").glob("test_eg[0-9]*.gd")) if p.name != Path(EG1).name]
    write_json(out / "focused-sibling-manifest.json", siblings)
    for sibling in siblings:
        run(root, out, sibling.removesuffix(".gd"), [engine, "--headless", "--path", str(root),
            "--script", f"res://tests/network/{sibling}"], 300)


def check_p7_leaf(text: str, name: str, count: int) -> None:
    prefix = re.escape(P7_SUMMARY_PREFIXES[name])
    # Existing canonical tests have three terminal formats. Bind the exact
    # test prefix, count and success form, not a generic PASS substring.
    if name in ("p5-mining-tool", "p5-two-client"):
        terminal = rf"{count} assertions, 0 failures"
    elif name in ("mw6", "mw7", "rl2", "rl3", "mw10-process-recovery", "mw10-transactions", "mw4"):
        terminal = rf"PASS \({count} assertions(?: / [0-9]+(?:\.[0-9]+)? s)?\)"
    else:
        terminal = rf"PASS \({count} assertions, 0 failures\)"
    matches = re.findall(rf"^{prefix}: {terminal}$", text, re.MULTILINE)
    negative = re.search(r"\[FAIL\]|: FAIL\b|\b[1-9][0-9]* failures\b", text)
    require(len(matches) == 1 and not negative and not FATAL.search(text), f"P7_LEAF_NOT_PROVEN:{name}")


def p7_train(root: Path, out: Path, engine: str, head: str) -> None:
    run(root, out, "p7-train", ["bash", "RUN_V0_P7_7_GRAPHICAL_DIGGING_GATE.sh", engine, head], 1800)
    stages = []
    for group, expected in P7_LEAVES.items():
        for name, count in expected.items():
            path = root / "artifacts/runtime" / group / f"{name}.log"
            text = path.read_text(encoding="utf-8", errors="replace")
            check_p7_leaf(text, name, count)
            stages.append({"log": str(path.relative_to(root / "artifacts")), "assertions": count,
                           "failures": 0, "sha256": digest(path)})
    require(len(stages) == 29 and sum(s["assertions"] for s in stages) == 2032, "P7_LEAF_COVERAGE_MISMATCH")
    write_json(out / "p7-stage-summary.json", {"passed": True, "stages": stages, "assertions": 2032})


def preserve(root: Path, out: Path) -> None:
    # Keep raw results, including every failed/negative attempt. No source export.
    for subdir in ("test-results", "runtime", "control"):
        source = root / "artifacts" / subdir
        if source.exists():
            shutil.copytree(source, out / subdir, dirs_exist_ok=True)
    files = [{"path": str(p.relative_to(out)), "bytes": p.stat().st_size, "sha256": digest(p)}
             for p in sorted(out.rglob("*")) if p.is_file() and p != out / "manifest.json"]
    write_json(out / "manifest.json", {"kind": "IMPLEMENTER_CI_EVIDENCE_NOT_INDEPENDENT_ACCEPTANCE",
        "subject": identity(root), "workflow_sha": os.environ["GITHUB_SHA"],
        "run_id": os.environ["GITHUB_RUN_ID"], "run_attempt": os.environ["GITHUB_RUN_ATTEMPT"],
        "job": os.environ["GITHUB_JOB"], "runner": os.environ["RUNNER_NAME"],
        "godot_sha256": ENGINE_SHA, "files": files})


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("kind", choices=["world", "p7"])
    args = parser.parse_args()
    root = Path.cwd().resolve()
    out = root / f"artifacts/p7-eg1-repair-{args.kind}"
    out.mkdir(parents=True, exist_ok=True)
    initial = identity(root)
    write_json(out / "preflight.json", initial)
    code = 1
    try:
        require(initial["head"] == os.environ["GITHUB_SHA"] and not initial["tracked_status"], "CANDIDATE_NOT_EXACT_CLEAN")
        check_source(root)
        engine = str(Path(os.environ["GODOT_BIN"]).resolve())
        require(digest(Path(engine)) == ENGINE_SHA, "UNAPPROVED_ENGINE")
        run(root, out, "version", [engine, "--version"], 15)
        require((out / "version.log").read_text().strip() == "4.7.1.stable.double.custom_build.a13da4feb", "ENGINE_VERSION_MISMATCH")
        run(root, out, "import", [engine, "--headless", "--editor", "--path", str(root), "--import"], 180)
        if args.kind == "world":
            probe_campaign(root, out, engine)
            run(root, out, "full-world-core", ["pwsh", "-NoProfile", "-Command",
                '$PSDefaultParameterValues = @{"Get-Item:Force" = $true}; & ./RUN_WORLD_REGRESSION_TESTS.ps1; exit $LASTEXITCODE'], 7200)
            summary = json.loads((root / "artifacts/test-results/world-regression-summary.json").read_text())
            require(summary["passed"] is True and summary["declared_test_count"] == summary["discovered_test_count"], "WORLD_SUMMARY_NOT_PASS")
            require(bool(summary["steps"]) and all(s["passed"] is True and s["exit_code"] == 0 for s in summary["steps"]), "WORLD_STAGE_NOT_PASS")
            require(any(s["name"] == "main_scene_cli_all" for s in summary["steps"]), "WORLD_AGGREGATE_MISSING")
        else:
            p7_train(root, out, engine, initial["head"])
        code = 0
    except Exception as error:
        write_json(out / "failure.json", {"type": type(error).__name__, "message": str(error)})
        print(f"VALIDATION_FAILED: {error}", file=sys.stderr, flush=True)
    finally:
        final = identity(root)
        write_json(out / "postflight.json", final)
        if final != initial or final["tracked_status"]:
            code = 1
        write_json(out / "result.json", {"passed": code == 0, "exit_code": code, "kind": args.kind,
                                        "subject": initial, "checkout_unchanged": final == initial})
        preserve(root, out)
    return code


if __name__ == "__main__":
    sys.exit(main())
