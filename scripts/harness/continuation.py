"""Derive role and mission continuation without treating role handoff as session end."""
from __future__ import annotations

from typing import Any

from .mission import mission_from_state

_AUTO_ROLE_BY_WORK_TYPE = {
    "IMPLEMENTATION": "IMPLEMENTER",
    "FIX": "IMPLEMENTER",
    "INTEGRATION": "INTEGRATOR",
    "VALIDATION": "VERIFIER",
    "REVIEW": "REVIEWER",
    "CONTROL": "DIRECTOR",
    "RECOVERY": "DIRECTOR",
    "HUMAN_OBSERVATION": "HUMAN",
}


def _threshold(policy: dict[str, Any]) -> int:
    closing = policy.get("self_closing_execution")
    if not isinstance(closing, dict):
        return 3
    return max(1, int(closing.get("max_same_defect_fix_required_events_before_takeover", 3)))


def _transition(
    *,
    mission: dict[str, Any],
    handoff_class: str,
    next_actor: str,
    next_action: str,
    resume_condition: str,
    reason: str,
    role_exit_allowed: bool,
    closure_loop_required: bool,
    stop_obligation: str,
    evidence_sink: str | None = "EXECUTION_LEDGER",
    hard_blocked: bool = False,
) -> dict[str, Any]:
    human_required = handoff_class == "HUMAN_DECISION_REQUIRED"
    mission_exit_allowed = bool(
        mission["mission_complete"] or human_required or hard_blocked
    )
    return {
        **mission,
        "handoff_class": handoff_class,
        "next_actor": next_actor,
        "next_action": next_action,
        "resume_condition": resume_condition,
        "reason": reason,
        "evidence_sink": evidence_sink,
        "human_decision_required": human_required,
        "hard_blocked": hard_blocked,
        "role_exit_allowed": role_exit_allowed,
        "mission_exit_allowed": mission_exit_allowed,
        # Compatibility alias: a user-visible session is the checkpoint mission.
        "session_exit_allowed": mission_exit_allowed,
        "closure_loop_required": closure_loop_required,
        "mission_driver_required": not mission_exit_allowed,
        "stop_obligation": stop_obligation,
    }


def _active_role(work_order: dict[str, Any], state_name: str) -> str:
    if state_name == "PLANNED":
        return "DIRECTOR"
    return _AUTO_ROLE_BY_WORK_TYPE.get(str(work_order.get("work_order_type", "IMPLEMENTATION")), "DIRECTOR")


