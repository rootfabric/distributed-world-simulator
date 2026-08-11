"""Read-only checkpoint selection with the mandatory H0.0 pilot override."""
from __future__ import annotations

from typing import Any


def build_plan(contracts: dict[str, dict[str, Any]], reduced: dict[str, Any]) -> dict[str, Any]:
    scheduler = contracts["scheduler_policy"]
    override = scheduler["current_pilot_override"]
    current = override["current_checkpoint"]
    target = reduced["work_order_id"]
    # The scheduler's current checkpoint names the H0.0 target; it is not a
    # main-owned declaration that the target has been accepted. H0.0 must
    # therefore never make C22 eligible by itself.
    required = contracts["checkpoint_catalog"]["checkpoints"][current]["required_predicates"]
    satisfied = set(reduced["completed_predicates"])
    return {
        "mode": "DRY_RUN_ONLY",
        "selected_checkpoint": current,
        "pilot_override": {"enabled": override["enabled"], "checkpoint_sequence": override["checkpoint_sequence"],
                           "reason": override["reason"]},
        "active_work_order": target,
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
