"""Build complete H0.0 status using only versioned JSON and Git metadata."""
from __future__ import annotations

import re
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Any

from .contracts import ContractBundle, ContractValidationError, read_json
from .epoch_validator import validate_epoch
from .event_reducer import load_guard_context, reduce_events


_EVIDENCE_MAP_SCHEMA = "distributed_world_simulator.harness_evidence_map.v1"
_EVIDENCE_MAP_SCHEMA_PREFIX = "distributed_world_simulator.harness_evidence_map"
_H0_0_CHECKPOINT_DOC = "docs/checkpoints/2026-08-11_H0_0_RESTART_SAFE_HARNESS_SCAFFOLD_R3_RU.md"

_EVENT_LEDGER_RECONCILIATION_SCHEMA = "distributed_world_simulator.harness_event_ledger_reconciliation.v1"
_EVENT_LEDGER_RECONCILIATION_MODE = "QUARANTINE_EXACT_IMMUTABLE_NONCANONICAL_EVENTS"
_EVENT_LEDGER_RECONCILIATION_AUTHORITY = "DIRECTOR_REPAIR_EXACT_PINNED_LEGACY_EVENTS"

_EVIDENCE_LEDGER_RECONCILIATION_SCHEMA = "distributed_world_simulator.harness_evidence_ledger_reconciliation.v1"
_EVIDENCE_LEDGER_RECONCILIATION_MODE = "QUARANTINE_EXACT_IMMUTABLE_MISTYPED_EVIDENCE_MAPS"
_EVIDENCE_LEDGER_RECONCILIATION_AUTHORITY = "DIRECTOR_REPAIR_EXACT_PINNED_LEGACY_EVIDENCE"

_REVIEW_LEDGER_RECONCILIATION_SCHEMA = "distributed_world_simulator.harness_review_ledger_reconciliation.v1"
_REVIEW_LEDGER_RECONCILIATION_MODE = "QUARANTINE_EXACT_IMMUTABLE_LEGACY_REVIEW_FORMATS"
_REVIEW_LEDGER_RECONCILIATION_AUTHORITY = "DIRECTOR_REPAIR_EXACT_PINNED_LEGACY_REVIEWS"

_HUMAN_ATTENTION_LEDGER_RECONCILIATION_SCHEMA = "distributed_world_simulator.harness_human_attention_ledger_reconciliation.v1"
_HUMAN_ATTENTION_LEDGER_RECONCILIATION_MODE = "QUARANTINE_EXACT_IMMUTABLE_RESOLVED_LEGACY_HUMAN_ATTENTION"
_HUMAN_ATTENTION_LEDGER_RECONCILIATION_AUTHORITY = "DIRECTOR_REPAIR_EXACT_PINNED_LEGACY_HUMAN_ATTENTION"


def _git_head(root: Path) -> str:
    output = subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, text=True, capture_output=True, check=False)
    if output.returncode != 0:
        raise ContractValidationError("GIT_HEAD_UNAVAILABLE")
    return output.stdout.strip()


def _git_branch(root: Path) -> str:
    output = subprocess.run(["git", "branch", "--show-current"], cwd=root, text=True, capture_output=True, check=False)
    branch = output.stdout.strip()
    if output.returncode != 0 or not branch:
        raise ContractValidationError("GIT_BRANCH_UNAVAILABLE")
    return branch


