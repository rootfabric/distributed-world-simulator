"""Command-line adapter for the restart-safe development control surface."""
from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path

from .checkpoint_planner import build_plan
from .continuation import build_continuation
from .contracts import ContractBundle, ContractValidationError
from .state_builder import build_state

SCHEMA = "distributed_world_simulator.control_development_output.v1"
EXIT_CODES = {"INVALID_INVOCATION":2,"CONTRACT_OR_DEPENDENCY_INVALID":3,"GIT_STATE_INVALID":4,"EXECUTION_STATE_INVALID":5,"INTERNAL_ERROR":6}

class SafeParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise ContractValidationError(f"INVALID_INVOCATION:{message}")

def _emit(payload: dict[str, object]) -> None:
    print(json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")))

def _category(detail: str) -> str:
    if detail.startswith("INVALID_INVOCATION"): return "INVALID_INVOCATION"
    if detail.startswith(("GIT_", "CANONICAL_MAIN_REF_", "MAIN_SHA_")): return "GIT_STATE_INVALID"
    if detail.startswith(("WORK_ORDER_SNAPSHOT_", "EVENT_", "STATE_", "GUARDED_", "EPOCH_INVALIDATED", "REPAIR_MAP_", "BLOCKING_")): return "EXECUTION_STATE_INVALID"
    return "CONTRACT_OR_DEPENDENCY_INVALID"

def _derive_repair_metrics(execution: Path, state: dict[str, object]) -> dict[str, object]:
    """Derive repeated current-defect attempts from the already validated event ledger."""
    reduced = state.get("reduced_work_order", {})
    work_order = state.get("active_work_order", {})
    if not isinstance(reduced, dict) or not isinstance(work_order, dict):
        return {"current_defect_key": None, "same_defect_fix_required_count": 0}
    if reduced.get("state") != "FIX_REQUIRED":
        return {"current_defect_key": None, "same_defect_fix_required_count": 0}
    defect_key = reduced.get("open_blocker")
    if not isinstance(defect_key, str) or not defect_key:
        return {"current_defect_key": None, "same_defect_fix_required_count": 0}
    work_order_id = work_order.get("work_order_id")
    if not isinstance(work_order_id, str) or not work_order_id:
        return {"current_defect_key": defect_key, "same_defect_fix_required_count": 0}
    count = 0
    event_dir = execution / "events" / work_order_id
    for path in sorted(event_dir.rglob("*.json")) if event_dir.exists() else []:
        try:
            event = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise ContractValidationError(f"REPAIR_HISTORY_EVENT_INVALID:{path.name}") from exc
        if not isinstance(event, dict) or event.get("event_type") != "FIX_REQUIRED":
            continue
        event_defect = event.get("blocker") or "FIX_REQUIRED"
        if event_defect == defect_key:
            count += 1
    return {"current_defect_key": defect_key, "same_defect_fix_required_count": count}

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
        bundle = ContractBundle.load(root)
        state = build_state(root, execution)
        repair = state.setdefault("repair", {})
        if not isinstance(repair, dict):
            raise ContractValidationError("REPAIR_STATE_INVALID")
        repair.update(_derive_repair_metrics(execution, state))
        continuation = build_continuation(state, bundle.contracts["continuation_policy"])
        command = args.mode.upper()
        state["command"] = command; state["ok"] = True; state["exit_codes"] = EXIT_CODES
        if args.mode == "plan":
            plan = build_plan(bundle.contracts, state["active_work_order"], state["reduced_work_order"])
            plan["next_action"] = continuation["next_action"]
            plan["session_exit_allowed"] = continuation["session_exit_allowed"]
            plan["closure_loop_required"] = continuation["closure_loop_required"]
            plan["stop_obligation"] = continuation["stop_obligation"]
            state["plan"] = plan
        elif args.mode == "resume":
            state["resume"] = {
                "active_epoch": state["epoch"]["epoch_id"], "branch": state["active_work_order"]["branch"],
                "current_branch_head_sha": state["repository"]["current_branch_head_sha"], "implementation_head_sha": state["repository"]["implementation_head_sha"],
                "last_completed_predicate": state["reduced_work_order"]["last_completed_predicate"], "open_blocker": state["reduced_work_order"]["open_blocker"],
                "next_work_order": state["active_work_order"]["work_order_id"] if continuation["next_actor"] in {"IMPLEMENTER","VERIFIER"} else None,
                "review_state": state["review"]["state"], "open_human_attention": state["human_attention"]["open_items"],
                "human_approval_required_for": state["active_work_order"].get("human_approval_required_for", []), "verification_commands": state["verification_commands"],
                "mission": {"mission_id":continuation["mission_id"],"objective":continuation["objective"],"parent_mission_id":continuation["parent_mission_id"],"mission_complete":continuation["mission_complete"]},
                "next_actor":continuation["next_actor"],"next_action":continuation["next_action"],"handoff_class":continuation["handoff_class"],"evidence_sink":continuation["evidence_sink"],"resume_condition":continuation["resume_condition"],
                "session_exit_allowed":continuation["session_exit_allowed"],"closure_loop_required":continuation["closure_loop_required"],"stop_obligation":continuation["stop_obligation"]}
        state["next"] = {
            "checkpoint":state["active_work_order"]["goal_checkpoint"],"work_order":state["active_work_order"]["work_order_id"],
            "mission_id":continuation["mission_id"],"mission_complete":continuation["mission_complete"],
            "handoff_class":continuation["handoff_class"],"next_actor":continuation["next_actor"],"next_action":continuation["next_action"],
            "evidence_sink":continuation["evidence_sink"],"resume_condition":continuation["resume_condition"],
            "on_success":continuation["on_success"],"on_failure":continuation["on_failure"],
            "human_decision_required":continuation["human_decision_required"],
            "session_exit_allowed":continuation["session_exit_allowed"],"closure_loop_required":continuation["closure_loop_required"],"stop_obligation":continuation["stop_obligation"],
            "verification_commands":state["verification_commands"],"human_gate":state["active_work_order"].get("human_approval_required_for", [])}
        _emit(state); return 0
    except ContractValidationError as exc:
        detail = str(exc); category = _category(detail); _emit({"schema":SCHEMA,"command":command,"ok":False,"error":{"code":category,"detail":detail},"exit_codes":EXIT_CODES}); return EXIT_CODES[category]
    except (OSError, subprocess.SubprocessError) as exc:
        _emit({"schema":SCHEMA,"command":command,"ok":False,"error":{"code":"GIT_STATE_INVALID","detail":type(exc).__name__},"exit_codes":EXIT_CODES}); return EXIT_CODES["GIT_STATE_INVALID"]
    except Exception as exc:
        _emit({"schema":SCHEMA,"command":command,"ok":False,"error":{"code":"INTERNAL_ERROR","detail":type(exc).__name__},"exit_codes":EXIT_CODES}); return EXIT_CODES["INTERNAL_ERROR"]

if __name__ == "__main__": raise SystemExit(main())
