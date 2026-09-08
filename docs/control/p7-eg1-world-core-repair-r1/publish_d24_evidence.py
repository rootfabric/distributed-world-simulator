#!/usr/bin/env python3
"""Append original d24 CI evidence; never run downloaded content or issue a verdict."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile

from audit_ci_packet import HEAD, TREE, RUN, audit_command, audit_manifest, audit_world, load_zip, parse, require
from validate_candidate import P7_LEAVES, check_p7_leaf

REPO = "rootfabric/distributed-world-simulator"
BRANCH = "repair/v0-p7-eg1-world-core-r1"
DOCS = "docs/control/p7-eg1-world-core-repair-r1/"
OUTPUT = DOCS + "evidence/d24-r1/"
EPOCH = "E2026-09-06-V0-P7-CANONICAL-CLOSURE-R1"
WORK_ORDER = "V0-P7-EG4-RECEIPT-COMPLETION-R1"
PC0_RUN = 34121808221


def encoded(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], text=True, timeout=60).strip()


def api(path: str, *, binary: bool = False):
    require(path.startswith(f"repos/{REPO}/actions/"), "API_SCOPE_INVALID")
    raw = subprocess.check_output(["gh", "api", path], timeout=180)
    return raw if binary else parse(raw)


def choose_artifact(artifacts: list[dict], name: str, run_id: int) -> dict:
    found = [a for a in artifacts if a.get("name") == name and not a.get("expired")]
    require(len(found) == 1, f"ARTIFACT_NOT_UNIQUE:{name}")
    item = found[0]
    require(item["workflow_run"]["id"] == run_id and item["workflow_run"]["head_sha"] == HEAD,
            "ARTIFACT_WRONG_SUBJECT")
    digest = item.get("digest", "")
    require(isinstance(digest, str) and digest.startswith("sha256:") and len(digest) == 71,
            "ARTIFACT_DIGEST_MISSING")
    return item


def get_artifact(item: dict) -> dict[str, bytes]:
    raw = api(f"repos/{REPO}/actions/artifacts/{item['id']}/zip", binary=True)
    with tempfile.NamedTemporaryFile(suffix=".zip") as stream:
        stream.write(raw)
        stream.flush()
        return load_zip(Path(stream.name), item["digest"].removeprefix("sha256:"))


def check_jobs(jobs: list[dict]) -> None:
    for name, job_id in (("exact-validation (world)", 101741388863),
                         ("exact-validation (p7)", 101741388945)):
        found = [j for j in jobs if j.get("name") == name and j.get("id") == job_id]
        require(len(found) == 1 and found[0]["status"] == "completed"
                and found[0]["conclusion"] == "success", f"JOB_NOT_SUCCESS:{name}")


def audit_p7(files: dict[str, bytes]) -> dict:
    source = audit_manifest(files, "p7")
    audit_command(files, "p7-train")
    summary = parse(files["p7-stage-summary.json"])
    require(summary["passed"] is True and summary["assertions"] == 2032
            and len(summary["stages"]) == 29, "P7_INCOMPLETE")
    expected_logs = set()
    for group, leaves in P7_LEAVES.items():
        for name, count in leaves.items():
            path = f"runtime/{group}/{name}.log"
            expected_logs.add(path)
            check_p7_leaf(files[path].decode("utf-8"), name, count)
    require({s["log"] for s in summary["stages"]} == expected_logs
            and all(s["failures"] == 0 and hashlib.sha256(files[s["log"]]).hexdigest() == s["sha256"]
                    for s in summary["stages"]), "P7_STAGE_DIGEST_OR_COVERAGE_INVALID")
    return source


def selected_world(name: str) -> bool:
    # Root files contain every command, exit, entire stdout, probes and source manifest.
    # Do not export incidental user-profile/cache files from hundreds of tests.
    if "/" not in name or name == "test-results/world-regression-summary.json":
        return True
    parts = name.split("/")
    return (len(parts) == 3 and parts[0] == "test-results"
            and parts[1].startswith(("eg1-gateway-", "eg4-gateway-"))
            and parts[-1].endswith((".json", ".log")))


def machine_manifest(group_files: dict[str, bytes], source_files: dict[str, dict[str, bytes]],
                     native_manifests: dict[str, dict]) -> dict:
    artifacts = [{"path": OUTPUT + name, "sha256": hashlib.sha256(raw).hexdigest(),
                  "run_id": RUN, "subject_head_sha": HEAD}
                 for name, raw in sorted(group_files.items()) if name.startswith(("world/", "p7/"))]
    commands = []
    for group in ("world", "p7"):
        for name, raw in sorted(source_files[group].items()):
            if "/" in name or not name.endswith(".command.json"):
                continue
            step = name.removesuffix(".command.json")
            expected = parse(raw)["expected_exit"]
            result = audit_command(source_files[group], step, expected)
            commands.append({"command": shlex.join(result["command"]),
                             "exit_code": result["exit_code"], "expected_exit_code": expected,
                             "log_path": OUTPUT + f"{group}/{step}.log"})
    require(bool(commands), "COMMANDS_MISSING")
    return {
        "schema": "distributed_world_simulator.harness_machine_evidence_manifest.v1",
        "work_order_id": WORK_ORDER, "project_epoch": EPOCH,
        "subject_head_sha": HEAD, "subject_tree_sha": TREE,
        "runner_id": "GitHubActions:34121804645:world-101741388863+p7-101741388945",
        "run_id": RUN, "tracked_checkout_clean_before": True, "tracked_checkout_clean_after": True,
        "artifacts": artifacts, "commands": commands,
        "native_job_provenance": {g: {k: native_manifests[g][k] for k in
            ("job", "runner", "run_id", "run_attempt", "workflow_sha", "godot_sha256")}
            for g in ("world", "p7")},
        "classification": "MACHINE_EVIDENCE_ONLY_NOT_INDEPENDENT_VERDICT",
    }


def prepare_packet(source: dict[str, dict[str, bytes]], metadata: dict[str, dict],
                   jobs: list[dict]) -> dict[str, bytes]:
    check_jobs(jobs)
    world_audit = audit_world(source["world"])
    native = {"world": parse(source["world"]["manifest.json"]), "p7": audit_p7(source["p7"])}
    # The official PC0 workflow must supply two explicit non-RED JSON reports.
    pc0_reports = [parse(v) for k, v in source["pc0"].items() if k.endswith(".json")]
    statuses = [v.get("overall_health") for v in pc0_reports if "overall_health" in v]
    require(len(statuses) == 2 and all(v in ("GREEN", "YELLOW") for v in statuses), "PC0_NOT_NON_RED")
    files = {}
    for group, entries in source.items():
        for name, raw in entries.items():
            if group == "world" and not selected_world(name):
                continue
            raw.decode("utf-8")  # Never publish opaque executables or binary user caches.
            files[f"{group}/{name}"] = raw
    manifest = machine_manifest(files, source, native)
    manifest_path = OUTPUT + "machine-evidence-manifest.v1.json"
    manifest_bytes = encoded(manifest)
    files["machine-evidence-manifest.v1.json"] = manifest_bytes
    files[".gitattributes"] = b"* -text\n"
    files["source-artifacts.v1.json"] = encoded({"subject_head_sha": HEAD, "subject_tree_sha": TREE,
        "runtime_jobs": jobs, "artifacts": metadata,
        "original_archive_digests_verified": True, "all_world_and_p7_source_member_digests_verified": True,
        "world_user_profiles_not_reused_or_exported": True})
    files["readiness.v1.json"] = encoded({
        "classification": "IMPLEMENTER_MACHINE_PACKET_NOT_ACCEPTANCE", "subject_head_sha": HEAD,
        "subject_tree_sha": TREE, "world_audit": world_audit, "p7_stages": 29, "p7_assertions": 2032,
        "manifest_path": manifest_path, "manifest_sha256": hashlib.sha256(manifest_bytes).hexdigest(),
        "canonical_acceptance": False, "independent_verifier_verdict": None,
        "current_epoch_role_reconciliation_complete": False,
        "overall_workflow_green": False, "control_observation_failure_preserved": True,
        "formal_current_epoch_provenance_validation": "REQUIRES_CANONICAL_FRESH_EXECUTION_CONTEXT",
        "required_next": ["Actual independent five-section role reports on exact d24",
                          "Reconcile fresh role context without rewriting historical generation-80 epoch",
                          "Human integration and canonical checkpoint acceptance decision"],
    })
    return files


def main() -> None:
    root = Path.cwd().resolve()
    require(os.environ.get("GITHUB_REPOSITORY") == REPO and os.environ.get("GITHUB_ACTOR") == "rootfabric"
            and os.environ.get("GITHUB_REF") == "refs/heads/" + BRANCH, "PUBLISHER_AUTHORITY_INVALID")
    require(git("rev-parse", "HEAD") == os.environ["GITHUB_SHA"]
            and not git("status", "--porcelain", "--untracked-files=no"), "CARRIER_NOT_EXACT_CLEAN")
    require(git("rev-parse", f"{HEAD}^{{tree}}") == TREE, "FROZEN_TREE_MISMATCH")
    git("merge-base", "--is-ancestor", HEAD, "HEAD")
    changed = git("diff", "--name-only", HEAD, "HEAD").splitlines()
    require(all(p.startswith(DOCS) or p == ".github/workflows/p7-eg1-world-core-repair.yml" for p in changed),
            "FROZEN_RUNTIME_CHANGED")
    output = root / OUTPUT
    require(not output.exists(), "APPEND_ONLY_EVIDENCE_ALREADY_EXISTS")
    runtime_artifacts = api(f"repos/{REPO}/actions/runs/{RUN}/artifacts?per_page=100")["artifacts"]
    pc0_artifacts = api(f"repos/{REPO}/actions/runs/{PC0_RUN}/artifacts?per_page=100")["artifacts"]
    jobs = api(f"repos/{REPO}/actions/runs/{RUN}/jobs?filter=latest&per_page=100")["jobs"]
    check_jobs(jobs)
    metadata = {g: choose_artifact(runtime_artifacts, f"p7-repair-{g}-{HEAD}-{RUN}", int(RUN))
                for g in ("world", "p7", "control")}
    metadata["pc0"] = choose_artifact(pc0_artifacts, "project-control-report", PC0_RUN)
    require(metadata["p7"]["digest"] == "sha256:79b76a6781b57801ff5d7d0f2c647e3a0cfb6cf22014e252f06add608592e0ff"
            and metadata["pc0"]["digest"] == "sha256:a2551584b5373d38b46d7c173bb23633fcb082ef44a193daf76021f7e2641f3a"
            and metadata["control"]["digest"] == "sha256:db1ec404da83ba4df9375d8b81b01a819d22b4083f329e2b412af6676c865d45",
            "PINNED_ARTIFACT_DIGEST_DRIFT")
    source = {g: get_artifact(item) for g, item in metadata.items()}
    files = prepare_packet(source, metadata, jobs)
    # All source checks precede the first repository write. 'xb' forbids replacement.
    for name, raw in sorted(files.items()):
        destination = output / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        with destination.open("xb") as stream:
            stream.write(raw)
    print(json.dumps({"published_worktree_files": len(files), "subject": HEAD,
                      "independent_verdict": None, "canonical_acceptance": False}))


if __name__ == "__main__":
    main()
