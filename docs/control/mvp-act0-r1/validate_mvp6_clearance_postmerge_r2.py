#!/usr/bin/env python3
"""Exact control-only validation. Simulated origin/main exists ONLY in a local fixture."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[3]
BASE = "a6d5eb6b287130a638ba6cf397c34e29169948c1"
CLEARANCE = "V0-MVP6-NX-POSTMERGE-CRITICAL-WATCH-CLEARANCE-005"
M4 = "scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd"
JOURNAL = "scripts/network/prediction/predicted_item_interaction_journal.gd"
PRODUCER = "feature/v0-mvp-playable-seamless-planet-r1"
CONSUMER = "feature/h0-2-nx-c1-owner-authority-r3"
OUT = Path(os.environ["MVP6_CLEARANCE_OUTPUT"]).resolve()
PRIOR = Path(os.environ["MVP6_POSTMERGE_ARTIFACT"]).resolve()
ALLOWED = {
    "config/control/directional-watch-clearances.v1.json",
    "scripts/control/directional_watch_clearance.py",
    "tests/harness/test_project_control_directional_clearance.py",
    "tests/harness/test_mvp6_postmerge_directional_clearance.py",
    "docs/control/mvp-act0-r1/MVP6_NX_CLEARANCE_POSTMERGE_R2_RU.md",
    "docs/control/mvp-act0-r1/MVP6_NX_CLEARANCE_POSTMERGE_R2_EVIDENCE.json",
    "docs/control/mvp-act0-r1/validate_mvp6_clearance_postmerge_r2.py",
}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(*args: str, cwd: Path = ROOT) -> str:
    return subprocess.check_output(["git", *args], cwd=cwd, text=True, stderr=subprocess.PIPE).strip()


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write(path: Path, value) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def capture(label: str, argv: list[str], cwd: Path, commands: list, timeout: int = 180) -> int:
    log = OUT / (label + ".log")
    begin = time.monotonic()
    timed_out = False
    with log.open("wb") as stream:
        try:
            code = subprocess.run(argv, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout, check=False).returncode
        except subprocess.TimeoutExpired:
            code, timed_out = 124, True
    row = {"label": label, "argv": argv, "cwd": str(cwd), "exit_code": code, "timed_out": timed_out, "duration_seconds": round(time.monotonic() - begin, 3), "log_sha256": digest(log)}
    commands.append(row)
    write(OUT / "commands.json", commands)
    print(json.dumps({k: row[k] for k in ("label", "exit_code", "duration_seconds")}), flush=True)
    return code


def verify_prior() -> dict:
    manifest = PRIOR / "manifest.json"
    assert digest(manifest) == "f09da9fcf04d9b0dc8e03f18867346f60c773cba41766d101d3d5318950f1a7f", "PRIOR_MANIFEST_DIGEST"
    m = read(manifest)
    assert m["canonical_main"] == BASE
    assert m["subject_head"] == "2497ecb6b89b6c1e20afbff9c823c7564b78f956"
    assert m["subject_tree"] == "59186fa72db6c280e0d26470674884f280fe474c"
    assert str(m["run_id"]) == "35162668295" and str(m["run_attempt"]) == "1"
    expected = {"manifest.json"}
    for f in m["files"]:
        path = (PRIOR / f["path"]).resolve()
        assert path.is_relative_to(PRIOR) and path.is_file(), "UNSAFE_OR_MISSING_PRIOR_MEMBER"
        assert digest(path) == f["sha256"], "PRIOR_MEMBER_DIGEST:" + f["path"]
        expected.add(path.relative_to(PRIOR).as_posix())
    assert expected == {p.relative_to(PRIOR).as_posix() for p in PRIOR.rglob("*") if p.is_file()}
    assert len(m["files"]) == 28
    nx = read(PRIOR / "nx/summary.json")
    assert nx["canonical_main"] == BASE and nx["journal_repair_input"] is None
    assert nx["dependency_revalidated"] is True and nx["candidate_regressed_consumer"] is False
    assert nx["consumer_head"] == "1a56fe0e845c941f14ce7b9296ee939e9d0ca8bc"
    assert nx["producer_critical_blob"] == "44841fb3719b1cf36fd5afdfc0f8a0e4d0eacb30"
    for key in ("baseline_tests", "candidate_tests"):
        rows = nx[key]
        assert len(rows) == 6 and all(r["exit_code"] == 0 and r["log_valid"] for r in rows)
        assert [r["assertions"] for r in rows[1:]] == [44, 31, 37, 25, 940]
    assert nx["unmodified_nx_runtime_pass_claimed"] is False
    return {"run_id": 35162668295, "artifact_id": 10474045529, "manifest_sha256": digest(manifest), "members_verified": 28, "baseline_assertions": 1077, "candidate_assertions": 1077, "journal_repair_override": False, "parser_normalization_disclosed": True}


def audit(cwd: Path, label: str, commands: list) -> dict:
    result = {}
    for name, script, filename in (
        ("standard", "project_control.py", "project-control-report.json"),
        ("directional", "project_control_directional_watch.py", "directional-watch-report.json"),
    ):
        argv = [sys.executable, "scripts/control/" + script, "--no-fail-on-red"]
        if name == "standard":
            argv.append("--no-fetch")
        assert capture(label + "-" + name, argv, cwd, commands) == 0, label + "_AUDITOR_EXECUTION_FAILED"
        report = read(cwd / "artifacts/control" / filename)
        write(OUT / (label + "-" + filename), report)
        result[name] = report
    return result


def run_tests(cwd: Path, label: str, pattern: str, commands: list, timeout: int) -> dict:
    result_path = OUT / (label + "-result.json")
    code = (
        "import json,pathlib,unittest;"
        f"suite=unittest.defaultTestLoader.discover('tests/harness',pattern={pattern!r});"
        "r=unittest.TextTestRunner(verbosity=2).run(suite);"
        "d={'tests':r.testsRun,'failures':[x[0].id() for x in r.failures],"
        "'errors':[x[0].id() for x in r.errors],'skipped':[x[0].id() for x in r.skipped],"
        "'passed':r.wasSuccessful() and not r.skipped};"
        f"pathlib.Path({str(result_path)!r}).write_text(json.dumps(d,indent=2)+'\\n');"
        "raise SystemExit(0 if d['passed'] else 1)"
    )
    exit_code = capture(label, [sys.executable, "-c", code], cwd, commands, timeout)
    result = read(result_path) if result_path.exists() else {"passed": False, "tests": 0, "missing_result": True}
    result["exit_code"] = exit_code
    return result


def main() -> int:
    assert not OUT.exists(), "PRESERVE_EXISTING_OUTPUT"
    OUT.mkdir(parents=True)
    commands = []
    summary = {"schema": "distributed_world_simulator.mvp6_clearance_postmerge_r2_validation.v1", "passed": False, "canonical_clearance_accepted": False, "main_merge": False, "independent_verdict": False, "mvp6_accepted": False}
    original_refs = git("for-each-ref", "--format=%(refname) %(objectname)", "refs/remotes/origin")
    try:
        head = git("rev-parse", "HEAD")
        tree = git("rev-parse", "HEAD^{tree}")
        summary.update(subject_head=head, subject_tree=tree, canonical_main=git("rev-parse", "origin/main"), driver_sha256=digest(Path(__file__)))
        assert head == os.environ["EXPECTED_HEAD"] and tree == os.environ["EXPECTED_TREE"], "EXACT_CANDIDATE_REQUIRED"
        assert summary["canonical_main"] == BASE, "MAIN_DRIFT"
        assert not git("status", "--porcelain", "--untracked-files=no"), "TRACKED_DIRTY"
        changes = git("diff", "--name-only", BASE, head).splitlines()
        assert set(changes) == ALLOWED, "CONTROL_WRITE_FENCE:" + repr(changes)
        git("diff", "--check", BASE, head)
        git("merge-base", "--is-ancestor", BASE, head)
        for name in ("project_control.py", "project_control_directional_watch.py"):
            p = "scripts/control/" + name
            assert git("rev-parse", head + ":" + p) == git("rev-parse", BASE + ":" + p), "AUDITOR_ENTRYPOINT_CHANGED"
        summary["changed_paths"] = changes
        summary["runtime_unchanged"] = True
        summary["prior_evidence"] = verify_prior()
        record = read(ROOT / "config/control/directional-watch-clearances.v1.json")["clearances"][-1]
        assert record["clearance_id"] == CLEARANCE
        assert git("rev-parse", "origin/" + CONSUMER) == record["consumer_head_sha"]
        git("merge-base", "--is-ancestor", record["reviewed_producer_head"], "origin/" + PRODUCER)
        git("merge-base", "--is-ancestor", "2497ecb6b89b6c1e20afbff9c823c7564b78f956", "origin/" + PRODUCER)
        for path, wanted in record["watched_file_blobs"].items():
            for ref in (record["reviewed_producer_head"], "origin/" + PRODUCER, "2497ecb6b89b6c1e20afbff9c823c7564b78f956"):
                assert git("rev-parse", ref + ":" + path) == wanted, "PRODUCER_BLOB_DRIFT"
        raw = audit(ROOT, "raw-canonical", commands)
        raw_hit = [r for r in raw["directional"]["findings"] if r.get("producer") == "V0" and r.get("consumer") == "NX" and r.get("kind") == "CRITICAL_WATCH_HIT"]
        assert len(raw_hit) == 1 and raw_hit[0]["level"] == "RED" and raw_hit[0]["files"] == [M4], "RAW_CANONICAL_NEGATIVE_CONTROL"
        summary["raw_canonical"] = {"standard": raw["standard"]["overall_health"], "directional": raw["directional"]["overall_health"], "candidate_self_clear_prevented": True}
        summary["historical_tests"] = run_tests(ROOT, "historical-clearance", "test_project_control_directional_clearance.py", commands, 180)
        summary["focused_tests"] = run_tests(ROOT, "postmerge-clearance", "test_mvp6_postmerge_directional_clearance.py", commands, 180)
        assert summary["historical_tests"]["passed"] and summary["focused_tests"]["passed"], "FOCUSED_FAILURE"

        # Local-only remote fixture: copy object access and refs, never mutate
        # the genuine origin/main or any GitHub branch to simulate acceptance.
        with tempfile.TemporaryDirectory(prefix="mvp6-clearance-r2-") as tmp:
            temp = Path(tmp); remote = temp / "remote.git"; projection = temp / "candidate-main"
            git("init", "--bare", str(remote))
            common = Path(git("rev-parse", "--git-common-dir"))
            if not common.is_absolute():
                common = ROOT / common
            (remote / "objects/info/alternates").write_text(str((common / "objects").resolve()) + "\n")
            git("config", "gc.auto", "0", cwd=remote)
            for line in original_refs.splitlines():
                ref, sha = line.split()
                name = ref.removeprefix("refs/remotes/origin/")
                if name == "HEAD":
                    continue
                git("update-ref", "refs/heads/" + name, head if name == "main" else sha, cwd=remote)
            git("symbolic-ref", "HEAD", "refs/heads/main", cwd=remote)
            git("clone", "--shared", str(remote), str(projection))
            git("config", "gc.auto", "0", cwd=projection)
            assert git("rev-parse", "HEAD", cwd=projection) == head
            assert git("rev-parse", "origin/main", cwd=projection) == head
            projected = audit(projection, "simulated-candidate-main", commands)
            hit = [r for r in projected["directional"]["findings"] if r.get("producer") == "V0" and r.get("consumer") == "NX" and r.get("kind") == "CRITICAL_WATCH_HIT"]
            assert len(hit) == 1 and hit[0]["level"] != "RED", "CANDIDATE_CLEARANCE_NOT_APPLIED"
            summary["simulated_candidate_main"] = {"kind": "DISPOSABLE_LOCAL_REF_PROJECTION_NOT_CANONICAL", "head": head, "standard": projected["standard"]["overall_health"], "directional": projected["directional"]["overall_health"], "v0_nx_hit": hit[0]}
            assert projected["standard"]["overall_health"] != "RED" and projected["directional"]["overall_health"] != "RED", "CANDIDATE_PC0_RED"
            summary["full_harness"] = run_tests(projection, "simulated-full-harness", "test_*.py", commands, 1200)
            assert summary["full_harness"]["passed"], "FULL_HARNESS_FAILURE"
        assert git("for-each-ref", "--format=%(refname) %(objectname)", "refs/remotes/origin") == original_refs, "GENUINE_REFS_CHANGED"
        assert git("rev-parse", "HEAD") == head and git("rev-parse", "HEAD^{tree}") == tree
        assert not git("status", "--porcelain", "--untracked-files=no"), "SOURCE_CHANGED"
        summary["source_clean_after"] = True
        summary["genuine_refs_unchanged"] = True
        summary["passed"] = True
    except Exception as exc:
        summary["failure"] = type(exc).__name__ + ":" + str(exc)
        print(summary["failure"], flush=True)
    finally:
        write(OUT / "summary.json", summary)
        write(OUT / "observed-refs.json", original_refs.splitlines())
        files = [{"path": p.relative_to(OUT).as_posix(), "bytes": p.stat().st_size, "sha256": digest(p)} for p in sorted(OUT.rglob("*")) if p.is_file() and p.name != "manifest.json"]
        manifest = {"schema": "distributed_world_simulator.mvp6_clearance_r2_manifest.v1", "subject_head": summary.get("subject_head"), "subject_tree": summary.get("subject_tree"), "canonical_main": BASE, "run_id": os.environ.get("GITHUB_RUN_ID", "local"), "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT", "1"), "passed": summary["passed"], "main_merge": False, "independent_verdict": False, "files": files}
        write(OUT / "manifest.json", manifest)
        print(json.dumps({"passed": summary["passed"], "head": summary.get("subject_head"), "manifest_sha256": digest(OUT / "manifest.json")}), flush=True)
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
