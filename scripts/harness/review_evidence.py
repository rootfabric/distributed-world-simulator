"""Machine-enforced provenance for fresh post-build review evidence."""
from __future__ import annotations

import re
import subprocess
from copy import deepcopy
from pathlib import Path
from typing import Any

from .contracts import ContractValidationError

_DIGEST_HEX_LENGTH = {"SHA256": 64, "SHA384": 96, "SHA512": 128}
_POST_BUILD_TYPES = {"POST_BUILD_IMPLEMENTATION_REVIEW", "POST_BUILD_EXACT_HEAD_REVIEW"}


def _git(root: Path, *args: str) -> tuple[int, str]:
    completed = subprocess.run(
        ["git", *args], cwd=root, text=True, capture_output=True, check=False
    )
    return completed.returncode, completed.stdout.strip()


def _repo_relative(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError as exc:
        raise ContractValidationError("REVIEW_PATH_ESCAPES_REPOSITORY") from exc


def _review_add_commit(root: Path, path: Path) -> str:
    relative = _repo_relative(root, path)
    code, add_commit = _git(root, "log", "--diff-filter=A", "-1", "--format=%H", "--", relative)
    if code != 0 or not re.fullmatch(r"[0-9a-f]{40}", add_commit):
        raise ContractValidationError(f"REVIEW_ADD_COMMIT_UNAVAILABLE:{relative}")
    return add_commit


def _machine_evidence_enforcement_applies(
    root: Path,
    path: Path,
    review_policy: dict[str, Any],
) -> bool:
    reuse = review_policy.get("verifier_execution", {}).get("reused_machine_evidence", {})
    activation = reuse.get("enforcement_activation_commit_sha")
    if not isinstance(activation, str) or not re.fullmatch(r"[0-9a-f]{40}", activation):
        raise ContractValidationError("REVIEW_MACHINE_EVIDENCE_ACTIVATION_INVALID")
    code, _ = _git(root, "cat-file", "-e", f"{activation}^{{commit}}")
    if code != 0:
        raise ContractValidationError("REVIEW_MACHINE_EVIDENCE_ACTIVATION_UNREACHABLE")
    add_commit = _review_add_commit(root, path)
    code, _ = _git(root, "merge-base", "--is-ancestor", activation, add_commit)
    if code == 0:
        return True
    if code == 1:
        return False
    raise ContractValidationError("REVIEW_MACHINE_EVIDENCE_ANCESTRY_UNAVAILABLE")


def _machine_evidence_gap(
    root: Path,
    review: dict[str, Any],
    review_policy: dict[str, Any],
) -> str | None:
    evidence = review.get("machine_evidence")
    if not isinstance(evidence, dict):
        return "MACHINE_EVIDENCE_MODE_UNDECLARED"

    mode = evidence.get("mode")
    if mode not in {"FRESH_REEXECUTION", "REUSED_TRUSTED"}:
        return "MACHINE_EVIDENCE_MODE_INVALID"
    if evidence.get("exact_head_sha") != review.get("reviewed_head_sha"):
        return "MACHINE_EVIDENCE_HEAD_UNBOUND"

    exact_tree = evidence.get("exact_tree_sha")
    if not isinstance(exact_tree, str) or not re.fullmatch(r"[0-9a-f]{40}", exact_tree):
        return "MACHINE_EVIDENCE_TREE_INVALID"
    code, observed_tree = _git(root, "rev-parse", f"{review['reviewed_head_sha']}^{{tree}}")
    if code != 0 or observed_tree != exact_tree:
        return "MACHINE_EVIDENCE_TREE_UNBOUND"

    runner = evidence.get("runner_or_workflow_run_id")
    if not isinstance(runner, str) or not runner.strip():
        return "MACHINE_EVIDENCE_RUNNER_UNBOUND"

    if mode == "FRESH_REEXECUTION":
        return None

    reuse = review_policy["verifier_execution"]["reused_machine_evidence"]
    minimum = reuse.get("minimum_digest_algorithm")
    if minimum not in _DIGEST_HEX_LENGTH:
        return "MACHINE_EVIDENCE_MINIMUM_DIGEST_INVALID"
    minimum_bits = int(minimum.removeprefix("SHA"))
    manifest = evidence.get("digest_manifest")
    if not isinstance(manifest, list) or not manifest:
        return "MACHINE_EVIDENCE_DIGEST_MANIFEST_MISSING"
    for item in manifest:
        if not isinstance(item, dict):
            return "MACHINE_EVIDENCE_DIGEST_ENTRY_INVALID"
        identity = item.get("artifact_id_or_path")
        algorithm = item.get("digest_algorithm")
        digest = item.get("digest")
        if not isinstance(identity, str) or not identity.strip():
            return "MACHINE_EVIDENCE_ARTIFACT_IDENTITY_UNBOUND"
        if algorithm not in _DIGEST_HEX_LENGTH or int(algorithm.removeprefix("SHA")) < minimum_bits:
            return "MACHINE_EVIDENCE_DIGEST_ALGORITHM_WEAK"
        if (
            not isinstance(digest, str)
            or len(digest) != _DIGEST_HEX_LENGTH[algorithm]
            or not re.fullmatch(r"[0-9a-f]+", digest)
        ):
            return "MACHINE_EVIDENCE_DIGEST_INVALID"
    return None


def apply_review_machine_evidence_policy(
    root: Path,
    path: Path,
    review: dict[str, Any],
    review_policy: dict[str, Any],
) -> dict[str, Any]:
    """Return the effective review claim after provenance policy enforcement.

    Historical reviews added before the autonomy amendment remain replayable. A
    fresh post-build PASS can no longer silently omit whether machine evidence
    was freshly re-executed or reused. Invalid/missing provenance degrades the
    effective verdict to INSUFFICIENT_EVIDENCE rather than rewriting Git data.
    """
    if review.get("verdict") != "PASS" or review.get("review_type") not in _POST_BUILD_TYPES:
        return review
    if not _machine_evidence_enforcement_applies(root, path, review_policy):
        return review

    gap = _machine_evidence_gap(root, review, review_policy)
    if gap is None:
        return review

    effective = deepcopy(review)
    effective["declared_verdict"] = "PASS"
    effective["verdict"] = "INSUFFICIENT_EVIDENCE"
    gaps = list(effective.get("evidence_gaps", []))
    if gap not in gaps:
        gaps.append(gap)
    effective["evidence_gaps"] = gaps
    effective["machine_evidence_policy_result"] = gap
    return effective
