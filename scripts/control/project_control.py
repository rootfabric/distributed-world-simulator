#!/usr/bin/env python3
"""PC0 outer auditor for fail-closed historical ownership compatibility.

The accepted architecture-compatibility auditor remains byte-preserved in
project_control_architecture_compat.py. This module only filters exact historical
FOUNDATION_OWNERSHIP_CONFLICT findings after that preserved layer has proved one
immutable historical passport identity.
"""

from __future__ import annotations

import json
from copy import deepcopy
from typing import Any

import project_control_architecture_compat as _arch
from project_control_architecture_compat import *  # noqa: F401,F403

_core = _arch._core
_ORIGINAL_AUDIT_PROGRAM = _arch._ORIGINAL_AUDIT_PROGRAM
_ARCHITECTURE_AUDIT_PROGRAM = _arch.audit_program

_OWNERSHIP_COMPAT_MODE = "EXPLICIT_PER_PROGRAM_HISTORICAL_OWNERSHIP_TRANSITIONS"
_OWNERSHIP_TRANSITION_REGISTRY_FIELD = "historical_passport_ownership_transitions"
_ARCHITECTURE_COMPAT_PREREQUISITE = "EXPLICIT_HISTORICAL_IDENTITY_ALLOWED"
_HISTORICAL_OWNERSHIP_REVISION = "GLOBAL-P0-2026-08-10-R2"
_HISTORICAL_OWNERSHIP_COMMIT = "ce40dd075045078ed70924f8d5a1011eb3eff03d"
_HISTORICAL_OWNERSHIP_PATH = "config/control/architecture-ownership.v1.json"
_HISTORICAL_OWNERSHIP_BLOB = "0cebf594ac7900292318d7533e4439cc7f3764d6"
_REQUIRED_TRANSITION_FIELDS = (
    "program",
    "architecture_revision",
    "foundation",
    "historical_owner",
    "canonical_owner",
)
_WILDCARD_MARKERS = ("*", "?", "[")


def _recompute_health(result: dict[str, Any]) -> None:
    _arch._recompute_health(result)


def _strict_ownership_metadata(reason: str) -> dict[str, Any]:
    return {
        "mode": "STRICT_HISTORICAL_OWNERSHIP_TRANSITION_REQUIRED",
        "reason": reason,
        "historical_source_revision": _HISTORICAL_OWNERSHIP_REVISION,
        "historical_source_commit_sha": _HISTORICAL_OWNERSHIP_COMMIT,
        "historical_source_blob_sha": _HISTORICAL_OWNERSHIP_BLOB,
        "authorized_conflicts": [],
    }


def _ownership_metadata(authorized_conflicts: list[dict[str, str]]) -> dict[str, Any]:
    return {
        "mode": _OWNERSHIP_COMPAT_MODE,
        "historical_source_revision": _HISTORICAL_OWNERSHIP_REVISION,
        "historical_source_commit_sha": _HISTORICAL_OWNERSHIP_COMMIT,
        "historical_source_blob_sha": _HISTORICAL_OWNERSHIP_BLOB,
        "authorized_conflicts": authorized_conflicts,
    }


def _fail_closed(result: dict[str, Any], reason: str) -> dict[str, Any]:
    result["ownership_compatibility"] = _strict_ownership_metadata(reason)
    return result


