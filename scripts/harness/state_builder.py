"""Build complete H0.0 status using only versioned JSON and Git metadata."""
from __future__ import annotations

import subprocess
import re
from datetime import datetime
from pathlib import Path
from typing import Any

from .contracts import ContractBundle, ContractValidationError, read_json
from .epoch_validator import validate_epoch
from .event_reducer import load_guard_context, reduce_events


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


def _git_path_head(root: Path, path: Path) -> str:
    relative = path.resolve().relative_to(root.resolve()).as_posix()
    output = subprocess.run(["git", "log", "-1", "--format=%H", "--", relative], cwd=root, text=True, capture_output=True, check=False)
    value = output.stdout.strip()
    if len(value) != 40:
        raise ContractValidationError(f"EVENT_LEDGER_HEAD_UNAVAILABLE:{path.as_posix()}")
    return value


def _git(root: Path, *args: str) -> tuple[int, str]:
    output = subprocess.run(["git", *args], cwd=root, text=True, capture_output=True, check=False)
    return output.returncode, output.stdout.strip()


def _validate_event_git_provenance(root: Path, event_paths: list[Path], events: list[dict[str, Any]], current_head: str) -> str:
    if len(event_paths) != len(events):
        raise ContractValidationError("EVENT_PATH_COUNT_MISMATCH")
    latest_add = ""
    for path, event in zip(event_paths, events):
        relative = path.resolve().relative_to(root.resolve()).as_posix()
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
    event_dir = event_paths[0].parent.resolve().relative_to(root.resolve()).as_posix()
    code, deleted = _git(root, "log", "--diff-filter=D", "--name-only", "--format=", "--", event_dir)
    if code != 0 or deleted.strip():
        raise ContractValidationError("EVENT_LEDGER_DELETION_DETECTED")
    return latest_add


def _json_files(directory: Path) -> list[Path]:
    return sorted(directory.rglob("*.json")) if directory.exists() else []


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
        missing = [field for field in bundle.contracts["review_policy"]["pre_build"]["design_brief_fields"] if not brief.get(field)]
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


def _validate_repair_map(bundle: ContractBundle, execution_dir: Path, work_order_id: str, evidence_paths: list[str]) -> dict[str, Any] | None:
    candidates: list[tuple[str, dict[str, Any]]] = []
    for path in _json_files(execution_dir / "repairs"):
        value = read_json(path)
        if value.get("schema") == "distributed_world_simulator.harness_repair_map.v1" and value.get("work_order_id") == work_order_id:
            relative = path.resolve().relative_to(bundle.root.resolve()).as_posix()
            candidates.append((relative, value))
    if not candidates:
        return None
    referenced = [value for relative, value in candidates if relative in {item.replace("\\", "/") for item in evidence_paths}]
    latest = referenced[-1] if referenced else candidates[-1][1]
    missing = [field for field in bundle.contracts["repair_doctrine"]["repair_map_fields"] if not latest.get(field)]
    if missing:
        raise ContractValidationError(f"REPAIR_MAP_FIELD_MISSING:{','.join(missing)}")
    return latest


def _load_reviews(root: Path, execution_dir: Path, work_order: dict[str, Any]) -> list[dict[str, Any]]:
    reviews = []
    review_ids: set[str] = set()
    required = {"schema", "review_id", "review_type", "work_order_id", "risk_class", "reviewed_head_sha", "reviewer", "verdict", "reviewed_at_utc", "required_fixes", "rank_up_moves", "evidence_gaps", "risk_assessment"}
    for path in _json_files(execution_dir / "reviews"):
        value = read_json(path)
        if value.get("schema") != "distributed_world_simulator.harness_review_result.v1" or required - value.keys():
            raise ContractValidationError(f"REVIEW_RESULT_INVALID:{path.name}")
        if value["review_id"] in review_ids:
            raise ContractValidationError("REVIEW_ID_NOT_UNIQUE")
        review_ids.add(value["review_id"])
        if value["work_order_id"] != work_order["work_order_id"] or value["risk_class"] != work_order["risk_class"]:
            raise ContractValidationError("REVIEW_WORK_ORDER_OR_RISK_MISMATCH")
        if value["verdict"] not in {"PASS", "FAIL", "INSUFFICIENT_EVIDENCE"}:
            raise ContractValidationError("REVIEW_VERDICT_INVALID")
        if value["review_type"] not in {"PRE_BUILD_DESIGN_AUTHORIZATION", "POST_BUILD_IMPLEMENTATION_REVIEW", "POST_BUILD_EXACT_HEAD_REVIEW"}:
            raise ContractValidationError("REVIEW_TYPE_INVALID")
        if not re.fullmatch(r"[0-9a-f]{40}", value["reviewed_head_sha"]):
            raise ContractValidationError("REVIEW_HEAD_SHA_INVALID")
        if "IMPLEMENTER" in value["reviewer"].upper() or not value["reviewer"].strip():
            raise ContractValidationError("REVIEWER_INDEPENDENCE_INVALID")
        if any(not isinstance(value[field], list) or any(not isinstance(item, str) for item in value[field]) for field in ("required_fixes", "rank_up_moves", "evidence_gaps")):
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
        reviews.append(value)
    return reviews


