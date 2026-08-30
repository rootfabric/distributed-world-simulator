"""Read-only checkpoint planning for the active harness Work Order."""
from __future__ import annotations

from typing import Any


_ACTIVE_TRAIN_STATES = {"DISPATCHED", "IN_PROGRESS", "IMPLEMENTED", "VERIFYING", "VERIFIED", "AUDITED"}
_MUTATION_SLOT_STATES = {"DISPATCHED", "IN_PROGRESS"}
_PRODUCT_CHECKPOINTS = {
    "V0_S1_NETWORKED_PLANETARY_OUTPOST",
    "V0_P4_REAL_RESOURCE_CONSTRUCTION",
    "V0_P5_EQUIPMENT_TOOLS",
    "V0_P6_PERSISTENT_SHARED_OUTPOST",
    "V0_P7_BOUNDED_TERRAIN_MUTATION",
}
_PRODUCT_GATE_NAMES = {
    "V0_S1_NETWORKED_PLANETARY_OUTPOST": "v0_s1_gate",
    "V0_P4_REAL_RESOURCE_CONSTRUCTION": "v0_p4_gate",
    "V0_P5_EQUIPMENT_TOOLS": "v0_p5_gate",
    "V0_P6_PERSISTENT_SHARED_OUTPOST": "v0_p6_gate",
    "V0_P7_BOUNDED_TERRAIN_MUTATION": "v0_p7_gate",
}
_PRODUCT_BEGIN_ACTIONS = {
    "V0_S1_NETWORKED_PLANETARY_OUTPOST": "BEGIN_V0_S1_NETWORKED_PLANETARY_OUTPOST_COMPOSITION",
    "V0_P4_REAL_RESOURCE_CONSTRUCTION": "BEGIN_V0_P4_REAL_RESOURCE_CONSTRUCTION",
    "V0_P5_EQUIPMENT_TOOLS": "BEGIN_V0_P5_EQUIPMENT_TOOLS",
    "V0_P6_PERSISTENT_SHARED_OUTPOST": "BEGIN_V0_P6_PERSISTENT_SHARED_OUTPOST",
    "V0_P7_BOUNDED_TERRAIN_MUTATION": "BEGIN_V0_P7_MATTER_PRODUCTION_CONVERGENCE",
}
_PRODUCT_VERIFY_ACTIONS = {
    "V0_S1_NETWORKED_PLANETARY_OUTPOST": "VERIFY_V0_S1_EXACT_HEAD",
    "V0_P4_REAL_RESOURCE_CONSTRUCTION": "VERIFY_V0_P4_EXACT_HEAD",
    "V0_P5_EQUIPMENT_TOOLS": "VERIFY_V0_P5_EXACT_HEAD",
    "V0_P6_PERSISTENT_SHARED_OUTPOST": "VERIFY_V0_P6_EXACT_HEAD",
    "V0_P7_BOUNDED_TERRAIN_MUTATION": "VERIFY_V0_P7_EXACT_HEAD",
}
_PRODUCT_DISPATCH_ACTIONS = {
    "V0_S1_NETWORKED_PLANETARY_OUTPOST": "ISSUE_MAIN_DECLARED_PRODUCT_BASE_V0_S1_WORK_ORDER_AND_DIRECTOR_DISPATCH",
    "V0_P4_REAL_RESOURCE_CONSTRUCTION": "ISSUE_MAIN_DECLARED_PRODUCT_BASE_V0_P4_WORK_ORDER_AND_DIRECTOR_DISPATCH",
    "V0_P5_EQUIPMENT_TOOLS": "DIRECTOR_DISPATCH_ACCEPTED_P4_BASE_V0_P5_WORK_ORDER",
    "V0_P6_PERSISTENT_SHARED_OUTPOST": "DIRECTOR_DISPATCH_ACCEPTED_P5_BASE_V0_P6_WORK_ORDER",
    "V0_P7_BOUNDED_TERRAIN_MUTATION": "DIRECTOR_DISPATCH_ACCEPTED_SM1_BASE_V0_P7_WORK_ORDER",
}


def _worker_count(state: str, limit: int) -> int:
    return limit if state in _MUTATION_SLOT_STATES else 0