def _load_historical_ownership_source(
    policy: dict[str, Any],
) -> tuple[dict[str, Any] | None, str]:
    section = policy.get("passport_ownership_compatibility")
    if not isinstance(section, dict):
        return None, "OWNERSHIP_COMPATIBILITY_POLICY_MISSING"
    if section.get("mode") != _OWNERSHIP_COMPAT_MODE:
        return None, "OWNERSHIP_COMPATIBILITY_MODE_INVALID"

    registry_field = section.get("central_registry_field")
    if not isinstance(registry_field, str) or registry_field != _OWNERSHIP_TRANSITION_REGISTRY_FIELD:
        return None, "OWNERSHIP_TRANSITION_REGISTRY_FIELD_INVALID"
    prerequisite = section.get("architecture_compatibility_prerequisite")
    if prerequisite != _ARCHITECTURE_COMPAT_PREREQUISITE:
        return None, "OWNERSHIP_ARCHITECTURE_PREREQUISITE_INVALID"

    required_fields = section.get("required_transition_fields")
    if required_fields != list(_REQUIRED_TRANSITION_FIELDS):
        return None, "OWNERSHIP_TRANSITION_REQUIRED_FIELDS_INVALID"

    source = section.get("historical_canonical_ownership_source")
    if not isinstance(source, dict):
        return None, "HISTORICAL_OWNERSHIP_SOURCE_INVALID"
    expected_source = {
        "architecture_revision": _HISTORICAL_OWNERSHIP_REVISION,
        "commit_sha": _HISTORICAL_OWNERSHIP_COMMIT,
        "path": _HISTORICAL_OWNERSHIP_PATH,
        "blob_sha": _HISTORICAL_OWNERSHIP_BLOB,
    }
    if source != expected_source:
        return None, "HISTORICAL_OWNERSHIP_SOURCE_PIN_INVALID"

    resolved_commit = _core.git(
        "rev-parse", "--verify", f"{_HISTORICAL_OWNERSHIP_COMMIT}^{{commit}}", allow_fail=True
    )
    if resolved_commit != _HISTORICAL_OWNERSHIP_COMMIT:
        return None, "HISTORICAL_OWNERSHIP_SOURCE_COMMIT_MISSING"
    resolved_blob = _core.git(
        "rev-parse",
        "--verify",
        f"{_HISTORICAL_OWNERSHIP_COMMIT}:{_HISTORICAL_OWNERSHIP_PATH}",
        allow_fail=True,
    )
    if resolved_blob != _HISTORICAL_OWNERSHIP_BLOB:
        return None, "HISTORICAL_OWNERSHIP_SOURCE_BLOB_MISMATCH"
    raw = _core.git(
        "show", f"{_HISTORICAL_OWNERSHIP_COMMIT}:{_HISTORICAL_OWNERSHIP_PATH}", allow_fail=True
    )
    if not raw:
        return None, "HISTORICAL_OWNERSHIP_SOURCE_PATH_MISSING"
    try:
        historical = json.loads(raw)
    except json.JSONDecodeError:
        return None, "HISTORICAL_OWNERSHIP_SOURCE_JSON_INVALID"
    if not isinstance(historical, dict):
        return None, "HISTORICAL_OWNERSHIP_SOURCE_JSON_INVALID"
    if historical.get("architecture_revision") != _HISTORICAL_OWNERSHIP_REVISION:
        return None, "HISTORICAL_OWNERSHIP_SOURCE_REVISION_MISMATCH"
    return historical, ""


def _load_transitions(central: dict[str, Any]) -> tuple[list[dict[str, str]] | None, str]:
    raw = central.get(_OWNERSHIP_TRANSITION_REGISTRY_FIELD, [])
    if not isinstance(raw, list):
        return None, "OWNERSHIP_TRANSITION_LIST_MALFORMED"
    transitions: list[dict[str, str]] = []
    for item in raw:
        if not isinstance(item, dict) or set(item) != set(_REQUIRED_TRANSITION_FIELDS):
            return None, "OWNERSHIP_TRANSITION_RECORD_MALFORMED"
        normalized: dict[str, str] = {}
        for field in _REQUIRED_TRANSITION_FIELDS:
            value = item.get(field)
            if not isinstance(value, str) or not value or any(marker in value for marker in _WILDCARD_MARKERS):
                return None, "OWNERSHIP_TRANSITION_RECORD_MALFORMED"
            normalized[field] = value
        transitions.append(normalized)
    return transitions, ""


def _matching_claim(
    result: dict[str, Any], foundation: str, claimed_owner: str
) -> dict[str, Any] | None:
    matches = [
        claim
        for claim in result.get("ownership_claims", [])
        if isinstance(claim, dict)
        and claim.get("foundation") == foundation
        and claim.get("claimed_owner") == claimed_owner
    ]
    return matches[0] if len(matches) == 1 else None


def _authorized_conflict(
    *,
    program: str,
    passport_revision: str,
    finding: dict[str, Any],
    result: dict[str, Any],
    transitions: list[dict[str, str]],
    historical_ownership: dict[str, Any],
    current_ownership: dict[str, Any],
) -> tuple[dict[str, str] | None, bool]:
    if finding.get("code") != "FOUNDATION_OWNERSHIP_CONFLICT":
        return None, False

    historical_foundations = historical_ownership.get("foundations")
    current_foundations = current_ownership.get("foundations")
    if not isinstance(historical_foundations, dict) or not isinstance(current_foundations, dict):
        return None, False

    candidate_matches: list[tuple[dict[str, str], str, str]] = []
    for transition in transitions:
        if transition["program"] != program or transition["architecture_revision"] != passport_revision:
            continue
        foundation = transition["foundation"]
        historical_entry = historical_foundations.get(foundation)
        current_entry = current_foundations.get(foundation)
        if not isinstance(historical_entry, dict) or not isinstance(current_entry, dict):
            continue
        historical_owner = historical_entry.get("owner")
        canonical_owner = current_entry.get("owner")
        if historical_owner != transition["historical_owner"]:
            continue
        if canonical_owner != transition["canonical_owner"]:
            continue
        claim = _matching_claim(result, foundation, transition["historical_owner"])
        if claim is None:
            continue
        exact_detail = (
            f"{foundation}: claimed={transition['historical_owner']}, "
            f"canonical={transition['canonical_owner']}"
        )
        if finding.get("detail") != exact_detail:
            continue
        candidate_matches.append((transition, transition["historical_owner"], transition["canonical_owner"]))

    if len(candidate_matches) > 1:
        return None, True
    if not candidate_matches:
        return None, False
    transition, historical_owner, canonical_owner = candidate_matches[0]
    return {
        "foundation": transition["foundation"],
        "historical_owner": historical_owner,
        "canonical_owner": canonical_owner,
    }, False


