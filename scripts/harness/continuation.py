"""Derive the next safe Harness transition without weakening existing gates."""
from __future__ import annotations

from typing import Any


_HARD_BLOCK_STATES = {"BLOCKED", "EPOCH_INVALIDATED", "CANCELLED"}
_DEFAULT_RECOVERABLE_FINDINGS = {"REPAIR_MAP_REQUIRED"}
_AUTO_ROLE_BY_WORK_TYPE = {
    "IMPLEMENTATION": "IMPLEMENTER",
    "FIX": "IMPLEMENTER",
    "INTEGRATION": "INTEGRATOR",
    "VALIDATION": "VERIFIER",
    "REVIEW": "REVIEWER",
    "CONTROL": "DIRECTOR",
    "RECOVERY": "DIRECTOR",
}


def _mission(work_order: dict[str, Any]) -> dict[str, Any]:
    declared = work_order.get("mission")
    if isinstance(declared, dict):
        mission_id = str(declared.get("mission_id") or f"CHECKPOINT:{work_order['goal_checkpoint']}")
        objective = str(declared.get("objective") or f"Reach checkpoint {work_order['goal_checkpoint']}")
        parent = declared.get("parent_mission_id")
        completion_condition = str(declared.get("completion_condition") or "CANONICAL_CHECKPOINT_ACCEPTED")
    else:
        mission_id = f"CHECKPOINT:{work_order['goal_checkpoint']}"
        objective = f"Reach checkpoint {work_order['goal_checkpoint']}"
        parent = None
        completion_condition = "CANONICAL_CHECKPOINT_ACCEPTED"
    return {
        "mission_id": mission_id,
        "objective": objective,
        "parent_mission_id": parent,
        "completion_condition": completion_condition,
        "mission_complete": False,
    }


def _review_sink(work_order: dict[str, Any], policy: dict[str, Any]) -> str:
    handoff = work_order.get("handoff")
    if isinstance(handoff, dict):
        declared = handoff.get("review_evidence_sink")
        if declared:
            return str(declared)
    return str(policy["review_evidence_sinks"]["default_harness_work_order"])


def _closure_policy(policy: dict[str, Any]) -> dict[str, Any]:
    configured = policy.get("self_closing_execution")
    return configured if isinstance(configured, dict) else {}


def _transition(
    *,
    mission: dict[str, Any],
    handoff_class: str,
    next_actor: str,
    next_action: str,
    evidence_sink: str | None,
    resume_condition: str,
    on_success: str,
    on_failure: str,
    reason: str,
    session_exit_allowed: bool,
    closure_loop_required: bool,
    stop_obligation: str,
) -> dict[str, Any]:
    return {
        **mission,
        "handoff_class": handoff_class,
        "next_actor": next_actor,
        "next_action": next_action,
        "evidence_sink": evidence_sink,
        "resume_condition": resume_condition,
        "on_success": on_success,
        "on_failure": on_failure,
        "reason": reason,
        "human_decision_required": handoff_class == "HUMAN_DECISION_REQUIRED",
        "session_exit_allowed": session_exit_allowed,
        "closure_loop_required": closure_loop_required,
        "stop_obligation": stop_obligation,
    }


def _same_defect_takeover_required(state: dict[str, Any], policy: dict[str, Any]) -> bool:
    repair = state.get("repair", {})
    if repair.get("escalation_required") is True:
        return True
    closure = _closure_policy(policy)
    threshold = int(closure.get("max_same_defect_fix_required_events_before_takeover", 3))
    count = int(repair.get("same_defect_fix_required_count", 0))
    return count >= threshold > 0


def _recoverable_findings(policy: dict[str, Any]) -> set[str]:
    closure = _closure_policy(policy)
    declared = closure.get("same_role_recoverable_findings")
    if isinstance(declared, list):
        return {str(item) for item in declared}
    return set(_DEFAULT_RECOVERABLE_FINDINGS)


def _active_role(work_order: dict[str, Any], state_name: str) -> str | None:
    if state_name == "PLANNED":
        return "DIRECTOR"
    work_type = str(work_order.get("work_order_type", "IMPLEMENTATION"))
    return _AUTO_ROLE_BY_WORK_TYPE.get(work_type)