def build_state(root: Path, execution_dir: Path) -> dict[str, Any]:
    bundle = ContractBundle.load(root)
    epoch = read_json(execution_dir / "project-epoch.v1.json")
    bundle.validate("project_epoch_schema", epoch, "project_epoch")
    transition_table = read_json(execution_dir / "transition-table.v1.json")
    if transition_table.get("schema") != "distributed_world_simulator.harness_transition_table.v1":
        raise ContractValidationError("TRANSITION_TABLE_INVALID")
    work_orders = []
    guard_context = load_guard_context(root, execution_dir)
    for path in _json_files(execution_dir / "work-orders"):
        work_order = read_json(path)
        bundle.validate("work_order_schema", work_order, f"work_order:{path.name}")
        _validate_semantics(bundle, epoch, work_order)
        event_dir = execution_dir / "events" / work_order["work_order_id"]
        event_paths = _json_files(event_dir)
        events = [read_json(event) for event in event_paths]
        work_orders.append({"definition": work_order, "events": events, "event_paths": event_paths,
                            "reduced": reduce_events(bundle, work_order, events, transition_table, guard_context), "event_dir": event_dir})
    if not work_orders:
        raise ContractValidationError("WORK_ORDER_REQUIRED")
    active = work_orders[-1]
    evidence = []
    for path in _json_files(execution_dir / "evidence"):
        value = read_json(path)
        bundle.validate("evidence_map_schema", value, f"evidence:{path.name}")
        evidence.append(value)
    attention = []
    for path in _json_files(execution_dir / "human-attention"):
        value = read_json(path)
        bundle.validate("human_attention_schema", value, f"human_attention:{path.name}")
        attention.append(value)
    for item in evidence:
        if item["work_order_id"] != active["definition"]["work_order_id"] or item["checkpoint"] != active["definition"]["goal_checkpoint"] or item["risk_class"] != active["definition"]["risk_class"]:
            raise ContractValidationError("EVIDENCE_IDENTITY_MISMATCH")
    reviews = _load_reviews(root, execution_dir, active["definition"])
    repair_map = _validate_repair_map(
        bundle,
        execution_dir,
        active["definition"]["work_order_id"],
        active["events"][-1].get("evidence_paths", []),
    )
    canonical_branch = bundle.contracts["harness_policy"]["canonical_branch"]
    current_head = _git_head(root)
    ledger_head = _validate_event_git_provenance(root, active["event_paths"], active["events"], current_head)
    audits = [item for item in guard_context["documents"].values() if item.get("schema") == "distributed_world_simulator.harness_epoch_audit.v1"]
    exact_audit = audits[-1] if audits else None
    epoch_validation = validate_epoch(root, epoch, canonical_branch, exact_audit)
    snapshot_mismatch = not active["reduced"]["snapshot_matches_authoritative_state"]
    findings = []
    if snapshot_mismatch:
        raise ContractValidationError("WORK_ORDER_SNAPSHOT_STATE_MISMATCH")
    if epoch_validation["status"] == "MAIN_MOVED_REVIEW_REQUIRED":
        findings.append("MAIN_MOVED_REVIEW_REQUIRED")
    if epoch_validation["status"] == "EPOCH_INVALIDATED":
        findings.append("EPOCH_INVALIDATED")
    if active["reduced"]["state"] == "FIX_REQUIRED" and repair_map is None:
        findings.append("REPAIR_MAP_REQUIRED")
    blocking_attention = [item for item in attention if item["status"] == "OPEN" and item.get("blocking", False)]
    decision_ids: set[str] = set()
    for item in attention:
        if item["decision_id"] in decision_ids:
            raise ContractValidationError("HUMAN_ATTENTION_ID_NOT_UNIQUE")
        decision_ids.add(item["decision_id"])
        if item["program"] != active["definition"]["program"] or item["checkpoint"] != active["definition"]["goal_checkpoint"] or item["risk_class"] != active["definition"]["risk_class"]:
            raise ContractValidationError("HUMAN_ATTENTION_IDENTITY_MISMATCH")
    if blocking_attention:
        findings.append("BLOCKING_HUMAN_ATTENTION")
    current_branch = _git_branch(root)
    if current_branch != active["definition"]["branch"]:
        findings.append("WORK_ORDER_BRANCH_NOT_CHECKED_OUT")
    pre_build_reviews = [item for item in reviews if item.get("review_type") == "PRE_BUILD_DESIGN_AUTHORIZATION"]
    post_build_reviews = [item for item in reviews if item.get("review_type") != "PRE_BUILD_DESIGN_AUTHORIZATION"]
    pre_build_state = pre_build_reviews[-1]["verdict"] if pre_build_reviews else "MISSING"
    post_build_state = "MISSING"
    if post_build_reviews:
        latest_review = post_build_reviews[-1]
        post_build_state = latest_review["verdict"] if latest_review["reviewed_head_sha"] == current_head else "STALE"
    review_state = "READY" if post_build_state == "PASS" else "PENDING_POST_BUILD_REVIEW"
    if evidence and evidence[-1]["evidence_head_sha"] != current_head:
        findings.append("EVIDENCE_HEAD_STALE")
    checkpoint_blockers = []
    required_predicates = active["definition"]["required_predicates"]
    missing_predicates = [item for item in required_predicates if item not in active["reduced"]["completed_predicates"]]
    if missing_predicates:
        checkpoint_blockers.append("REQUIRED_PREDICATES_INCOMPLETE")
    if post_build_state != "PASS":
        checkpoint_blockers.append("POST_BUILD_REVIEW_NOT_FRESH_PASS")
    if not evidence:
        checkpoint_blockers.append("EVIDENCE_MAP_MISSING")
    elif evidence[-1]["evidence_head_sha"] != current_head or evidence[-1]["review_verdict"] != "PASS":
        checkpoint_blockers.append("EVIDENCE_MAP_NOT_FRESH_PASS")
    if blocking_attention:
        checkpoint_blockers.append("BLOCKING_HUMAN_ATTENTION")
    if epoch_validation["action"] != "CONTINUE":
        checkpoint_blockers.append("EPOCH_NOT_CONTINUABLE")
    return {
        "schema": "distributed_world_simulator.control_development_output.v1",
        "source": "GIT_ONLY_WORKER_DATA",
        "repository": {"event_subject_head_sha": active["reduced"]["event_subject_head_sha"],
                       "event_ledger_head_sha": ledger_head,
                       "current_branch_head_sha": current_head,
                       "current_branch": current_branch,
                       "origin_main_head_sha": epoch_validation["main_sha"],
                       "worktree_dirty": bool(subprocess.run(["git", "status", "--porcelain"], cwd=root, text=True, capture_output=True, check=True).stdout.strip())},
        "contracts_loaded": sorted(bundle.contracts),
        "epoch": {**epoch, "validation": epoch_validation},
        "active_work_order": active["definition"],
        "reduced_work_order": active["reduced"],
        "review": {"required": active["definition"]["review_required"], "roles": active["definition"].get("required_review_roles", []),
                   "reviews": reviews, "evidence_maps": evidence, "state": review_state,
                   "pre_build_state": pre_build_state, "post_build_state": post_build_state},
        "repair": {"map": repair_map, "required": active["reduced"]["state"] == "FIX_REQUIRED"},
        "human_attention": {"open_items": [item for item in attention if item["status"] == "OPEN"], "all_items": attention},
        "findings": findings,
        "continuation_blocked": bool(findings) or active["reduced"]["state"] in {"FIX_REQUIRED", "BLOCKED", "WAITING_HUMAN", "EPOCH_INVALIDATED", "CANCELLED"},
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
