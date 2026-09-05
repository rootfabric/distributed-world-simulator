"""Command-line adapter for restart-safe checkpoint-session development control."""
from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path

from .checkpoint_planner import build_plan
from .continuation import build_continuation
from .contracts import ContractBundle, ContractValidationError
from .execution_selector import resolve_execution
from .git_authority import build_git_authority
from .mission import load_checkpoint_acceptance
from .state_builder import build_state
from .project_overview import canonical_reconciliation_route, project_overview

SCHEMA = "distributed_world_simulator.control_development_output.v1"
EXIT_CODES = {
    "INVALID_INVOCATION": 2,
    "CONTRACT_OR_DEPENDENCY_INVALID": 3,
    "GIT_STATE_INVALID": 4,
    "EXECUTION_STATE_INVALID": 5,
    "INTERNAL_ERROR": 6,
    "ROLE_EXIT_FORBIDDEN": 7,
    "MISSION_EXIT_FORBIDDEN": 8,
}


class SafeParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise ContractValidationError(f"INVALID_INVOCATION:{message}")


def _emit(payload: dict[str, object]) -> None:
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")))


def _category(detail: str) -> str:
    if detail.startswith("INVALID_INVOCATION"):
        return "INVALID_INVOCATION"
    if detail.startswith(("GIT_", "CANONICAL_MAIN_REF_", "MAIN_SHA_", "CHECKPOINT_ACCEPTANCE_TREE_", "CHECKPOINT_ACCEPTANCE_BLOB_")):
        return "GIT_STATE_INVALID"
    if detail.startswith((
        "WORK_ORDER_SNAPSHOT_",
        "EVENT_",
        "STATE_",
        "GUARDED_",
        "EPOCH_INVALIDATED",
        "REPAIR_MAP_",
        "BLOCKING_",
        "ACTIVE_EXECUTION_",
        "EXECUTION_PATH_",
        "CHECKPOINT_ACCEPTANCE_AMBIGUOUS",
    )):
        return "EXECUTION_STATE_INVALID"
    return "CONTRACT_OR_DEPENDENCY_INVALID"


def _attach_mission_state(
    root: Path,
    state: dict[str, object],
    bundle: ContractBundle,
) -> dict[str, object]:
    checkpoint = str(state["active_work_order"]["goal_checkpoint"])  # type: ignore[index]
    state["checkpoint_acceptance"] = load_checkpoint_acceptance(
        root,
        checkpoint,
        str(bundle.contracts["harness_policy"]["canonical_branch"]),
    )
    continuation = build_continuation(
        state, bundle.contracts["continuation_policy"]  # type: ignore[arg-type]
    )
    state["next"] = {
        **continuation,
        "checkpoint": checkpoint,
        "work_order": state["active_work_order"]["work_order_id"],  # type: ignore[index]
        "verification_commands": state["verification_commands"],
        "human_gate": state["active_work_order"].get("human_approval_required_for", []),  # type: ignore[union-attr]
        "git_authority": build_git_authority(bundle.contracts["harness_policy"]),
    }
    return continuation


def _deny_close(
    state: dict[str, object],
    code: str,
    detail: str,
) -> int:
    state["ok"] = False
    state["error"] = {"code": code, "detail": detail}
    _emit(state)
    return EXIT_CODES[code]


def _emit_control_route(command: str, route: dict[str, object]) -> int:
    """A control handoff is not a reduced execution or a mission acceptance."""
    code = None
    if not route["mission_exit_allowed"]:
        code = "MISSION_EXIT_FORBIDDEN" if command == "CLOSE_MISSION" else (
            "ROLE_EXIT_FORBIDDEN" if command == "CLOSE_ROLE" else None)
    payload = {"schema": SCHEMA, "command": command, "ok": code is None,
               "output_kind": "PROJECT_CONTROL_ROUTING", "control_route": route,
               "runtime_authorized": False, "exit_codes": EXIT_CODES}
    if code:
        payload["error"] = {"code": code, "detail": "CONTROL_RECONCILIATION_OR_ACTIVATION_REQUIRED"}
    _emit(payload)
    return EXIT_CODES[code] if code else 0


