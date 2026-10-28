"""Execution advice; never changes role requirements, verdicts or acceptance gates."""
from __future__ import annotations
from typing import Any


def execution_plan(work_order: dict[str, Any]) -> dict[str, Any]:
    risk = str(work_order.get("risk_class", "UNKNOWN"))
    roles = work_order.get("required_review_roles", [])
    routine = (risk in {"LOW", "MEDIUM"} and isinstance(roles, list)
               and bool(roles) and all(isinstance(role, str) for role in roles) and set(roles) <= {"IMPLEMENTER", "REVIEWER", "VERIFIER"}
               and not work_order.get("human_review_required", False)
               and not work_order.get("independent_execution_required", False)
               and not work_order.get("separate_machine_required", False))
    return {
        "policy_revision": "DEV-FLOW-2026-10-28-R1",
        "risk_class": risk,
        "mode": "SINGLE_INDEPENDENT_REVIEW_BATCH" if routine else "RISK_REQUIRED_SEPARATE_ROLES",
        "same_independent_actor_may_cover_reviewer_and_verifier": routine,
        "reuse_trusted_exact_machine_evidence": True,
        "explicit_work_order_execution_requirements_take_precedence": True,
        "existing_roles_predicates_and_verdict_formats_unchanged": True,
        "implementer_self_acceptance_allowed": False,
        "scope_expansion_requires_new_risk_decision": True,
        "repair_review_scope": "CHANGED_SURFACE_AND_RELEVANT_REGRESSIONS",
    }
