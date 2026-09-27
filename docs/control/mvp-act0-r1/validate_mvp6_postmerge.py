#!/usr/bin/env python3
"""Post-PR646 read-only diagnostics; neither clearance nor MVP6 acceptance.

Run the existing default NX probe without its optional journal repair override.
Its symmetric parser-only NX compatibility edits remain disclosed in its output.
Keep actual PC0 colors and controller exit codes, including nonterminal exit 8.
"""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
MAIN = "a6d5eb6b287130a638ba6cf397c34e29169948c1"
MAIN_TREE = "4925ea293c15d88153278437976a3b69f8985ccf"
PARENTS = ["6982a563dd0c88c81449566131852c601ae89868", "d9706b157e84c653a753cc54243ce6651d53319c"]
BASE = "17941a19c4e92473c440869148a25f0016f03d51"
ENGINE = "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"
CHECKPOINT = "V0_PLAYABLE_SEAMLESS_PLANET_COMPOSITION_ACCEPTANCE"
PREFIX = "docs/control/mvp-act0-r1/"
OUT = Path(os.environ["MVP6_POSTMERGE_OUTPUT"]).resolve()


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {}


def main() -> int:
    if OUT.exists() and any(OUT.iterdir()):
        raise RuntimeError("PRESERVE_PREVIOUS_POSTMERGE_EVIDENCE")
    OUT.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    commands: list[dict] = []
    result = {"schema": "distributed_world_simulator.mvp6_postmerge_probe.v1", "merged_main": MAIN,
              "diagnostic_passed": False, "clearance_accepted": False, "epoch_audit_written": False,
              "mvp6_predicate_verified": False, "independent_verdict": False, "full_world_core_executed": False}

    def run(label: str, argv: list[str], seconds: int = 240) -> int:
        target = OUT / (label + ".log")
        with target.open("wb") as stream:
            process = subprocess.Popen(argv, cwd=ROOT, env=env, stdout=stream,
                                       stderr=subprocess.STDOUT, start_new_session=True)
            try:
                code = process.wait(timeout=seconds)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
                code = 124
        commands.append({"label": label, "argv": argv, "exit_code": code, "timeout_seconds": seconds,
                         "log_sha256": sha(target)})
        (OUT / "commands.json").write_text(json.dumps(commands, indent=2) + "\n")
        print(json.dumps({"command": label, "exit_code": code}), flush=True)
        return code

    try:
        head = git("rev-parse", "HEAD")
        tree = git("rev-parse", "HEAD^{tree}")
        result.update(subject_head=head, subject_tree=tree, subject_branch=git("symbolic-ref", "--short", "HEAD"))
        assert head == env["EXPECTED_HEAD"], "SUBJECT_HEAD_CHANGED"
        assert git("rev-parse", "origin/main") == MAIN, "CANONICAL_MAIN_MOVED"
        assert git("rev-parse", MAIN + "^{tree}") == MAIN_TREE, "MERGE_TREE_CHANGED"
        assert git("show", "-s", "--format=%P", MAIN).split() == PARENTS, "MERGE_PARENTS_CHANGED"
        assert not git("status", "--porcelain", "--untracked-files=all"), "SOURCE_NOT_CLEAN_BEFORE"
        assert not git("diff", "--name-only", BASE, "HEAD", "--", "scripts", "scenes", "tests", "project.godot"), "POSTMERGE_DRIVER_CHANGED_RUNTIME_OR_TESTS"
        assert not env.get("MVP6_NX_JOURNAL_REPAIR_HEAD", ""), "JOURNAL_REPAIR_OVERRIDE_FORBIDDEN"
        engine = Path(env["GODOT_BIN"])
        assert engine.is_file() and sha(engine) == ENGINE, "EXACT_ENGINE_REQUIRED"
        result["engine_sha256"] = ENGINE
        result["source_probe_hashes"] = {name: sha(ROOT / PREFIX / name) for name in
                                         ("mvp6_nx_dependency_probe.py", "mvp6_current_main_pc0_probe.py")}
        env.update(MVP6_NX_PROBE_OUTPUT=str(OUT / "nx"),
                   MVP6_NX_PROBE_WORKTREE=str(OUT.parent / (OUT.name + "-nx-worktree")),
                   MVP6_MAIN_PC0_OUTPUT=str(OUT / "pc0"),
                   MVP6_MAIN_PC0_WORKTREE=str(OUT.parent / (OUT.name + "-main-worktree")),
                   MVP6_EXPECTED_MAIN_SHA=MAIN)
        nx_code = run("default-nx", [sys.executable, PREFIX + "mvp6_nx_dependency_probe.py"], 600)
        pc0_code = run("raw-pc0", [sys.executable, PREFIX + "mvp6_current_main_pc0_probe.py"])
        controller_codes = {}
        for mode in ("Drive", "CloseMission"):
            label = mode.lower()
            controller_codes[mode] = run(label, ["pwsh", "-NoProfile", "-File", "./CONTROL_DEVELOPMENT.ps1", "-" + mode, "-Checkpoint", CHECKPOINT])
            documents = []
            for line in (OUT / (label + ".log")).read_text(encoding="utf-8-sig", errors="replace").splitlines():
                if line.startswith("{"):
                    documents.append(json.loads(line))
            (OUT / (label + ".json")).write_text(json.dumps(documents, indent=2) + "\n")
            assert documents, "CONTROLLER_JSON_MISSING:" + mode
        nx = read(OUT / "nx/summary.json")
        pc0 = read(OUT / "pc0/probe-summary.json")
        exact = git("rev-parse", "origin/main") == MAIN and git("rev-parse", "HEAD") == head and git("rev-parse", "HEAD^{tree}") == tree
        clean = not git("status", "--porcelain", "--untracked-files=all")
        default_nx = nx_code == 0 and nx.get("dependency_revalidated") is True and nx.get("journal_repair_input") is None and nx.get("canonical_main") == MAIN and nx.get("producer_head") == head
        pc0_valid = pc0_code == 0 and pc0.get("main_sha") == MAIN and pc0.get("standard_overall") in ("GREEN", "YELLOW", "RED") and pc0.get("directional_overall") in ("GREEN", "YELLOW", "RED")
        result.update(default_nx_dependency_revalidated=default_nx, baseline_passed=nx.get("baseline_passed"),
                      candidate_passed=nx.get("candidate_passed"), journal_repair_input=nx.get("journal_repair_input"),
                      unmodified_nx_source_acceptance=False, consumer_head=nx.get("consumer_head"),
                      producer_critical_blob=nx.get("producer_critical_blob"), standard_pc0=pc0.get("standard_overall"),
                      directional_pc0=pc0.get("directional_overall"), controller_exit_codes=controller_codes,
                      identity_unchanged=exact, source_clean_after=clean)
        result["diagnostic_passed"] = default_nx and pc0_valid and exact and clean and controller_codes["Drive"] == 0 and controller_codes["CloseMission"] in (0, 8)
    except Exception as exc:
        result["execution_error"] = str(exc)
    finally:
        (OUT / "summary.json").write_text(json.dumps(result, indent=2) + "\n")
        files = [{"path": p.relative_to(OUT).as_posix(), "bytes": p.stat().st_size, "sha256": sha(p)}
                 for p in sorted(OUT.rglob("*")) if p.is_file() and p != OUT / "manifest.json"]
        manifest = {"schema": "distributed_world_simulator.mvp6_postmerge_manifest.v1", "subject_head": result.get("subject_head"),
                    "subject_tree": result.get("subject_tree"), "canonical_main": MAIN, "canonical_main_tree": MAIN_TREE,
                    "run_id": env.get("GITHUB_RUN_ID"), "run_attempt": env.get("GITHUB_RUN_ATTEMPT"),
                    "driver_sha256": sha(Path(__file__)), "diagnostic_passed": result["diagnostic_passed"],
                    "mvp6_predicate_verified": False, "clearance_accepted": False, "files": files}
        (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        print(json.dumps(result, sort_keys=True), flush=True)
    return 0 if result["diagnostic_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