def main(argv: list[str] | None = None) -> int:
    command = "UNKNOWN"
    parser = SafeParser(add_help=True)
    parser.add_argument(
        "mode",
        choices=("status", "plan", "resume", "drive", "close-role", "close-mission", "overview", "check-consistency"),
    )
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--execution", type=Path)
    parser.add_argument("--checkpoint")
    parser.add_argument("--candidate", action="store_true", help="Non-authorizing checkout preview for overview/consistency only")
    try:
        args = parser.parse_args(argv)
        root = args.root.resolve()
        command = args.mode.replace("-", "_").upper()
        project_mode = args.mode in ("overview", "check-consistency")
        if args.candidate and not project_mode:
            raise ContractValidationError("INVALID_INVOCATION:CANDIDATE_REQUIRES_PROJECT_OVERVIEW_MODE")
        if project_mode:
            if args.execution or args.checkpoint:
                raise ContractValidationError("INVALID_INVOCATION:PROJECT_OVERVIEW_HAS_NO_EXECUTION_SELECTOR")
            overview = project_overview(root, candidate=args.candidate)
            failed = args.mode == "check-consistency" and any(
                item["severity"] == "ERROR" and item["scope"] in ("product_blocking", "observability")
                for item in overview["consistency_findings"]
            )
            payload = {"schema": SCHEMA, "command": command, "ok": not failed,
                       "output_kind": "PROJECT_OVERVIEW", "overview": overview, "exit_codes": EXIT_CODES}
            if failed:
                payload["error"] = {"code": "CONTRACT_OR_DEPENDENCY_INVALID", "detail": "PROJECT_CONSISTENCY_ERRORS"}
            _emit(payload)
            return 3 if failed else 0

        # Default product routing must remain visible even when old epochs can no
        # longer be loaded. Explicit executions still resolve their true checkpoint.
        route = None if args.execution else canonical_reconciliation_route(root, args.checkpoint)
        if route is not None:
            return _emit_control_route(command, route)
        bundle = ContractBundle.load(root)
        execution, selected_checkpoint = resolve_execution(
            root,
            bundle.contracts,
            execution=args.execution,
            checkpoint=args.checkpoint,
        )
        route = canonical_reconciliation_route(root, selected_checkpoint)
        if route is not None:
            return _emit_control_route(command, route)
        state = build_state(root, execution)
        verification_commands = state.setdefault("verification_commands", [])
        for required_command in (
            ".\\CONTROL_DEVELOPMENT.ps1 -Drive",
            ".\\CONTROL_DEVELOPMENT.ps1 -Close",
        ):
            if required_command not in verification_commands:
                verification_commands.append(required_command)
        command = args.mode.replace("-", "_").upper()
        state["command"] = command
        state["ok"] = True
        state["exit_codes"] = EXIT_CODES
        state["selected_execution"] = execution.relative_to(root).as_posix()
        state["selected_checkpoint"] = selected_checkpoint

        continuation = _attach_mission_state(root, state, bundle)

        if args.mode == "plan":
            state["plan"] = build_plan(
                bundle.contracts,
                state["active_work_order"],
                state["reduced_work_order"],
            )
        elif args.mode == "resume":
            state["resume"] = {
                "active_epoch": state["epoch"]["epoch_id"],
                "branch": state["active_work_order"]["branch"],
                "current_branch_head_sha": state["repository"]["current_branch_head_sha"],
                "implementation_head_sha": state["repository"]["implementation_head_sha"],
                "last_completed_predicate": state["reduced_work_order"]["last_completed_predicate"],
                "open_blocker": state["reduced_work_order"]["open_blocker"],
                "next_work_order": state["active_work_order"]["work_order_id"],
                "review_state": state["review"]["state"],
                "open_human_attention": state["human_attention"]["open_items"],
                "human_approval_required_for": state["active_work_order"].get("human_approval_required_for", []),
                "verification_commands": state["verification_commands"],
                "mission_id": continuation["mission_id"],
                "mission_complete": continuation["mission_complete"],
                "mission_exit_allowed": continuation["mission_exit_allowed"],
                "next_actor": continuation["next_actor"],
                "next_action": continuation["next_action"],
                "resume_condition": continuation["resume_condition"],
            }
        elif args.mode == "drive":
            if continuation["mission_complete"]:
                drive_status = "MISSION_COMPLETE"
            elif continuation["human_decision_required"]:
                drive_status = "WAITING_HUMAN"
            elif continuation["hard_blocked"]:
                drive_status = "HARD_BLOCKED"
            else:
                drive_status = "CONTINUE_REQUIRED"
            state["drive"] = {
                "status": drive_status,
                "auto_continue_required": not continuation["mission_exit_allowed"],
                "next_actor": continuation["next_actor"],
                "next_action": continuation["next_action"],
                "resume_condition": continuation["resume_condition"],
                "instruction": (
                    "Execute the returned next role/action inside the same parent checkpoint session, "
                    "using pre-authorized routine A0-A3 Git operations within Work Order scope; "
                    "persist durable evidence, then rerun DRIVE."
                ),
                "git_authority": state["next"]["git_authority"],
            }
        elif args.mode == "close-role" and not continuation["role_exit_allowed"]:
            return _deny_close(
                state,
                "ROLE_EXIT_FORBIDDEN",
                f"ROLE_STILL_OWNS_AUTOMATABLE_WORK:{continuation['next_actor']}:{continuation['next_action']}",
            )
        elif args.mode == "close-mission" and not continuation["mission_exit_allowed"]:
            return _deny_close(
                state,
                "MISSION_EXIT_FORBIDDEN",
                f"CHECKPOINT_MISSION_STILL_OPEN:{continuation['next_actor']}:{continuation['next_action']}",
            )

        _emit(state)
        return 0
    except ContractValidationError as exc:
        detail = str(exc)
        category = _category(detail)
        _emit(
            {
                "schema": SCHEMA,
                "command": command,
                "ok": False,
                "error": {"code": category, "detail": detail},
                "exit_codes": EXIT_CODES,
            }
        )
        return EXIT_CODES[category]
    except (OSError, subprocess.SubprocessError) as exc:
        _emit(
            {
                "schema": SCHEMA,
                "command": command,
                "ok": False,
                "error": {"code": "GIT_STATE_INVALID", "detail": type(exc).__name__},
                "exit_codes": EXIT_CODES,
            }
        )
        return EXIT_CODES["GIT_STATE_INVALID"]
    except Exception as exc:
        _emit(
            {
                "schema": SCHEMA,
                "command": command,
                "ok": False,
                "error": {"code": "INTERNAL_ERROR", "detail": type(exc).__name__},
                "exit_codes": EXIT_CODES,
            }
        )
        return EXIT_CODES["INTERNAL_ERROR"]


if __name__ == "__main__":
    raise SystemExit(main())
