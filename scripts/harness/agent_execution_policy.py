"""Model-neutral execution-slice policy layered over the canonical DWS Harness.

This module never changes checkpoint truth, mission completion, review requirements,
or Git authority. It only decides whether the current agent execution slice may
yield after durable state has been persisted.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

PROFILE_SCHEMA = "distributed_world_simulator.agent_execution_profiles.v1"
DECISION_SCHEMA = "distributed_world_simulator.agent_execution_decision.v1"
DEFAULT_CONFIG = Path("config/control/harness/agent-execution-profiles.v1.json")


class AgentExecutionPolicyError(ValueError):
    pass


def load_profile_config(root: Path) -> dict[str, Any]:
    path = root / DEFAULT_CONFIG
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise AgentExecutionPolicyError("AGENT_EXECUTION_PROFILE_CONFIG_INVALID") from exc
    if not isinstance(value, dict) or value.get("schema") != PROFILE_SCHEMA:
        raise AgentExecutionPolicyError("AGENT_EXECUTION_PROFILE_SCHEMA_INVALID")
    profiles = value.get("profiles")
    if not isinstance(profiles, dict) or not profiles:
        raise AgentExecutionPolicyError("AGENT_EXECUTION_PROFILES_REQUIRED")
    default_profile = value.get("default_profile")
    if default_profile not in profiles:
        raise AgentExecutionPolicyError("AGENT_EXECUTION_DEFAULT_PROFILE_INVALID")
    return value


def resolve_profile(config: dict[str, Any], requested: str | None) -> tuple[str, dict[str, Any]]:
    profiles = config["profiles"]
    name = requested or str(config["default_profile"])
    profile = profiles.get(name)
    if not isinstance(profile, dict):
        raise AgentExecutionPolicyError(f"AGENT_EXECUTION_PROFILE_UNKNOWN:{name}")
    return name, profile


def evaluate_execution_slice(
    state: dict[str, Any],
    continuation: dict[str, Any],
    config: dict[str, Any],
    profile_name: str | None = None,
    *,
    external_pending: bool = False,
    external_ref: str | None = None,
    resumed: bool = False,
) -> dict[str, Any]:
    name, profile = resolve_profile(config, profile_name)
    global_rules = config.get("global_rules", {})
    repository = state.get("repository", {})
    worktree_dirty = bool(repository.get("worktree_dirty", True))
    findings = set(state.get("findings", []))
    state_name = str(state.get("reduced_work_order", {}).get("state", ""))
    next_actor = str(continuation.get("next_actor", ""))
    next_action = str(continuation.get("next_action", ""))
    handoff_class = str(continuation.get("handoff_class", ""))
    mission_exit_allowed = bool(continuation.get("mission_exit_allowed"))
    role_exit_allowed = bool(continuation.get("role_exit_allowed"))

    branch_mismatch = "WORK_ORDER_BRANCH_NOT_CHECKED_OUT" in findings
    safe_states = set(global_rules.get("external_pending_safe_states", []))
    same_role_states = set(profile.get("same_role_yield_states", []))
    durable_role_boundary = role_exit_allowed or handoff_class == "ROLE_BOUNDARY"
    same_role_boundary = state_name in same_role_states
    durable_boundary = (
        not worktree_dirty
        and not branch_mismatch
        and (durable_role_boundary or same_role_boundary)
    )
    external_boundary = (
        external_pending
        and bool(profile.get("yield_on_external_pending", True))
        and not worktree_dirty
        and not branch_mismatch
        and state_name in safe_states
    )

    if mission_exit_allowed:
        yield_allowed = True
        yield_recommended = True
        reason = "MISSION_TERMINAL"
    elif external_pending and not external_boundary:
        yield_allowed = False
        yield_recommended = False
        if worktree_dirty:
            reason = "EXTERNAL_PENDING_BUT_WORKTREE_DIRTY"
        elif branch_mismatch:
            reason = "EXTERNAL_PENDING_BUT_WRONG_WORK_ORDER_BRANCH"
        else:
            reason = f"EXTERNAL_PENDING_NOT_SAFE_IN_STATE:{state_name}"
    else:
        yield_allowed = durable_boundary or external_boundary
        excluded_actions = set(global_rules.get("do_not_recommend_yield_actions", []))
        fresh_context_actors = set(profile.get("fresh_context_actors", []))
        profile_recommends = (
            (bool(profile.get("yield_on_durable_role_boundary")) and durable_role_boundary)
            or (
                bool(profile.get("yield_on_fresh_context_boundary"))
                and next_actor in fresh_context_actors
            )
            or state_name in set(profile.get("yield_on_states", []))
        )
        yield_recommended = yield_allowed and (
            external_boundary
            or (profile_recommends and next_action not in excluded_actions)
        )
        if external_boundary:
            reason = "EXTERNAL_DEPENDENCY_PENDING"
        elif yield_recommended:
            reason = "PROFILE_RECOMMENDS_FRESH_EXECUTION_SLICE"
        elif yield_allowed:
            reason = "SAFE_DURABLE_BOUNDARY_CONTINUATION_PREFERRED"
        elif worktree_dirty:
            reason = "WORKTREE_DIRTY"
        elif branch_mismatch:
            reason = "WRONG_WORK_ORDER_BRANCH"
        else:
            reason = "NO_SAFE_DURABLE_SESSION_BOUNDARY"

    if resumed and not external_pending and not mission_exit_allowed:
        yield_recommended = False
        reason = "RESUME_REQUIRES_PROGRESS_BEFORE_REEVALUATING_YIELD"

    return {
        "schema": DECISION_SCHEMA,
        "profile": name,
        "session_yield_allowed": yield_allowed,
        "session_yield_recommended": yield_recommended,
        "immediate_continue_required": not mission_exit_allowed and not yield_recommended,
        "mission_remains_open": not mission_exit_allowed,
        "mission_exit_allowed": mission_exit_allowed,
        "resume_required": yield_allowed and not mission_exit_allowed,
        "resume_requires_progress_before_reyield": resumed and not external_pending and not mission_exit_allowed,
        "reason": reason,
        "work_state": state_name,
        "handoff_class": handoff_class,
        "next_actor": next_actor,
        "next_action": next_action,
        "external_pending": external_pending,
        "external_ref": external_ref,
        "worktree_dirty": worktree_dirty,
        "branch_mismatch": branch_mismatch,
    }


def _build_live_context(
    root: Path,
    *,
    execution: Path | None = None,
    checkpoint: str | None = None,
) -> tuple[dict[str, Any], dict[str, Any], Path, str]:
    from .continuation import build_continuation
    from .contracts import ContractBundle
    from .execution_selector import resolve_execution
    from .mission import load_checkpoint_acceptance
    from .state_builder import build_state

    bundle = ContractBundle.load(root)
    selected_execution, selected_checkpoint = resolve_execution(
        root,
        bundle.contracts,
        execution=execution,
        checkpoint=checkpoint,
    )
    state = build_state(root, selected_execution)
    goal_checkpoint = str(state["active_work_order"]["goal_checkpoint"])
    state["checkpoint_acceptance"] = load_checkpoint_acceptance(
        root,
        goal_checkpoint,
        str(bundle.contracts["harness_policy"]["canonical_branch"]),
    )
    continuation = build_continuation(
        state,
        bundle.contracts["continuation_policy"],
    )
    return state, continuation, selected_execution, selected_checkpoint


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("drive", "resume", "yield"))
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--profile")
    parser.add_argument("--execution", type=Path)
    parser.add_argument("--checkpoint")
    parser.add_argument("--external-pending", action="store_true")
    parser.add_argument("--external-ref")
    args = parser.parse_args(argv)

    root = args.root.resolve()
    try:
        config = load_profile_config(root)
        state, continuation, selected_execution, selected_checkpoint = _build_live_context(
            root,
            execution=args.execution,
            checkpoint=args.checkpoint,
        )
        decision = evaluate_execution_slice(
            state,
            continuation,
            config,
            args.profile,
            external_pending=args.external_pending,
            external_ref=args.external_ref,
            resumed=args.mode == "resume",
        )
        payload = {
            "schema": DECISION_SCHEMA,
            "command": args.mode.upper(),
            "ok": True,
            "selected_execution": selected_execution.relative_to(root).as_posix(),
            "selected_checkpoint": selected_checkpoint,
            "branch": state["repository"]["current_branch"],
            "current_branch_head_sha": state["repository"]["current_branch_head_sha"],
            "implementation_head_sha": state["repository"]["implementation_head_sha"],
            "mission": {
                "mission_id": continuation["mission_id"],
                "mission_complete": continuation["mission_complete"],
                "mission_exit_allowed": continuation["mission_exit_allowed"],
                "goal_checkpoint": continuation["goal_checkpoint"],
            },
            "next": {
                "actor": continuation["next_actor"],
                "action": continuation["next_action"],
                "resume_condition": continuation["resume_condition"],
                "handoff_class": continuation["handoff_class"],
            },
            "agent_execution": decision,
        }
        if args.mode == "yield" and not decision["session_yield_allowed"]:
            payload["ok"] = False
            payload["error"] = {
                "code": "SESSION_YIELD_FORBIDDEN",
                "detail": decision["reason"],
            }
            print(json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
            return 9

        print(json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
        return 0
    except AgentExecutionPolicyError as exc:
        print(
            json.dumps(
                {
                    "schema": DECISION_SCHEMA,
                    "command": args.mode.upper(),
                    "ok": False,
                    "error": {"code": "AGENT_EXECUTION_POLICY_INVALID", "detail": str(exc)},
                },
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            )
        )
        return 3
    except Exception as exc:
        print(
            json.dumps(
                {
                    "schema": DECISION_SCHEMA,
                    "command": args.mode.upper(),
                    "ok": False,
                    "error": {
                        "code": "CONTROL_STATE_UNAVAILABLE",
                        "detail": f"{type(exc).__name__}:{exc}",
                    },
                },
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            )
        )
        return 4


if __name__ == "__main__":
    raise SystemExit(main())
