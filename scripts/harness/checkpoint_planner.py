"""Read-only checkpoint planning for the active harness Work Order."""
from __future__ import annotations

import fnmatch
from typing import Any


_ACTIVE_TRAIN_STATES = {"DISPATCHED", "IN_PROGRESS", "IMPLEMENTED", "VERIFYING", "VERIFIED", "AUDITED"}
_MUTATION_SLOT_STATES = {"DISPATCHED", "IN_PROGRESS", "IMPLEMENTED"}
_V0_NX_FOUNDATION_PATHS: dict[str, tuple[str, ...]] = {
    "PROTOCOL": (
        "config/network/**",
        "scripts/network/contracts/**",
        "scripts/network/observability/network_protocol_manifest.gd",
        "scripts/network/transports/**",
        "scripts/runtime/networked_gameplay/contracts/**",
    ),
    "AUTHORITY": (
        "scripts/runtime/networked_gameplay/networked_gameplay_service*.gd",
        "scripts/runtime/networked_gameplay/backends/**",
        "scripts/runtime/networked_gameplay/services/player_movement_service.gd",
        "scripts/runtime/networked_gameplay/services/replication_publisher.gd",
        "scripts/runtime/networked_gameplay/transports/**",
    ),
    "OWNERSHIP_EPOCH": (
        "scripts/runtime/networked_gameplay/services/player_ownership_service.gd",
        "scripts/runtime/networked_gameplay/services/player_registry.gd",
        "scripts/runtime/networked_gameplay/contracts/player_ownership_snapshot.gd",
        "scripts/network/session/**",
        "scripts/runtime/networked_gameplay/m6/**",
    ),
    "RECONCILIATION": (
        "scripts/network/prediction/**",
        "scripts/network/interpolation/**",
        "scripts/runtime/networked_gameplay/m3/m3_graphical_client_runtime_nx6.gd",
    ),
    "CHARACTER_OWNERSHIP": (
        "scripts/characters/**",
    ),
}


def _worker_count(state: str, limit: int) -> int:
    return limit if state in _MUTATION_SLOT_STATES else 0