def _enforce_runtime_mutation_lease(
    scheduler: dict[str, Any],
    work_order: dict[str, Any],
    state: str,
) -> None:
    lease = scheduler.get("pre_h0_3_runtime_mutation_lease")
    if not isinstance(lease, dict):
        return
    mutating_states = set(lease.get("mutating_states", []))
    if state not in mutating_states:
        return
    if int(lease.get("capacity", 0)) != 1:
        raise ValueError("GLOBAL_MUTATION_SLOT_LEASE_CAPACITY_INVALID")
    holder_checkpoint = str(lease.get("holder_checkpoint", ""))
    current = str(work_order.get("goal_checkpoint", ""))
    if current != holder_checkpoint:
        raise ValueError(f"GLOBAL_MUTATION_SLOT_RESERVED_FOR:{holder_checkpoint}")
    holder_branch = str(lease.get("holder_branch", ""))
    work_order_branch = str(work_order.get("branch", ""))
    if holder_branch and work_order_branch and work_order_branch != holder_branch:
        raise ValueError(f"GLOBAL_MUTATION_SLOT_BRANCH_MISMATCH:{holder_branch}")


def _build_product_plan(
    scheduler: dict[str, Any],
    override: dict[str, Any],
    work_order: dict[str, Any],
    reduced: dict[str, Any],
    required: list[str],
    satisfied: set[str],
) -> dict[str, Any]:
    current = work_order["goal_checkpoint"]
    state = reduced["state"]
    active = state in _ACTIVE_TRAIN_STATES
    mutating = state in _MUTATION_SLOT_STATES
    parallel = scheduler["parallel_product_checkpoints"]
    rules = parallel["rules"]
    lease = scheduler.get("pre_h0_3_runtime_mutation_lease", {})
    gate_name = _PRODUCT_GATE_NAMES[current]
    gate = {
        "requested_checkpoint": current,
        "risk_floor": "CRITICAL" if current == "V0_P7_BOUNDED_TERRAIN_MUTATION" else "HIGH",
        "network_baseline": "SERVER_PREDICTED",
        "status": "READY_FOR_BOUNDED_PRODUCT_IMPLEMENTATION" if mutating else ("VERIFYING_PRODUCT_HEAD" if active else "WAITING_DIRECTOR_DISPATCH"),
        "runtime_mutation": "AUTHORIZED_BY_DISPATCH" if mutating else ("NO_ACTIVE_MUTATION_SLOT" if active else "FORBIDDEN_UNTIL_DISPATCH"),
        "control_epoch_anchor": "CURRENT_MAIN",
        "runtime_execution_base": "MAIN_DECLARED_V0_PRODUCT_LINEAGE",
        "requires_main_declared_product_execution_base": rules["requires_main_declared_product_execution_base"],
        "stacked_product_lineage_allowed": rules["runtime_branch_may_continue_from_main_declared_stacked_product_lineage"],
        "bounded_implementation_may_proceed_with_prior_acceptance_debt": rules["bounded_implementation_may_proceed_with_prior_acceptance_debt"],
        "checkpoint_acceptance_requires_prior_acceptance_debt_resolved": rules["checkpoint_acceptance_requires_prior_acceptance_debt_resolved"],
        "pre_h0_3_total_mutation_workers_max": rules["pre_h0_3_total_runtime_mutation_workers_max"],
        "global_mutation_lease_holder_checkpoint": lease.get("holder_checkpoint"),
        "global_mutation_lease_holder_branch": lease.get("holder_branch"),
        "global_mutation_lease_state": lease.get("state"),
        "nx_verification_review_only_may_coexist": rules["verification_or_review_only_work_does_not_consume_mutation_worker_slot"],
        "v0_plus_nx_or_sm0_fix_mutation_forbidden": rules["v0_mutation_plus_nx_or_sm0_nontrivial_fix_mutation_forbidden"],
        "network_foundation_change_fails_closed_to": rules["v0_network_foundation_change_fails_closed_to"],
    }
    if current == "V0_P5_EQUIPMENT_TOOLS":
        routing = scheduler.get("v0_product_train_routing", {})
        gate.update(
            {
                "accepted_predecessor_checkpoint": routing.get("accepted_predecessor_checkpoint"),
                "accepted_predecessor_base": routing.get("accepted_predecessor_base"),
                "equipment_truth": "CANONICAL_ITEM_GRAPH_RELATION_NOT_PRIVATE_INVENTORY",
                "director_dispatch_required": True,
            }
        )
    if current == "V0_P6_PERSISTENT_SHARED_OUTPOST":
        routing = scheduler.get("v0_product_train_routing", {})
        gate.update(
            {
                "accepted_predecessor_checkpoint": routing.get("accepted_predecessor_checkpoint"),
                "accepted_predecessor_base": routing.get("accepted_predecessor_base"),
                "edge_gateway_foundation": "ACCEPTED_TRANSPORT_AND_SESSION_STACK_DONOR_ONLY",
                "persistence_truth": "SINGLE_EXISTING_PERSISTENCE_OWNER_NOT_PRIVATE_SAVE",
                "director_dispatch_required": True,
            }
        )
    if current == "V0_P7_BOUNDED_TERRAIN_MUTATION":
        routing = scheduler.get("v0_product_train_routing", {})
        remaining = list(routing.get("p7_remaining_activation_prerequisites", []))
        gate.update(
            {
                "accepted_predecessor_checkpoint": routing.get("accepted_predecessor_checkpoint"),
                "accepted_predecessor_base": routing.get("accepted_predecessor_base"),
                "matter_truth": "MW4_MW10_EXISTING_CANONICAL_FOUNDATION",
                "item_truth": "CANONICAL_ITEM_GRAPH",
                "multi_region_rule": "MW10_ONLY_FOR_TRUE_MULTI_REGION_MATTER_MUTATION",
                "owner_map_review_required": "P7_MATTER_OWNER_MAP_FRESH_REVIEW_PASS" in remaining,
                "director_dispatch_required": True,
            }
        )
        if mutating and remaining:
            raise ValueError("V0_P7_RUNTIME_DISPATCH_BLOCKED:" + ",".join(remaining))

    return {
        "mode": "PLANNING_ONLY" if not active else ("SINGLE_HIGH_RISK_PRODUCT_SLICE" if mutating else "PRODUCT_RUNTIME_VERIFICATION"),
        "selected_checkpoint": current,
        "pilot_override": {
            "enabled": override["enabled"],
            "current_checkpoint": override["current_checkpoint"],
            "reason": override["reason"],
        },
        "parallel_product_checkpoint": True,
        "active_work_order": reduced["work_order_id"],
        "satisfied_predicates": [item for item in required if item in satisfied],
        "unsatisfied_predicates": [item for item in required if item not in satisfied],
        "autonomous_runtime_workers": _worker_count(
            state,
            scheduler["concurrency"]["v0_product_max_autonomous_runtime_mutation_workers"],
        ),
        gate_name: gate,
        "next_action": (
            _PRODUCT_BEGIN_ACTIONS[current]
            if mutating
            else (_PRODUCT_VERIFY_ACTIONS[current] if active else _PRODUCT_DISPATCH_ACTIONS[current])
        ),
        "stop_gates": [
            "V0_RUNTIME_MUTATION_BEFORE_DISPATCH",
            "PRIVATE_V0_NETWORK_AUTHORITY",
            "PRIVATE_V0_CONSTRUCTION_TRUTH",
            "PRIVATE_V0_ITEM_GRAPH",
            "PRIVATE_V0_EQUIPMENT_TRUTH",
            "PRIVATE_V0_PERSISTENCE_OWNER",
            "PRIVATE_V0_TERRAIN_TRUTH",
            "SECOND_MATTER_FOUNDATION",
            "SECOND_PRE_H0_3_RUNTIME_MUTATION_WORKER",
            "SHIP_FLIGHT",
            "SERVER_HANDOFF",
        ],
    }


