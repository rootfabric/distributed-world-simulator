#!/usr/bin/env python3
"""PC0 project control auditor with fail-closed architecture passport compatibility.

The legacy auditor implementation remains in project_control_core.py. This
facade preserves exact-match behavior by default and permits an older Branch
Passport architecture revision only when BOTH conditions hold:

1. the main-owned Project Control policy enables explicit historical
   compatibility; and
2. the main-owned central registry entry for that exact program explicitly
   allowlists the exact historical passport revision.

This is provenance compatibility only. It never relabels historical evidence
and never authorizes new work on an old architecture revision.
"""

from __future__ import annotations

from typing import Any

import project_control_core as _core
from project_control_core import *  # noqa: F401,F403

_ORIGINAL_AUDIT_PROGRAM = _core.audit_program
_COMPATIBILITY_MODE = "EXPLICIT_PER_PROGRAM_HISTORICAL_ALLOWLIST"
_DEFAULT_REGISTRY_FIELD = "historical_passport_architecture_revisions"


def evaluate_passport_architecture_compatibility(
    central: dict[str, Any],
    registry: dict[str, Any],
    passport: dict[str, Any],
    policy: dict[str, Any],
) -> dict[str, Any]:
    """Return a deterministic fail-closed compatibility decision.

    Exact canonical revision equality always passes. A historical mismatch can
    pass only under the explicitly enabled per-program allowlist contract. Any
    missing/malformed policy or allowlist fails closed for a mismatch.
    """
    canonical_revision = str(registry.get("architecture_revision", ""))
    passport_revision = str(passport.get("architecture_revision", ""))
    if passport_revision == canonical_revision:
        return {
            "compatible": True,
            "mode": "EXACT_CANONICAL_REVISION",
            "passport_revision": passport_revision,
            "canonical_revision": canonical_revision,
            "allowlist_field": None,
            "allowed_historical_revisions": [],
        }

    compatibility_policy = policy.get("passport_architecture_compatibility", {})
    if not isinstance(compatibility_policy, dict):
        compatibility_policy = {}
    mode = str(compatibility_policy.get("mode", ""))
    field = str(compatibility_policy.get("central_registry_field", _DEFAULT_REGISTRY_FIELD))
    if mode != _COMPATIBILITY_MODE or not field:
        return {
            "compatible": False,
            "mode": "STRICT_MISMATCH_POLICY_NOT_ENABLED",
            "passport_revision": passport_revision,
            "canonical_revision": canonical_revision,
            "allowlist_field": field or _DEFAULT_REGISTRY_FIELD,
            "allowed_historical_revisions": [],
        }

    allowed_raw = central.get(field, [])
    if not isinstance(allowed_raw, list) or any(not isinstance(value, str) or not value for value in allowed_raw):
        return {
            "compatible": False,
            "mode": "STRICT_MISMATCH_MALFORMED_ALLOWLIST",
            "passport_revision": passport_revision,
            "canonical_revision": canonical_revision,
            "allowlist_field": field,
            "allowed_historical_revisions": [],
        }

    allowed = list(dict.fromkeys(allowed_raw))
    compatible = passport_revision in allowed
    return {
        "compatible": compatible,
        "mode": "EXPLICIT_HISTORICAL_REVISION_ALLOWED" if compatible else "STRICT_MISMATCH_NOT_ALLOWLISTED",
        "passport_revision": passport_revision,
        "canonical_revision": canonical_revision,
        "allowlist_field": field,
        "allowed_historical_revisions": allowed,
    }


def _recompute_health(result: dict[str, Any]) -> None:
    declared = str(result.get("health_declared", "GREEN"))
    health = declared if declared in _core.HEALTH_RANK else "YELLOW"
    for finding in result.get("findings", []):
        if not isinstance(finding, dict):
            continue
        level = str(finding.get("level", "GREEN"))
        if _core.HEALTH_RANK.get(level, 0) > _core.HEALTH_RANK.get(health, 0):
            health = level
    result["health"] = health


def audit_program(
    key: str,
    central: dict[str, Any],
    registry: dict[str, Any],
    policy: dict[str, Any],
    ownership: dict[str, Any],
) -> dict[str, Any]:
    result = _ORIGINAL_AUDIT_PROGRAM(key, central, registry, policy, ownership)
    passport_path = str(central.get("passport_path", ""))
    branch = str(central.get("branch", ""))
    if not branch or not passport_path or not result.get("passport_loaded"):
        return result

    passport = _core.load_branch_json(_core.remote_ref(branch), passport_path)
    if passport is None:
        return result

    decision = evaluate_passport_architecture_compatibility(central, registry, passport, policy)
    result["architecture_compatibility"] = decision
    if not decision["compatible"] or decision["mode"] == "EXACT_CANONICAL_REVISION":
        return result

    result["findings"] = [
        finding for finding in result.get("findings", [])
        if not (isinstance(finding, dict) and finding.get("code") == "ARCHITECTURE_REVISION_MISMATCH")
    ]
    _recompute_health(result)
    return result


_core.audit_program = audit_program
main = _core.main


if __name__ == "__main__":
    raise SystemExit(main())
