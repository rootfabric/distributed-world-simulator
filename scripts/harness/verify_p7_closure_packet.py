"""Audit frozen P7 machine evidence. This command cannot accept or dispatch work."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import tarfile
from typing import Any

PACKAGE = Path("docs/control/p7-canonical-closure-r1")
HEAD = "c14c37cce4930a8b5132d5d5fdfab3a5dfa82f5f"
TREE = "04679a6e67fc86ec156d4341140fd5b0225d6085"
GODOT = "4.7.1.stable.double.custom_build.a13da4feb"
FATAL = ("SCRIPT ERROR:", "Parse Error:", "Compile Error:",
         "Failed to instantiate an autoload", "Failed to load script")
ARCHIVES = {
    "runtime-evidence.tar.xz": "7fae5c5dc3e8e778262b01d91dfed9c9edb2fd1f105e8b590cb8348b928c4ea6",
    "pc0-evidence.tar.xz": "be611313835b08e73ec73b9a688bc5217d3978b8b9e6204157df9ed6c5675e96",
}


def require(condition: bool, code: str) -> None:
    if not condition:
        raise ValueError(code)


def read_json(raw: str | bytes) -> Any:
    def pairs(items: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in items:
            require(key not in result, f"DUPLICATE_JSON_KEY:{key}")
            result[key] = value
        return result
    return json.loads(raw, object_pairs_hook=pairs)


def read_archive(path: Path, digest: str) -> dict[str, bytes]:
    raw = path.read_bytes()
    require(hashlib.sha256(raw).hexdigest() == digest, "ARCHIVE_DIGEST_MISMATCH")
    result: dict[str, bytes] = {}
    size = 0
    # Never extract archive paths or execute artifact contents.
    with tarfile.open(fileobj=io.BytesIO(raw), mode="r:xz") as archive:
        for member in archive:
            name = PurePosixPath(member.name)
            require(member.isfile() and not name.is_absolute() and ".." not in name.parts,
                    "ARCHIVE_MEMBER_INVALID")
            require(member.name not in result, "ARCHIVE_DUPLICATE_MEMBER")
            size += member.size
            require(size <= 4_000_000 and len(result) < 100, "ARCHIVE_LIMIT_EXCEEDED")
            stream = archive.extractfile(member)
            require(stream is not None, "ARCHIVE_MEMBER_UNREADABLE")
            result[member.name] = stream.read()
    return result


def audit(manifest: dict[str, Any], runtime: dict[str, bytes], pc0: dict[str, bytes]) -> dict[str, Any]:
    require(manifest["subject_head_sha"] == HEAD and manifest["subject_tree_sha"] == TREE,
            "SUBJECT_MISMATCH")
    console = runtime["runtime/v0-p7-canonical-acceptance/full-gate-console.log"].decode()
    for marker in ("V0-P7.7 GRAPHICAL DIGGING GATE GREEN", "EXACT_HEAD=" + HEAD,
                   "EXACT_TREE=" + TREE, "GODOT=" + GODOT):
        require(marker in console, "GATE_MARKER_MISSING:" + marker)
    for name, content in runtime.items():
        if name.endswith(".log"):
            text = content.decode("utf-8")
            require(not any(pattern in text for pattern in FATAL), "FATAL_LOG:" + name)
            require(not re.search(r": FAIL(?:\s|\()|[1-9]\d* failures", text), "FAILED_LOG:" + name)

    excluded = {"import.log", "p7-5-subgate.log", "full-gate-console.log"}
    leaves = {n for n in runtime if n.endswith(".log") and PurePosixPath(n).name not in excluded}
    stages = manifest["stages"]
    names = [stage["log"] for stage in stages]
    require(len(names) == len(set(names)) == 29 and set(names) == leaves, "STAGE_COVERAGE_MISMATCH")
    totals = {"direct": 0, "nested_p7_5": 0}
    for stage in stages:
        text = runtime[stage["log"]].decode()
        counts = re.findall(r"\b(\d+) assertions\b", text)
        require(len(counts) == 1 and int(counts[0]) == stage["assertions"], "ASSERTION_COUNT_MISMATCH")
        require("PASS" in text or "0 failures" in text, "STAGE_SUCCESS_MARKER_MISSING")
        require(stage["group"] in totals, "STAGE_GROUP_INVALID")
        totals[stage["group"]] += int(counts[0])
    require(totals == {"direct": 887, "nested_p7_5": 1145}, "FORMAL_TOTAL_MISMATCH")

    # Original workflow inadvertently hashed its own checksum file. Preserve it;
    # exclude only that self-entry, never a stage log. Archive digest binds all bytes.
    sum_name = "runtime/v0-p7-canonical-acceptance/SHA256SUMS"
    checked: set[str] = set()
    for line in runtime[sum_name].decode().splitlines():
        digest, original = line.split("  ", 1)
        require(original.startswith("artifacts/runtime/"), "ORIGINAL_MANIFEST_PATH_INVALID")
        name = "runtime/" + original.removeprefix("artifacts/runtime/")
        require(name not in checked, "ORIGINAL_MANIFEST_DUPLICATE")
        checked.add(name)
        if name != sum_name:
            require(name in runtime and hashlib.sha256(runtime[name]).hexdigest() == digest,
                    "ORIGINAL_MEMBER_DIGEST_MISMATCH:" + name)
    require(checked == set(runtime), "ORIGINAL_MANIFEST_COVERAGE_MISMATCH")

    standard = read_json(pc0["project-control-report.json"])
    directional = read_json(pc0["directional-watch-report.json"])
    require(standard["main_head"] == HEAD and standard["registry_generation"] == 81,
            "PC0_SUBJECT_MISMATCH")
    require(standard["overall_health"] in ("GREEN", "YELLOW") and not standard["cross_branch_overlaps"],
            "PC0_BLOCKING")
    require(all(p["health"] != "RED" or p.get("blocks_global_progress") is False
                for p in standard["programs"]), "PC0_PROGRAM_BLOCKING")
    require(directional["registry_generation"] == 81 and directional["overall_health"] in ("GREEN", "YELLOW"),
            "DIRECTIONAL_PC0_BLOCKING")
    require(not any(f["level"] == "RED" and f.get("global_blocking", True)
                    for f in directional["findings"]), "DIRECTIONAL_CRITICAL_HIT")
    return {
        "subject_head_sha": HEAD, "subject_tree_sha": TREE,
        "result": "FROZEN_MACHINE_EVIDENCE_VALID", "stages": 29,
        "assertions": sum(totals.values()), "failures": 0, "fatal_matches": 0,
        "stage_totals": totals, "runtime_files_digest_checked": len(runtime),
        "standard_pc0": standard["overall_health"], "directional_pc0": directional["overall_health"],
        "directional_findings": directional["findings"],
        "checksum_self_entry": "ORIGINAL_PRESERVED_NOT_USED_AS_AUTHORITY",
        "independent_verdict": None, "canonical_acceptance": False, "runtime_authorized": False,
        "unresolved_gates": manifest["unresolved_gates"],
    }


WORKFLOW_HEAD = "eb94c9f1a902e7a0acfd263f9d4df87c4986042e"
EXECUTED_INPUTS = {
    "original-runtime-workflow.yml": (
        WORKFLOW_HEAD, ".github/workflows/v0-p7-canonical-acceptance-runtime.yml",
        "d8fe918d14c32626ff0a26d462691145f0a36cf9",
        "d935be6c32454c1177374afc7d78b8284b33b33fd355eeed2056e81456375d13",
    ),
    "RUN_V0_P7_7_GRAPHICAL_DIGGING_GATE.sh": (
        HEAD, "RUN_V0_P7_7_GRAPHICAL_DIGGING_GATE.sh",
        "5afb111675ed9bd7e36deb1a278db49def03fc7f",
        "07ec70fffe52390dd296956836d9754145446f1fb4e57b92061c2a19b3ae2f29",
    ),
    "RUN_V0_P7_5_TWO_CLIENT_CONVERGENCE_GATE.sh": (
        HEAD, "RUN_V0_P7_5_TWO_CLIENT_CONVERGENCE_GATE.sh",
        "1cba86abfef21a73a72c57d70a485a10eb73082c",
        "5f7601bbf1829f8176d9e7a7557683d9436b4c81a6d19ac06e78dced20cea0ce",
    ),
}


def audit_execution_provenance(package: Path) -> list[dict[str, Any]]:
    """Verify executed commands even when the workflow branch was not fetched.

    Snapshots retain exact original blobs; SHA256 additionally pins all bytes.
    They are read only, never substituted for or executed as the tested product.
    """
    folder = package / "provenance"
    manifest = read_json((folder / "manifest.v1.json").read_bytes())
    expected = {
        "schema": "distributed_world_simulator.p7_execution_provenance.v1",
        "run_id": 34034752294, "job_id": 101490676888,
        "runtime_head": HEAD, "runtime_tree": TREE, "workflow_head": WORKFLOW_HEAD,
    }
    require(all(manifest.get(k) == v for k, v in expected.items()), "EXECUTED_PROVENANCE_IDENTITY_MISMATCH")
    files = manifest.get("files")
    require(isinstance(files, list) and len(files) == len(EXECUTED_INPUTS), "EXECUTED_INPUT_SET_MISMATCH")
    seen: set[str] = set()
    for item in files:
        require(isinstance(item, dict), "EXECUTED_INPUT_INVALID")
        name = item.get("snapshot")
        require(isinstance(name, str) and name in EXECUTED_INPUTS and name not in seen,
                "EXECUTED_INPUT_SET_MISMATCH")
        seen.add(name)
        commit, original_path, blob, digest = EXECUTED_INPUTS[name]
        require((item.get("source_commit"), item.get("source_path"), item.get("git_blob_sha"), item.get("sha256"))
                == (commit, original_path, blob, digest), "EXECUTED_INPUT_BINDING_MISMATCH")
        path = folder / name
        require(path.is_file() and not path.is_symlink(), "EXECUTED_INPUT_MISSING_OR_LINKED")
        raw = path.read_bytes()
        require(hashlib.sha256(raw).hexdigest() == digest, "EXECUTED_INPUT_DIGEST_MISMATCH")
        object_bytes = b"blob " + str(len(raw)).encode("ascii") + b"\0" + raw
        require(hashlib.sha1(object_bytes).hexdigest() == blob, "EXECUTED_INPUT_GIT_BLOB_MISMATCH")
    require(seen == set(EXECUTED_INPUTS), "EXECUTED_INPUT_SET_MISMATCH")
    return files


ACTIONS_SNAPSHOT_SHA256 = "1d5444be794761d8f39680eb766f44fbced809a37f3b3cb16780afa5c7b40818"
ENGINE_SHA256 = "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"


def audit_actions_provenance(package: Path, manifest: dict[str, Any],
                             runtime: dict[str, bytes], pc0: dict[str, bytes]) -> dict[str, Any]:
    raw = (package / "provenance/actions-snapshot.v1.json").read_bytes()
    require(hashlib.sha256(raw).hexdigest() == ACTIONS_SNAPSHOT_SHA256, "ACTIONS_SNAPSHOT_DIGEST_MISMATCH")
    snapshot = read_json(raw)
    claims = {
        "runtime_run": 34034752294, "runtime_job": 101490676888, "pc0_run": 34034314222,
        "workflow_head_sha": WORKFLOW_HEAD, "godot_binary_sha256": ENGINE_SHA256,
        "gate_exit_code": 0, "tracked_clean_before": True, "tracked_clean_after": True,
    }
    for key, expected in claims.items():
        require(type(manifest.get(key)) is type(expected) and manifest[key] == expected,
                "ACTIONS_CLAIM_MISMATCH:" + key)
    job = snapshot["runtime_job"]
    require(job["id"] == manifest["runtime_job"] and job["run_id"] == manifest["runtime_run"]
            and job["conclusion"] == "success" and all(s["conclusion"] == "success" for s in job["steps"]),
            "ACTIONS_JOB_BINDING_INVALID")
    for record, role, contents in zip(snapshot["artifacts"], ("runtime", "pc0"), (runtime, pc0)):
        claim = manifest[role + "_artifact"]
        run = snapshot[role + "_run"]
        require(claim["id"] == record["id"] and "sha256:" + claim["zip_sha256"] == record["digest"],
                "ACTIONS_ARTIFACT_IDENTITY_MISMATCH")
        require(run["id"] == manifest[role + "_run"] and run["status"] == "completed"
                and run["conclusion"] == "success" and record["workflow_run"]["id"] == run["id"]
                and record["workflow_run"]["head_sha"] == run["head_sha"], "ACTIONS_RUN_BINDING_INVALID")
        members = {item["original_path"]: item for item in record["members"]}
        observed: set[str] = set()
        for name, content in contents.items():
            original = name.removeprefix("runtime/") if role == "runtime" else name
            require(original in members, "ARTIFACT_MEMBER_IDENTITY_MISMATCH")
            item = members[original]
            require(len(content) == item["size"] and hashlib.sha256(content).hexdigest() == item["sha256"],
                    "ARTIFACT_MEMBER_DIGEST_MISMATCH")
            observed.add(original)
        expected_members = set(members) if role == "runtime" else {n for n in members if n.endswith('.json')}
        require(observed == expected_members, "ARTIFACT_MEMBER_COVERAGE_MISMATCH")
    return snapshot


def verify_live_github(snapshot: dict[str, Any]) -> int:
    """Recheck provider identities online; do not download or run untrusted code."""
    import os
    import urllib.request
    base = "https://api.github.com/repos/rootfabric/distributed-world-simulator/"
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "DWS-P7-closure-audit"}
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = "Bearer " + token
    queries = [
        ("actions/runs/34034752294", snapshot["runtime_run"]),
        ("actions/runs/34034314222", snapshot["pc0_run"]),
        ("actions/jobs/101490676888", snapshot["runtime_job"]),
        *[(f"actions/artifacts/{a['id']}", {k: a[k] for k in ("id", "digest", "size_in_bytes", "workflow_run")})
          for a in snapshot["artifacts"]],
    ]
    def matches(actual: Any, expected: Any) -> bool:
        if isinstance(expected, dict):
            return isinstance(actual, dict) and all(k in actual and matches(actual[k], v) for k, v in expected.items())
        if isinstance(expected, list):
            return isinstance(actual, list) and all(any(matches(item, value) for item in actual) for value in expected)
        return type(actual) is type(expected) and actual == expected
    for relative, expected in queries:
        request = urllib.request.Request(base + relative, headers=headers)
        with urllib.request.urlopen(request, timeout=30) as response:
            actual = read_json(response.read(4_000_001))
        require(matches(actual, expected), "LIVE_GITHUB_BINDING_MISMATCH:" + relative)
    return len(queries)


def git_checks(root: Path, manifest: dict[str, Any]) -> None:
    def git(*args: str) -> str:
        return subprocess.check_output(["git", *args], cwd=root, text=True, timeout=30).strip()
    require(git("rev-parse", HEAD + "^{tree}") == TREE, "GIT_SUBJECT_TREE_MISMATCH")
    git("merge-base", "--is-ancestor", HEAD, "origin/main")
    for stage in manifest["historical_p7_map"]:
        git("merge-base", "--is-ancestor", stage["merge_commit"], HEAD)
        for relative in stage["evidence_paths"]:
            git("cat-file", "-e", f"{HEAD}:{relative}")
    git("merge-base", "--is-ancestor", manifest["accepted_sm1_product_lineage"], HEAD)
    for _, (commit, path, blob, _) in EXECUTED_INPUTS.items():
        if commit == HEAD:
            require(git("rev-parse", f"{commit}:{path}") == blob, "EXECUTED_RUNNER_SOURCE_MISMATCH")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--git", action="store_true")
    parser.add_argument("--github", action="store_true", help="Recheck original provider run/job/artifact identities")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        package = args.root / PACKAGE
        manifest = read_json((package / "manifest.v1.json").read_bytes())
        execution_inputs = audit_execution_provenance(package)
        archives = {name: read_archive(package / name, digest) for name, digest in ARCHIVES.items()}
        provider = audit_actions_provenance(package, manifest, archives["runtime-evidence.tar.xz"], archives["pc0-evidence.tar.xz"])
        report = audit(manifest, archives["runtime-evidence.tar.xz"], archives["pc0-evidence.tar.xz"])
        report["executed_inputs"] = execution_inputs
        report["actions_provenance"] = "PINNED_PROVIDER_CAPTURE_AND_ORIGINAL_MEMBER_HASHES_VALID"
        report["live_github_identities_checked"] = verify_live_github(provider) if args.github else 0
        if args.git:
            git_checks(args.root, manifest)
        text = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
        print(text, end="")
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(text, encoding="utf-8")
        return 0
    except (ValueError, KeyError, TypeError, OSError, tarfile.TarError, subprocess.SubprocessError) as exc:
        print(json.dumps({"result": "EVIDENCE_INVALID", "error": str(exc), "runtime_authorized": False}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