def _call_architecture_auditor(
    key: str,
    central: dict[str, Any],
    registry: dict[str, Any],
    policy: dict[str, Any],
    ownership: dict[str, Any],
) -> dict[str, Any]:
    # Preserve the accepted wrapper as an immutable module while retaining its
    # test seam: callers that patch this outer module's original auditor still
    # exercise the exact accepted architecture-compatibility implementation.
    previous = _arch._ORIGINAL_AUDIT_PROGRAM
    _arch._ORIGINAL_AUDIT_PROGRAM = _ORIGINAL_AUDIT_PROGRAM
    try:
        return _ARCHITECTURE_AUDIT_PROGRAM(key, central, registry, policy, ownership)
    finally:
        _arch._ORIGINAL_AUDIT_PROGRAM = previous


def audit_program(
    key: str,
    central: dict[str, Any],
    registry: dict[str, Any],
    policy: dict[str, Any],
    ownership: dict[str, Any],
) -> dict[str, Any]:
    result = _call_architecture_auditor(key, central, registry, policy, ownership)
    architecture_compatibility = result.get("architecture_compatibility")
    if (
        not isinstance(architecture_compatibility, dict)
        or architecture_compatibility.get("mode") != _ARCHITECTURE_COMPAT_PREREQUISITE
        or architecture_compatibility.get("compatible") is not True
        or architecture_compatibility.get("matching_historical_identities") != 1
    ):
        return result

    conflicts = [
        finding
        for finding in result.get("findings", [])
        if isinstance(finding, dict) and finding.get("code") == "FOUNDATION_OWNERSHIP_CONFLICT"
    ]
    if not conflicts:
        return result

    passport_path = str(central.get("passport_path", ""))
    branch = str(central.get("branch", ""))
    if not branch or not passport_path or not result.get("passport_loaded"):
        return _fail_closed(result, "HISTORICAL_PASSPORT_CONTEXT_MISSING")
    passport = _core.load_branch_json(_core.remote_ref(branch), passport_path)
    if not isinstance(passport, dict):
        return _fail_closed(result, "HISTORICAL_PASSPORT_UNREADABLE")
    passport_revision = passport.get("architecture_revision")
    if passport_revision != _HISTORICAL_OWNERSHIP_REVISION:
        return _fail_closed(result, "HISTORICAL_PASSPORT_REVISION_NOT_PINNED_SOURCE")

    historical_ownership, source_error = _load_historical_ownership_source(policy)
    if historical_ownership is None:
        return _fail_closed(result, source_error)
    transitions, transition_error = _load_transitions(central)
    if transitions is None:
        return _fail_closed(result, transition_error)
    if not transitions:
        return _fail_closed(result, "OWNERSHIP_TRANSITION_NOT_AUTHORIZED")

    authorized_by_finding: dict[int, dict[str, str]] = {}
    for index, finding in enumerate(result.get("findings", [])):
        if not isinstance(finding, dict) or finding.get("code") != "FOUNDATION_OWNERSHIP_CONFLICT":
            continue
        authorized, ambiguous = _authorized_conflict(
            program=key,
            passport_revision=passport_revision,
            finding=finding,
            result=result,
            transitions=transitions,
            historical_ownership=historical_ownership,
            current_ownership=ownership,
        )
        if ambiguous:
            return _fail_closed(result, "OWNERSHIP_TRANSITION_AMBIGUOUS")
        if authorized is not None:
            authorized_by_finding[index] = authorized

    if not authorized_by_finding:
        return _fail_closed(result, "OWNERSHIP_TRANSITION_NOT_AUTHORIZED")

    filtered = [
        finding
        for index, finding in enumerate(result.get("findings", []))
        if index not in authorized_by_finding
    ]
    updated = deepcopy(result)
    updated["findings"] = filtered
    authorized_conflicts = [authorized_by_finding[index] for index in sorted(authorized_by_finding)]
    updated["ownership_compatibility"] = _ownership_metadata(authorized_conflicts)
    _recompute_health(updated)
    return updated


_core.audit_program = audit_program
main = _core.main


if __name__ == "__main__":
    raise SystemExit(main())
