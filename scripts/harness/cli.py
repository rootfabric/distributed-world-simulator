"""Command-line adapter for the restart-safe development control surface."""
from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path

from .checkpoint_planner import build_plan
from .contracts import ContractBundle, ContractValidationError
from .state_builder import build_state


SCHEMA = "distributed_world_simulator.control_development_output.v1"
EXIT_CODES = {
    "INVALID_INVOCATION": 2,
    "CONTRACT_OR_DEPENDENCY_INVALID": 3,
    "GIT_STATE_INVALID": 4,
    "EXECUTION_STATE_INVALID": 5,
    "INTERNAL_ERROR": 6,
}


class SafeParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise ContractValidationError(f"INVALID_INVOCATION:{message}")


def _emit(payload: dict[str, object]) -> None:
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")))


def _category(detail: str) -> str:
    if detail.startswith("INVALID_INVOCATION"):
        return "INVALID_INVOCATION"
    if detail.startswith(("GIT_", "CANONICAL_MAIN_REF_", "MAIN_SHA_")):
        return "GIT_STATE_INVALID"
    if detail.startswith(("WORK_ORDER_SNAPSHOT_", "EVENT_", "STATE_", "GUARDED_", "EPOCH_INVALIDATED", "REPAIR_MAP_", "BLOCKING_")):
        return "EXECUTION_STATE_INVALID"
    return "CONTRACT_OR_DEPENDENCY_INVALID"


def main(argv: list[str] | None = None) -> int:
    command = "UNKNOWN"
    parser = SafeParser(add_help=True)
    parser.add_argument("mode", choices=("status", "plan", "resume"))
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--execution", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        root = args.root.resolve()
        execution = args.execution if args.execution.is_absolute() else root / args.execution
        state = build_state(root, execution)
        command = args.mode.upper()
        state["command"] = command
        state["ok"] = True
        state["exit_codes"] = EXIT_CODES
        if args.mode == "plan":
            state["plan"] = build_plan(
                ContractBundle.load(root).contracts,
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
            }
        state["next"] = {
            "checkpoint": state["active_work_order"]["goal_checkpoint"],
            "work_order": state["active_work_order"]["work_order_id"],
            "verification_commands": state["verification_commands"],
            "human_gate": state["active_work_order"].get("human_approval_required_for", []),
        }
        _emit(state)
        return 0
    except ContractValidationError as exc:
        detail = str(exc)
        category = _category(detail)
        _emit({"schema": SCHEMA, "command": command, "ok": False, "error": {"code": category, "detail": detail}, "exit_codes": EXIT_CODES})
        return EXIT_CODES[category]
    except (OSError, subprocess.SubprocessError) as exc:
        _emit({"schema": SCHEMA, "command": command, "ok": False, "error": {"code": "GIT_STATE_INVALID", "detail": type(exc).__name__}, "exit_codes": EXIT_CODES})
        return EXIT_CODES["GIT_STATE_INVALID"]
    except Exception as exc:
        _emit({"schema": SCHEMA, "command": command, "ok": False, "error": {"code": "INTERNAL_ERROR", "detail": type(exc).__name__}, "exit_codes": EXIT_CODES})
        return EXIT_CODES["INTERNAL_ERROR"]


if __name__ == "__main__":
    raise SystemExit(main())
