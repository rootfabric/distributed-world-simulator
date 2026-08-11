"""Read-only checkpoint planning for the active harness Work Order."""
from __future__ import annotations

from typing import Any


def build_plan(
    contracts: dict[str, dict[str, Any]],
    work_order: dict[str, Any],
    reduced: dict[str, Any],
) -> dict[str, Any]:
    scheduler = contracts["scheduler_policy"]
    override = scheduler["current_pilot_override"]
    current = work_order["goal_checkpoint"]
    required = contracts["checkpoint_catalog"]["checkpoints"][current]["required_predicates"]
    satisfied = set(reduced["completed_predicates"])

    if current == "H0_0_SCAFFOLD_READY":
        return {
            "mode": "DRY_RUN_ONLY",
            "selected_checkpoint": current,
            "pilot_override": {"enabled": override["enabled"], "checkpoint_sequence": override["checkpoint_sequence"], "reason": override["reason"]},
            "active_work_order": reduced["work_order_id"],
            "satisfied_predicates": [item for item in required if item in satisfied],
            "unsatisfied_predicates": [item for item in required if item not in satisfied],
            "autonomous_runtime_workers": scheduler["concurrency"]["h0_0_max_autonomous_runtime_workers"],
            "c22_dry_run": {
                "requested_checkpoint": "H0_1_CLOSED_LOOP_C22_PILOT",
                "status": "BLOCKED",
                "reason": "H0_0_SCAFFOLD_READY_REQUIRED",
                "branch_creation": "FORBIDDEN",
            },
            "next_action": "IMPLEMENT_OR_REVIEW_H0_0_CONTROL_SCAFFOLD",
            "stop_gates": ["AUTONOMOUS_RUNTIME_BRANCH_CREATION", "CONTROL_DOCS_ONLY_MERGE"],
        }

    if current == "H0_1_CLOSED_LOOP_C22_PILOT":
        dispatched = reduced["state"] in {"DISPATCHED", "IN_PROGRESS", "IMPLEMENTED", "VERIFYING", "VERIFIED", "AUDITED"}
        return {
            "mode": "PLANNING_ONLY" if not dispatched else "SINGLE_RUNTIME_PILOT",
            "selected_checkpoint": current,
            "pilot_override": {"enabled": override["enabled"], "checkpoint_sequence": override["checkpoint_sequence"], "reason": override["reason"]},
            "active_work_order": reduced["work_order_id"],
            "satisfied_predicates": [item for item in required if item in satisfied],
            "unsatisfied_predicates": [item for item in required if item not in satisfied],
            "autonomous_runtime_workers": scheduler["concurrency"]["h0_1_max_autonomous_runtime_workers"] if dispatched else 0,
            "c22_dry_run": {
                "requested_checkpoint": "H0_1_CLOSED_LOOP_C22_PILOT",
                "status": "READY_FOR_FRESH_BRANCH" if dispatched else "WAITING_DIRECTOR_DISPATCH",
                "reason": "DIRECTOR_DISPATCHED_H0_1" if dispatched else "H0_1_PLANNING_WORK_ORDER_NOT_DISPATCHED",
                "branch_creation": "AUTHORIZED_BY_DISPATCH" if dispatched else "FORBIDDEN_UNTIL_DISPATCH",
            },
            "next_action": "CREATE_FRESH_CURRENT_MAIN_C22_CHILD_WORK_ORDER" if dispatched else "POST_MERGE_AUDIT_THEN_DIRECTOR_DISPATCH_H0_1",
            "stop_gates": ["C22_RUNTIME_BRANCH_CREATION_BEFORE_DISPATCH", "C22_RUNTIME_MERGE", "TS0_4_START"],
        }

    raise ValueError(f"UNSUPPORTED_CHECKPOINT:{current}")
