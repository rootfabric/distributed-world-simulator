#!/usr/bin/env python3
"""Exact post-acceptance repair validation; never grants acceptance or merge."""
from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

BASE = "438b21d0f5f348d838c2fae0bfae3547ba56a875"
ENGINE_SHA = "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"
DOCS = "docs/control/p7-post-acceptance-r1"
NATIVE = "tests/matter/transactions/test_matter_repository_lock_reclaim.gd"
MW9_RECOVERY = "tests/matter/handoff/test_mw9_durable_handoff_recovery.gd"
REVIEW = "docs/control/p7-eg1-world-core-repair-r1/review"
HISTORICAL = {
    f"{REVIEW}/REVIEWER-RESULT-DCA12CEC-R2.v1.json": "8021cd51cdbd153c0f05b2b0d7b6d15864835fb4",
    f"{REVIEW}/VERIFIER-RESULT-DCA12CEC-R2.v1.json": "f31aec4c9b12b9e0d0863ed12a8343dcbcd1ff82",
}
LOCKS = {
    "scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_repository.gd":
        ("be7c5ee411752a2623cbf89279b136892d1f0852", "b414fe83502dd95d58f87b4f1fdd79442484d240"),
    "scripts/simulation/matter/handoff/durable/matter_durable_handoff_repository.gd":
        ("1a1900d18e823fccc1be99fd048343ec86610297", "4ed26431b940f1dd2e95351f69944b8946200e5c"),
}


def git(root: Path, *args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=root, text=True).strip()