def classify_v0_nx_foundation_scope(work_order: dict[str, Any]) -> dict[str, Any]:
    """Classify V0's actual diff and fail closed on NX-owned foundations.

    Planning may use a declared scope before an implementation exists. Once
    ``implementation_changed_paths`` is supplied by state_builder, it is the
    authoritative input. Late, non-evidence deltas are a separate fail-closed
    input so an out-of-scope runtime commit cannot hide behind the freshness
    implementation head.
    """
    if work_order.get("goal_checkpoint") != "V0_S1_NETWORKED_PLANETARY_OUTPOST":
        return {
            "blocked": False,
            "status": "NOT_V0_S1",
            "matched_paths": [],
            "matched_categories": [],
            "source": "NOT_APPLICABLE",
            "classification_complete": True,
            "late_delta_paths": [],
        }

    has_actual_diff = "implementation_changed_paths" in work_order
    implementation_paths = work_order.get(
        "implementation_changed_paths",
        work_order.get("allowed_paths", []),
    )
    late_delta_paths = work_order.get("late_delta_changed_paths", []) if has_actual_diff else []
    normalized_implementation_paths = {
        str(path).replace("\\", "/") for path in implementation_paths
    }
    normalized_late_delta_paths = {
        str(path).replace("\\", "/") for path in late_delta_paths
    }
    scope_paths = sorted(normalized_implementation_paths | normalized_late_delta_paths)
    matches_by_category = {
        category: sorted(
            path
            for path in scope_paths
            if any(fnmatch.fnmatch(path, pattern) for pattern in patterns)
        )
        for category, patterns in _V0_NX_FOUNDATION_PATHS.items()
    }
    matches_by_category = {
        category: paths for category, paths in matches_by_category.items() if paths
    }
    matched = sorted({path for paths in matches_by_category.values() for path in paths})
    unexpected_late_delta_paths = sorted(
        str(path).replace("\\", "/")
        for path in work_order.get("unexpected_late_delta_paths", [])
    )
    blocked = bool(matched or unexpected_late_delta_paths)
    status = "V0_S1_BLOCKED_REQUIRES_NX" if matched else (
        "V0_S1_BLOCKED_UNCLASSIFIED_LATE_DELTA"
        if unexpected_late_delta_paths
        else "V0_S1_SCOPE_CLASSIFIED_COMPOSITION_ONLY"
    )
    return {
        "blocked": blocked,
        "status": status,
        "matched_paths": matched,
        "matched_categories": sorted(matches_by_category),
        "matches_by_category": matches_by_category,
        "source": "IMPLEMENTATION_GIT_DIFF" if has_actual_diff else "DECLARED_ALLOWED_PATHS",
        "classification_complete": has_actual_diff,
        "late_delta_paths": sorted(normalized_late_delta_paths),
        "unexpected_late_delta_paths": unexpected_late_delta_paths,
    }


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
    state = reduced["state"]

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
        active = state in _ACTIVE_TRAIN_STATES
        return {
            "mode": "PLANNING_ONLY" if not active else ("SINGLE_RUNTIME_PILOT" if state in _MUTATION_SLOT_STATES else "RUNTIME_VERIFICATION"),
            "selected_checkpoint": current,
            "pilot_override": {"enabled": override["enabled"], "checkpoint_sequence": override["checkpoint_sequence"], "reason": override["reason"]},
            "active_work_order": reduced["work_order_id"],
            "satisfied_predicates": [item for item in required if item in satisfied],
            "unsatisfied_predicates": [item for item in required if item not in satisfied],
            "autonomous_runtime_workers": _worker_count(state, scheduler["concurrency"]["h0_1_max_autonomous_runtime_workers"]),
            "c22_dry_run": {
                "requested_checkpoint": "H0_1_CLOSED_LOOP_C22_PILOT",
                "status": "READY_FOR_FRESH_BRANCH" if active else "WAITING_DIRECTOR_DISPATCH",
                "reason": "DIRECTOR_DISPATCHED_H0_1" if active else "H0_1_PLANNING_WORK_ORDER_NOT_DISPATCHED",
                "branch_creation": "AUTHORIZED_BY_DISPATCH" if active else "FORBIDDEN_UNTIL_DISPATCH",
            },
            "next_action": "CREATE_FRESH_CURRENT_MAIN_C22_CHILD_WORK_ORDER" if state in _MUTATION_SLOT_STATES else ("VERIFY_C22_EXACT_HEAD" if active else "POST_MERGE_AUDIT_THEN_DIRECTOR_DISPATCH_H0_1"),
            "stop_gates": ["C22_RUNTIME_BRANCH_CREATION_BEFORE_DISPATCH", "C22_RUNTIME_MERGE", "TS0_4_START"],
        }

    if current == "H0_2_NX_C1_HIGH_RISK_PILOT":
        active = state in _ACTIVE_TRAIN_STATES
        requested_mutation = state in _MUTATION_SLOT_STATES
        mutating = requested_mutation
        global_mutation = work_order.get("global_runtime_mutation_arbiter", {})
        global_mutation_authorized = bool(global_mutation.get("authorized", False))
        if requested_mutation and not global_mutation_authorized:
            mutating = False
        return {
            "mode": "PLANNING_ONLY" if not active else ("SINGLE_HIGH_RISK_RUNTIME_PILOT" if mutating else "HIGH_RISK_RUNTIME_VERIFICATION"),
            "selected_checkpoint": current,
            "pilot_override": {"enabled": override["enabled"], "checkpoint_sequence": override["checkpoint_sequence"], "reason": override["reason"]},
            "active_work_order": reduced["work_order_id"],
            "satisfied_predicates": [item for item in required if item in satisfied],
            "unsatisfied_predicates": [item for item in required if item not in satisfied],
            "autonomous_runtime_workers": scheduler["concurrency"]["h0_2_max_autonomous_runtime_workers"] if mutating else 0,
            "nx_c1_gate": {
                "requested_checkpoint": "H0_2_NX_C1_HIGH_RISK_PILOT",
                "project_checkpoint": "NX_SOURCE_ACCEPTED",
                "risk_floor": "HIGH",
                "status": "READY_FOR_BOUNDED_RUNTIME_IMPLEMENTATION" if mutating else ("VERIFYING_IMPLEMENTED_HEAD" if active else "PLANNING_BRANCH_READY_WAITING_DIRECTOR_DISPATCH"),
                "reason": "DIRECTOR_DISPATCHED_H0_2" if mutating else ("IMPLEMENTATION_COMPLETE_MUTATION_SLOT_RELEASED_FOR_VERIFICATION" if active else "PLANNING_BRANCH_MAY_EXIST_CONTROL_ONLY_RUNTIME_MUTATION_REQUIRES_DISPATCH"),
                "branch_creation": "CURRENT_WORK_ORDER_BRANCH" if active else "PLANNING_BRANCH_ALLOWED_CONTROL_ONLY",
                "runtime_mutation": "AUTHORIZED_BY_MAIN_OWNED_LEASE" if mutating else ("BLOCKED_BY_GLOBAL_MUTATION_LEASE" if requested_mutation else ("NO_ACTIVE_MUTATION_SLOT" if active else "FORBIDDEN_UNTIL_DISPATCH")),
                "global_mutation_arbiter": global_mutation,
                "source_acceptance_requires": "CH_TO_NX_DIRECTIONAL_REVALIDATION_PASS",
            },
            "next_action": "BEGIN_BOUNDED_NX_C1_IMPLEMENTATION_ON_DISPATCHED_BRANCH" if mutating else ("PRE_H0_3_GLOBAL_RUNTIME_MUTATION_LEASE_REQUIRED" if requested_mutation else ("RUN_EXACT_NX_C1_RUNTIME_VERIFICATION" if active else "ISSUE_FRESH_R3_H0_2_NX_C1_WORK_ORDER_AND_DIRECTOR_DISPATCH")),
            "stop_gates": ["NX_C1_RUNTIME_MUTATION_BEFORE_DISPATCH", "NX_C1_RUNTIME_MERGE", "H0_3_IMPLEMENTATION"],
        }

    if current == "V0_S1_NETWORKED_PLANETARY_OUTPOST":
        active = state in _ACTIVE_TRAIN_STATES
        requested_mutation = state in _MUTATION_SLOT_STATES
        mutating = requested_mutation
        parallel = scheduler["parallel_product_checkpoints"]
        rules = parallel["rules"]
        foundation_scope = classify_v0_nx_foundation_scope(work_order)
        global_mutation = work_order.get("global_runtime_mutation_arbiter", {})
        global_mutation_authorized = bool(global_mutation.get("authorized", False))
        if foundation_scope["blocked"] or (requested_mutation and not global_mutation_authorized):
            mutating = False
        return {
            "mode": "PLANNING_ONLY" if not active else ("SINGLE_HIGH_RISK_PRODUCT_SLICE" if mutating else "PRODUCT_RUNTIME_VERIFICATION"),
            "selected_checkpoint": current,
            "pilot_override": {"enabled": override["enabled"], "current_checkpoint": override["current_checkpoint"], "reason": override["reason"]},
            "parallel_product_checkpoint": True,
            "active_work_order": reduced["work_order_id"],
            "satisfied_predicates": [item for item in required if item in satisfied],
            "unsatisfied_predicates": [item for item in required if item not in satisfied],
            "autonomous_runtime_workers": scheduler["concurrency"]["v0_s1_max_autonomous_runtime_mutation_workers"] if mutating else 0,
            "v0_s1_gate": {
                "requested_checkpoint": "V0_S1_NETWORKED_PLANETARY_OUTPOST",
                "risk_floor": "HIGH",
                "network_baseline": "SERVER_PREDICTED",
                "status": "READY_FOR_BOUNDED_PRODUCT_IMPLEMENTATION" if mutating else ("VERIFYING_PRODUCT_HEAD" if active else "WAITING_DIRECTOR_DISPATCH"),
                "runtime_mutation": "BLOCKED_BY_GLOBAL_MUTATION_LEASE" if requested_mutation and not global_mutation_authorized else ("AUTHORIZED_BY_MAIN_OWNED_LEASE" if mutating else ("NO_ACTIVE_MUTATION_SLOT" if active else "FORBIDDEN_UNTIL_DISPATCH")),
                "pre_h0_3_total_mutation_workers_max": rules["pre_h0_3_total_runtime_mutation_workers_max"],
                "nx_verification_review_only_may_coexist": rules["verification_or_review_only_work_does_not_consume_mutation_worker_slot"],
                "v0_plus_nx_fix_mutation_forbidden": rules["v0_mutation_plus_nx_nontrivial_fix_mutation_forbidden"],
                "network_foundation_change_fails_closed_to": rules["v0_network_foundation_change_fails_closed_to"],
                "foundation_scope": foundation_scope,
                "global_mutation_arbiter": global_mutation,
            },
            "next_action": foundation_scope["status"] if foundation_scope["blocked"] else ("PRE_H0_3_GLOBAL_RUNTIME_MUTATION_LEASE_REQUIRED" if requested_mutation and not global_mutation_authorized else ("BEGIN_V0_S1_NETWORKED_PLANETARY_OUTPOST_COMPOSITION" if mutating else ("VERIFY_V0_S1_EXACT_HEAD" if active else "ISSUE_EXACT_MAIN_V0_S1_WORK_ORDER_AND_DIRECTOR_DISPATCH"))),
            "stop_gates": [
                "V0_RUNTIME_MUTATION_BEFORE_DISPATCH",
                "PRIVATE_V0_NETWORK_AUTHORITY",
                "PRIVATE_V0_CONSTRUCTION_TRUTH",
                "SECOND_PRE_H0_3_RUNTIME_MUTATION_WORKER",
                "SHIP_FLIGHT",
                "SERVER_HANDOFF",
            ],
        }

    raise ValueError(f"UNSUPPORTED_CHECKPOINT:{current}")
