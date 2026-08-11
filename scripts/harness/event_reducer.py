"""Append-only event reduction into a durable Work Order state."""
from __future__ import annotations

from datetime import datetime
import json
from pathlib import Path
import subprocess
from typing import Any

from .contracts import ContractBundle, ContractValidationError, read_json


def load_guard_context(root: Path, execution_dir: Path) -> dict[str, Any]:
    documents: dict[str, dict[str, Any]] = {}
    for area in ("repairs", "reviews", "evidence", "human-attention", "audits"):
        directory = execution_dir / area
        if not directory.exists():
            continue
        for path in sorted(directory.rglob("*.json")):
            documents[path.resolve().relative_to(root.resolve()).as_posix()] = read_json(path)
    return {"root": root, "execution_dir": execution_dir, "documents": documents}


def _referenced_documents(event: dict[str, Any], context: dict[str, Any] | None) -> list[dict[str, Any]]:
    if context is None:
        return []
    documents = context["documents"]
    return [documents[path.replace("\\", "/")] for path in event.get("evidence_paths", []) if path.replace("\\", "/") in documents]


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
    documents: list[dict[str, Any]],
    context: dict[str, Any] | None,
) -> bool:
    typed_resolution = any(
        (
            item.get("schema") == "distributed_world_simulator.harness_repair_resolution.v1"
            and item.get("work_order_id") == work_order["work_order_id"]
            and item.get("state") == "FIX_VERIFIED"
        )
        or (
            item.get("schema") == "distributed_world_simulator.harness_review_result.v1"
            and item.get("work_order_id") == work_order["work_order_id"]
            and item.get("verdict") == "PASS"
        )
        for item in documents
    )
    if typed_resolution:
        return True
    if context is None:
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
    if transition == ("BLOCKED", "DISPATCHED"):
        if event["actor"] != "DIRECTOR" or not _blocked_resolution_proven(bundle, work_order, event, documents, context):
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


def reduce_events(bundle: ContractBundle, work_order: dict[str, Any], events: list[dict[str, Any],], transition_table: dict[str, Any], guard_context: dict[str, Any] | None = None) -> dict[str, Any]:
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