def _repo_relative(root: Path, path: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError as exc:
        raise ContractValidationError("EXECUTION_PATH_ESCAPES_REPOSITORY") from exc


def _implementation_pathspecs(
    root: Path,
    execution_dir: Path,
    work_order: dict[str, Any],
) -> tuple[str, ...]:
    """Return review-freshness pathspecs for the active bounded implementation.

    The Work Order is the authority for implementation scope. Append-only execution
    records, branch passports and checkpoint-only documents are intentionally
    excluded so writing evidence cannot stale its own review target. The active
    transition table remains part of the implementation fence because it controls
    reducer semantics for this execution.
    """
    execution_prefix = f"{_repo_relative(root, execution_dir).rstrip('/')}/"
    excluded_prefixes = (execution_prefix, "config/control/branches/", "docs/checkpoints/")
    pathspecs: list[str] = []
    for raw_path in work_order["allowed_paths"]:
        normalized = raw_path.replace("\\", "/")
        if any(normalized.startswith(prefix) for prefix in excluded_prefixes):
            continue
        if normalized not in pathspecs:
            pathspecs.append(normalized)

    transition_path = _repo_relative(root, execution_dir / "transition-table.v1.json")
    if transition_path not in pathspecs:
        pathspecs.append(transition_path)
    if not pathspecs:
        raise ContractValidationError("IMPLEMENTATION_PATHS_UNAVAILABLE")
    return tuple(pathspecs)


def _git_implementation_head(
    root: Path,
    execution_dir: Path,
    work_order: dict[str, Any],
) -> str:
    """Return the latest commit touching the active bounded implementation."""
    implementation_paths = _implementation_pathspecs(root, execution_dir, work_order)
    output = subprocess.run(
        ["git", "log", "-1", "--format=%H", "--", *implementation_paths],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )
    value = output.stdout.strip()
    if output.returncode != 0 or not re.fullmatch(r"[0-9a-f]{40}", value):
        raise ContractValidationError("GIT_IMPLEMENTATION_HEAD_UNAVAILABLE")
    return value


def _git_path_head(root: Path, path: Path) -> str:
    relative = _repo_relative(root, path)
    output = subprocess.run(
        ["git", "log", "-1", "--format=%H", "--", relative],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )
    value = output.stdout.strip()
    if len(value) != 40:
        raise ContractValidationError(f"EVENT_LEDGER_HEAD_UNAVAILABLE:{path.as_posix()}")
    return value


def _git(root: Path, *args: str) -> tuple[int, str]:
    output = subprocess.run(["git", *args], cwd=root, text=True, capture_output=True, check=False)
    return output.returncode, output.stdout.strip()


def _validate_event_git_provenance(
    root: Path,
    event_paths: list[Path],
    events: list[dict[str, Any]],
    current_head: str,
) -> str:
    if len(event_paths) != len(events):
        raise ContractValidationError("EVENT_PATH_COUNT_MISMATCH")
    if not event_paths:
        raise ContractValidationError("EVENT_LEDGER_EMPTY")
    latest_add = ""
    for path, event in zip(event_paths, events):
        relative = _repo_relative(root, path)
        code, dirty = _git(root, "status", "--porcelain", "--", relative)
        if code != 0 or dirty:
            raise ContractValidationError(f"EVENT_WORKTREE_MUTATION_DETECTED:{relative}")
        code, history = _git(root, "log", "--format=%H", "--", relative)
        commits = [line for line in history.splitlines() if line]
        if code != 0 or len(commits) != 1:
            raise ContractValidationError(f"EVENT_IMMUTABILITY_NOT_PROVEN:{relative}")
        code, add_commit = _git(root, "log", "--diff-filter=A", "-1", "--format=%H", "--", relative)
        if code != 0 or len(add_commit) != 40 or add_commit != commits[0]:
            raise ContractValidationError(f"EVENT_ADD_COMMIT_NOT_PROVEN:{relative}")
        code, _ = _git(root, "merge-base", "--is-ancestor", add_commit, current_head)
        if code != 0:
            raise ContractValidationError(f"EVENT_LEDGER_NOT_REACHABLE:{relative}")
        code, _ = _git(root, "cat-file", "-e", f"{event['head_sha']}^{{commit}}")
        if code != 0:
            raise ContractValidationError(f"EVENT_SUBJECT_HEAD_UNREACHABLE:{event['event_id']}")
        code, _ = _git(root, "merge-base", "--is-ancestor", event["head_sha"], current_head)
        if code != 0:
            raise ContractValidationError(f"EVENT_SUBJECT_NOT_ANCESTOR:{event['event_id']}")
        latest_add = add_commit

    event_dir = _repo_relative(root, event_paths[0].parent)
    code, deleted = _git(root, "log", "--diff-filter=D", "--name-only", "--format=", "--", event_dir)
    if code != 0 or deleted.strip():
        raise ContractValidationError("EVENT_LEDGER_DELETION_DETECTED")
    return latest_add


def _json_files(directory: Path) -> list[Path]:
    return sorted(directory.rglob("*.json")) if directory.exists() else []


def _select_authoritative_event_paths(
    root: Path,
    execution_dir: Path,
    work_order: dict[str, Any],
    event_dir: Path,
    raw_event_paths: list[Path],
) -> tuple[list[Path], dict[str, Any] | None]:
    """Return reducer-authoritative event paths after strict legacy reconciliation.

    Historical files are never edited or deleted. A reconciliation may quarantine
    only exact event paths whose current Git blob identity is pinned in the
    execution-local manifest. Unlisted/future events always remain authoritative.
    """

    manifest_path = execution_dir / "event-ledger-reconciliation.v1.json"
    if not manifest_path.exists():
        return raw_event_paths, None

    reconciliation = read_json(manifest_path)
    if reconciliation.get("schema") != _EVENT_LEDGER_RECONCILIATION_SCHEMA:
        raise ContractValidationError("EVENT_RECONCILIATION_SCHEMA_INVALID")
    if reconciliation.get("version") != 1:
        raise ContractValidationError("EVENT_RECONCILIATION_VERSION_INVALID")
    if reconciliation.get("project_epoch") != work_order["project_epoch"]:
        raise ContractValidationError("EVENT_RECONCILIATION_EPOCH_MISMATCH")
    if reconciliation.get("work_order_id") != work_order["work_order_id"]:
        raise ContractValidationError("EVENT_RECONCILIATION_WORK_ORDER_MISMATCH")
    if reconciliation.get("authority") != _EVENT_LEDGER_RECONCILIATION_AUTHORITY:
        raise ContractValidationError("EVENT_RECONCILIATION_AUTHORITY_INVALID")
    if reconciliation.get("mode") != _EVENT_LEDGER_RECONCILIATION_MODE:
        raise ContractValidationError("EVENT_RECONCILIATION_MODE_INVALID")

    constraints = reconciliation.get("constraints")
    required_constraints = {
        "quarantine_exact_paths_only": True,
        "git_blob_pin_required": True,
        "quarantined_file_must_remain_present": True,
        "quarantined_file_must_have_single_add_commit": True,
        "wildcard_paths_forbidden": True,
        "event_schema_unchanged": True,
        "reducer_transition_table_unchanged": True,
        "future_unlisted_events_are_authoritative": True,
    }
    if constraints != required_constraints:
        raise ContractValidationError("EVENT_RECONCILIATION_CONSTRAINTS_INVALID")

    canonical_next_sequence = reconciliation.get("canonical_next_sequence")
    if not isinstance(canonical_next_sequence, int) or canonical_next_sequence < 2:
        raise ContractValidationError("EVENT_RECONCILIATION_NEXT_SEQUENCE_INVALID")

    raw_by_resolved = {path.resolve(): path for path in raw_event_paths}
    quarantined_paths: set[Path] = set()
    records = reconciliation.get("quarantined_events")
    if not isinstance(records, list) or not records:
        raise ContractValidationError("EVENT_RECONCILIATION_QUARANTINE_EMPTY")

    for item in records:
        if not isinstance(item, dict) or set(item) != {"path", "git_blob_sha", "reasons"}:
            raise ContractValidationError("EVENT_RECONCILIATION_RECORD_INVALID")
        relative = item.get("path")
        blob_pin = item.get("git_blob_sha")
        reasons = item.get("reasons")
        if (
            not isinstance(relative, str)
            or not relative
            or any(marker in relative for marker in ("*", "?", "["))
            or not isinstance(blob_pin, str)
            or not re.fullmatch(r"[0-9a-f]{40}", blob_pin)
            or not isinstance(reasons, list)
            or not reasons
            or any(not isinstance(reason, str) or not reason for reason in reasons)
        ):
            raise ContractValidationError("EVENT_RECONCILIATION_RECORD_INVALID")

        candidate = (root / relative).resolve()
        if candidate.parent != event_dir.resolve() or candidate not in raw_by_resolved:
            raise ContractValidationError(f"EVENT_RECONCILIATION_PATH_INVALID:{relative}")
        if candidate in quarantined_paths:
            raise ContractValidationError(f"EVENT_RECONCILIATION_PATH_DUPLICATE:{relative}")

        code, observed_blob = _git(root, "rev-parse", f"HEAD:{relative}")
        if code != 0 or observed_blob != blob_pin:
            raise ContractValidationError(f"EVENT_RECONCILIATION_BLOB_MISMATCH:{relative}")

        code, history = _git(root, "log", "--format=%H", "--", relative)
        commits = [line for line in history.splitlines() if line]
        if code != 0 or len(commits) != 1:
            raise ContractValidationError(f"EVENT_RECONCILIATION_IMMUTABILITY_NOT_PROVEN:{relative}")
        code, add_commit = _git(root, "log", "--diff-filter=A", "-1", "--format=%H", "--", relative)
        if code != 0 or add_commit != commits[0]:
            raise ContractValidationError(f"EVENT_RECONCILIATION_ADD_COMMIT_NOT_PROVEN:{relative}")

        raw_event = read_json(candidate)
        sequence = raw_event.get("sequence")
        if not isinstance(sequence, int) or sequence < canonical_next_sequence:
            raise ContractValidationError(f"EVENT_RECONCILIATION_SEQUENCE_INVALID:{relative}")
        quarantined_paths.add(candidate)

    authoritative = [
        path for path in raw_event_paths if path.resolve() not in quarantined_paths
    ]
    if not authoritative:
        raise ContractValidationError("EVENT_RECONCILIATION_REMOVED_ALL_EVENTS")

    canonical_relative = reconciliation.get("canonical_reconstruction_event")
    if not isinstance(canonical_relative, str) or not canonical_relative:
        raise ContractValidationError("EVENT_RECONCILIATION_CANONICAL_EVENT_INVALID")
    canonical_path = (root / canonical_relative).resolve()
    if canonical_path not in {path.resolve() for path in authoritative}:
        raise ContractValidationError("EVENT_RECONCILIATION_CANONICAL_EVENT_MISSING")
    canonical_event = read_json(canonical_path)
    if canonical_event.get("sequence") != canonical_next_sequence - 1:
        raise ContractValidationError("EVENT_RECONCILIATION_CANONICAL_SEQUENCE_INVALID")

    return authoritative, {
        "active": True,
        "schema": reconciliation["schema"],
        "reconciliation_id": reconciliation.get("reconciliation_id"),
        "mode": reconciliation["mode"],
        "quarantined_event_count": len(quarantined_paths),
        "authoritative_event_count": len(authoritative),
        "canonical_next_sequence": canonical_next_sequence,
        "canonical_reconstruction_event": canonical_relative,
    }


def _validate_semantics(bundle: ContractBundle, epoch: dict[str, Any], work_order: dict[str, Any]) -> None:
    if epoch["epoch_id"] != work_order["project_epoch"] or epoch["base_sha"] != work_order["base_sha"]:
        raise ContractValidationError("EPOCH_WORK_ORDER_IDENTITY_OR_BASE_MISMATCH")
    if work_order["goal_checkpoint"] not in bundle.contracts["checkpoint_catalog"]["checkpoints"]:
        raise ContractValidationError("WORK_ORDER_CHECKPOINT_NOT_CANONICAL")
    if work_order["goal_checkpoint"] not in epoch["eligible_checkpoints"]:
        raise ContractValidationError("WORK_ORDER_CHECKPOINT_NOT_EPOCH_ELIGIBLE")
    if epoch["registry_generation"] != bundle.contracts["project_registry"]["registry_generation"]:
        raise ContractValidationError("EPOCH_REGISTRY_GENERATION_MISMATCH")
    if epoch["harness_revision"] != bundle.contracts["harness_policy"]["harness_revision"]:
        raise ContractValidationError("EPOCH_HARNESS_REVISION_MISMATCH")

    expected_roles = bundle.contracts["risk_policy"]["classes"][work_order["risk_class"]]["required_roles"]
    if work_order.get("required_review_roles") != expected_roles:
        raise ContractValidationError("RISK_REQUIRED_ROLES_MISMATCH")
    if work_order["risk_class"] in {"MEDIUM", "HIGH", "CRITICAL"}:
        if not work_order.get("review_required"):
            raise ContractValidationError("RISK_REVIEW_REQUIRED")
        if not work_order.get("evidence_map_required"):
            raise ContractValidationError("RISK_EVIDENCE_MAP_REQUIRED")
        brief = work_order.get("design_brief", {})
        missing = [
            field
            for field in bundle.contracts["review_policy"]["pre_build"]["design_brief_fields"]
            if not brief.get(field)
        ]
        if missing:
            raise ContractValidationError(f"DESIGN_BRIEF_FIELD_MISSING:{','.join(missing)}")

    for collection in (work_order["allowed_paths"], work_order["forbidden_paths"]):
        for raw_path in collection:
            normalized = raw_path.replace("\\", "/")
            if normalized.startswith("/") or ":" in normalized or ".." in normalized.split("/"):
                raise ContractValidationError("SCOPE_PATH_NOT_REPOSITORY_RELATIVE")
            static_prefix = normalized
            for marker in ("*", "?", "["):
                static_prefix = static_prefix.split(marker, 1)[0]
            candidate = (bundle.root / static_prefix.rstrip("/")).resolve()
            try:
                candidate.relative_to(bundle.root.resolve())
            except ValueError as exc:
                raise ContractValidationError("SCOPE_PATH_ESCAPES_REPOSITORY") from exc


def _validate_repair_map(
    bundle: ContractBundle,
    execution_dir: Path,
    work_order_id: str,
    evidence_paths: list[str],
) -> dict[str, Any] | None:
    candidates: list[tuple[str, dict[str, Any]]] = []
    for path in _json_files(execution_dir / "repairs"):
        value = read_json(path)
        if (
            value.get("schema") == "distributed_world_simulator.harness_repair_map.v1"
            and value.get("work_order_id") == work_order_id
        ):
            candidates.append((_repo_relative(bundle.root, path), value))
    if not candidates:
        return None
    normalized_evidence = {item.replace("\\", "/") for item in evidence_paths}
    referenced = [value for relative, value in candidates if relative in normalized_evidence]
    latest = referenced[-1] if referenced else candidates[-1][1]
    missing = [
        field
        for field in bundle.contracts["repair_doctrine"]["repair_map_fields"]
        if not latest.get(field)
    ]
    if missing:
        raise ContractValidationError(f"REPAIR_MAP_FIELD_MISSING:{','.join(missing)}")
    return latest


def _select_authoritative_review_paths(
    root: Path,
    execution_dir: Path,
    work_order: dict[str, Any],
) -> list[Path]:
    """Return current-contract review paths after exact-pinned legacy quarantine."""

    review_dir = execution_dir / "reviews"
    raw_paths = _json_files(review_dir)
    manifest_path = execution_dir / "review-ledger-reconciliation.v1.json"
    if not manifest_path.exists():
        return raw_paths

    reconciliation = read_json(manifest_path)
    if reconciliation.get("schema") != _REVIEW_LEDGER_RECONCILIATION_SCHEMA:
        raise ContractValidationError("REVIEW_RECONCILIATION_SCHEMA_INVALID")
    if reconciliation.get("version") != 1:
        raise ContractValidationError("REVIEW_RECONCILIATION_VERSION_INVALID")
    if reconciliation.get("project_epoch") != work_order["project_epoch"]:
        raise ContractValidationError("REVIEW_RECONCILIATION_EPOCH_MISMATCH")
    if reconciliation.get("work_order_id") != work_order["work_order_id"]:
        raise ContractValidationError("REVIEW_RECONCILIATION_WORK_ORDER_MISMATCH")
    if reconciliation.get("authority") != _REVIEW_LEDGER_RECONCILIATION_AUTHORITY:
        raise ContractValidationError("REVIEW_RECONCILIATION_AUTHORITY_INVALID")
    if reconciliation.get("mode") != _REVIEW_LEDGER_RECONCILIATION_MODE:
        raise ContractValidationError("REVIEW_RECONCILIATION_MODE_INVALID")

    required_constraints = {
        "quarantine_exact_paths_only": True,
        "git_blob_pin_required": True,
        "quarantined_file_must_remain_present": True,
        "quarantined_file_must_have_single_add_commit": True,
        "wildcard_paths_forbidden": True,
        "current_review_contract_unchanged": True,
        "future_unlisted_reviews_are_authoritative": True,
    }
    if reconciliation.get("constraints") != required_constraints:
        raise ContractValidationError("REVIEW_RECONCILIATION_CONSTRAINTS_INVALID")

    records = reconciliation.get("quarantined_reviews")
    if not isinstance(records, list) or not records:
        raise ContractValidationError("REVIEW_RECONCILIATION_QUARANTINE_EMPTY")

    raw_by_resolved = {path.resolve(): path for path in raw_paths}
    quarantined: set[Path] = set()
    for item in records:
        if not isinstance(item, dict) or set(item) != {"path", "git_blob_sha", "reason"}:
            raise ContractValidationError("REVIEW_RECONCILIATION_RECORD_INVALID")
        relative = item.get("path")
        blob_pin = item.get("git_blob_sha")
        reason = item.get("reason")
        if (
            not isinstance(relative, str)
            or not relative
            or any(marker in relative for marker in ("*", "?", "["))
            or not isinstance(blob_pin, str)
            or not re.fullmatch(r"[0-9a-f]{40}", blob_pin)
            or not isinstance(reason, str)
            or not reason
        ):
            raise ContractValidationError("REVIEW_RECONCILIATION_RECORD_INVALID")

        candidate = (root / relative).resolve()
        if candidate.parent != review_dir.resolve() or candidate not in raw_by_resolved:
            raise ContractValidationError(f"REVIEW_RECONCILIATION_PATH_INVALID:{relative}")
        if candidate in quarantined:
            raise ContractValidationError(f"REVIEW_RECONCILIATION_PATH_DUPLICATE:{relative}")

        code, observed_blob = _git(root, "rev-parse", f"HEAD:{relative}")
        if code != 0 or observed_blob != blob_pin:
            raise ContractValidationError(f"REVIEW_RECONCILIATION_BLOB_MISMATCH:{relative}")
        code, history = _git(root, "log", "--format=%H", "--", relative)
        commits = [line for line in history.splitlines() if line]
        if code != 0 or len(commits) != 1:
            raise ContractValidationError(f"REVIEW_RECONCILIATION_IMMUTABILITY_NOT_PROVEN:{relative}")
        code, add_commit = _git(root, "log", "--diff-filter=A", "-1", "--format=%H", "--", relative)
        if code != 0 or add_commit != commits[0]:
            raise ContractValidationError(f"REVIEW_RECONCILIATION_ADD_COMMIT_NOT_PROVEN:{relative}")

        value = read_json(candidate)
        if value.get("schema") != "distributed_world_simulator.harness_review_result.v1":
            raise ContractValidationError(f"REVIEW_RECONCILIATION_SCHEMA_MISUSE_NOT_PRESENT:{relative}")
        quarantined.add(candidate)

    return [path for path in raw_paths if path.resolve() not in quarantined]


def _load_reviews(
    root: Path,
    execution_dir: Path,
    work_order: dict[str, Any],
) -> list[dict[str, Any]]:
    """Validate every review claim, then return reviews for the active Work Order."""
    validated_reviews: list[dict[str, Any]] = []
    review_ids: set[str] = set()
    required = {
        "schema",
        "review_id",
        "review_type",
        "work_order_id",
        "risk_class",
        "reviewed_head_sha",
        "reviewer",
        "verdict",
        "reviewed_at_utc",
        "required_fixes",
        "rank_up_moves",
        "evidence_gaps",
        "risk_assessment",
    }
    for path in _select_authoritative_review_paths(root, execution_dir, work_order):
        value = read_json(path)
        if value.get("schema") != "distributed_world_simulator.harness_review_result.v1" or required - value.keys():
            raise ContractValidationError(f"REVIEW_RESULT_INVALID:{path.name}")
        if value["review_id"] in review_ids:
            raise ContractValidationError("REVIEW_ID_NOT_UNIQUE")
        review_ids.add(value["review_id"])
        if value["verdict"] not in {"PASS", "FAIL", "INSUFFICIENT_EVIDENCE"}:
            raise ContractValidationError("REVIEW_VERDICT_INVALID")
        if value["review_type"] not in {
            "PRE_BUILD_DESIGN_AUTHORIZATION",
            "POST_BUILD_IMPLEMENTATION_REVIEW",
            "POST_BUILD_EXACT_HEAD_REVIEW",
        }:
            raise ContractValidationError("REVIEW_TYPE_INVALID")
        if not re.fullmatch(r"[0-9a-f]{40}", value["reviewed_head_sha"]):
            raise ContractValidationError("REVIEW_HEAD_SHA_INVALID")
        if "IMPLEMENTER" in value["reviewer"].upper() or not value["reviewer"].strip():
            raise ContractValidationError("REVIEWER_INDEPENDENCE_INVALID")
        if any(
            not isinstance(value[field], list)
            or any(not isinstance(item, str) for item in value[field])
            for field in ("required_fixes", "rank_up_moves", "evidence_gaps")
        ):
            raise ContractValidationError("REVIEW_SECTIONS_INVALID")
        if not isinstance(value["risk_assessment"], str) or not value["risk_assessment"]:
            raise ContractValidationError("REVIEW_RISK_ASSESSMENT_INVALID")
        try:
            datetime.fromisoformat(value["reviewed_at_utc"].replace("Z", "+00:00"))
        except (AttributeError, ValueError) as exc:
            raise ContractValidationError("REVIEW_TIMESTAMP_INVALID") from exc
        code, _ = _git(root, "cat-file", "-e", f"{value['reviewed_head_sha']}^{{commit}}")
        if code != 0:
            raise ContractValidationError("REVIEW_HEAD_UNREACHABLE")
        validated_reviews.append(value)

    active_reviews = [
        item
        for item in validated_reviews
        if item["work_order_id"] == work_order["work_order_id"]
    ]
    if any(item["risk_class"] != work_order["risk_class"] for item in active_reviews):
        raise ContractValidationError("REVIEW_WORK_ORDER_OR_RISK_MISMATCH")
    return active_reviews


def _select_epoch_audit(
    guard_context: dict[str, Any],
    events: list[dict[str, Any]],
) -> dict[str, Any] | None:
    audited_paths = {
        path.replace("\\", "/")
        for event in events
        if event.get("event_type") == "AUDIT_COMPLETED"
        and event.get("work_state") == "AUDITED"
        and event.get("exit_code") == 0
        and event.get("command")
        for path in event.get("evidence_paths", [])
    }
    audits = [
        item
        for path, item in guard_context["documents"].items()
        if path in audited_paths
        and item.get("schema") == "distributed_world_simulator.harness_epoch_audit.v1"
    ]
    return audits[-1] if audits else None


def _select_authoritative_evidence_paths(
    bundle: ContractBundle,
    evidence_dir: Path,
    work_order_id: str | None,
) -> list[Path]:
    """Return Evidence Map candidates after strict exact-pinned legacy quarantine."""

    raw_paths = _json_files(evidence_dir)
    manifest_path = evidence_dir.parent / "evidence-ledger-reconciliation.v1.json"
    if not manifest_path.exists():
        return raw_paths

    reconciliation = read_json(manifest_path)
    if reconciliation.get("schema") != _EVIDENCE_LEDGER_RECONCILIATION_SCHEMA:
        raise ContractValidationError("EVIDENCE_RECONCILIATION_SCHEMA_INVALID")
    if reconciliation.get("version") != 1:
        raise ContractValidationError("EVIDENCE_RECONCILIATION_VERSION_INVALID")
    if reconciliation.get("project_epoch") != evidence_dir.parent.name:
        raise ContractValidationError("EVIDENCE_RECONCILIATION_EPOCH_MISMATCH")
    if work_order_id is not None and reconciliation.get("work_order_id") != work_order_id:
        raise ContractValidationError("EVIDENCE_RECONCILIATION_WORK_ORDER_MISMATCH")
    if reconciliation.get("authority") != _EVIDENCE_LEDGER_RECONCILIATION_AUTHORITY:
        raise ContractValidationError("EVIDENCE_RECONCILIATION_AUTHORITY_INVALID")
    if reconciliation.get("mode") != _EVIDENCE_LEDGER_RECONCILIATION_MODE:
        raise ContractValidationError("EVIDENCE_RECONCILIATION_MODE_INVALID")

    constraints = reconciliation.get("constraints")
    required_constraints = {
        "quarantine_exact_paths_only": True,
        "git_blob_pin_required": True,
        "quarantined_file_must_remain_present": True,
        "quarantined_file_must_have_single_add_commit": True,
        "wildcard_paths_forbidden": True,
        "canonical_evidence_map_schema_unchanged": True,
        "future_unlisted_evidence_is_authoritative": True,
    }
    if constraints != required_constraints:
        raise ContractValidationError("EVIDENCE_RECONCILIATION_CONSTRAINTS_INVALID")

    records = reconciliation.get("quarantined_evidence")
    if not isinstance(records, list) or not records:
        raise ContractValidationError("EVIDENCE_RECONCILIATION_QUARANTINE_EMPTY")

    raw_by_resolved = {path.resolve(): path for path in raw_paths}
    quarantined_paths: set[Path] = set()
    for item in records:
        if not isinstance(item, dict) or set(item) != {"path", "git_blob_sha", "reason"}:
            raise ContractValidationError("EVIDENCE_RECONCILIATION_RECORD_INVALID")
        relative = item.get("path")
        blob_pin = item.get("git_blob_sha")
        reason = item.get("reason")
        if (
            not isinstance(relative, str)
            or not relative
            or any(marker in relative for marker in ("*", "?", "["))
            or not isinstance(blob_pin, str)
            or not re.fullmatch(r"[0-9a-f]{40}", blob_pin)
            or not isinstance(reason, str)
            or not reason
        ):
            raise ContractValidationError("EVIDENCE_RECONCILIATION_RECORD_INVALID")

        candidate = (bundle.root / relative).resolve()
        if candidate.parent != evidence_dir.resolve() or candidate not in raw_by_resolved:
            raise ContractValidationError(f"EVIDENCE_RECONCILIATION_PATH_INVALID:{relative}")
        if candidate in quarantined_paths:
            raise ContractValidationError(f"EVIDENCE_RECONCILIATION_PATH_DUPLICATE:{relative}")

        code, observed_blob = _git(bundle.root, "rev-parse", f"HEAD:{relative}")
        if code != 0 or observed_blob != blob_pin:
            raise ContractValidationError(f"EVIDENCE_RECONCILIATION_BLOB_MISMATCH:{relative}")

        code, history = _git(bundle.root, "log", "--format=%H", "--", relative)
        commits = [line for line in history.splitlines() if line]
        if code != 0 or len(commits) != 1:
            raise ContractValidationError(f"EVIDENCE_RECONCILIATION_IMMUTABILITY_NOT_PROVEN:{relative}")
        code, add_commit = _git(
            bundle.root, "log", "--diff-filter=A", "-1", "--format=%H", "--", relative
        )
        if code != 0 or add_commit != commits[0]:
            raise ContractValidationError(f"EVIDENCE_RECONCILIATION_ADD_COMMIT_NOT_PROVEN:{relative}")

        value = read_json(candidate)
        if value.get("schema") != _EVIDENCE_MAP_SCHEMA:
            raise ContractValidationError(f"EVIDENCE_RECONCILIATION_SCHEMA_MISUSE_NOT_PRESENT:{relative}")
        quarantined_paths.add(candidate)

    return [path for path in raw_paths if path.resolve() not in quarantined_paths]


def _select_authoritative_human_attention_paths(
    bundle: ContractBundle,
    execution_dir: Path,
    work_order_id: str,
) -> list[Path]:
    """Return active-attention candidates after exact-pinned resolved legacy quarantine."""

    attention_dir = execution_dir / "human-attention"
    raw_paths = _json_files(attention_dir)
    manifest_path = execution_dir / "human-attention-ledger-reconciliation.v1.json"
    if not manifest_path.exists():
        return raw_paths

    reconciliation = read_json(manifest_path)
    if reconciliation.get("schema") != _HUMAN_ATTENTION_LEDGER_RECONCILIATION_SCHEMA:
        raise ContractValidationError("HUMAN_ATTENTION_RECONCILIATION_SCHEMA_INVALID")
    if reconciliation.get("version") != 1:
        raise ContractValidationError("HUMAN_ATTENTION_RECONCILIATION_VERSION_INVALID")
    if reconciliation.get("project_epoch") != execution_dir.name:
        raise ContractValidationError("HUMAN_ATTENTION_RECONCILIATION_EPOCH_MISMATCH")
    if reconciliation.get("work_order_id") != work_order_id:
        raise ContractValidationError("HUMAN_ATTENTION_RECONCILIATION_WORK_ORDER_MISMATCH")
    if reconciliation.get("authority") != _HUMAN_ATTENTION_LEDGER_RECONCILIATION_AUTHORITY:
        raise ContractValidationError("HUMAN_ATTENTION_RECONCILIATION_AUTHORITY_INVALID")
    if reconciliation.get("mode") != _HUMAN_ATTENTION_LEDGER_RECONCILIATION_MODE:
        raise ContractValidationError("HUMAN_ATTENTION_RECONCILIATION_MODE_INVALID")

    required_constraints = {
        "quarantine_exact_paths_only": True,
        "git_blob_pin_required": True,
        "quarantined_file_must_remain_present": True,
        "full_git_history_pin_required": True,
        "add_commit_must_be_oldest_pinned_history_commit": True,
        "wildcard_paths_forbidden": True,
        "current_human_attention_schema_unchanged": True,
        "only_resolved_items_may_be_quarantined": True,
        "future_unlisted_attention_is_authoritative": True,
    }
    if reconciliation.get("constraints") != required_constraints:
        raise ContractValidationError("HUMAN_ATTENTION_RECONCILIATION_CONSTRAINTS_INVALID")

    records = reconciliation.get("quarantined_items")
    if not isinstance(records, list) or not records:
        raise ContractValidationError("HUMAN_ATTENTION_RECONCILIATION_QUARANTINE_EMPTY")

    raw_by_resolved = {path.resolve(): path for path in raw_paths}
    quarantined: set[Path] = set()
    for item in records:
        if not isinstance(item, dict) or set(item) != {"path", "git_blob_sha", "git_history_commits", "reason"}:
            raise ContractValidationError("HUMAN_ATTENTION_RECONCILIATION_RECORD_INVALID")
        relative = item.get("path")
        blob_pin = item.get("git_blob_sha")
        history_pin = item.get("git_history_commits")
        reason = item.get("reason")
        if (
            not isinstance(relative, str)
            or not relative
            or any(marker in relative for marker in ("*", "?", "["))
            or not isinstance(blob_pin, str)
            or not re.fullmatch(r"[0-9a-f]{40}", blob_pin)
            or not isinstance(history_pin, list)
            or not history_pin
            or any(not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40}", commit) for commit in history_pin)
            or not isinstance(reason, str)
            or not reason
        ):
            raise ContractValidationError("HUMAN_ATTENTION_RECONCILIATION_RECORD_INVALID")

        candidate = (bundle.root / relative).resolve()
        if candidate.parent != attention_dir.resolve() or candidate not in raw_by_resolved:
            raise ContractValidationError(f"HUMAN_ATTENTION_RECONCILIATION_PATH_INVALID:{relative}")
        if candidate in quarantined:
            raise ContractValidationError(f"HUMAN_ATTENTION_RECONCILIATION_PATH_DUPLICATE:{relative}")

        code, observed_blob = _git(bundle.root, "rev-parse", f"HEAD:{relative}")
        if code != 0 or observed_blob != blob_pin:
            raise ContractValidationError(f"HUMAN_ATTENTION_RECONCILIATION_BLOB_MISMATCH:{relative}")
        code, history = _git(bundle.root, "log", "--format=%H", "--", relative)
        commits = [line for line in history.splitlines() if line]
        if code != 0 or commits != history_pin:
            raise ContractValidationError(f"HUMAN_ATTENTION_RECONCILIATION_HISTORY_MISMATCH:{relative}")
        code, add_commit = _git(
            bundle.root, "log", "--diff-filter=A", "-1", "--format=%H", "--", relative
        )
        if code != 0 or add_commit != history_pin[-1]:
            raise ContractValidationError(f"HUMAN_ATTENTION_RECONCILIATION_ADD_COMMIT_NOT_PROVEN:{relative}")

        value = read_json(candidate)
        if value.get("schema") != "distributed_world_simulator.harness_human_attention.v1":
            raise ContractValidationError(f"HUMAN_ATTENTION_RECONCILIATION_SCHEMA_MISUSE_NOT_PRESENT:{relative}")
        if value.get("status") != "RESOLVED":
            raise ContractValidationError(f"HUMAN_ATTENTION_RECONCILIATION_OPEN_ITEM_FORBIDDEN:{relative}")
        quarantined.add(candidate)

    return [path for path in raw_paths if path.resolve() not in quarantined]


def _load_evidence_maps(
    bundle: ContractBundle,
    evidence_dir: Path,
    work_order_id: str | None = None,
) -> list[dict[str, Any]]:
    """Validate every Evidence Map claim, then optionally select one Work Order.

    Supporting evidence may share the directory, but it cannot enter checkpoint
    authorization. A malformed or ambiguous Evidence Map claim still fails
    closed before Work Order filtering.
    """
    evidence_maps: list[dict[str, Any]] = []
    for path in _select_authoritative_evidence_paths(bundle, evidence_dir, work_order_id):
        value = read_json(path)
        schema_identity = value.get("schema")
        if schema_identity == _EVIDENCE_MAP_SCHEMA:
            bundle.validate("evidence_map_schema", value, f"evidence:{path.name}")
            evidence_maps.append(value)
        elif not isinstance(schema_identity, str) or not schema_identity:
            raise ContractValidationError(f"EVIDENCE_SCHEMA_IDENTITY_REQUIRED:{path.name}")
        elif schema_identity.startswith(_EVIDENCE_MAP_SCHEMA_PREFIX):
            raise ContractValidationError(f"EVIDENCE_MAP_SCHEMA_AMBIGUOUS:{path.name}")
    if work_order_id is None:
        return evidence_maps
    return [item for item in evidence_maps if item["work_order_id"] == work_order_id]


def build_state(root: Path, execution_dir: Path) -> dict[str, Any]:
    execution_dir = execution_dir.resolve()
    _repo_relative(root, execution_dir)

    bundle = ContractBundle.load(root)
    epoch = read_json(execution_dir / "project-epoch.v1.json")
    bundle.validate("project_epoch_schema", epoch, "project_epoch")
    transition_table = read_json(execution_dir / "transition-table.v1.json")
    if transition_table.get("schema") != "distributed_world_simulator.harness_transition_table.v1":
        raise ContractValidationError("TRANSITION_TABLE_INVALID")

    work_orders: list[dict[str, Any]] = []
    guard_context = load_guard_context(root, execution_dir)
    for path in _json_files(execution_dir / "work-orders"):
        work_order = read_json(path)
        bundle.validate("work_order_schema", work_order, f"work_order:{path.name}")
        _validate_semantics(bundle, epoch, work_order)
        event_dir = execution_dir / "events" / work_order["work_order_id"]
        raw_event_paths = _json_files(event_dir)
        event_paths, reconciliation = _select_authoritative_event_paths(
            root,
            execution_dir,
            work_order,
            event_dir,
            raw_event_paths,
        )
        events = [read_json(event) for event in event_paths]
        work_orders.append(
            {
                "definition": work_order,
                "events": events,
                "event_paths": event_paths,
                "event_ledger_reconciliation": reconciliation,
                "reduced": reduce_events(
                    bundle,
                    work_order,
                    events,
                    transition_table,
                    guard_context,
                ),
                "event_dir": event_dir,
            }
        )
    if not work_orders:
        raise ContractValidationError("WORK_ORDER_REQUIRED")

    active = work_orders[-1]
    active_id = active["definition"]["work_order_id"]

    evidence = _load_evidence_maps(bundle, execution_dir / "evidence", active_id)
    reviews = _load_reviews(root, execution_dir, active["definition"])

    attention: list[dict[str, Any]] = []
    for path in _select_authoritative_human_attention_paths(
        bundle, execution_dir, active_id
    ):
        value = read_json(path)
        bundle.validate("human_attention_schema", value, f"human_attention:{path.name}")
        attention.append(value)

    for item in evidence:
        if (
            item["work_order_id"] != active_id
            or item["checkpoint"] != active["definition"]["goal_checkpoint"]
            or item["risk_class"] != active["definition"]["risk_class"]
        ):
            raise ContractValidationError("EVIDENCE_IDENTITY_MISMATCH")

    repair_map = _validate_repair_map(
        bundle,
        execution_dir,
        active_id,
        active["events"][-1].get("evidence_paths", []),
    )

    canonical_branch = bundle.contracts["harness_policy"]["canonical_branch"]
    current_head = _git_head(root)
    implementation_head = _git_implementation_head(root, execution_dir, active["definition"])
    ledger_head = _validate_event_git_provenance(
        root,
        active["event_paths"],
        active["events"],
        current_head,
    )
    exact_audit = _select_epoch_audit(guard_context, active["events"])
    epoch_validation = validate_epoch(
        root,
        epoch,
        canonical_branch,
        exact_audit,
    )

    if not active["reduced"]["snapshot_matches_authoritative_state"]:
        raise ContractValidationError("WORK_ORDER_SNAPSHOT_STATE_MISMATCH")

    findings: list[str] = []
    if epoch_validation["status"] == "MAIN_MOVED_REVIEW_REQUIRED":
        findings.append("MAIN_MOVED_REVIEW_REQUIRED")
    if epoch_validation["status"] == "EPOCH_INVALIDATED":
        findings.append("EPOCH_INVALIDATED")
    if active["reduced"]["state"] == "FIX_REQUIRED" and repair_map is None:
        findings.append("REPAIR_MAP_REQUIRED")

    blocking_attention = [
        item
        for item in attention
        if item["status"] == "OPEN" and item.get("blocking", False)
    ]
    decision_ids: set[str] = set()
    for item in attention:
        if item["decision_id"] in decision_ids:
            raise ContractValidationError("HUMAN_ATTENTION_ID_NOT_UNIQUE")
        decision_ids.add(item["decision_id"])
        if (
            item["program"] != active["definition"]["program"]
            or item["checkpoint"] != active["definition"]["goal_checkpoint"]
            or item["risk_class"] != active["definition"]["risk_class"]
        ):
            raise ContractValidationError("HUMAN_ATTENTION_IDENTITY_MISMATCH")
    if blocking_attention:
        findings.append("BLOCKING_HUMAN_ATTENTION")

    current_branch = _git_branch(root)
    if current_branch != active["definition"]["branch"]:
        findings.append("WORK_ORDER_BRANCH_NOT_CHECKED_OUT")

    pre_build_reviews = [
        item
        for item in reviews
        if item.get("review_type") == "PRE_BUILD_DESIGN_AUTHORIZATION"
    ]
    post_build_reviews = [
        item
        for item in reviews
        if item.get("review_type") != "PRE_BUILD_DESIGN_AUTHORIZATION"
    ]
    pre_build_state = pre_build_reviews[-1]["verdict"] if pre_build_reviews else "MISSING"
    post_build_state = "MISSING"
    if post_build_reviews:
        latest_review = post_build_reviews[-1]
        post_build_state = (
            latest_review["verdict"]
            if latest_review["reviewed_head_sha"] == implementation_head
            else "STALE"
        )
    review_state = "READY" if post_build_state == "PASS" else "PENDING_POST_BUILD_REVIEW"

    if evidence and evidence[-1]["evidence_head_sha"] != implementation_head:
        findings.append("EVIDENCE_HEAD_STALE")

    required_predicates = active["definition"]["required_predicates"]
    missing_predicates = [
        item
        for item in required_predicates
        if item not in active["reduced"]["completed_predicates"]
    ]
    checkpoint_blockers: list[str] = []
    if missing_predicates:
        checkpoint_blockers.append("REQUIRED_PREDICATES_INCOMPLETE")
    if post_build_state != "PASS":
        checkpoint_blockers.append("POST_BUILD_REVIEW_NOT_FRESH_PASS")
    if not evidence:
        checkpoint_blockers.append("EVIDENCE_MAP_MISSING")
    elif (
        evidence[-1]["evidence_head_sha"] != implementation_head
        or evidence[-1]["review_verdict"] != "PASS"
    ):
        checkpoint_blockers.append("EVIDENCE_MAP_NOT_FRESH_PASS")
    if blocking_attention:
        checkpoint_blockers.append("BLOCKING_HUMAN_ATTENTION")
    if epoch_validation["action"] != "CONTINUE":
        checkpoint_blockers.append("EPOCH_NOT_CONTINUABLE")

    return {
        "schema": "distributed_world_simulator.control_development_output.v1",
        "source": "GIT_ONLY_WORKER_DATA",
        "repository": {
            "event_subject_head_sha": active["reduced"]["event_subject_head_sha"],
            "event_ledger_head_sha": ledger_head,
            "current_branch_head_sha": current_head,
            "implementation_head_sha": implementation_head,
            "current_branch": current_branch,
            "origin_main_head_sha": epoch_validation["main_sha"],
            "worktree_dirty": bool(
                subprocess.run(
                    ["git", "status", "--porcelain"],
                    cwd=root,
                    text=True,
                    capture_output=True,
                    check=True,
                ).stdout.strip()
            ),
        },
        "contracts_loaded": sorted(bundle.contracts),
        "epoch": {**epoch, "validation": epoch_validation},
        "active_work_order": active["definition"],
        "reduced_work_order": active["reduced"],
        "event_ledger_reconciliation": active.get("event_ledger_reconciliation"),
        "review": {
            "required": active["definition"]["review_required"],
            "roles": active["definition"].get("required_review_roles", []),
            "reviews": reviews,
            "evidence_maps": evidence,
            "state": review_state,
            "pre_build_state": pre_build_state,
            "post_build_state": post_build_state,
            "review_target_head_sha": implementation_head,
        },
        "repair": {
            "map": repair_map,
            "required": active["reduced"]["state"] == "FIX_REQUIRED",
        },
        "human_attention": {
            "open_items": [item for item in attention if item["status"] == "OPEN"],
            "all_items": attention,
        },
        "findings": findings,
        "continuation_blocked": bool(findings)
        or active["reduced"]["state"]
        in {
            "FIX_REQUIRED",
            "BLOCKED",
            "WAITING_HUMAN",
            "EPOCH_INVALIDATED",
            "CANCELLED",
        },
        "checkpoint_proposal_blocked": bool(checkpoint_blockers),
        "checkpoint_blockers": checkpoint_blockers,
        "runtime_authorized": False,
        "verification_commands": [
            "python -m unittest discover -s tests/harness -v",
            ".\\CONTROL_DEVELOPMENT.ps1 -Status",
            ".\\CONTROL_DEVELOPMENT.ps1 -Plan",
            ".\\CONTROL_DEVELOPMENT.ps1 -Resume",
        ],
    }
