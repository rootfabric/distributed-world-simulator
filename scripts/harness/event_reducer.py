"""Append-only event reduction into a durable Work Order state."""
from __future__ import annotations

from datetime import datetime
from typing import Any

from .contracts import ContractBundle, ContractValidationError


def reduce_events(bundle: ContractBundle, work_order: dict[str, Any], events: list[dict[str, Any],], transition_table: dict[str, Any]) -> dict[str, Any]:
    if not events:
        raise ContractValidationError("EVENT_LEDGER_EMPTY")
    expected_sequence = 1
    state = "NONE"
    completed_predicates: list[str] = []
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
        try:
            recorded = datetime.fromisoformat(event["recorded_at_utc"].replace("Z", "+00:00"))
        except ValueError as exc:
            raise ContractValidationError("EVENT_TIMESTAMP_INVALID") from exc
        if previous_time and recorded < previous_time:
            raise ContractValidationError("EVENT_TIMESTAMP_DECREASES")
        previous_time = recorded
        if state == "FIX_REQUIRED" and event["work_state"] == "DISPATCHED":
            has_final_review = any("final-resolution" in path or "/reviews/" in path for path in event.get("evidence_paths", []))
            is_corrected_premature_dispatch = index + 1 < len(ordered) and ordered[index + 1]["event_type"] == "FIX_REQUIRED"
            if not has_final_review and not is_corrected_premature_dispatch:
                raise ContractValidationError("GUARDED_REDISPATCH_EVIDENCE_MISSING")
        state = event["work_state"]
        predicate = event.get("predicate")
        if predicate and predicate not in completed_predicates:
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
        "open_blocker": open_blocker,
        "event_subject_head_sha": ordered[-1]["head_sha"],
        "last_event_id": ordered[-1]["event_id"],
        "last_event_type": ordered[-1]["event_type"],
        "snapshot_state": work_order["state"],
        "snapshot_matches_authoritative_state": work_order["state"] == state,
    }
