"""Checkpoint mission identity and canonical acceptance lookup."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any

from .contracts import ContractValidationError

_ACCEPTANCE_PREFIX = "config/control/harness/acceptance"


def _git(root: Path, *args: str) -> tuple[int, str]:
    completed = subprocess.run(
        ["git", *args], cwd=root, text=True, capture_output=True, check=False
    )
    return completed.returncode, completed.stdout.strip()


def _canonical_ref(root: Path, canonical_branch: str) -> str:
    for ref in (f"origin/{canonical_branch}", canonical_branch):
        code, value = _git(root, "rev-parse", "--verify", ref)
        if code == 0 and len(value) == 40:
            return ref
    raise ContractValidationError("CANONICAL_MAIN_REF_UNAVAILABLE")


def _parse_json_object(raw: str, label: str) -> dict[str, Any]:
    def reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ContractValidationError(f"JSON_DUPLICATE_KEY:{label}:{key}")
            result[key] = value
        return result

    try:
        value = json.loads(raw, object_pairs_hook=reject_duplicates)
    except ContractValidationError:
        raise
    except json.JSONDecodeError as exc:
        raise ContractValidationError(f"CHECKPOINT_ACCEPTANCE_JSON_INVALID:{label}") from exc
    if not isinstance(value, dict):
        raise ContractValidationError(f"CHECKPOINT_ACCEPTANCE_OBJECT_REQUIRED:{label}")
    return value


def load_checkpoint_acceptance(
    root: Path, checkpoint: str, canonical_branch: str
) -> dict[str, Any] | None:
    """Read acceptance only from the canonical main ref, never from branch prose."""
    canonical_ref = _canonical_ref(root, canonical_branch)
    code, listing = _git(
        root,
        "ls-tree",
        "-r",
        "--name-only",
        canonical_ref,
        "--",
        _ACCEPTANCE_PREFIX,
    )
    if code != 0:
        raise ContractValidationError("CHECKPOINT_ACCEPTANCE_TREE_UNAVAILABLE")

    matches: list[tuple[str, dict[str, Any]]] = []
    for path in sorted(line for line in listing.splitlines() if line.endswith(".json")):
        code, raw = _git(root, "show", f"{canonical_ref}:{path}")
        if code != 0:
            raise ContractValidationError(f"CHECKPOINT_ACCEPTANCE_BLOB_UNAVAILABLE:{path}")
        record = _parse_json_object(raw, path)
        if record.get("checkpoint") == checkpoint and record.get("status") == "ACCEPTED":
            matches.append((path, record))

    if not matches:
        return None

    runtime_heads = {str(record.get("accepted_runtime_head", "")) for _, record in matches}
    if len(runtime_heads) > 1:
        raise ContractValidationError(f"CHECKPOINT_ACCEPTANCE_AMBIGUOUS:{checkpoint}")
    path, record = max(matches, key=lambda item: str(item[1].get("accepted_at_utc", "")))
    return {
        "source": "CANONICAL_MAIN_ACCEPTANCE_RECORD",
        "canonical_ref": canonical_ref,
        "path": path,
        "checkpoint": checkpoint,
        "status": "ACCEPTED",
        "decision": record.get("decision"),
        "accepted_runtime_head": record.get("accepted_runtime_head"),
        "accepted_product_lineage_head": record.get("accepted_product_lineage_head"),
        "accepted_at_utc": record.get("accepted_at_utc"),
    }


def mission_from_state(state: dict[str, Any]) -> dict[str, Any]:
    work_order = state["active_work_order"]
    declared = work_order.get("mission")
    checkpoint = str(work_order["goal_checkpoint"])
    if isinstance(declared, dict):
        mission_id = str(declared.get("mission_id") or f"CHECKPOINT:{checkpoint}")
        objective = str(declared.get("objective") or f"Reach accepted checkpoint {checkpoint}")
        parent = declared.get("parent_mission_id")
        completion_condition = str(
            declared.get("completion_condition") or "CANONICAL_CHECKPOINT_ACCEPTED"
        )
    else:
        mission_id = f"CHECKPOINT:{checkpoint}"
        objective = f"Reach accepted checkpoint {checkpoint}"
        parent = None
        completion_condition = "CANONICAL_CHECKPOINT_ACCEPTED"

    acceptance = state.get("checkpoint_acceptance")
    mission_complete = bool(
        isinstance(acceptance, dict)
        and acceptance.get("checkpoint") == checkpoint
        and acceptance.get("status") == "ACCEPTED"
    )
    return {
        "mission_id": mission_id,
        "objective": objective,
        "parent_mission_id": parent,
        "goal_checkpoint": checkpoint,
        "session_scope": "CHECKPOINT",
        "completion_condition": completion_condition,
        "mission_complete": mission_complete,
    }
