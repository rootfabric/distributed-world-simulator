"""Append-only event reduction into a durable Work Order state."""
from __future__ import annotations

from datetime import datetime
import json
from pathlib import Path
import subprocess
from typing import Any

from .contracts import ContractBundle, ContractValidationError, read_json


_P4_CHECKPOINT = "V0_P4_REAL_RESOURCE_CONSTRUCTION"
_P4_AUDIT_SCHEMA = "distributed_world_simulator.v0_p4_post_activation_epoch_audit.v1"


def load_guard_context(root: Path, execution_dir: Path) -> dict[str, Any]:
    documents: dict[str, dict[str, Any]] = {}
    for area in ("repairs", "reviews", "evidence", "human-attention", "audits"):
        directory = execution_dir / area
        if not directory.exists():
            continue
        for path in sorted(directory.rglob("*.json")):
            documents[path.resolve().relative_to(root.resolve()).as_posix()] = read_json(path)
    epoch_path = execution_dir / "project-epoch.v1.json"
    epoch = read_json(epoch_path) if epoch_path.exists() else None
    return {"root": root, "execution_dir": execution_dir, "documents": documents, "epoch": epoch}


def _safe_repository_json(context: dict[str, Any], relative: str) -> dict[str, Any] | None:
    normalized = relative.replace("\\", "/")
    root = context["root"].resolve()
    candidate = (root / normalized).resolve()
    try:
        candidate.relative_to(root)
    except ValueError:
        return None
    if candidate.suffix.lower() != ".json" or not candidate.is_file():
        return None
    try:
        value = read_json(candidate)
    except (OSError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None


def _referenced_documents(event: dict[str, Any], context: dict[str, Any] | None) -> list[dict[str, Any]]:
    if context is None:
        return []
    documents = context["documents"]
    referenced: list[dict[str, Any]] = []
    for raw_path in event.get("evidence_paths", []):
        normalized = raw_path.replace("\\", "/")
        document = documents.get(normalized)
        if document is None:
            document = _safe_repository_json(context, normalized)
            if document is not None:
                documents[normalized] = document
        if document is not None:
            referenced.append(document)
    return referenced


def _current_main_sha(context: dict[str, Any] | None) -> str:
    if context is None:
        raise ContractValidationError("GUARDED_INITIAL_DISPATCH_CONTEXT_REQUIRED")
    completed = subprocess.run(
        ["git", "rev-parse", "--verify", "origin/main"],
        cwd=context["root"], text=True, capture_output=True, check=False,
    )
    if completed.returncode != 0:
        raise ContractValidationError("GUARDED_INITIAL_DISPATCH_MAIN_REF_UNAVAILABLE")
    sha = completed.stdout.strip().lower()
    if len(sha) != 40:
        raise ContractValidationError("GUARDED_INITIAL_DISPATCH_MAIN_REF_INVALID")
    return sha


def _lease_applies(bundle: ContractBundle, context: dict[str, Any] | None) -> tuple[bool, dict[str, Any]]:
    lease = bundle.contracts["scheduler_policy"].get("pre_h0_3_runtime_mutation_lease")
    if not isinstance(lease, dict):
        return False, {}
    if context is None or not isinstance(context.get("epoch"), dict):
        raise ContractValidationError("GUARDED_INITIAL_DISPATCH_EPOCH_CONTEXT_REQUIRED")
    generation = int(context["epoch"].get("registry_generation", -1))
    effective = int(lease.get("effective_registry_generation", 10**9))
    return generation >= effective, lease


def _authoritative_p4_audit_present(
    work_order: dict[str, Any],
    event: dict[str, Any],
    documents: list[dict[str, Any]],
    context: dict[str, Any] | None,
) -> bool:
    current_main = _current_main_sha(context)
    for item in documents:
        if item.get("schema") != _P4_AUDIT_SCHEMA:
            continue
        if item.get("decision") != "CONTINUE":
            continue
        if item.get("authoritative_for_dispatch") is not True:
            continue
        if item.get("refs_fetch_performed") is not True:
            continue
        if item.get("checkpoint") != _P4_CHECKPOINT:
            continue
        if str(item.get("p4_head", "")).lower() != event["head_sha"].lower():
            continue
        if str(item.get("canonical_main_head", "")).lower() != current_main:
            continue
        if int(item.get("registry_generation", -1)) < 80:
            continue
        if item.get("production_runtime_mutation_present") is not False:
            continue
        if item.get("director_dispatch_still_required") is not True:
            continue
        if str(work_order.get("branch", "")) != "feature/v0-p4-construction-real-resources":
            continue
        return True
    return False


def _enforce_initial_dispatch(
    bundle: ContractBundle,
    work_order: dict[str, Any],
    event: dict[str, Any],
    documents: list[dict[str, Any]],
    context: dict[str, Any] | None,
) -> None:
    if event.get("actor") != "DIRECTOR":
        raise ContractValidationError("GUARDED_INITIAL_DISPATCH_DIRECTOR_REQUIRED")

    applies, lease = _lease_applies(bundle, context)
    if not applies:
        return
    if int(lease.get("capacity", 0)) != 1:
        raise ContractValidationError("GLOBAL_MUTATION_SLOT_LEASE_CAPACITY_INVALID")
    holder_checkpoint = str(lease.get("holder_checkpoint", ""))
    holder_branch = str(lease.get("holder_branch", ""))
    checkpoint = str(work_order.get("goal_checkpoint", ""))
    branch = str(work_order.get("branch", ""))
    if lease.get("non_holder_dispatch_forbidden") is True and checkpoint != holder_checkpoint:
        raise ContractValidationError(f"GLOBAL_MUTATION_SLOT_RESERVED_FOR:{holder_checkpoint}")
    if checkpoint == holder_checkpoint and holder_branch and branch != holder_branch:
        raise ContractValidationError(f"GLOBAL_MUTATION_SLOT_BRANCH_MISMATCH:{holder_branch}")
    if checkpoint == _P4_CHECKPOINT and lease.get("holder_initial_dispatch_requires_authoritative_epoch_audit") is True:
        if not _authoritative_p4_audit_present(work_order, event, documents, context):
            raise ContractValidationError("GUARDED_P4_INITIAL_DISPATCH_AUDIT_CONTINUE_REQUIRED")


def _is_complete_repair(document: dict[str, Any], bundle: ContractBundle, work_order_id: str) -> bool:
    return (
        document.get("schema") == "distributed_world_simulator.harness_repair_map.v1"
        and document.get("work_order_id") == work_order_id
        and document.get("state") in {"REPAIR_MAP_READY", "FIX_IN_PROGRESS", "FIX_VERIFIED"}
        and all(document.get(field) for field in bundle.contracts["repair_doctrine"]["repair_map_fields"])
    )


def _blocked_resolution_proven(
    bundle: ContractBundle,
    work_order: dict[str, Any],
    event: dict[str, Any],
    previous_event: dict[str, Any] | None,
    documents: list[dict[str, Any]],
    context: dict[str, Any] | None,
) -> bool:
    typed_resolution = any(
        item.get("schema") == "distributed_world_simulator.harness_blocker_resolution.v1"
        and item.get("work_order_id") == work_order["work_order_id"]
        and previous_event is not None
        and item.get("blocker") == previous_event.get("blocker")
        and item.get("status") == "RESOLVED"
        and bool(item.get("resolution"))
        and item.get("resolved_head_sha") == event["head_sha"]
        and item.get("resolved_by") == "DIRECTOR"
        for item in documents
    )
    if typed_resolution:
        return True
    legacy_risk_reclassification = bool(
        previous_event
        and previous_event.get("sequence") == 3
        and previous_event.get("event_type") == "BLOCKED"
        and previous_event.get("blocker") == "HIGH_RISK_RECLASSIFICATION_AND_RECOVERY_SEMANTICS_CLARIFICATION_REQUIRED"
        and event.get("sequence") == 4
        and event.get("predicate") == "H0_0_HIGH_RISK_DESIGN_ACCEPTED"
        and {
            "config/control/harness/risk-policy.v1.json",
            "config/control/harness/review-policy.v1.json",
        }.issubset({path.replace("\\", "/") for path in event.get("evidence_paths", [])})
    )
    if not legacy_risk_reclassification or context is None:
        return False
    work_order_paths = [
        path.replace("\\", "/") for path in event.get("evidence_paths", [])
        if "/work-orders/" in path.replace("\\", "/") and path.endswith(".json")
    ]
    for relative in work_order_paths:
        completed = subprocess.run(
            ["git", "show", f"{event['head_sha']}:{relative}"],
            cwd=context["root"], text=True, capture_output=True, check=False,
        )
        if completed.returncode != 0:
            continue
        try:
            historical = json.loads(completed.stdout)
        except json.JSONDecodeError:
            continue
        if (
            historical.get("schema") == "distributed_world_simulator.work_order.v1"
            and historical.get("work_order_id") == work_order["work_order_id"]
            and historical.get("risk_class") == work_order["risk_class"]
            and historical.get("review_required") is True
            and historical.get("evidence_map_required") is True
            and historical.get("design_brief")
        ):
            return True
    return False


def _enforce_guard(
    bundle: ContractBundle,
    work_order: dict[str, Any],
    previous_state: str,
    event: dict[str, Any],
    ordered: list[dict[str, Any]],
    index: int,
    context: dict[str, Any] | None,
) -> None:
    transition = (previous_state, event["work_state"])
    documents = _referenced_documents(event, context)
    if transition == ("PLANNED", "DISPATCHED"):
        _enforce_initial_dispatch(bundle, work_order, event, documents, context)
    elif transition == ("BLOCKED", "DISPATCHED"):
        previous_event = ordered[index - 1] if index > 0 else None
        if event["actor"] != "DIRECTOR" or not _blocked_resolution_proven(bundle, work_order, event, previous_event, documents, context):
            raise ContractValidationError("GUARDED_BLOCKED_REDISPATCH_EVIDENCE_MISSING")
    elif transition == ("WAITING_HUMAN", "DISPATCHED"):
        resolved = any(
            item.get("schema") == "distributed_world_simulator.harness_human_attention.v1"
            and item.get("status") == "RESOLVED"
            and item.get("resolution")
            for item in documents
        )
        if event["actor"] != "DIRECTOR" or not resolved:
            raise ContractValidationError("GUARDED_HUMAN_REDISPATCH_RESOLUTION_MISSING")
    elif transition == ("FIX_REQUIRED", "DISPATCHED"):
        next_event = ordered[index + 1] if index + 1 < len(ordered) else None
        corrected_premature = (
            next_event is not None
            and next_event["event_type"] == "FIX_REQUIRED"
            and next_event["work_state"] == "FIX_REQUIRED"
            and next_event.get("actor") in {"REVIEWER", "DIRECTOR", "INDEPENDENT_REVIEWER_SOL"}
            and bool(next_event.get("blocker"))
        )
        all_documents = list(context["documents"].values()) if context else []
        direct_repair_ready = any(_is_complete_repair(item, bundle, work_order["work_order_id"]) for item in documents)
        referenced_resolutions = [
            item for item in documents
            if item.get("schema") == "distributed_world_simulator.harness_repair_resolution.v1"
            and item.get("work_order_id") == work_order["work_order_id"]
            and item.get("state") == "FIX_VERIFIED"
            and item.get("reviewed_head_sha") == event["head_sha"]
            and item.get("remaining_required_fixes") == []
        ]
        chained_repair_ready = any(
            resolution.get("repair_id") == repair.get("repair_id")
            and _is_complete_repair(repair, bundle, work_order["work_order_id"])
            for resolution in referenced_resolutions
            for repair in all_documents
        )
        repair_ready = direct_repair_ready or chained_repair_ready
        review_pass = any(
            item.get("schema") == "distributed_world_simulator.harness_review_result.v1"
            and item.get("work_order_id") == work_order["work_order_id"]
            and item.get("verdict") == "PASS"
            and item.get("reviewed_head_sha") == event["head_sha"]
            for item in documents
        )
        if not corrected_premature and not (event["actor"] == "DIRECTOR" and repair_ready and review_pass):
            raise ContractValidationError("GUARDED_FIX_REDISPATCH_EVIDENCE_MISSING")
    elif transition == ("AUDITED", "CHECKPOINT_PROPOSED"):
        evidence_pass = any(
            item.get("schema") == "distributed_world_simulator.harness_evidence_map.v1"
            and item.get("work_order_id") == work_order["work_order_id"]
            and item.get("review_verdict") == "PASS"
            and item.get("pc0") == "NON_RED"
            and item.get("directional_pc0") == "NON_RED"
            and item.get("evidence_head_sha") == event["head_sha"]
            for item in documents
        )
        review_pass = any(
            item.get("schema") == "distributed_world_simulator.harness_review_result.v1"
            and item.get("verdict") == "PASS"
            and item.get("reviewed_head_sha") == event["head_sha"]
            for item in documents
        )
        if event["actor"] != "DIRECTOR" or not evidence_pass or not review_pass:
            raise ContractValidationError("GUARDED_CHECKPOINT_PROPOSAL_EVIDENCE_MISSING")


def reduce_events(bundle: ContractBundle, work_order: dict[str, Any], events: list[dict[str, Any]], transition_table: dict[str, Any], guard_context: dict[str, Any] | None = None) -> dict[str, Any]:
    if not events:
        raise ContractValidationError("EVENT_LEDGER_EMPTY")
    expected_sequence = 1
    state = "NONE"
    completed_predicates: list[str] = []
    observed_predicates: list[str] = []
    open_blocker: str | None = None
    event_ids: set[str] = set()
    for event in events:
        bundle.validate("event_schema", event, f"event:{event.get('event_id', 'unknown')}")
    sequences = [event["sequence"] for event in events]
    if len(sequences) != len(set(sequences)):
        raise ContractValidationError("EVENT_SEQUENCE_NOT_UNIQUE")
    ordered = sorted(events, key=lambda item: item["sequence"])
    previous_time: datetime | None = None
    for index, event in enumerate(ordered):
        if event["sequence"] != expected_sequence:
            raise ContractValidationError(f"EVENT_SEQUENCE_GAP:expected={expected_sequence}:actual={event['sequence']}")
        expected_sequence += 1
        if event["event_id"] in event_ids:
            raise ContractValidationError("EVENT_ID_NOT_UNIQUE")
        event_ids.add(event["event_id"])
        if event["work_order_id"] != work_order["work_order_id"] or event["project_epoch"] != work_order["project_epoch"]:
            raise ContractValidationError("EVENT_WORK_ORDER_OR_EPOCH_MISMATCH")
        if event["branch"] != work_order["branch"]:
            raise ContractValidationError("EVENT_BRANCH_MISMATCH")
        allowed_event_states = transition_table["event_type_states"].get(event["event_type"], [])
        if event["work_state"] not in allowed_event_states:
            raise ContractValidationError("EVENT_TYPE_STATE_PAIR_INVALID")
        if event["work_state"] not in transition_table["allowed_state_transitions"].get(state, []):
            raise ContractValidationError(f"STATE_TRANSITION_INVALID:{state}->{event['work_state']}")
        _enforce_guard(bundle, work_order, state, event, ordered, index, guard_context)
        try:
            recorded = datetime.fromisoformat(event["recorded_at_utc"].replace("Z", "+00:00"))
        except ValueError as exc:
            raise ContractValidationError("EVENT_TIMESTAMP_INVALID") from exc
        if previous_time and recorded < previous_time:
            raise ContractValidationError("EVENT_TIMESTAMP_DECREASES")
        previous_time = recorded
        state = event["work_state"]
        predicate = event.get("predicate")
        if predicate and predicate not in observed_predicates:
            observed_predicates.append(predicate)
        successful_predicate_event = event["event_type"] in {"PREDICATE_VERIFIED", "AUDIT_COMPLETED", "CHECKPOINT_PROPOSED"}
        successful_exit = event.get("exit_code") == 0
        evidence_complete = bool(event.get("command")) and bool(event.get("evidence_paths"))
        if predicate and successful_predicate_event and successful_exit and evidence_complete and predicate not in completed_predicates:
            completed_predicates.append(predicate)
        if event["event_type"] in {"BLOCKED", "FIX_REQUIRED", "WAITING_HUMAN", "EPOCH_INVALIDATED"}:
            open_blocker = event.get("blocker") or event["event_type"]
        elif event["event_type"] in {"DISPATCHED", "IMPLEMENTATION_COMMITTED", "RECOVERY_RESUMED", "PREDICATE_VERIFIED"}:
            open_blocker = None
    return {
        "work_order_id": work_order["work_order_id"],
        "project_epoch": work_order["project_epoch"],
        "state": state,
        "last_event_sequence": expected_sequence - 1,
        "last_completed_predicate": completed_predicates[-1] if completed_predicates else None,
        "completed_predicates": completed_predicates,
        "observed_predicates": observed_predicates,
        "open_blocker": open_blocker,
        "event_subject_head_sha": ordered[-1]["head_sha"],
        "last_event_id": ordered[-1]["event_id"],
        "last_event_type": ordered[-1]["event_type"],
        "snapshot_state": work_order["state"],
        "snapshot_matches_authoritative_state": work_order["state"] == state,
    }
