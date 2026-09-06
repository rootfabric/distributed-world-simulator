"""Resolve the active Harness execution without hard-coding an old pilot path."""
from __future__ import annotations

from datetime import datetime
from pathlib import Path
import re
from typing import Any

from .contracts import ContractValidationError, read_json


def _issued_at(value: dict[str, Any]) -> datetime:
    raw = str(value.get("issued_at_utc", ""))
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ContractValidationError(f"WORK_ORDER_ISSUED_AT_INVALID:{raw}") from exc


def default_checkpoint(contracts: dict[str, dict[str, Any]]) -> str:
    scheduler = contracts["scheduler_policy"]
    product = scheduler.get("v0_product_train_routing")
    if isinstance(product, dict) and product.get("current_checkpoint"):
        return str(product["current_checkpoint"])
    pilot = scheduler.get("current_pilot_override")
    if isinstance(pilot, dict) and pilot.get("current_checkpoint"):
        return str(pilot["current_checkpoint"])
    raise ContractValidationError("ACTIVE_CHECKPOINT_NOT_DECLARED")


def _require_canonical_execution_path(root: Path, candidate: Path) -> None:
    """Bind explicit execution selection to the directory named by its committed identity.

    build_state() reads transition/work-order/event files from the selected directory.
    An arbitrary in-repository clone/alias must therefore never be allowed to carry a
    canonical epoch id while supplying different worktree-controlled authority inputs.
    """
    epoch = read_json(candidate / "project-epoch.v1.json")
    epoch_id = epoch.get("epoch_id")
    if not isinstance(epoch_id, str) or re.fullmatch(r"[A-Za-z0-9._-]+", epoch_id) is None:
        raise ContractValidationError("ACTIVE_EXECUTION_EPOCH_ID_INVALID")
    expected = (root / "config/control/harness/executions" / epoch_id).resolve()
    if candidate != expected:
        raise ContractValidationError(
            f"EXECUTION_PATH_NOT_CANONICAL:{candidate.relative_to(root).as_posix()}:{expected.relative_to(root).as_posix()}"
        )


def resolve_execution(
    root: Path,
    contracts: dict[str, dict[str, Any]],
    execution: Path | None = None,
    checkpoint: str | None = None,
) -> tuple[Path, str]:
    root = root.resolve()
    if execution is not None:
        candidate = execution if execution.is_absolute() else root / execution
        candidate = candidate.resolve()
        try:
            candidate.relative_to(root)
        except ValueError as exc:
            raise ContractValidationError("EXECUTION_PATH_ESCAPES_REPOSITORY") from exc
        if not (candidate / "project-epoch.v1.json").is_file() or not (candidate / "work-orders").is_dir():
            raise ContractValidationError(f"EXECUTION_PATH_INVALID:{candidate}")
        _require_canonical_execution_path(root, candidate)
        work_order_paths = sorted((candidate / "work-orders").rglob("*.json"))
        if not work_order_paths:
            raise ContractValidationError(f"ACTIVE_EXECUTION_WORK_ORDER_NOT_FOUND:{candidate}")
        active_work_order = read_json(work_order_paths[-1])
        actual_checkpoint = str(active_work_order.get("goal_checkpoint", ""))
        if not actual_checkpoint:
            raise ContractValidationError(f"ACTIVE_EXECUTION_CHECKPOINT_NOT_DECLARED:{candidate}")
        if checkpoint is not None and checkpoint != actual_checkpoint:
            raise ContractValidationError(
                f"ACTIVE_EXECUTION_CHECKPOINT_MISMATCH:{checkpoint}:{actual_checkpoint}"
            )
        return candidate, actual_checkpoint

    target = checkpoint or default_checkpoint(contracts)
    executions_root = root / "config" / "control" / "harness" / "executions"
    candidates: dict[Path, tuple[datetime, str]] = {}
    if executions_root.is_dir():
        for work_order_path in executions_root.glob("*/work-orders/*.json"):
            work_order = read_json(work_order_path)
            if work_order.get("goal_checkpoint") != target:
                continue
            execution_dir = work_order_path.parent.parent.resolve()
            issued = _issued_at(work_order)
            previous = candidates.get(execution_dir)
            if previous is None or issued > previous[0]:
                candidates[execution_dir] = (issued, str(work_order.get("work_order_id", "")))
    if not candidates:
        raise ContractValidationError(f"ACTIVE_EXECUTION_NOT_FOUND:{target}")

    ordered = sorted(
        ((issued, work_order_id, path) for path, (issued, work_order_id) in candidates.items()),
        key=lambda item: (item[0], item[1], item[2].as_posix()),
        reverse=True,
    )
    if len(ordered) > 1 and ordered[0][0] == ordered[1][0]:
        raise ContractValidationError(f"ACTIVE_EXECUTION_AMBIGUOUS:{target}")
    return ordered[0][2], target