def _unfinished_same_role_transition(
    work_order: dict[str, Any],
    state_name: str,
    blockers: set[str],
    mission: dict[str, Any],
) -> dict[str, Any] | None:
    actor = _active_role(work_order, state_name)
    if actor is None:
        return None
    if state_name == "PLANNED":
        return _transition(
            mission=mission,
            handoff_class="CONTINUE_SAME_ROLE",
            next_actor="DIRECTOR",
            next_action="DISPATCH_ACTIVE_WORK_ORDER",
            evidence_sink="EXECUTION_LEDGER",
            resume_condition="WORK_ORDER_DURABLY_DISPATCHED_OR_REAL_BLOCKER_RECORDED",
            on_success="RECOMPUTE_CONTINUATION",
            on_failure="RECORD_BLOCKER_AND_REPLAN",
            reason="A planned automatable Work Order is unfinished work, not a session terminal.",
            session_exit_allowed=False,
            closure_loop_required=True,
            stop_obligation="DO_NOT_STOP_BEFORE_DISPATCH_OR_DURABLE_BLOCKER",
        )
    if state_name in {"DISPATCHED", "IN_PROGRESS"}:
        return _transition(
            mission=mission,
            handoff_class="CONTINUE_SAME_ROLE",
            next_actor=actor,
            next_action="CONTINUE_ACTIVE_WORK_ORDER_TO_IMPLEMENTED_AND_VALIDATED",
            evidence_sink="EXECUTION_LEDGER",
            resume_condition="ROLE_OUTPUT_IMPLEMENTED_AND_REQUIRED_SELF_VALIDATION_COMPLETE_OR_REAL_BOUNDARY_REACHED",
            on_success="RECOMPUTE_CONTINUATION",
            on_failure="FIX_IN_SCOPE_FAILURE_AND_RETEST_OR_RECORD_REAL_BLOCKER",
            reason=f"Work Order state {state_name} still has executable work owned by {actor}.",
            session_exit_allowed=False,
            closure_loop_required=True,
            stop_obligation="DO_NOT_STOP_WITH_AUTOMATABLE_WORK_STILL_IN_PROGRESS",
        )
    if state_name == "IMPLEMENTED" and "REQUIRED_PREDICATES_INCOMPLETE" in blockers and actor in {"IMPLEMENTER", "INTEGRATOR", "DIRECTOR"}:
        return _transition(
            mission=mission,
            handoff_class="CONTINUE_SAME_ROLE",
            next_actor=actor,
            next_action="RUN_REQUIRED_VALIDATION_AND_REPAIR_UNTIL_GREEN",
            evidence_sink="EXECUTION_LEDGER",
            resume_condition="ALL_REQUIRED_PREDICATES_GREEN_OR_REAL_ROLE_BOUNDARY_REACHED",
            on_success="RECOMPUTE_CONTINUATION",
            on_failure="FIX_IN_SCOPE_FAILURE_AND_RETEST_OR_ESCALATE_AT_TAKEOVER_THRESHOLD",
            reason="Implementation exists, but required predicates are still incomplete; review handoff would be premature.",
            session_exit_allowed=False,
            closure_loop_required=True,
            stop_obligation="DO_NOT_HANDOFF_OR_STOP_BEFORE_REQUIRED_VALIDATION_COMPLETES",
        )
    if state_name == "VERIFYING" and "REQUIRED_PREDICATES_INCOMPLETE" in blockers:
        return _transition(
            mission=mission,
            handoff_class="CONTINUE_SAME_ROLE",
            next_actor="VERIFIER",
            next_action="CONTINUE_VERIFICATION_UNTIL_PREDICATES_COMPLETE",
            evidence_sink="EXECUTION_LEDGER",
            resume_condition="ALL_REQUIRED_PREDICATES_DURABLY_VERIFIED_OR_FAILED_PREDICATE_ROUTED_TO_REPAIR",
            on_success="RECOMPUTE_CONTINUATION",
            on_failure="ROUTE_FAILED_PREDICATE_TO_REPAIR",
            reason="Verification is active and incomplete; the Verifier must finish or route a concrete failure.",
            session_exit_allowed=False,
            closure_loop_required=True,
            stop_obligation="DO_NOT_STOP_WITH_REQUIRED_VERIFICATION_STILL_INCOMPLETE",
        )
    return None


