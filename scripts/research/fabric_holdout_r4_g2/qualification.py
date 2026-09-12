#!/usr/bin/env python3
"""Offline, fail-closed R4 evidence reducer. It never accepts or freezes a checkpoint."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

POLICY_SCHEMA = "fabric.r4.qualification.policy.v1"
REPORT_SCHEMA = "fabric.r4.qualification.receipts.v1"
RESULT_SCHEMA = "fabric.r4.qualification.result.v1"
SHA1 = re.compile(r"[0-9a-f]{40}\Z")
SHA256 = re.compile(r"[0-9a-f]{64}\Z")
FATAL = re.compile(r"(?m)^ERROR:|SCRIPT ERROR:|Parse Error:|Assertion failed|Segmentation fault|^Traceback \(most recent call last\)")
CLASSIFICATIONS = {"CANDIDATE_REGRESSION", "BASELINE_FAILURE", "INFRASTRUCTURE", "HISTORICAL_DRIFT", "INDETERMINATE", "NONE"}


class EvidenceError(ValueError):
    """Evidence cannot establish the requested claim."""


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _unique_pairs(items: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in items:
        if key in result:
            raise EvidenceError(f"DUPLICATE_JSON_KEY:{key}")
        result[key] = value
    return result


def _reject_constant(value: str) -> Any:
    raise EvidenceError(f"NONFINITE_JSON:{value}")


def load_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=_unique_pairs,
                       parse_constant=_reject_constant)
    if not isinstance(value, dict):
        raise EvidenceError("JSON_ROOT_NOT_OBJECT")
    return value


def git(repo: Path, *args: str) -> str:
    result = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, check=False)
    if result.returncode:
        raise EvidenceError(f"GIT_READ_FAILED:{args[0]}:{result.stderr.strip()}")
    return result.stdout.strip()


def read_evidence(root: Path, entry: dict[str, Any]) -> str:
    relative = entry.get("path")
    checksum = entry.get("sha256")
    if not isinstance(relative, str) or not relative or not isinstance(checksum, str) or not SHA256.fullmatch(checksum):
        raise EvidenceError("INVALID_EVIDENCE_REFERENCE")
    path = Path(relative)
    if path.is_absolute() or ".." in path.parts or "\\" in relative:
        raise EvidenceError("EVIDENCE_PATH_ESCAPE")
    target = (root / path).resolve()
    if not target.is_relative_to(root.resolve()) or not target.is_file():
        raise EvidenceError("EVIDENCE_MISSING_OR_OUTSIDE_ROOT")
    if target.stat().st_size > 64 * 1024 * 1024:
        raise EvidenceError("EVIDENCE_FILE_TOO_LARGE")
    data = target.read_bytes()
    if digest(data) != checksum:
        raise EvidenceError("EVIDENCE_HASH_MISMATCH")
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise EvidenceError("EVIDENCE_NOT_UTF8") from exc


def verify_subject(repo: Path, head: str, tree: str, policy: dict[str, Any]) -> list[str]:
    if not isinstance(head, str) or not isinstance(tree, str) or not SHA1.fullmatch(head) or not SHA1.fullmatch(tree):
        raise EvidenceError("FULL_HEAD_AND_TREE_REQUIRED")
    if git(repo, "rev-parse", f"{head}^{{tree}}") != tree:
        raise EvidenceError("SUBJECT_HEAD_TREE_MISMATCH")
    historical = policy.get("historical_control", {})
    if not isinstance(historical, dict):
        raise EvidenceError("HISTORICAL_CONTROL_MISSING")
    reference = historical.get("head", "")
    paths = historical.get("paths", [])
    if not isinstance(reference, str) or not SHA1.fullmatch(reference) or not isinstance(paths, list) or not paths:
        raise EvidenceError("HISTORICAL_CONTROL_MISSING")
    if historical.get("verdict") != "FALSIFIED":
        raise EvidenceError("HISTORICAL_VERDICT_CHANGED")
    findings = []
    for path in paths:
        if not isinstance(path, str) or not path or path.startswith("/") or ".." in Path(path).parts:
            raise EvidenceError("INVALID_FROZEN_PATH")
        if git(repo, "cat-file", "-t", f"{reference}:{path}") != "blob":
            raise EvidenceError("FROZEN_PATH_NOT_FILE")
        old = git(repo, "rev-parse", f"{reference}:{path}")
        new = git(repo, "rev-parse", f"{head}:{path}")
        if old != new:
            findings.append(f"HISTORICAL_BYTES_CHANGED:{path}")
    for spec in policy.get("gates", []):
        if isinstance(spec, dict) and spec.get("mode") == "ci_workflow":
            path = spec.get("workflow_path", "")
            if not isinstance(path, str) or not path.startswith(".github/workflows/") or ".." in Path(path).parts:
                raise EvidenceError("INVALID_WORKFLOW_PATH")
            if git(repo, "rev-parse", f"{head}:{path}") != spec.get("workflow_blob"):
                findings.append("WORKFLOW_BLOB_CHANGED:" + path)
    return findings


def ci_findings(spec: dict[str, Any], receipt: dict[str, Any], root: Path, head: str, tree: str) -> list[str]:
    """Validate an explicitly limited API observation, not a fabricated full CI log.

    The independent reviewer must authenticate the linked run/job and read full logs.
    No unknown executable hash is invented for a workflow that did not record one.
    """
    issues = []
    if receipt.get("workflow_blob") != spec["workflow_blob"] or receipt.get("workflow_path") != spec["workflow_path"]:
        issues.append("WRONG_WORKFLOW")
    refs = receipt.get("evidence")
    if not isinstance(refs, list) or len(refs) != 1 or not isinstance(refs[0], dict) or refs[0].get("role") != "ci_api_observation":
        return issues + ["CI_OBSERVATION_REQUIRED"]
    try:
        text = read_evidence(root, refs[0])
        observation = json.loads(text, object_pairs_hook=_unique_pairs, parse_constant=_reject_constant)
        if not isinstance(observation, dict) or observation.get("schema") != "fabric.r4.ci-observation.v1":
            raise EvidenceError("CI_OBSERVATION_SCHEMA")
        for name in ("run_id", "job_id"):
            if type(observation.get(name)) is not int or observation[name] <= 0:
                raise EvidenceError("CI_OBSERVATION_IDS")
        prefix = "https://api.github.com/repos/rootfabric/distributed-world-simulator/actions/"
        if observation.get("run_url") != prefix + "runs/" + str(observation["run_id"]) or observation.get("job_url") != prefix + "jobs/" + str(observation["job_id"]):
            issues.append("CI_OBSERVATION_URL")
        if observation.get("tested_head") != head or observation.get("tested_tree") != tree or observation.get("run_head_sha") != head:
            issues.append("CI_OBSERVATION_STALE")
        if observation.get("run_conclusion") != "success" or observation.get("job_conclusion") != "success" or observation.get("status") != "completed":
            issues.append("CI_OBSERVATION_NOT_PASS")
        if observation.get("job_name") != spec["job_name"]:
            issues.append("CI_OBSERVATION_WRONG_JOB")
        steps = observation.get("steps")
        if not isinstance(steps, list) or any(not isinstance(x, dict) for x in steps):
            raise EvidenceError("CI_STEPS_INVALID")
        if len({x.get("name") for x in steps}) != len(steps):
            raise EvidenceError("CI_DUPLICATE_STEPS")
        for name in spec["steps"]:
            if not any(x.get("name") == name and x.get("status") == "completed" and x.get("conclusion") == "success" for x in steps):
                issues.append("CI_STEP_MISSING_OR_FAILED:" + name)
        lines = observation.get("log_excerpt")
        if not isinstance(lines, list) or any(not isinstance(x, str) or "\n" in x for x in lines):
            raise EvidenceError("CI_EXCERPT_INVALID")
        for marker in spec["pass_markers"] + ["HEAD=" + head, "TREE=" + tree]:
            if not any(x == marker or x.startswith(marker + " (") for x in lines):
                issues.append("CI_MARKER_MISSING:" + marker)
        if observation.get("full_log_archived") is not False:
            issues.append("CI_OBSERVATION_SCOPE_UNDECLARED")
        if any(FATAL.search(x) for x in lines):
            issues.append("CI_FATAL_IN_EXCERPT")
    except (EvidenceError, ValueError, TypeError) as exc:
        issues.append(str(exc))
    return issues


def reduce_evidence(policy: dict[str, Any], report: dict[str, Any], root: Path,
                    head: str, tree: str, policy_sha256: str,
                    subject_findings: list[str]) -> dict[str, Any]:
    """Reduce verified files, not GitHub colours. Classification never waives a gate.

    A trusted caller must separately live-resolve the PR subject and authenticate
    run/reviewer provenance. This offline reducer validates consistency, not identity.
    """
    if policy.get("schema") != POLICY_SCHEMA or report.get("schema") != REPORT_SCHEMA:
        raise EvidenceError("UNSUPPORTED_SCHEMA")
    if not SHA1.fullmatch(head) or not SHA1.fullmatch(tree) or not SHA256.fullmatch(policy_sha256):
        raise EvidenceError("INVALID_EXPECTED_IDENTITY")
    gates = policy.get("gates")
    receipts = report.get("gates")
    if not isinstance(gates, list) or not gates or not isinstance(receipts, list):
        raise EvidenceError("GATE_LIST_REQUIRED")
    specs: dict[str, dict[str, Any]] = {}
    for spec in gates:
        if not isinstance(spec, dict) or not isinstance(spec.get("id"), str) or not spec["id"] or spec["id"] in specs:
            raise EvidenceError("INVALID_OR_DUPLICATE_POLICY_GATE")
        if spec.get("required") is not True:
            raise EvidenceError("V1_DOES_NOT_SUPPORT_WAIVERS")
        for field in ("command_id", "environment_id"):
            if not isinstance(spec.get(field), str) or not spec[field]:
                raise EvidenceError(f"INVALID_GATE_SPEC:{field}")
        mode = spec.get("mode", "exact_binary")
        if mode == "exact_binary":
            if not isinstance(spec.get("godot_sha256"), str) or not SHA256.fullmatch(spec["godot_sha256"]):
                raise EvidenceError("INVALID_GODOT_DIGEST")
        elif mode == "ci_workflow":
            if not isinstance(spec.get("workflow_blob"), str) or not SHA1.fullmatch(spec["workflow_blob"]):
                raise EvidenceError("INVALID_WORKFLOW_BLOB")
            if not isinstance(spec.get("workflow_path"), str) or not spec["workflow_path"].startswith(".github/workflows/"):
                raise EvidenceError("INVALID_WORKFLOW_PATH")
            if not isinstance(spec.get("steps"), list) or not spec["steps"] or any(not isinstance(x, str) or not x for x in spec["steps"]):
                raise EvidenceError("INVALID_CI_STEPS")
            if not isinstance(spec.get("job_name"), str) or not spec["job_name"]:
                raise EvidenceError("INVALID_CI_JOB_NAME")
        else:
            raise EvidenceError("UNKNOWN_GATE_MODE")
        markers = spec.get("pass_markers")
        argv = spec.get("argv")
        if not isinstance(markers, list) or not markers or any(not isinstance(m, str) or not m or "\n" in m for m in markers):
            raise EvidenceError("INVALID_PASS_MARKERS")
        if not isinstance(argv, list) or not argv or any(not isinstance(a, str) or not a for a in argv):
            raise EvidenceError("INVALID_COMMAND_ARGV")
        specs[spec["id"]] = spec
    index: dict[str, dict[str, Any]] = {}
    for receipt in receipts:
        if not isinstance(receipt, dict) or not isinstance(receipt.get("id"), str) or receipt["id"] not in specs or receipt["id"] in index:
            raise EvidenceError("UNKNOWN_OR_DUPLICATE_RECEIPT")
        index[receipt["id"]] = receipt
    global_findings = list(subject_findings)
    if report.get("subject_head") != head or report.get("subject_tree") != tree:
        global_findings.append("REPORT_SUBJECT_STALE")
    if report.get("policy_sha256") != policy_sha256:
        global_findings.append("REPORT_POLICY_STALE")
    rows = []
    for gate_id, spec in specs.items():
        receipt = index.get(gate_id)
        issues: list[str] = []
        if receipt is None:
            issues.append("MISSING_RECEIPT")
            receipt = {}
        else:
            if receipt.get("subject_head") != head or receipt.get("subject_tree") != tree:
                issues.append("STALE_SUBJECT")
            if receipt.get("policy_sha256") != policy_sha256:
                issues.append("STALE_POLICY")
            if receipt.get("command_id") != spec["command_id"] or receipt.get("argv") != spec["argv"]:
                issues.append("WRONG_COMMAND")
            if receipt.get("environment_id") != spec["environment_id"] or (spec.get("mode", "exact_binary") == "exact_binary" and receipt.get("godot_sha256") != spec["godot_sha256"]):
                issues.append("WRONG_ENVIRONMENT")
            if receipt.get("classification") not in CLASSIFICATIONS:
                issues.append("INVALID_CLASSIFICATION")
            if receipt.get("status") != "COMPLETED" or receipt.get("conclusion") != "PASS":
                issues.append("NOT_COMPLETED_PASS")
            if receipt.get("mode", "exact_binary") != spec.get("mode", "exact_binary"):
                issues.append("WRONG_GATE_MODE")
            if spec.get("mode", "exact_binary") == "ci_workflow":
                issues.extend(ci_findings(spec, receipt, root, head, tree))
            else:
                if type(receipt.get("exit_code")) is not int or receipt["exit_code"] != 0:
                    issues.append("NONZERO_OR_MISSING_EXIT")
                if receipt.get("source_clean") is not True:
                    issues.append("SOURCE_NOT_CLEAN")
                references = receipt.get("evidence")
                texts: list[str] = []
                if not isinstance(references, list) or not references:
                    issues.append("EVIDENCE_REQUIRED")
                else:
                    for entry in references:
                        try:
                            if not isinstance(entry, dict):
                                raise EvidenceError("INVALID_EVIDENCE_REFERENCE")
                            texts.append(read_evidence(root, entry))
                        except EvidenceError as exc:
                            issues.append(str(exc))
                if not isinstance(references, list) or len(references) != 1 or not isinstance(references[0], dict) or references[0].get("role") != "combined_log":
                    issues.append("COMPLETE_COMBINED_LOG_REQUIRED")
                lines = [line.rstrip("\r") for text in texts for line in text.splitlines()]
                for marker in spec["pass_markers"]:
                    if not any(line == marker or line.startswith(marker + " (") for line in lines):
                        issues.append("PASS_MARKER_MISSING:" + marker)
                if any(FATAL.search(text) for text in texts):
                    issues.append("FATAL_RUNTIME_MARKER")
        rows.append({"id": gate_id, "result": "PASS" if not issues else "BLOCKED",
                     "classification": receipt.get("classification", "INDETERMINATE"),
                     "findings": sorted(set(issues))})
    blocking = [row["id"] for row in rows if row["result"] != "PASS"]
    qualified = not blocking and not global_findings
    return {"schema": RESULT_SCHEMA, "subject_head": head, "subject_tree": tree,
            "policy_sha256": policy_sha256, "qualification": "PASS" if qualified else "BLOCKED",
            "blocking_gate_count": len(blocking), "blocking_total": len(blocking) + len(set(global_findings)), "blocking_gates": blocking,
            "global_findings": sorted(set(global_findings)), "gates": rows,
            "ready_for_independent_review": qualified,
            "production_freeze_allowed": False, "unseen_holdout_allowed": False,
            "checkpoint_accepted": False, "acceptance_authority": "CANONICAL_HARNESS_ONLY",
            "provenance_authentication": "REQUIRES_INDEPENDENT_REVIEW"}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--policy", type=Path, required=True)
    parser.add_argument("--policy-sha256", required=True, help="Separately pinned contract digest; never inferred from a report")
    parser.add_argument("--receipts", type=Path, required=True)
    parser.add_argument("--evidence-root", type=Path, required=True)
    parser.add_argument("--head", required=True, help="Full independently resolved product HEAD")
    parser.add_argument("--tree", required=True, help="Full independently resolved product TREE")
    parser.add_argument("--out", type=Path)
    args = parser.parse_args(argv)
    try:
        if digest(args.policy.read_bytes()) != args.policy_sha256:
            raise EvidenceError("POLICY_FILE_DIGEST_MISMATCH")
        policy, report = load_json(args.policy), load_json(args.receipts)
        findings = verify_subject(args.repo, args.head, args.tree, policy)
        result = reduce_evidence(policy, report, args.evidence_root, args.head,
                                 args.tree, args.policy_sha256, findings)
        code = 0 if result["qualification"] == "PASS" else 2
    except (OSError, ValueError, TypeError, KeyError) as exc:
        result = {"schema": RESULT_SCHEMA, "qualification": "INVALID_EVIDENCE",
                  "error": str(exc), "production_freeze_allowed": False,
                  "unseen_holdout_allowed": False, "checkpoint_accepted": False}
        code = 3
    encoded = json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(encoded, encoding="utf-8")
    print(encoded, end="")
    return code


if __name__ == "__main__":
    sys.exit(main())
