"""Derive project-level Git authority for an active checkpoint mission."""
from __future__ import annotations

from typing import Any


def build_git_authority(policy: dict[str, Any]) -> dict[str, Any]:
    configured = policy.get("git_execution_authority", {})
    if not isinstance(configured, dict):
        configured = {}
    return {
        "status": str(
            configured.get(
                "default_mode", "PREAUTHORIZED_WITHIN_ACTIVE_CHECKPOINT_MISSION"
            )
        ),
        "autonomy_ceiling": str(
            policy.get("default_autonomy_ceiling", "A3_INTEGRATE_CANDIDATE")
        ),
        "scope": str(
            configured.get(
                "scope", "ACTIVE_CHECKPOINT_MISSION_AND_ACTIVE_WORK_ORDER"
            )
        ),
        "routine_confirmation_required": bool(
            configured.get("routine_confirmation_required", False)
        ),
        "routine_operations": list(configured.get("routine_operations", [])),
        "human_confirmation_required_for": list(
            configured.get("human_confirmation_required_for", [])
        ),
        "external_tool_boundary": str(configured.get("external_tool_boundary", "")),
    }