def build_continuation(state: dict[str, Any], policy: dict[str, Any]) -> dict[str, Any]:
    work_order = state["active_work_order"]
    reduced = state["reduced_work_order"]
    mission = mission_from_state(state)
    state_name = str(reduced.get("state", ""))
    blockers = set(state.get("checkpoint_blockers", []))
    findings = set(state.get("findings", []))
    review = state.get("review", {})
    open_attention = state.get("human_attention", {}).get("open_items", [])

    if mission["mission_complete"]:
        return _transition(
            mission=mission,
            handoff_class="MISSION_COMPLETE",
            next_actor="NONE",
            next_action="REPORT_CHECKPOINT_MISSION_COMPLETE",
            resume_condition="NONE",
            reason="Canonical main contains an ACCEPTED record for the mission checkpoint.",
            role_exit_allowed=True,
            closure_loop_required=False,
            stop_obligation="REPORT_ACCEPTANCE_RECORD_AND_EXACT_ACCEPTED_HEAD",
            evidence_sink=state.get("checkpoint_acceptance", {}).get("path"),
        )

    if state_name == "WAITING_HUMAN" or any(item.get("blocking") for item in open_attention):
        return _transition(
            mission=mission,
            handoff_class="HUMAN_DECISION_REQUIRED",
            next_actor="HUMAN",
            next_action="RESOLVE_DECLARED_HUMAN_ATTENTION",
            resume_condition="BLOCKING_HUMAN_ATTENTION_RESOLVED_DURABLY",
            reason="A declared blocking human decision is a valid mission-session stop.",
            role_exit_allowed=True,
            closure_loop_required=False,
            stop_obligation="PERSIST_HUMAN_ATTENTION_ITEM_WITH_EXACT_RESUME_CONDITION",
            evidence_sink="HUMAN_ATTENTION_LEDGER",
        )

    hard_proof = state.get("hard_block_proof")
    if state_name == "BLOCKED" and isinstance(hard_proof, dict) and hard_proof.get("proven_non_automatable") is True:
        return _transition(
            mission=mission,
            handoff_class="SYSTEM_BLOCKED",
            next_actor="DIRECTOR",
            next_action="REPORT_PROVEN_NON_AUTOMATABLE_BLOCKER",
            resume_condition=str(hard_proof.get("resume_condition") or "EXTERNAL_BLOCKER_RESOLVED"),
            reason="A durable proof marks the blocker as non-automatable in current scope.",
            role_exit_allowed=True,
            closure_loop_required=False,
            stop_obligation="PERSIST_HARD_BLOCK_PROOF_AND_RESUME_CONDITION",
            hard_blocked=True,
        )

    if state_name == "PLANNED":
        return _transition(
            mission=mission,
            handoff_class="CONTINUE_SAME_ROLE",
            next_actor="DIRECTOR",
            next_action="DISPATCH_ACTIVE_WORK_ORDER",
            resume_condition="WORK_ORDER_DURABLY_DISPATCHED_OR_REAL_BLOCKER_RECORDED",
            reason="PLANNED checkpoint work is unfinished automatable work.",
            role_exit_allowed=False,
            closure_loop_required=True,
            stop_obligation="DO_NOT_STOP_BEFORE_DISPATCH_OR_DURABLE_BLOCKER",
        )

    if state_name in {"DISPATCHED", "IN_PROGRESS"}:
        actor = _active_role(work_order, state_name)
        return _transition(
            mission=mission,
            handoff_class="CONTINUE_SAME_ROLE",
            next_actor=actor,
            next_action="CONTINUE_ACTIVE_WORK_ORDER_TO_IMPLEMENTED_AND_VALIDATED",
            resume_condition="ROLE_OUTPUT_IMPLEMENTED_AND_REQUIRED_SELF_VALIDATION_COMPLETE_OR_REAL_BOUNDARY_REACHED",
            reason=f"Work Order state {state_name} still belongs to {actor}.",
            role_exit_allowed=False,
            closure_loop_required=True,
            stop_obligation="DO_NOT_STOP_WITH_AUTOMATABLE_WORK_STILL_IN_PROGRESS",
        )

    if state_name == "FIX_REQUIRED" or "REPAIR_MAP_REQUIRED" in findings:
        count = int(state.get("repair", {}).get("same_defect_fix_required_count", 0))
        if count >= _threshold(policy):
            return _transition(
                mission=mission,
                handoff_class="ROLE_BOUNDARY",
                next_actor="DIRECTOR",
                next_action="ESCALATE_REPEATED_DEFECT_FOR_TAKEOVER",
                resume_condition="STRONGER_CONTEXT_REPAIR_WORK_ORDER_DISPATCHED",
                reason="Repeated same-defect repairs reached the configured takeover threshold.",
                role_exit_allowed=True,
                closure_loop_required=False,
                stop_obligation="PERSIST_REPAIR_HISTORY_AND_DISPATCH_TAKEOVER_WITHOUT_ENDING_MISSION",
            )
        return _transition(
            mission=mission,
            handoff_class="CONTINUE_SAME_ROLE",
            next_actor="IMPLEMENTER",
            next_action="EXECUTE_REPAIR_TEST_CLOSURE_LOOP",
            resume_condition="IMPLEMENTER_OWNED_PREDICATES_GREEN_OR_TAKEOVER_THRESHOLD_REACHED",
            reason="Automatable FIX_REQUIRED remains inside the checkpoint mission.",
            role_exit_allowed=False,
            closure_loop_required=True,
            stop_obligation="DO_NOT_STOP_WHILE_AN_IN_SCOPE_AUTOMATABLE_REPAIR_REMAINS",
        )

    if state_name == "EPOCH_INVALIDATED" or "EPOCH_INVALIDATED" in findings:
        return _transition(
            mission=mission,
            handoff_class="ROLE_BOUNDARY",
            next_actor="DIRECTOR",
            next_action="REFRESH_PROJECT_EPOCH_AND_REDISPATCH_CHECKPOINT_WORK",
            resume_condition="FRESH_PROJECT_EPOCH_AND_WORK_ORDER_DURABLY_DISPATCHED",
            reason="Epoch invalidation requires control refresh, not checkpoint-session termination.",
            role_exit_allowed=True,
            closure_loop_required=False,
            stop_obligation="KEEP_PARENT_MISSION_OPEN_ACROSS_EPOCH_REFRESH",
        )

    if "MAIN_MOVED_REVIEW_REQUIRED" in findings:
        return _transition(
            mission=mission,
            handoff_class="ROLE_BOUNDARY",
            next_actor="DIRECTOR",
            next_action="RUN_MAIN_MOVEMENT_EPOCH_AUDIT_AND_ROUTE_RESULT",
            resume_condition="EPOCH_AUDIT_CONTINUE_OR_REFRESH_RECORDED",
            reason="Canonical main movement is a Director control transition, not a mission terminal.",
            role_exit_allowed=True,
            closure_loop_required=False,
            stop_obligation="KEEP_PARENT_MISSION_OPEN_WHILE_MAIN_MOVEMENT_IS_AUDITED",
        )

    if "WORK_ORDER_BRANCH_NOT_CHECKED_OUT" in findings:
        return _transition(
            mission=mission,
            handoff_class="CONTINUE_SAME_ROLE",
            next_actor="DIRECTOR",
            next_action="CHECKOUT_ACTIVE_WORK_ORDER_BRANCH_AND_RESUME",
            resume_condition="ACTIVE_WORK_ORDER_BRANCH_CHECKED_OUT",
            reason="Wrong checkout is recoverable local state.",
            role_exit_allowed=False,
            closure_loop_required=True,
            stop_obligation="DO_NOT_END_MISSION_FOR_LOCAL_CHECKOUT_MISMATCH",
        )

    if state_name == "CANCELLED":
        return _transition(
            mission=mission,
            handoff_class="ROLE_BOUNDARY",
            next_actor="DIRECTOR",
            next_action="ISSUE_REPLACEMENT_WORK_ORDER_OR_RECORD_EXPLICIT_MISSION_DECISION",
            resume_condition="REPLACEMENT_WORK_ORDER_DISPATCHED_OR_HUMAN_DECISION_RECORDED",
            reason="Cancelling one Work Order does not implicitly cancel its checkpoint mission.",
            role_exit_allowed=True,
            closure_loop_required=False,
            stop_obligation="DO_NOT_TREAT_WORK_ORDER_CANCELLATION_AS_MISSION_COMPLETION",
        )

    if state_name == "BLOCKED":
        return _transition(
            mission=mission,
            handoff_class="ROLE_BOUNDARY",
            next_actor="DIRECTOR",
            next_action="DIAGNOSE_BLOCKER_AND_ROUTE_AUTOMATABLE_RECOVERY",
            resume_condition="RECOVERY_WORK_ORDER_DISPATCHED_OR_NON_AUTOMATABLE_HARD_BLOCK_PROVEN",
            reason="BLOCKED alone is not enough to terminate the checkpoint mission.",
            role_exit_allowed=True,
            closure_loop_required=False,
            stop_obligation="PROVE_NON_AUTOMATABLE_BLOCK_OR_CONTINUE_RECOVERY",
        )

    implementation_validation = state.get("implementation_validation")
    if (
        state_name == "IMPLEMENTED"
        and isinstance(implementation_validation, dict)
        and implementation_validation.get("complete") is False
    ):
        actor = _active_role(work_order, state_name)
        return _transition(
            mission=mission,
            handoff_class="CONTINUE_SAME_ROLE",
            next_actor=actor,
            next_action="RUN_IMPLEMENTER_OWNED_VALIDATION_AND_REPAIR_UNTIL_GREEN",
            resume_condition="IMPLEMENTER_OWNED_VALIDATION_COMPLETE_OR_CONCRETE_FAILURE_ROUTED",
            reason="An explicit implementation-validation signal proves the current role still owns unfinished work.",
            role_exit_allowed=False,
            closure_loop_required=True,
            stop_obligation="DO_NOT_HANDOFF_BEFORE_EXPLICIT_IMPLEMENTER_VALIDATION_COMPLETES",
        )

    if state_name == "VERIFYING" and "REQUIRED_PREDICATES_INCOMPLETE" in blockers:
        return _transition(
            mission=mission,
            handoff_class="CONTINUE_SAME_ROLE",
            next_actor="VERIFIER",
            next_action="CONTINUE_VERIFICATION_UNTIL_PREDICATES_COMPLETE",
            resume_condition="ALL_REQUIRED_PREDICATES_DURABLY_VERIFIED_OR_FAILED_PREDICATE_ROUTED",
            reason="Active verification is unfinished Verifier work.",
            role_exit_allowed=False,
            closure_loop_required=True,
            stop_obligation="DO_NOT_STOP_WITH_REQUIRED_VERIFICATION_INCOMPLETE",
        )

    post_build_state = str(review.get("post_build_state", "MISSING"))
    if work_order.get("review_required") and post_build_state == "FAIL":
        return _transition(
            mission=mission,
            handoff_class="ROLE_BOUNDARY",
            next_actor="IMPLEMENTER",
            next_action="CONSUME_REVIEW_FINDINGS_AND_EXECUTE_REPAIR_CLOSURE_LOOP",
            resume_condition="NEW_EXACT_HEAD_GREEN_AND_READY_FOR_FRESH_REVIEW",
            reason="Review FAIL routes to repair ownership while the parent mission remains open.",
            role_exit_allowed=True,
            closure_loop_required=False,
            stop_obligation="DISPATCH_REPAIR_WITHOUT_ENDING_USER_CHECKPOINT_SESSION",
        )

    if work_order.get("review_required") and post_build_state == "INSUFFICIENT_EVIDENCE":
        return _transition(
            mission=mission,
            handoff_class="ROLE_BOUNDARY",
            next_actor="DIRECTOR",
            next_action="ROUTE_EXACT_EVIDENCE_GAPS_TO_OWNING_ROLE",
            resume_condition="EVIDENCE_GAPS_CLOSED_AND_FRESH_REVIEW_REQUESTED",
            reason="Insufficient evidence is actionable checkpoint work.",
            role_exit_allowed=True,
            closure_loop_required=False,
            stop_obligation="CLOSE_EVIDENCE_GAPS_WITHOUT_ENDING_MISSION",
        )

    if work_order.get("review_required") and post_build_state != "PASS":
        target = review.get("review_target_head_sha") or state.get("repository", {}).get("implementation_head_sha")
        return _transition(
            mission=mission,
            handoff_class="ROLE_BOUNDARY",
            next_actor="REVIEWER",
            next_action="PERSIST_FRESH_EXACT_HEAD_REVIEW",
            resume_condition=f"DURABLE_REVIEW_RESULT_FOR_EXACT_HEAD:{target}",
            reason="Independent review is an isolated role boundary inside the same checkpoint mission.",
            role_exit_allowed=True,
            closure_loop_required=False,
            stop_obligation="FRESH_REVIEWER_CONTEXT_MAY_END; PARENT_CHECKPOINT_SESSION_MUST_CONTINUE",
        )

    if "EVIDENCE_MAP_MISSING" in blockers or "EVIDENCE_MAP_NOT_FRESH_PASS" in blockers or "EVIDENCE_HEAD_STALE" in findings:
        return _transition(
            mission=mission,
            handoff_class="ROLE_BOUNDARY",
            next_actor="DIRECTOR",
            next_action="REFRESH_DURABLE_EVIDENCE_MAP_FOR_EXACT_HEAD",
            resume_condition="FRESH_EVIDENCE_MAP_BINDS_EXACT_HEAD_AND_REVIEW_RESULT",
            reason="Evidence refresh is routine checkpoint closure work.",
            role_exit_allowed=True,
            closure_loop_required=False,
            stop_obligation="REFRESH_EVIDENCE_WITHOUT_ENDING_MISSION",
        )

    if "REQUIRED_PREDICATES_INCOMPLETE" in blockers:
        return _transition(
            mission=mission,
            handoff_class="ROLE_BOUNDARY",
            next_actor="VERIFIER",
            next_action="COMPLETE_REQUIRED_PREDICATES",
            resume_condition="ALL_REQUIRED_PREDICATES_DURABLY_VERIFIED",
            reason="Remaining checkpoint predicates require independent verification.",
            role_exit_allowed=True,
            closure_loop_required=False,
            stop_obligation="VERIFIER_ROLE_MAY_ROTATE; PARENT_MISSION_MUST_STAY_OPEN",
        )

    unknown_findings = findings - {
        "MAIN_MOVED_REVIEW_REQUIRED",
        "EPOCH_INVALIDATED",
        "REPAIR_MAP_REQUIRED",
        "BLOCKING_HUMAN_ATTENTION",
        "WORK_ORDER_BRANCH_NOT_CHECKED_OUT",
        "EVIDENCE_HEAD_STALE",
    }
    if unknown_findings:
        return _transition(
            mission=mission,
            handoff_class="ROLE_BOUNDARY",
            next_actor="DIRECTOR",
            next_action="DIAGNOSE_AND_ROUTE_NONTERMINAL_FINDINGS",
            resume_condition="FINDINGS_ROUTED_TO_OWNER_OR_HARD_BLOCK_PROVEN",
            reason=f"Unclassified findings fail closed without ending the mission: {','.join(sorted(unknown_findings))}.",
            role_exit_allowed=True,
            closure_loop_required=False,
            stop_obligation="ROUTE_FINDINGS_OR_PROVE_HARD_BLOCK; DO_NOT_REPORT MISSION COMPLETE",
        )

    return _transition(
        mission=mission,
        handoff_class="ROLE_BOUNDARY",
        next_actor="DIRECTOR",
        next_action="EVALUATE_CHECKPOINT_ACCEPTANCE_OR_REQUIRED_HUMAN_GATE",
        resume_condition="CANONICAL_CHECKPOINT_ACCEPTED_OR_DECLARED_HUMAN_GATE_OPENED",
        reason="Local Work Order closure is not checkpoint mission completion until canonical acceptance exists.",
        role_exit_allowed=True,
        closure_loop_required=False,
        stop_obligation="KEEP_PARENT_SESSION_OPEN_UNTIL_ACCEPTANCE_HUMAN_DECISION_OR_PROVEN_HARD_BLOCK",
    )
