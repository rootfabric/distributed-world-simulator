#!/usr/bin/env python3
"""Read-only exact ACT0 validation. No commits, pushes, dispatches or acceptance."""
from __future__ import annotations

import argparse
import ast
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

BASE = "3d7672cba293d8e7bd72427b803f73fc8fcee5da"
PREDECESSOR = "c5d3eed5532c9dbe61b3ca13a87242bf6f2ea73d"
REVIEWED_PREDECESSOR = "df1af401a11ef0c65ef442433f888f3a21963ac3"
IDENTITY_PREDECESSOR = "03ec952da8540b2665017138b31dcefcb3cfdf60"
MVP = "V0_PLAYABLE_SEAMLESS_PLANET_COMPOSITION_ACCEPTANCE"
DOC = "docs/control/mvp-act0-r1/"
EX = "config/control/harness/executions/E2026-09-09-V0-MVP-R1/"
ROOT = Path.cwd().resolve()


def git(*args: str, cwd: Path = ROOT) -> str:
    return subprocess.check_output(["git", *args], cwd=cwd, encoding="utf-8").strip()


def identity() -> dict:
    return {"head":git("rev-parse", "HEAD"), "tree":git("rev-parse", "HEAD^{tree}"),
            "tracked_status":git("status", "--porcelain", "--untracked-files=no")}


