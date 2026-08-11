"""Project Epoch freshness checks against Git, without mutating refs."""
from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Any

from .contracts import ContractValidationError


def _git(root: Path, *args: str) -> tuple[int, str]:
    try:
        completed = subprocess.run(["git", *args], cwd=root, text=True, capture_output=True, check=False)
    except (OSError, subprocess.SubprocessError) as exc:
        raise ContractValidationError(f"GIT_COMMAND_FAILED:{args[0]}") from exc
    return completed.returncode, completed.stdout.strip()


def current_main_sha(root: Path, canonical_branch: str) -> str:
    for candidate in (f"origin/{canonical_branch}", canonical_branch):
        code, value = _git(root, "rev-parse", candidate)
        if code == 0 and len(value) == 40:
            return value
    raise ContractValidationError("CANONICAL_MAIN_REF_UNAVAILABLE")


def validate_epoch(root: Path, epoch: dict[str, Any], canonical_branch: str, audit_continue: bool, main_sha: str | None = None) -> dict[str, Any]:
    base_sha = epoch["base_sha"]
    actual_main = main_sha or current_main_sha(root, canonical_branch)
    if len(actual_main) != 40:
        raise ContractValidationError("MAIN_SHA_INVALID")
    if epoch.get("status") == "INVALIDATED" or epoch.get("decision") == "REFRESH_REQUIRED":
        return {"status": "EPOCH_INVALIDATED", "base_sha": base_sha, "main_sha": actual_main,
                "action": "STOP_AND_REFRESH", "reason": "EPOCH_MARKED_INVALIDATED"}
    if actual_main == base_sha:
        return {"status": "EXACT_BASE", "base_sha": base_sha, "main_sha": actual_main,
                "action": "CONTINUE", "reason": "CANONICAL_MAIN_EQUALS_EPOCH_BASE"}
    code, _ = _git(root, "merge-base", "--is-ancestor", base_sha, actual_main)
    if code == 0 and audit_continue:
        return {"status": "MAIN_MOVED_AUDIT_CONTINUE", "base_sha": base_sha, "main_sha": actual_main,
                "action": "CONTINUE", "reason": "RECORDED_AUDIT_PERMITS_CONTINUATION"}
    if code == 0:
        return {"status": "MAIN_MOVED_REVIEW_REQUIRED", "base_sha": base_sha, "main_sha": actual_main,
                "action": "BLOCK_CONTINUATION", "reason": "CANONICAL_MAIN_ADVANCED_WITHOUT_RECORDED_AUDIT"}
    return {"status": "EPOCH_INVALIDATED", "base_sha": base_sha, "main_sha": actual_main,
            "action": "STOP_AND_REFRESH", "reason": "EPOCH_BASE_NOT_ANCESTOR_OF_CANONICAL_MAIN"}