def build_continuation(state: dict[str, Any], policy: dict[str, Any]) -> dict[str, Any]:
    """Return a deterministic next transition derived only from durable state."""
    work_order = state["active_work_order"]
    reduced = state["reduced_work_order"]
    mission = _mission(work_order)
    review = state.get("review", {})
    blockers = set(state.get("checkpoint_blockers", []))
    findings = set(state.get("findings", []))
    open_attention = state.get("human_attention", {}).get("open_items", [])
    state_name = str(reduced.get("state", ""))

    if state_name == "WAITING_HUMAN" or any(item.get("blocking") for item in open_attention):
        return _transition(
            mission=mission,
            handoff_class="HUMAN_DECISION_REQUIRED",
            next_actor="HUMAN",
            next_action="RESOLVE_DECLARED_HUMAN_ATTENTION",
            evidence_sink="HUMAN_ATTENTION_LEDGER",
            resume_condition="BLOCKING_HUMAN_ATTENTION_RESOLVED_DURABLY",
            on_success="RECOMPUTE_CONTINUATION",
            on_failure="REMAIN_WAITING_HUMAN",
            reason="A declared blocking human decision is the only valid human stop.",
            session_exit_allowed=True,
            closure_loop_required=False,
            stop_obligation="PERSIST_HUMAN_ATTENTION_ITEM_WITH_EXACT_RESUME_CONDITION",
        )

    recoverable_findings = _recoverable_findings(policy)
    hard_findings = findings - recoverable_findings
    if hard_findings:
        return _transition(
            mission=mission,
            handoff_class="SYSTEM_BLOCKED",
            next_actor="DIRECTOR",
            next_action="DIAGNOSE_AND_ROUTE_BLOCKER",
            evidence_sink=None,
            resume_condition="ALL_HARD_EXECUTION_FINDINGS_RESOLVED",
            on_success="RECOMPUTE_CONTINUATION",
            on_failure="RECORD_BLOCKER_AND_REPLAN",
            reason=f"Hard execution findings fail closed: {','.join(sorted(hard_findings))}.",
            session_exit_allowed=True,
            closure_loop_required=False,
            stop_obligation="PERSIST_BLOCKER_PROOF_AND_EXACT_NEXT_ACTOR_ACTION",
        )

    if state_name == "FIX_REQUIRED" or findings & recoverable_findings:
        if _same_defect_takeover_required(state, policy):
            return _transition(
                mission=mission,
                handoff_class="ROLE_BOUNDARY",
                next_actor="DIRECTOR",
                next_action="ESCALATE_REPEATED_DEFECT_FOR_TAKEOVER",
                evidence_sink="EXECUTION_LEDGER",
                resume_condition="TAKEOVER_OR_STRONGER_CONTEXT_REPAIR_WORK_ORDER_DISPATCHED",
                on_success="RECOMPUTE_CONTINUATION",
                on_failure="RECORD_BLOCKER_AND_REPLAN",
                reason="The same defect reached the configured repair-attempt ceiling; ownership must escalate, not silently stop.",
                session_exit_allowed=True,
                closure_loop_required=False,
                stop_obligation="PERSIST_REPAIR_HISTORY_FAILING_COMMAND_AND_TAKEOVER_REQUEST",
            )
        return _transition(
            mission=mission,
            handoff_class="CONTINUE_SAME_ROLE",
            next_actor="IMPLEMENTER",
            next_action="EXECUTE_REPAIR_TEST_CLOSURE_LOOP",
            evidence_sink="EXECUTION_LEDGER",
            resume_condition="IMPLEMENTER_OWNED_PREDICATES_GREEN_OR_TAKEOVER_THRESHOLD_REACHED",
            on_success="RUN_REQUIRED_REGRESSION_PERSIST_EVIDENCE_AND_RECOMPUTE",
            on_failure="REFRESH_REPAIR_MAP_FIX_AND_RETEST_WITHIN_SCOPE",
            reason="FIX_REQUIRED is an automatable same-role state while repair remains within scope and below takeover threshold.",
            session_exit_allowed=False,
            closure_loop_required=True,
            stop_obligation="DO_NOT_STOP_WHILE_AN_IN_SCOPE_AUTOMATABLE_REPAIR_REMAINS",
        )

    if state_name in _HARD_BLOCK_STATES:
        return _transition(
            mission=mission,
            handoff_class="SYSTEM_BLOCKED",
            next_actor="DIRECTOR",
            next_action="DIAGNOSE_AND_ROUTE_BLOCKER",
            evidence_sink="EXECUTION_LEDGER",
            resume_condition="BLOCKER_RESOLVED_OR_REPAIR_WORK_ORDER_DISPATCHED",
            on_success="RECOMPUTE_CONTINUATION",
            on_failure="RECORD_BLOCKER_AND_REPLAN",
            reason=f"Work Order state {state_name} is not a successful mission terminal.",
            session_exit_allowed=True,
            closure_loop_required=False,
            stop_obligation="PERSIST_BLOCKER_PROOF_AND_EXACT_NEXT_ACTOR_ACTION",
        )

    unfinished = _unfinished_same_role_transition(work_order, state_name, blockers, mission)
    if unfinished is not None:
        return unfinished

    post_build_state = str(review.get("post_build_state", "MISSING"))
    if work_order.get("review_required") and post_build_state == "FAIL":
        return _transition(
            mission=mission,
            handoff_class="ROLE_BOUNDARY",
            next_actor="IMPLEMENTER",
            next_action="CONSUME_REVIEW_FINDINGS_AND_EXECUTE_REPAIR_CLOSURE_LOOP",
            evidence_sink="EXECUTION_LEDGER",
            resume_condition="REPAIR_CANDIDATE_GREEN_AND_NEW_EXACT_HEAD_READY_FOR_FRESH_REVIEW",
            on_success="REQUEST_FRESH_EXACT_HEAD_REVIEW",
            on_failure="CONTINUE_REPAIR_OR_ESCALATE_AT_TAKEOVER_THRESHOLD",
            reason="A durable review FAIL routes to repair ownership; it must not loop back to the Reviewer.",
            session_exit_allowed=True,
            closure_loop_required=False,
            stop_obligation="PERSIST_REVIEW_FINDINGS_AS_REPAIR_INPUT_AND_DISPATCH_IMPLEMENTER",
        )

    if work_order.get("review_required") and post_build_state == "INSUFFICIENT_EVIDENCE":
        return _transition(
            mission=mission,
            handoff_class="ROLE_BOUNDARY",
            next_actor="DIRECTOR",
            next_action="ROUTE_EXACT_EVIDENCE_GAPS_TO_OWNING_ROLE",
            evidence_sink="EXECUTION_LEDGER",
            resume_condition="EVIDENCE_GAPS_CLOSED_AND_FRESH_EXACT_HEAD_REVIEW_REQUESTED",
            on_success="RECOMPUTE_CONTINUATION",
            on_failure="RECORD_EVIDENCE_BLOCKER_AND_REPLAN",
            reason="INSUFFICIENT_EVIDENCE is actionable work, not a terminal verdict and not permission to guess.",
            session_exit_allowed=True,
            closure_loop_required=False,
            stop_obligation="PERSIST_EVIDENCE_GAPS_AND_EXACT_OWNER_FOR_EACH_GAP",
        )

    if work_order.get("review_required") and post_build_state != "PASS":
        sink = _review_sink(work_order, policy)
        target = review.get("review_target_head_sha") or state["repository"]["implementation_head_sha"]
        return _transition(
            mission=mission,
            handoff_class="ROLE_BOUNDARY",
            next_actor="REVIEWER",
            next_action="PERSIST_FRESH_EXACT_HEAD_REVIEW",
            evidence_sink=sink,
            resume_condition=f"DURABLE_REVIEW_PASS_FOR_EXACT_HEAD:{target}",
            on_success="DIRECTOR_INGEST_REVIEW_AND_RECOMPUTE",
            on_failure="ROUTE_FAIL_OR_INSUFFICIENT_EVIDENCE_TO_REPAIR",
            reason="Independent review is routine work, not a human decision; chat-only verdicts do not satisfy this transition.",
            session_exit_allowed=True,
            closure_loop_required=False,
            stop_obligation="PERSIST_COMPLETE_REVIEW_REQUEST_BOUND_TO_EXACT_HEAD_BEFORE_STOP",
        )

    if "EVIDENCE_MAP_MISSING" in blockers or "EVIDENCE_MAP_NOT_FRESH_PASS" in blockers:
        return _transition(
            mission=mission,
            handoff_class="ROLE_BOUNDARY",
            next_actor="DIRECTOR",
            next_action="INGEST_DURABLE_REVIEW_AND_REFRESH_EVIDENCE_MAP",
            evidence_sink="EXECUTION_LEDGER",
            resume_condition="FRESH_EVIDENCE_MAP_BINDS_IMPLEMENTATION_HEAD_AND_DURABLE_REVIEW_PASS",
            on_success="RECOMPUTE_CONTINUATION",
            on_failure="ROUTE_EVIDENCE_GAP_TO_REVIEW_OR_REPAIR",
            reason="A review PASS is not enough until the durable evidence package is synchronized.",
            session_exit_allowed=True,
            closure_loop_required=False,
            stop_obligation="PERSIST_EXACT_EVIDENCE_REFRESH_ACTION",
        )

    if "REQUIRED_PREDICATES_INCOMPLETE" in blockers:
        return _transition(
            mission=mission,
            handoff_class="ROLE_BOUNDARY",
            next_actor="VERIFIER",
            next_action="COMPLETE_REQUIRED_PREDICATES",
            evidence_sink="EXECUTION_LEDGER",
            resume_condition="ALL_REQUIRED_PREDICATES_DURABLY_VERIFIED",
            on_success="RECOMPUTE_CONTINUATION",
            on_failure="ROUTE_FAILED_PREDICATE_TO_REPAIR",
            reason="Verification is a routine role transition and does not require human message passing.",
            session_exit_allowed=True,
            closure_loop_required=False,
            stop_obligation="PERSIST_VERIFICATION_COMMANDS_AND_MISSING_PREDICATES",
        )

    if state.get("checkpoint_proposal_blocked"):
        return _transition(
            mission=mission,
            handoff_class="SYSTEM_BLOCKED",
            next_actor="DIRECTOR",
            next_action="DIAGNOSE_CHECKPOINT_BLOCKERS",
            evidence_sink="EXECUTION_LEDGER",
            resume_condition="CHECKPOINT_BLOCKERS_EMPTY",
            on_success="RECOMPUTE_CONTINUATION",
            on_failure="RECORD_BLOCKER_AND_REPLAN",
            reason="Unknown checkpoint blockers remain after known routing rules.",
            session_exit_allowed=True,
            closure_loop_required=False,
            stop_obligation="PERSIST_CHECKPOINT_BLOCKER_DIAGNOSIS_AND_NEXT_ACTION",
        )

    return _transition(
        mission=mission,
        handoff_class="ROLE_BOUNDARY",
        next_actor="DIRECTOR",
        next_action="EVALUATE_CHECKPOINT_AND_NEXT_DECLARED_GATE",
        evidence_sink="EXECUTION_LEDGER",
        resume_condition="CANONICAL_CHECKPOINT_OR_DECLARED_POST_GATE_RESULT_RECORDED",
        on_success="RESUME_PARENT_MISSION_OR_DECLARE_MISSION_COMPLETE",
        on_failure="ROUTE_TO_REPAIR_OR_HUMAN_ATTENTION_AS_DECLARED",
        reason="The local Work Order is ready, but only canonical project state can close the end-to-end mission.",
        session_exit_allowed=True,
        closure_loop_required=False,
        stop_obligation="PERSIST_COMPLETE_EVIDENCE_PACKAGE_AND_EXACT_NEXT_GATE",
    )
