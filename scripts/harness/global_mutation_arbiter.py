"""Fail-closed arbitration for the main-owned pre-H0.3 runtime mutation lease."""
from __future__ import annotations

import re
from typing import Any


MUTATION_SLOT_STATES = frozenset({"DISPATCHED", "IN_PROGRESS", "IMPLEMENTED"})
PRE_H0_3_CHECKPOINTS = frozenset({
    "H0_2_NX_C1_HIGH_RISK_PILOT",
    "V0_S1_NETWORKED_PLANETARY_OUTPOST",
})


def requires_runtime_mutation_lease(work_order: dict[str, Any], reduced: dict[str, Any]) -> bool:
    return (
        str(work_order.get("goal_checkpoint", "")) in PRE_H0_3_CHECKPOINTS
        and str(reduced.get("state", "")) in MUTATION_SLOT_STATES
    )


def evaluate_pre_h0_3_runtime_mutation_lease(
    registry: dict[str, Any] | None,
    work_order: dict[str, Any],
    reduced: dict[str, Any],
    source_main_sha: str = "",
    checked_out_branch: str = "",
) -> dict[str, Any]:
    """Authorize only the Work Order named by the sole active main lease.

    Verification/review/fix work consumes no mutation slot.  A missing or invalid
    registry cannot authorize a runtime mutation, even if a branch-local copy says
    otherwise.
    """
    work_order_id = str(reduced.get("work_order_id", work_order.get("work_order_id", "UNKNOWN")))
    mutating = requires_runtime_mutation_lease(work_order, reduced)
    result: dict[str, Any] = {
        "authorized": not mutating,
        "status": "NOT_A_RUNTIME_MUTATOR" if not mutating else "PRE_H0_3_RUNTIME_MUTATION_LEASE_REQUIRED",
        "work_order_id": work_order_id,
        "mutating": mutating,
        "source_main_sha": source_main_sha,
        "active_mutation_work_orders": [],
    }
    if not mutating:
        return result
    if not isinstance(registry, dict):
        result["status"] = "PRE_H0_3_RUNTIME_MUTATION_LEASE_REGISTRY_UNAVAILABLE"
        return result
    if str(registry.get("canonical_ref", "")) != "origin/main":
        result["status"] = "PRE_H0_3_RUNTIME_MUTATION_LEASE_REGISTRY_REF_INVALID"
        return result
    registry_issued_sha = str(registry.get("issued_main_sha", ""))
    if not re.fullmatch(r"[0-9a-f]{40}", registry_issued_sha):
        result["status"] = "PRE_H0_3_RUNTIME_MUTATION_LEASE_REGISTRY_ISSUED_SHA_INVALID"
        return result
    reservations = registry.get("reservations")
    if not isinstance(reservations, list):
        result["status"] = "PRE_H0_3_RUNTIME_MUTATION_LEASE_REGISTRY_INVALID"
        return result
    reservation_ids = [str(item.get("reservation_id", "")) for item in reservations if isinstance(item, dict)]
    if len(reservation_ids) != len(reservations) or not all(reservation_ids) or len(set(reservation_ids)) != len(reservation_ids):
        result["status"] = "PRE_H0_3_RUNTIME_MUTATION_LEASE_REGISTRY_RESERVATION_ID_INVALID"
        return result
    active = [item for item in reservations if isinstance(item, dict) and item.get("state") == "ACTIVE"]
    active_ids = sorted(str(item.get("work_order_id", "UNKNOWN")) for item in active)
    result["active_mutation_work_orders"] = active_ids
    if len(active) != int(registry.get("max_active_runtime_mutators", 0)) or len(active) != 1:
        result["status"] = "PRE_H0_3_RUNTIME_MUTATION_LEASE_REGISTRY_INVALID_ACTIVE_COUNT"
        return result
    lease = active[0]
    if str(lease.get("kind", "")) != "RUNTIME_MUTATION" or str(lease.get("issued_by", "")) != "DIRECTOR":
        result["status"] = "PRE_H0_3_RUNTIME_MUTATION_LEASE_INVALID"
        return result
    if not re.fullmatch(r"[0-9a-f]{40}", str(lease.get("issued_main_sha", ""))):
        result["status"] = "PRE_H0_3_RUNTIME_MUTATION_LEASE_ISSUED_SHA_INVALID"
        return result
    if str(lease.get("work_order_id", "")) != work_order_id:
        result["status"] = "PRE_H0_3_RUNTIME_MUTATION_LEASE_HELD_BY_OTHER_WORK_ORDER"
        return result
    if str(lease.get("project_epoch", "")) != str(work_order.get("project_epoch", "")):
        result["status"] = "PRE_H0_3_RUNTIME_MUTATION_LEASE_EPOCH_MISMATCH"
        return result
    if str(lease.get("branch", "")) != str(work_order.get("branch", "")):
        result["status"] = "PRE_H0_3_RUNTIME_MUTATION_LEASE_BRANCH_MISMATCH"
        return result
    if checked_out_branch and str(lease.get("branch", "")) != checked_out_branch:
        result["status"] = "PRE_H0_3_RUNTIME_MUTATION_LEASE_CHECKED_OUT_BRANCH_MISMATCH"
        result["checked_out_branch"] = checked_out_branch
        return result
    if str(lease.get("checkpoint", "")) != str(work_order.get("goal_checkpoint", "")):
        result["status"] = "PRE_H0_3_RUNTIME_MUTATION_LEASE_CHECKPOINT_MISMATCH"
        return result
    result["authorized"] = True
    result["status"] = "PRE_H0_3_RUNTIME_MUTATION_LEASE_HELD_BY_ACTIVE_WORK_ORDER"
    result["reservation_id"] = str(lease.get("reservation_id", ""))
    return result
