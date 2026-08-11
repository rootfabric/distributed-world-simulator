"""Build complete H0.0 status using only versioned JSON and Git metadata."""
from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Any

from .contracts import ContractBundle, ContractValidationError, read_json
from .epoch_validator import validate_epoch
from .event_reducer import reduce_events


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
        brief = work_order.get("design_brief", {})
        missing = [field for field in bundle.contracts["review_policy"]["pre_build"]["design_brief_fields"] if not brief.get(field)]
        if missing:
            raise ContractValidationError(f"DESIGN_BRIEF_FIELD_MISSING:{','.join(missing)}")
    for collection in (work_order["allowed_paths"], work_order["forbidden_paths"]):
        for raw_path in collection:
            normalized = raw_path.replace("\\", "/")
            if normalized.startswith("/") or ":" in normalized or ".." in normalized.split("/"):
                raise ContractValidationError("SCOPE_PATH_NOT_REPOSITORY_RELATIVE")


def _validate_repair_map(bundle: ContractBundle, execution_dir: Path, work_order_id: str) -> dict[str, Any] | None:
    candidates = []
    for path in _json_files(execution_dir / "repairs"):
        value = read_json(path)
        if value.get("schema") == "distributed_world_simulator.harness_repair_map.v1" and value.get("work_order_id") == work_order_id:
            candidates.append(value)
    if not candidates:
        return None
    latest = candidates[-1]
    missing = [field for field in bundle.contracts["repair_doctrine"]["repair_map_fields"] if not latest.get(field)]
    if missing:
        raise ContractValidationError(f"REPAIR_MAP_FIELD_MISSING:{','.join(missing)}")
    return latest


def _load_reviews(execution_dir: Path, work_order: dict[str, Any]) -> list[dict[str, Any]]:
    reviews = []
    required = {"schema", "work_order_id", "risk_class", "reviewed_head_sha", "reviewer", "verdict", "required_fixes", "rank_up_moves", "evidence_gaps", "risk_assessment"}
    for path in _json_files(execution_dir / "reviews"):
        value = read_json(path)
        if value.get("schema") != "distributed_world_simulator.harness_review_result.v1" or required - value.keys():
            raise ContractValidationError(f"REVIEW_RESULT_INVALID:{path.name}")
        if value["work_order_id"] != work_order["work_order_id"] or value["risk_class"] != work_order["risk_class"]:
            raise ContractValidationError("REVIEW_WORK_ORDER_OR_RISK_MISMATCH")
        if value["verdict"] not in {"PASS", "FAIL", "INSUFFICIENT_EVIDENCE"}:
            raise ContractValidationError("REVIEW_VERDICT_INVALID")
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
    for path in _json_files(execution_dir / "work-orders"):
        work_order = read_json(path)
        bundle.validate("work_order_schema", work_order, f"work_order:{path.name}")
        _validate_semantics(bundle, epoch, work_order)
        event_dir = execution_dir / "events" / work_order["work_order_id"]
        events = [read_json(event) for event in _json_files(event_dir)]
        work_orders.append({"definition": work_order, "reduced": reduce_events(bundle, work_order, events, transition_table), "event_dir": event_dir})
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
    reviews = _load_reviews(execution_dir, active["definition"])
    repair_map = _validate_repair_map(bundle, execution_dir, active["definition"]["work_order_id"])
    canonical_branch = bundle.contracts["harness_policy"]["canonical_branch"]
    audit_continue = any(event.get("event_type") == "AUDIT_COMPLETED" and event.get("work_state") == "AUDITED" for event in [read_json(path) for path in _json_files(active["event_dir"])])
    epoch_validation = validate_epoch(root, epoch, canonical_branch, audit_continue)
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
    if blocking_attention:
        findings.append("BLOCKING_HUMAN_ATTENTION")
    current_head = _git_head(root)
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
    return {
        "schema": "distributed_world_simulator.control_development_output.v1",
        "source": "GIT_ONLY_WORKER_DATA",
        "repository": {"event_subject_head_sha": active["reduced"]["event_subject_head_sha"],
                       "event_ledger_head_sha": _git_path_head(root, active["event_dir"]),
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
        "runtime_authorized": False,
        "verification_commands": [
            "python -m unittest discover -s tests/harness -v",
            ".\\CONTROL_DEVELOPMENT.ps1 -Status",
            ".\\CONTROL_DEVELOPMENT.ps1 -Plan",
            ".\\CONTROL_DEVELOPMENT.ps1 -Resume",
        ],
    }