def build_plan(
    contracts: dict[str, dict[str, Any]],
    work_order: dict[str, Any],
    reduced: dict[str, Any],
) -> dict[str, Any]:
    scheduler = contracts["scheduler_policy"]
    override = scheduler["current_pilot_override"]
    current = work_order["goal_checkpoint"]
    state = reduced["state"]
    _enforce_runtime_mutation_lease(scheduler, work_order, state)
    catalog = contracts["checkpoint_catalog"]["checkpoints"]
    if current not in catalog:
        raise ValueError(f"UNSUPPORTED_CHECKPOINT:{current}")
    required = catalog[current]["required_predicates"]
    satisfied = set(reduced["completed_predicates"])

    if current == "H0_0_SCAFFOLD_READY":
        return {
            "mode": "DRY_RUN_ONLY",
            "selected_checkpoint": current,
            "pilot_override": {
                "enabled": override["enabled"],
                "checkpoint_sequence": override["checkpoint_sequence"],
                "reason": override["reason"],
            },
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
        active = state in _ACTIVE_TRAIN_STATES
        mutating = state in _MUTATION_SLOT_STATES
        return {
            "mode": "PLANNING_ONLY" if not active else ("SINGLE_RUNTIME_PILOT" if mutating else "RUNTIME_VERIFICATION"),
            "selected_checkpoint": current,
            "pilot_override": {
                "enabled": override["enabled"],
                "checkpoint_sequence": override["checkpoint_sequence"],
                "reason": override["reason"],
            },
            "active_work_order": reduced["work_order_id"],
            "satisfied_predicates": [item for item in required if item in satisfied],
            "unsatisfied_predicates": [item for item in required if item not in satisfied],
            "autonomous_runtime_workers": _worker_count(
                state,
                scheduler["concurrency"]["h0_1_max_autonomous_runtime_workers"],
            ),
            "c22_dry_run": {
                "requested_checkpoint": "H0_1_CLOSED_LOOP_C22_PILOT",
                "status": "READY_FOR_FRESH_BRANCH" if active else "WAITING_DIRECTOR_DISPATCH",
                "reason": "DIRECTOR_DISPATCHED_H0_1" if mutating else ("IMPLEMENTATION_COMPLETE_MUTATION_SLOT_RELEASED_FOR_VERIFICATION" if active else "H0_1_PLANNING_WORK_ORDER_NOT_DISPATCHED"),
                "branch_creation": "AUTHORIZED_BY_DISPATCH" if mutating else ("CURRENT_WORK_ORDER_BRANCH" if active else "FORBIDDEN_UNTIL_DISPATCH"),
            },
            "next_action": "CREATE_FRESH_CURRENT_MAIN_C22_CHILD_WORK_ORDER" if mutating else ("VERIFY_C22_EXACT_HEAD" if active else "POST_MERGE_AUDIT_THEN_DIRECTOR_DISPATCH_H0_1"),
            "stop_gates": ["C22_RUNTIME_BRANCH_CREATION_BEFORE_DISPATCH", "C22_RUNTIME_MERGE", "TS0_4_START"],
        }

    if current == "H0_2_NX_C1_HIGH_RISK_PILOT":
        active = state in _ACTIVE_TRAIN_STATES
        mutating = state in _MUTATION_SLOT_STATES
        return {
            "mode": "PLANNING_ONLY" if not active else ("SINGLE_HIGH_RISK_RUNTIME_PILOT" if mutating else "HIGH_RISK_RUNTIME_VERIFICATION"),
            "selected_checkpoint": current,
            "pilot_override": {
                "enabled": override["enabled"],
                "checkpoint_sequence": override["checkpoint_sequence"],
                "reason": override["reason"],
            },
            "active_work_order": reduced["work_order_id"],
            "satisfied_predicates": [item for item in required if item in satisfied],
            "unsatisfied_predicates": [item for item in required if item not in satisfied],
            "autonomous_runtime_workers": _worker_count(
                state,
                scheduler["concurrency"]["h0_2_max_autonomous_runtime_workers"],
            ),
            "nx_c1_gate": {
                "requested_checkpoint": "H0_2_NX_C1_HIGH_RISK_PILOT",
                "project_checkpoint": "NX_SOURCE_ACCEPTED",
                "risk_floor": "HIGH",
                "status": "READY_FOR_BOUNDED_RUNTIME_IMPLEMENTATION" if mutating else ("VERIFYING_IMPLEMENTED_HEAD" if active else "PLANNING_BRANCH_READY_WAITING_DIRECTOR_DISPATCH"),
                "reason": "DIRECTOR_DISPATCHED_H0_2" if mutating else ("IMPLEMENTATION_COMPLETE_MUTATION_SLOT_RELEASED_FOR_VERIFICATION" if active else "PLANNING_BRANCH_MAY_EXIST_CONTROL_ONLY_RUNTIME_MUTATION_REQUIRES_DISPATCH"),
                "branch_creation": "CURRENT_WORK_ORDER_BRANCH" if active else "PLANNING_BRANCH_ALLOWED_CONTROL_ONLY",
                "runtime_mutation": "AUTHORIZED_BY_DISPATCH" if mutating else ("NO_ACTIVE_MUTATION_SLOT" if active else "FORBIDDEN_UNTIL_DISPATCH"),
                "source_acceptance_requires": "CH_TO_NX_DIRECTIONAL_REVALIDATION_PASS",
            },
            "next_action": "BEGIN_BOUNDED_NX_C1_IMPLEMENTATION_ON_DISPATCHED_BRANCH" if mutating else ("RUN_EXACT_NX_C1_RUNTIME_VERIFICATION" if active else "ISSUE_FRESH_R3_H0_2_NX_C1_WORK_ORDER_AND_DIRECTOR_DISPATCH"),
            "stop_gates": ["NX_C1_RUNTIME_MUTATION_BEFORE_DISPATCH", "NX_C1_RUNTIME_MERGE", "H0_3_IMPLEMENTATION"],
        }

    if current in _PRODUCT_CHECKPOINTS:
        return _build_product_plan(scheduler, override, work_order, reduced, required, satisfied)

    raise ValueError(f"UNSUPPORTED_CHECKPOINT:{current}")