def save(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def require(condition: bool, detail: str) -> None:
    if not condition:
        raise RuntimeError(detail)


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def without_selector(text: str) -> str:
    node = next(n for n in ast.walk(ast.parse(text)) if isinstance(n,ast.FunctionDef) and n.name == "_select_epoch_audit")
    lines = text.splitlines(keepends=True)
    return ''.join(lines[:node.lineno-1] + lines[node.end_lineno:])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["candidate", "post-adoption"], default="candidate")
    args = parser.parse_args()
    run_id = os.environ.get("GITHUB_RUN_ID", str(time.time_ns()))
    out = ROOT / "artifacts/act0-exact" / run_id
    out.mkdir(parents=True, exist_ok=False)
    before = identity()
    records = []
    errors = []
    save(out / "preflight.json", before)

    def run(name: str, command: list[str], expected: int = 0, cwd: Path = ROOT) -> str:
        started = time.time()
        log = out / (name + ".log")
        with log.open("wb") as stream:
            process = subprocess.Popen(command, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                code = process.wait(timeout=720)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                code = 124
        text = log.read_text(encoding="utf-8", errors="replace")
        passed = code == expected
        if name in {"predecessor-epoch-resume", "predecessor-progress-audit"}:
            passed = passed and "FAILED (failures=1)" in text and "ERROR:" not in text and "MAIN_MOVED_AUDIT_CONTINUE" in text and "MAIN_MOVED_REVIEW_REQUIRED" in text
        if name == "predecessor-completed-identity":
            passed = passed and "FAILED (failures=1)" in text and "ERROR:" not in text and "AssertionError: 3 != 0" in text and "FOREIGN-WORK-ORDER" in text
        record = {"name":name,"command":command,"cwd":str(cwd),"expected_exit":expected,
                  "exit_code":code,"passed":passed,"elapsed_seconds":round(time.time()-started,3),"log_sha256":digest(log)}
        records.append(record)
        save(out / (name + ".result.json"), record)
        print(name, "PASS" if passed else "FAIL", "exit", code, flush=True)
        if not passed:
            errors.append("FAILED_STEP:" + name)
        return text

    try:
        require(not before["tracked_status"], "DIRTY_CHECKOUT")
        require(before["head"] == os.environ.get("GITHUB_SHA", before["head"]), "WRONG_SUBJECT")
        require(not (ROOT / ".github/workflows/mvp-act0-assemble.yml").exists(), "CI_AUTHORING_WORKFLOW_MUST_BE_ABSENT")
        main_head = git("rev-parse", "origin/main")
        save(out / "canonical-context.json", {"head":main_head,"mode":args.mode})
        if args.mode == "candidate":
            require(main_head == BASE, "MAIN_MOVED_REQUIRES_REVIEW")
            orders = [json.loads((ROOT / DOC / p).read_text()) for p in (
                "work-order.v1.json", "work-order-epoch-resume-r3.v1.json",
                "work-order-audit-lifecycle-r4.v1.json", "work-order-audit-identity-r5.v1.json")]
            allowed = [p for o in orders for p in o["allowed_paths"]]
            forbidden = [p for o in orders for p in o["forbidden_paths"]]
            for path in git("diff", "--name-only", BASE, "HEAD").splitlines():
                require(any(fnmatch.fnmatchcase(path, p) for p in allowed), "OUT_OF_SCOPE:" + path)
                require(not any(fnmatch.fnmatchcase(path, p) for p in forbidden), "FORBIDDEN_SCOPE:" + path)
            builder_path = "scripts/harness/state_builder.py"
            original_builder = subprocess.check_output(["git","show",f"{REVIEWED_PREDECESSOR}:{builder_path}"],cwd=ROOT).decode("utf-8")
            require(without_selector(original_builder) == without_selector((ROOT/builder_path).read_text()), "R4_NON_SELECTOR_CODE_DRIFT")
            cases = [
                ("predecessor-epoch-resume", PREDECESSOR, "test_v0_mvp_epoch_resume", "MVPEpochResumeTests.test_committed_exact_audit_resumes_without_product_completion"),
                ("predecessor-progress-audit", REVIEWED_PREDECESSOR, "test_v0_mvp_epoch_resume", "MVPEpochResumeTests.test_audit_survives_implementation_and_verification_events"),
                ("predecessor-completed-identity", IDENTITY_PREDECESSOR, "test_v0_mvp_audit_identity", "MVPAuditIdentityTests.test_foreign_completed_order_is_rejected"),
            ]
            for name, head, module, method in cases:
                old = Path(os.environ.get("RUNNER_TEMP", "/tmp")) / (name + "-" + run_id)
                require(not old.exists(), "PREDECESSOR_DIRECTORY_EXISTS")
                git("worktree", "add", "--detach", str(old), head)
                probe = "tests/harness/" + module + "_probe.py"
                shutil.copyfile(ROOT / ("tests/harness/" + module + ".py"), old / probe)
                run(name, [sys.executable,"-m","unittest", "tests.harness." + module + "_probe." + method,"-v"], expected=1, cwd=old)
                save(out / (name + "-identity.json"), {"head":git("rev-parse","HEAD",cwd=old),"tree":git("rev-parse","HEAD^{tree}",cwd=old),
                    "tracked_status":git("status","--porcelain","--untracked-files=no",cwd=old),"added_probe_only":probe})
            run("control-json", [sys.executable,"-m","harness.control_candidate_validation"])
            run("candidate-consistency", [sys.executable,"-m","harness.cli","check-consistency","--candidate"])
            run("act0-focused", [sys.executable,"-m","unittest","tests.harness.test_v0_mvp_act0","tests.harness.test_v0_mvp_epoch_resume","tests.harness.test_v0_mvp_audit_identity","-v"])
            run("full-harness", [sys.executable,"-m","unittest","discover","-s","tests/harness","-p","test_*.py","-v"])
        else:
            require(git("branch", "--show-current") == "feature/v0-mvp-playable-seamless-planet-r1", "WRONG_RUNTIME_BRANCH")
            git("merge-base", "--is-ancestor", main_head, "HEAD")
            for path in git("diff","--name-only",main_head,"HEAD").splitlines():
                require(path.startswith(EX) or path.startswith(DOC), "POST_ADOPTION_IS_CONTROL_ONLY:" + path)
            payload = json.loads(run("actual-drive", [sys.executable,"-m","harness.cli","drive"]))
            require(payload.get("selected_checkpoint") == MVP, "WRONG_CHECKPOINT")
            require(payload["epoch"]["validation"]["action"] == "CONTINUE", "EPOCH_NOT_CONTINUABLE")
            require(payload.get("continuation_blocked") is False, "CONTINUATION_BLOCKED")
            require(payload["reduced_work_order"]["completed_predicates"] == [], "PRODUCT_PREDICATES_MUST_REMAIN_OPEN")
            require(payload["next"]["mission_complete"] is False, "FALSE_MVP_ACCEPTANCE")
            require(payload["next"]["next_action"] == "CONTINUE_ACTIVE_WORK_ORDER_TO_IMPLEMENTED_AND_VALIDATED", "WRONG_NEXT_ACTION")
            run("actual-close-mission", [sys.executable,"-m","harness.cli","close-mission"], expected=8)
        run("canonical-overview", [sys.executable,"-m","harness.cli","overview"])
        run("canonical-consistency", [sys.executable,"-m","harness.cli","check-consistency"])
        run("pc0", [sys.executable,"scripts/control/project_control.py","--no-fetch","--no-fail-on-red"])
        run("directional", [sys.executable,"scripts/control/project_control_directional_watch.py","--no-fail-on-red"])
        for name in ("project-control-report.json", "directional-watch-report.json"):
            path = ROOT / "artifacts/control" / name
            report = json.loads(path.read_text(encoding="utf-8"))
            require(report.get("overall_health") in ("GREEN","YELLOW"), "PC0_RED_OR_MISSING:" + name)
            if name == "project-control-report.json":
                require(report.get("cross_branch_overlaps") == [], "PC0_OVERLAP_OR_MISSING")
            for finding in report.get("findings", []):
                require(finding.get("level") != "RED" or finding.get("global_blocking") is False, "BLOCKING_DIRECTIONAL_RED")
            shutil.copyfile(path, out / name)
        save(out / "pc0-scope.json", {"canonical_subject":main_head,"post_merge":args.mode == "post-adoption"})
        run("diff-check", ["git","diff","--check",BASE,"HEAD"])
    except Exception as error:
        errors.append(type(error).__name__ + ":" + str(error))
    after = identity()
    if before != after or after["tracked_status"]:
        errors.append("CHECKOUT_CHANGED")
    save(out / "postflight.json", after)
    save(out / "result.json", {"schema":"distributed_world_simulator.act0_machine_evidence.v1",
        "subject":before,"mode":args.mode,"workflow_sha":os.environ.get("GITHUB_SHA"),"run_id":run_id,
        "runner":os.environ.get("RUNNER_NAME","LOCAL"),"checks":records,"passed":not errors,
        "errors":errors,"independent_verdict":False,"mvp_accepted":False})
    files = [{"path":p.relative_to(out).as_posix(),"bytes":p.stat().st_size,"sha256":digest(p)}
             for p in sorted(out.rglob("*")) if p.is_file() and p.name != "manifest.json"]
    save(out / "manifest.json", {"subject":before,"run_id":run_id,"mode":args.mode,"files":files})
    print(json.dumps({"passed":not errors,"errors":errors},ensure_ascii=False))
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