def require(value: bool, message: str) -> None:
    if not value:
        raise RuntimeError(message)


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def blob(data: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()


def write(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def source_guard(root: Path) -> None:
    changed = git(root, "diff", "--name-only", BASE, "HEAD").splitlines()
    allowed = set(LOCKS) | set(HISTORICAL) | {
        NATIVE, NATIVE + ".uid", MW9_RECOVERY, "tests/harness/test_project_control_validation.py",
        "tests/harness/test_p7_post_acceptance_packet.py",
        ".github/workflows/p7-post-acceptance-repair.yml",
    }
    require(all(p in allowed or p.startswith(DOCS + "/") for p in changed), "WORK_ORDER_SCOPE_DRIFT")
    modified = {"_acquire_lock", "_release_lock", "_remove_stale_lock", "_lock_is_stale",
                "_read_lock_owner_at", "_remove_directory", "_wait_for_unlock"}
    def functions(text: str) -> dict[str, str]:
        return {m.group(1): m.group(0) for m in re.finditer(r"(?ms)^func (\w+)\(.*?(?=^func |\Z)", text)}
    for path, (old, new) in LOCKS.items():
        original = subprocess.check_output(["git", "show", f"{BASE}:{path}"], cwd=root)
        current = (root / path).read_bytes()
        require(blob(original) == old and blob(current) == new, "LOCK_SOURCE_PIN_MISMATCH:" + path)
        previous, candidate = functions(original.decode()), functions(current.decode())
        require(all(candidate.get(name) == text for name, text in previous.items() if name not in modified),
                "CHECKPOINT_CAS_OR_PENDING_PROTOCOL_CHANGED:" + path)
    for path, expected in HISTORICAL.items():
        require(blob((root / path).read_bytes()) == expected, "HISTORICAL_VERDICT_CHANGED:" + path)
    spec = json.loads((root / DOCS / "mw9-fixture-guard.v1.json").read_text())
    current = (root / MW9_RECOVERY).read_bytes()
    original = subprocess.check_output(["git", "show", f"{BASE}:{MW9_RECOVERY}"], cwd=root)
    require(spec["path"] == MW9_RECOVERY and blob(original) == spec["original_blob_sha"]
            and blob(current) == spec["candidate_blob_sha"], "MW9_FIXTURE_SOURCE_PIN_MISMATCH")
    restored = current.decode("utf-8")
    require(len(spec["additions"]) == 3, "MW9_FIXTURE_ADDITIONS_CHANGED")
    for addition in spec["additions"]:
        require(isinstance(addition, str) and bool(addition) and restored.count(addition) == 1,
                "MW9_FIXTURE_ADDITION_MISSING")
        restored = restored.replace(addition, "")
    require(restored.encode("utf-8") == original, "MW9_ORIGINAL_ASSERTIONS_CHANGED")
    git(root, "diff", "--check", BASE, "HEAD")


def validate_world_step_identities(steps: list[dict]) -> None:
    require(all(isinstance(step, dict) for step in steps), "WORLD_STAGE_RECORD_INVALID")
    identities = [
        (str(step.get("kind", "")), str(step.get("target", "")), str(step.get("name", "")))
        for step in steps
    ]
    require(len(identities) == len(set(identities)), "WORLD_STEP_IDENTITY_COLLISION")


def validate_world_step_contracts(steps: list[dict], discovered: set[str], p74: str,
                                  phases: list[str]) -> None:
    validate_world_step_identities(steps)
    require(len(steps) >= 3, "WORLD_SPECIAL_STAGE_MISSING")
    manifest = steps[0]
    editor = steps[1]
    aggregate = steps[-1]
    require(str(manifest.get("name", "")) == "test_manifest_coverage"
            and str(manifest.get("kind", "")) == "static"
            and re.fullmatch(rf"{len(discovered)} tests; appended [0-9]+ discovered overlays",
                             str(manifest.get("target", ""))) is not None,
            "WORLD_MANIFEST_STAGE_CONTRACT_INVALID")
    require(str(editor.get("name", "")) == "editor_import_parse"
            and str(editor.get("kind", "")) == "editor"
            and str(editor.get("target", "")) == "res://",
            "WORLD_EDITOR_STAGE_CONTRACT_INVALID")
    require(str(aggregate.get("name", "")) == "main_scene_cli_all"
            and str(aggregate.get("kind", "")) == "main_scene_cli"
            and str(aggregate.get("target", "")) == "playground:test.run all",
            "WORLD_AGGREGATE_STAGE_CONTRACT_INVALID")
    allowed_phases = set(phases)
    for step in steps[2:-1]:
        require(str(step.get("kind", "")) == "headless_script", "WORLD_STAGE_KIND_INVALID")
        target = str(step.get("target", ""))
        name = str(step.get("name", ""))
        require(target in discovered, "WORLD_HEADLESS_TARGET_NOT_DISCOVERED")
        if target == p74:
            require(name in allowed_phases, "WORLD_HEADLESS_NAME_TARGET_MISMATCH")
        else:
            expected_name = Path(target.removeprefix("res://")).stem
            require(name == expected_name, "WORLD_HEADLESS_NAME_TARGET_MISMATCH")


def world_summary(root: Path) -> dict:
    summary = json.loads((root / "artifacts/test-results/world-regression-summary.json").read_text())
    discovered = {"res://" + p.relative_to(root).as_posix()
                  for p in (root / "tests").rglob("test_*.gd")
                  if "fixtures" not in p.relative_to(root / "tests").parts[:-1]}
    steps = summary["steps"]
    require(summary["passed"] is True and summary["declared_test_count"] == summary["discovered_test_count"]
            == len(discovered), "WORLD_DISCOVERY_NOT_COMPLETE")
    require(all(s["passed"] is True and s["exit_code"] == 0 for s in steps), "WORLD_STAGE_FAILED")
    p74 = "res://tests/runtime/test_v0_p7_4_persistence_restart_composition.gd"
    phases = ["test_v0_p7_4_persistence_restart_composition[" + p + "]"
              for p in ("seed", "recover-deliver", "recover-replay")]
    validate_world_step_contracts(steps, discovered, p74, phases)
    counts = Counter(s["target"] for s in steps if s["kind"] == "headless_script")
    expected = Counter({path: 3 if path == p74 else 1 for path in discovered})
    require(counts == expected and "res://" + NATIVE in counts, "WORLD_TARGET_COVERAGE_MISMATCH")
    require(len(steps) == len(discovered) + 5, "WORLD_STEP_COUNT_MISMATCH")
    names = [s["name"] for s in steps]
    indexes = [names.index(p) for p in phases]
    require(indexes == list(range(indexes[0], indexes[0] + 3)), "P74_PHASE_ORDER_CHANGED")
    return summary


def blocking_directional_findings(report: dict) -> list[dict]:
    """Keep advisory RED visible; only an explicit Boolean false is nonblocking."""
    findings = report["findings"]
    require(isinstance(findings, list) and all(isinstance(row, dict) for row in findings),
            "DIRECTIONAL_FINDINGS_INVALID")
    return [row for row in findings if row.get("level") == "RED"
            and row.get("global_blocking", True) is not False]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("kind", choices=("world", "p7", "control"))
    parser.add_argument("--engine", default=os.environ.get("GODOT_BIN", ""))
    args = parser.parse_args()
    root = Path.cwd().resolve()
    sys.path.insert(0, str(root / "docs/control/p7-eg1-world-core-repair-r1"))
    import validate_candidate as legacy
    initial = legacy.identity(root)
    run_id = os.environ.get("GITHUB_RUN_ID", "local")
    attempt = os.environ.get("GITHUB_RUN_ATTEMPT", "1")
    require(re.fullmatch(r"[A-Za-z0-9_-]+", run_id + attempt) is not None, "INVALID_RUN_ID")
    out = root / "artifacts/p7-post-acceptance" / args.kind / (run_id + "-" + attempt)
    require(not out.exists(), "EVIDENCE_DIRECTORY_ALREADY_EXISTS_USE_NEW_RUN_ID")
    out.mkdir(parents=True)
    write(out / "preflight.json", initial)
    passed = False
    def run(name: str, command: list[str], timeout: int = 180, expected: int = 0,
            cwd: Path | None = None) -> None:
        legacy.run(root, out, name, command, timeout, expected=expected, cwd=cwd)
    try:
        require(not initial["tracked_status"] and initial["head"] == os.environ.get("GITHUB_SHA", initial["head"]),
                "CHECKOUT_NOT_EXACT_CLEAN")
        source_guard(root)
        require(not any((root / "artifacts" / name).exists() for name in ("test-results", "runtime", "control")),
                "FRESH_ARTIFACT_DIRS_REQUIRED_USE_A_NEW_WORKTREE")
        if args.kind == "control":
            run("harness", [sys.executable, "-m", "unittest", "discover", "-s", "tests/harness", "-p", "test_*.py"], 1200)
            run("pc0", ["pwsh", "-NoProfile", "-File", "CONTROL_PROJECT.ps1", "-NoFetch"])
            for file in ("project-control-report.json", "directional-watch-report.json"):
                value = json.loads((root / "artifacts/control" / file).read_text())
                require(value["overall_health"] in ("GREEN", "YELLOW"), "PC0_RED:" + file)
                if file == "project-control-report.json":
                    require(value["main_head"] == git(root, "rev-parse", "origin/main")
                            and value["cross_branch_overlaps"] == [], "PC0_AUTHORITY_OR_OVERLAP_MISMATCH")
                else:
                    blocking = blocking_directional_findings(value)
                    write(out / "directional-classification.json", {
                        "overall_health": value["overall_health"],
                        "blocking_findings": blocking, "all_findings": value["findings"],
                        "policy": "Only explicit global_blocking=false is advisory; no source finding is removed.",
                    })
                    require(not blocking, "DIRECTIONAL_CRITICAL_HIT")
            for mode in ("Overview", "CheckConsistency", "Drive", "CloseMission"):
                run("controller-" + mode, ["pwsh", "-NoProfile", "-File", "CONTROL_DEVELOPMENT.ps1", "-" + mode])
            write(out / "controller-boundary.json", {
                "authority_head": git(root, "rev-parse", "origin/main"),
                "candidate_head": initial["head"], "new_candidate_accepted": False,
                "note": "Historical P7 acceptance is not acceptance of this post-acceptance repair. CloseRole of the obsolete generation-80 execution is not a gate for this new proposal.",
            })
        else:
            engine = str(Path(args.engine).resolve())
            require(Path(engine).is_file() and digest(Path(engine)) == ENGINE_SHA, "UNAPPROVED_ENGINE")
            run("version", [engine, "--version"], 20)
            require((out / "version.log").read_text().strip() == "4.7.1.stable.double.custom_build.a13da4feb", "ENGINE_VERSION_MISMATCH")
            run("import", [engine, "--headless", "--editor", "--path", str(root), "--import"], 240)
            if args.kind == "p7":
                legacy.p7_train(root, out, engine, initial["head"])
            else:
                baseline = Path(os.environ.get("RUNNER_TEMP", str(out))) / ("p7-post-baseline-" + run_id + "-" + attempt)
                require(not baseline.exists(), "BASELINE_EXISTS")
                git(root, "worktree", "add", "--detach", str(baseline), BASE)
                before = legacy.identity(baseline)
                run("baseline-import", [engine, "--headless", "--editor", "--path", str(baseline), "--import"], 240)
                run("baseline-aba", [engine, "--headless", "--path", str(baseline), "--script", str(root / NATIVE),
                                     "--", "--case=aba"], 45, expected=1)
                report = legacy.single_report(out / "baseline-aba.log", "matter_repository_lock_reclaim")
                failures = [repo + ":" + code for repo in ("mw10", "mw9") for code in (
                    "c-must-not-acquire-before-b-release", "b-marker-must-survive", "b-must-release-own-lock")]
                require(report["verdict"] == "FAIL" and report["assertions"] == 22
                        and report["failures"] == failures, "BASELINE_FAILURE_NOT_THE_ABA_COUNTEREXAMPLE")
                run("baseline-control-fixture", [sys.executable, "-m", "unittest",
                    "tests.harness.test_project_control_validation.ProjectControlValidationTests.test_valid_hold_routes_without_loading_obsolete_execution"],
                    120, expected=1, cwd=baseline)
                text = (out / "baseline-control-fixture.log").read_text()
                require("8 != 0" in text and "FAILED (failures=1)" in text, "BASELINE_CONTROL_FAILURE_NOT_EXPECTED")
                require(before == legacy.identity(baseline) and not before["tracked_status"], "BASELINE_MUTATED")
                write(out / "baseline-identity.json", before)
                previous = baseline.with_name(baseline.name + "-review-r1")
                require(not previous.exists(), "REVIEW_BASELINE_EXISTS")
                git(root, "worktree", "add", "--detach", str(previous), "912742d1bd7368138c5c057664dfe871b6cf8dbd")
                previous_before = legacy.identity(previous)
                run("review-baseline-import", [engine, "--headless", "--editor", "--path", str(previous), "--import"], 240)
                run("review-baseline-empty-writer", [engine, "--headless", "--path", str(previous), "--script", str(root / NATIVE),
                                                     "--", "--case=empty-writer"], 45, expected=1)
                report = legacy.single_report(out / "review-baseline-empty-writer.log", "matter_repository_lock_reclaim")
                failures = [repo + ":" + code for repo in ("mw10", "mw9") for code in (
                    "fresh-empty-writer-lock-reclaimed", "fresh-empty-writer-directory-removed")]
                require(report["verdict"] == "FAIL" and report["assertions"] == 14
                        and report["failures"] == failures, "REVIEW_BASELINE_FAILURE_NOT_EMPTY_WRITER_RECOVERY")
                require(previous_before == legacy.identity(previous) and not previous_before["tracked_status"], "REVIEW_BASELINE_MUTATED")
                write(out / "review-baseline-identity.json", previous_before)
                fixture_baseline = baseline.with_name(baseline.name + "-fixture-r2")
                require(not fixture_baseline.exists(), "FIXTURE_BASELINE_EXISTS")
                git(root, "worktree", "add", "--detach", str(fixture_baseline),
                    "dded2e488b161276d7ba679af078c288bd53cf55")
                fixture_before = legacy.identity(fixture_baseline)
                run("fixture-baseline-import", [engine, "--headless", "--editor", "--path", str(fixture_baseline), "--import"], 240)
                run("fixture-baseline-mw9", [engine, "--headless", "--path", str(fixture_baseline),
                    "--script", "res://" + MW9_RECOVERY], 300, expected=1)
                text = (out / "fixture-baseline-mw9.log").read_text()
                expected_errors = ["Fresh ownerless lock was reclaimed without grace",
                                   "Fresh ownerless lock disappeared during grace"]
                require(re.findall(r"^ERROR: (.*)$", text, re.MULTILINE) == expected_errors
                        and text.count("MW9 durable handoff recovery: FAIL (203 assertions, 2 failures)") == 1,
                        "MW9_FIXTURE_BASELINE_NOT_EXPECTED_FAILURE")
                require(fixture_before == legacy.identity(fixture_baseline)
                        and not fixture_before["tracked_status"], "FIXTURE_BASELINE_MUTATED")
                write(out / "fixture-baseline-identity.json", fixture_before)
                run("native-locks", [engine, "--headless", "--path", str(root), "--script", "res://" + NATIVE], 90)
                report = legacy.single_report(out / "native-locks.log", "matter_repository_lock_reclaim")
                require(report["verdict"] == "PASS" and report["assertions"] == 82 and not report["failures"], "NATIVE_LOCK_SUITE_INCOMPLETE")
                for file in sorted((root / "tests/matter/handoff").glob("test_mw9*.gd")):
                    run(file.stem, [engine, "--headless", "--path", str(root), "--script", "res://" + file.relative_to(root).as_posix()], 300)
                    if file.relative_to(root).as_posix() == MW9_RECOVERY:
                        text = (out / (file.stem + ".log")).read_text()
                        require(text.count("MW9 durable handoff recovery: PASS (208 assertions)") == 1
                                and not re.search(r"^ERROR:|: FAIL", text, re.MULTILINE),
                                "MW9_RECONCILED_FIXTURE_NOT_PROVEN")
                run("mw10-processes", [engine, "--headless", "--path", str(root), "--script",
                    "res://tests/matter/transactions/test_mw10_cross_region_processes.gd"], 300)
                for family, count in (("eg1", 5), ("eg4", 3)):
                    for index in range(1, count + 1):
                        run(f"{family}-{index}", [engine, "--headless", "--path", str(root), "--script",
                            f"res://tests/network/test_{family}_gateway_processes.gd"], 300)
                run("full-world-core", ["pwsh", "-NoProfile", "-Command",
                    '$PSDefaultParameterValues = @{"Get-Item:Force" = $true}; & ./RUN_WORLD_REGRESSION_TESTS.ps1; exit $LASTEXITCODE'], 7200)
                summary = world_summary(root)
                write(out / "world-coverage.json", {"passed": True, "distinct_scripts": summary["declared_test_count"],
                    "stages": len(summary["steps"]), "summary_sha256": digest(root / "artifacts/test-results/world-regression-summary.json")})
        write(out / "historical-verdicts-audit.json", {"subject_is_historical_not_current_review": True,
            "source_commit": "0f9454c482803af7ddeec1ea0c944ad5e3c5d819",
            "files": [{"path": path, "blob": expected, "sha256": digest(root / path)} for path, expected in HISTORICAL.items()]})
        passed = True
    except Exception as error:
        write(out / "failure.json", {"type": type(error).__name__, "message": str(error)})
        print("VALIDATION_FAILED:", error, file=sys.stderr, flush=True)
    finally:
        final = legacy.identity(root)
        passed = passed and final == initial and not final["tracked_status"]
        write(out / "postflight.json", final)
        for directory in ("test-results", "runtime", "control"):
            source = root / "artifacts" / directory
            if source.exists():
                shutil.copytree(source, out / "raw" / directory)
        write(out / "result.json", {"passed": passed, "kind": args.kind, "subject": initial,
            "checkout_unchanged": final == initial, "canonical_acceptance": False})
        write(out / "manifest.json", {"classification": "IMPLEMENTER_MACHINE_EVIDENCE_NOT_INDEPENDENT_ACCEPTANCE",
            "subject": initial, "run_id": run_id, "run_attempt": attempt,
            "job": os.environ.get("GITHUB_JOB", args.kind), "runner": os.environ.get("RUNNER_NAME", "LOCAL"),
            "godot_sha256": ENGINE_SHA if args.kind != "control" else None,
            "files": [{"path": p.relative_to(out).as_posix(), "bytes": p.stat().st_size, "sha256": digest(p)}
                      for p in sorted(out.rglob("*")) if p.is_file()]})
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
