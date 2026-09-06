"""Committed provenance shared by continuation, review loading and event guards."""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path, PurePosixPath
from typing import Any

from .contracts import ContractValidationError

HARD_BLOCK_SCHEMA = "distributed_world_simulator.harness_hard_block_proof.v1"
MANIFEST_SCHEMA = "distributed_world_simulator.harness_machine_evidence_manifest.v1"
REVIEW_SCHEMA = "distributed_world_simulator.harness_review_result.v1"
PROVENANCE_GENERATION = 81

_CURRENT_BUNDLE_POLICY_KEYS = (
    "project_goals",
    "checkpoint_catalog",
    "scheduler_policy",
    "work_order_schema",
    "event_schema",
    "project_epoch_schema",
    "risk_policy",
    "review_policy",
    "repair_doctrine",
    "evidence_map_schema",
    "human_attention_schema",
    "continuation_policy",
)


def _require(condition: bool, code: str) -> None:
    if not condition:
        raise ContractValidationError(code)


def _git(root: Path, *args: str) -> bytes:
    try:
        result = subprocess.run(
            ["git", *args], cwd=root, capture_output=True, check=False, timeout=30,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise ContractValidationError("PROVENANCE_GIT_UNAVAILABLE") from exc
    _require(result.returncode == 0, f"PROVENANCE_GIT_FAILED:{args[0]}")
    return result.stdout


def _text(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def _sha(value: Any, length: int = 40) -> bool:
    return isinstance(value, str) and re.fullmatch(rf"[0-9a-f]{{{length}}}", value) is not None


def _path(value: Any) -> str:
    _require(_text(value), "PROVENANCE_PATH_REQUIRED")
    path = PurePosixPath(value)
    _require(
        not path.is_absolute() and path.as_posix() == value
        and not any(part in (".", "..", ".git") for part in path.parts)
        and not any(char in value for char in ("\\", ":", "\0", "\n", "\r")),
        "PROVENANCE_PATH_INVALID",
    )
    return value


def _decode(raw: bytes) -> dict[str, Any]:
    def pairs(items: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in items:
            _require(key not in result, f"PROVENANCE_DUPLICATE_KEY:{key}")
            result[key] = value
        return result
    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=pairs)
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise ContractValidationError("PROVENANCE_JSON_INVALID") from exc
    _require(isinstance(value, dict), "PROVENANCE_JSON_OBJECT_REQUIRED")
    return value


def committed_bytes(root: Path, relative: str, *, immutable: bool = True) -> bytes:
    """Read canonical blob bytes, never untracked/modified files or symbolic links."""
    relative = _path(relative)
    literal = f":(literal){relative}"
    entries = _git(root, "ls-tree", "-z", "HEAD", "--", literal).split(b"\0")
    entries = [entry for entry in entries if entry]
    _require(len(entries) == 1, "PROVENANCE_COMMITTED_FILE_REQUIRED")
    metadata, name = entries[0].split(b"\t", 1)
    mode, kind, blob = metadata.split()
    _require(mode in (b"100644", b"100755") and kind == b"blob"
             and name.decode("utf-8") == relative, "PROVENANCE_REGULAR_FILE_REQUIRED")
    candidate = root / relative
    _require(candidate.is_file() and not candidate.is_symlink(), "PROVENANCE_FILE_MISSING")
    _require(candidate.resolve() == root.resolve().joinpath(relative), "PROVENANCE_SYMLINK_FORBIDDEN")
    # --path applies Git's canonical EOL conversion on Windows. A clean index alone
    # does not prove the working file is clean (assume-unchanged can conceal edits).
    actual = _git(root, "hash-object", f"--path={relative}", "--", relative).strip()
    _require(actual == blob, "PROVENANCE_WORKTREE_MODIFIED")
    if immutable:
        history = _git(root, "log", "--format=%H", "HEAD", "--", literal).splitlines()
        added = _git(root, "log", "--diff-filter=A", "--format=%H", "HEAD", "--", literal).splitlines()
        _require(len(history) == 1 and history == added, "PROVENANCE_NOT_APPEND_ONLY")
    return _git(root, "cat-file", "blob", blob.decode("ascii"))


def _subject(root: Path, head: Any, tree: Any) -> None:
    _require(_sha(head) and _sha(tree), "PROVENANCE_SUBJECT_INVALID")
    actual = _git(root, "rev-parse", "--verify", f"{head}^{{tree}}").decode().strip()
    _require(tree == actual, "PROVENANCE_TREE_MISMATCH")
    _git(root, "merge-base", "--is-ancestor", head, "HEAD")


def load_hard_block_proof(
    root: Path, work_order: dict[str, Any], event_path: str,
) -> dict[str, Any] | None:
    event = _decode(committed_bytes(root, event_path))
    _require(event.get("work_order_id") == work_order["work_order_id"]
             and event.get("project_epoch") == work_order["project_epoch"],
             "HARD_BLOCK_EVENT_IDENTITY_MISMATCH")
    if event.get("event_type") != "BLOCKED" or event.get("work_state") != "BLOCKED":
        return None
    _require(_text(event.get("blocker")), "HARD_BLOCK_EVENT_BLOCKER_REQUIRED")
    proofs: list[dict[str, Any]] = []
    for relative in event.get("evidence_paths", []):
        _path(relative)
        if not relative.endswith(".json"):
            continue
        try:
            proof = _decode(committed_bytes(root, relative))
        except ContractValidationError:
            continue
        if proof.get("schema") != HARD_BLOCK_SCHEMA:
            continue
        expected = {
            "work_order_id": work_order["work_order_id"],
            "project_epoch": work_order["project_epoch"],
            "checkpoint": work_order["goal_checkpoint"],
            "blocked_event_id": event["event_id"],
            "blocked_head_sha": event["head_sha"],
            "blocker": event.get("blocker"),
            "proof_evidence_path": relative,
        }
        _require(all(proof.get(key) == value for key, value in expected.items()),
                 "HARD_BLOCK_PROOF_IDENTITY_MISMATCH")
        _subject(root, proof.get("blocked_head_sha"), proof.get("blocked_tree_sha"))
        proofs.append(proof)
    _require(len(proofs) <= 1, "HARD_BLOCK_PROOF_AMBIGUOUS")
    return proofs[0] if proofs else None


def hard_block_matches_state(root: Path | None, state: dict[str, Any]) -> bool:
    """Synthetic flags are not authority; re-read the immutable event and proof."""
    if root is None or not _text(state.get("hard_block_event_path")):
        return False
    event_path = state["hard_block_event_path"]
    event = _decode(committed_bytes(root, event_path))
    reduced = state["reduced_work_order"]
    if (event.get("event_id") != reduced.get("last_event_id")
            or event.get("head_sha") != reduced.get("event_subject_head_sha")
            or reduced.get("state") != "BLOCKED"):
        return False
    proof = load_hard_block_proof(root, state["active_work_order"], event_path)
    return proof is not None and proof == state.get("hard_block_proof")


def _current_bundle_contract_paths(root: Path) -> tuple[str, ...]:
    """Resolve the exact current ContractBundle dependency set from committed policy."""
    harness_path = "config/control/harness/harness-policy.v1.json"
    policy = _decode(committed_bytes(root, harness_path, immutable=False))
    paths = ["config/control/project-program-registry.v1.json", harness_path]
    for key in _CURRENT_BUNDLE_POLICY_KEYS:
        relative = policy.get(key)
        _require(_text(relative), f"CURRENT_BUNDLE_PATH_REQUIRED:{key}")
        paths.append(_path(relative))
    _require(len(paths) == len(set(paths)), "CURRENT_BUNDLE_PATHS_NOT_UNIQUE")
    return tuple(paths)


def _current_execution_json_paths(root: Path, epoch_id: str) -> tuple[str, ...]:
    """Return the exact JSON set under a current execution, committed and worktree-visible.

    build_state() and load_guard_context() consume several execution-local JSON surfaces
    directly from the worktree (transition table, Work Orders, events, reviews, evidence,
    repairs, audits and human-attention ledgers). For generation 81+ none of those bytes,
    nor the membership of that JSON set, may differ from HEAD before reduction.
    """
    _require(re.fullmatch(r"[A-Za-z0-9._-]+", epoch_id) is not None,
             "REVIEW_EPOCH_IDENTITY_REQUIRED")
    prefix = f"config/control/harness/executions/{epoch_id}"
    base = root / prefix
    _require(base.is_dir() and not base.is_symlink(), "EXECUTION_AUTHORITY_DIRECTORY_REQUIRED")

    committed_raw = _git(root, "ls-tree", "-r", "-z", "--name-only", "HEAD", "--", prefix)
    committed = {
        item.decode("utf-8") for item in committed_raw.split(b"\0")
        if item and item.decode("utf-8").endswith(".json")
    }
    worktree: set[str] = set()
    for candidate in base.rglob("*.json"):
        try:
            relative = candidate.relative_to(root).as_posix()
        except ValueError as exc:
            raise ContractValidationError("EXECUTION_AUTHORITY_PATH_ESCAPES_REPOSITORY") from exc
        worktree.add(_path(relative))

    _require(bool(committed), "EXECUTION_AUTHORITY_JSON_REQUIRED")
    _require(committed == worktree, "EXECUTION_AUTHORITY_JSON_SET_MISMATCH")
    return tuple(sorted(committed))


def committed_enforcement_generation(root: Path, epoch: dict[str, Any]) -> int:
    """A dirty generation downgrade or authority input edit cannot select legacy rules."""
    registry_path = "config/control/project-program-registry.v1.json"
    registry = _decode(_git(root, "show", f"HEAD:{registry_path}"))
    pinned_generation = registry.get("registry_generation")
    generation = epoch.get("registry_generation")
    _require(type(pinned_generation) is int and type(generation) is int,
             "REVIEW_EPOCH_GENERATION_REQUIRED")
    if pinned_generation >= PROVENANCE_GENERATION:
        # ContractBundle.load() reads these files from the worktree. Fence the full
        # committed dependency set before any reducer/review result can become authority.
        for relative in _current_bundle_contract_paths(root):
            committed_bytes(root, relative, immutable=False)
        epoch_id = epoch.get("epoch_id")
        _require(_text(epoch_id) and re.fullmatch(r"[A-Za-z0-9._-]+", epoch_id) is not None,
                 "REVIEW_EPOCH_IDENTITY_REQUIRED")
        relative = f"config/control/harness/executions/{epoch_id}/project-epoch.v1.json"
        pinned_epoch = _decode(committed_bytes(root, relative, immutable=False))
        _require(pinned_epoch == epoch, "REVIEW_COMMITTED_EPOCH_MISMATCH")
        # Fence every execution-local JSON byte and the exact JSON membership before
        # reducer/continuation authority. This also closes assume-unchanged, deletion
        # and untracked-injection bypasses for transition/work-order/event/evidence data.
        for relative in _current_execution_json_paths(root, epoch_id):
            committed_bytes(root, relative, immutable=False)
    return generation


def validate_review_machine_evidence(
    root: Path, policy: dict[str, Any], epoch: dict[str, Any],
    review: dict[str, Any],
) -> None:
    """Reject current post-build PASS without exact committed machine provenance."""
    generation = committed_enforcement_generation(root, epoch)
    if generation < PROVENANCE_GENERATION or review.get("verdict") != "PASS":
        return
    if review.get("review_type") == "PRE_BUILD_DESIGN_AUTHORIZATION":
        return
    execution = policy.get("verifier_execution", {})
    _require(isinstance(execution, dict), "REVIEW_MACHINE_POLICY_INVALID")
    enforcement = execution.get("machine_evidence_enforcement", {})
    _require(isinstance(enforcement, dict), "REVIEW_MACHINE_ENFORCEMENT_REQUIRED")
    _require(enforcement.get("effective_registry_generation") == PROVENANCE_GENERATION
             and enforcement.get("post_build_pass_requires_manifest") is True,
             "REVIEW_MACHINE_ENFORCEMENT_REQUIRED")
    reuse_policy = execution.get("reused_machine_evidence", {})
    _require(isinstance(reuse_policy, dict), "REVIEW_MACHINE_POLICY_INVALID")
    _require(reuse_policy.get("minimum_digest_algorithm") == "SHA256"
             and reuse_policy.get("digest_manifest_required") is True,
             "REVIEW_MACHINE_POLICY_INVALID")
    evidence = review.get("machine_evidence")
    _require(isinstance(evidence, dict), "REVIEW_MACHINE_EVIDENCE_REQUIRED")
    _require(evidence.get("mode") in ("FRESH_EXECUTION", "REUSED"), "REVIEW_EVIDENCE_MODE_INVALID")
    _require(_sha(evidence.get("manifest_sha256"), 64), "REVIEW_MANIFEST_DIGEST_REQUIRED")
    raw = committed_bytes(root, evidence.get("manifest_path"))
    _require(hashlib.sha256(raw).hexdigest() == evidence["manifest_sha256"],
             "REVIEW_MANIFEST_DIGEST_MISMATCH")
    manifest = _decode(raw)
    _require(manifest.get("schema") == MANIFEST_SCHEMA, "REVIEW_MANIFEST_SCHEMA_INVALID")
    expected = {
        "work_order_id": review.get("work_order_id"),
        "project_epoch": epoch.get("epoch_id"),
        "subject_head_sha": review.get("reviewed_head_sha"),
    }
    _require(all(manifest.get(key) == value for key, value in expected.items()),
             "REVIEW_MANIFEST_IDENTITY_MISMATCH")
    _subject(root, manifest.get("subject_head_sha"), manifest.get("subject_tree_sha"))
    for field in ("runner_id", "run_id"):
        _require(_text(manifest.get(field)) and evidence.get(field) == manifest[field],
                 f"REVIEW_MANIFEST_BINDING_INVALID:{field}")
    _require(manifest.get("tracked_checkout_clean_before") is True
             and manifest.get("tracked_checkout_clean_after") is True,
             "REVIEW_MACHINE_CHECKOUT_NOT_CLEAN")
    artifacts = manifest.get("artifacts")
    _require(isinstance(artifacts, list) and bool(artifacts), "REVIEW_ARTIFACTS_REQUIRED")
    seen: set[str] = set()
    for artifact in artifacts:
        _require(isinstance(artifact, dict), "REVIEW_ARTIFACT_INVALID")
        relative = _path(artifact.get("path"))
        _require(relative not in seen, "REVIEW_ARTIFACT_DUPLICATE")
        seen.add(relative)
        _require(_sha(artifact.get("sha256"), 64), "REVIEW_ARTIFACT_DIGEST_REQUIRED")
        _require(artifact.get("run_id") == manifest["run_id"]
                 and artifact.get("subject_head_sha") == manifest["subject_head_sha"],
                 "REVIEW_ARTIFACT_RUN_BINDING_INVALID")
        content = committed_bytes(root, relative)
        _require(hashlib.sha256(content).hexdigest() == artifact["sha256"],
                 "REVIEW_ARTIFACT_DIGEST_MISMATCH")
    requested = evidence.get("artifact_paths")
    _require(isinstance(requested, list) and all(isinstance(path, str) for path in requested)
             and len(requested) == len(seen) and set(requested) == seen,
             "REVIEW_ARTIFACT_COVERAGE_MISMATCH")
    commands = manifest.get("commands")
    _require(isinstance(commands, list) and bool(commands), "REVIEW_COMMANDS_REQUIRED")
    for command in commands:
        _require(isinstance(command, dict) and _text(command.get("command"))
                 and type(command.get("exit_code")) is int
                 and type(command.get("expected_exit_code")) is int
                 and command["exit_code"] == command["expected_exit_code"]
                 and _text(command.get("log_path"))
                 and command["log_path"] in seen, "REVIEW_COMMAND_RESULT_INVALID")


def validate_review_record(
    root: Path, policy: dict[str, Any], epoch: dict[str, Any],
    review: dict[str, Any], relative: str,
) -> None:
    """The authoritative consumers also require the review claim itself in Git."""
    generation = epoch.get("registry_generation")
    if type(generation) is int and generation >= PROVENANCE_GENERATION and review.get("verdict") == "PASS":
        _require(_decode(committed_bytes(root, relative)) == review, "REVIEW_COMMITTED_RECORD_MISMATCH")
    validate_review_machine_evidence(root, policy, epoch, review)
