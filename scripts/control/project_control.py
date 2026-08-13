#!/usr/bin/env python3
"""PC0 project control auditor with fail-closed architecture passport compatibility.

The legacy auditor implementation remains byte-preserved in
project_control_core.py. Exact canonical architecture equality is accepted
without exception metadata. A historical architecture mismatch is accepted only
when the main-owned policy explicitly enables the compatibility contract, the
exact historical revision is allowlisted for the audited program, and exactly
one immutable historical passport identity matches observed Git evidence.
"""

from __future__ import annotations

import re
from typing import Any

import project_control_core as _core
from project_control_core import *  # noqa: F401,F403

_ORIGINAL_AUDIT_PROGRAM = _core.audit_program
_COMPATIBILITY_MODE = "EXPLICIT_PER_PROGRAM_HISTORICAL_ALLOWLIST"
_REVISION_REGISTRY_FIELD = "historical_passport_architecture_revisions"
_IDENTITY_REGISTRY_FIELD = "historical_passport_identities"
_REQUIRED_IDENTITY_FIELDS = (
    "program",
    "branch",
    "passport_path",
    "architecture_revision",
    "pinned_head_sha",
    "passport_blob_sha",
)
_FULL_GIT_SHA_RE = re.compile(r"^[0-9a-fA-F]{40}$")


def _is_full_git_sha(value: Any) -> bool:
    return isinstance(value, str) and bool(_FULL_GIT_SHA_RE.fullmatch(value))


def _compatibility_result(
    *,
    compatible: bool,
    mode: str,
    passport_revision: str,
    canonical_revision: str,
    allowlist_field: Any = None,
    identity_field: Any = None,
    allowed_historical_revisions: list[str] | None = None,
    matching_historical_identities: int = 0,
    observed_head_sha: str = "",
    observed_passport_blob_sha: str = "",
) -> dict[str, Any]:
    return {
        "compatible": compatible,
        "mode": mode,
        "passport_revision": passport_revision,
        "canonical_revision": canonical_revision,
        "allowlist_field": allowlist_field,
        "identity_field": identity_field,
        "allowed_historical_revisions": allowed_historical_revisions or [],
        "matching_historical_identities": matching_historical_identities,
        "observed_head_sha": observed_head_sha,
        "observed_passport_blob_sha": observed_passport_blob_sha,
    }


def evaluate_passport_architecture_compatibility(
    central: dict[str, Any],
    registry: dict[str, Any],
    passport: dict[str, Any],
    policy: dict[str, Any],
    *,
    audited_program: str = "",
    observed_branch: str = "",
    observed_passport_path: str = "",
    observed_head_sha: str = "",
    observed_passport_blob_sha: str = "",
) -> dict[str, Any]:
    """Return a deterministic fail-closed architecture compatibility decision.

    Exact canonical equality requires no historical exception. A mismatch is
    compatible only when both the explicit historical revision allowlist and
    one exact immutable historical identity match the observed branch head and
    passport blob. Missing or malformed policy, registry identity, or Git
    evidence fails closed.
    """
    canonical_raw = registry.get("architecture_revision")
    passport_raw = passport.get("architecture_revision")
    canonical_revision = canonical_raw if isinstance(canonical_raw, str) else ""
    passport_revision = passport_raw if isinstance(passport_raw, str) else ""

    if canonical_revision and passport_revision == canonical_revision:
        return _compatibility_result(
            compatible=True,
            mode="EXACT_CANONICAL_REVISION",
            passport_revision=passport_revision,
            canonical_revision=canonical_revision,
        )

    compatibility_policy = policy.get("passport_architecture_compatibility")
    if not isinstance(compatibility_policy, dict):
        return _compatibility_result(
            compatible=False,
            mode="STRICT_MISMATCH_POLICY_NOT_ENABLED",
            passport_revision=passport_revision,
            canonical_revision=canonical_revision,
        )

    mode = compatibility_policy.get("mode")
    if mode != _COMPATIBILITY_MODE:
        return _compatibility_result(
            compatible=False,
            mode="STRICT_MISMATCH_POLICY_NOT_ENABLED",
            passport_revision=passport_revision,
            canonical_revision=canonical_revision,
        )

    revision_field = compatibility_policy.get("central_registry_field")
    if not isinstance(revision_field, str) or revision_field != _REVISION_REGISTRY_FIELD:
        return _compatibility_result(
            compatible=False,
            mode="STRICT_MISMATCH_REVISION_POLICY_FIELD_INVALID",
            passport_revision=passport_revision,
            canonical_revision=canonical_revision,
            allowlist_field=revision_field,
        )

    identity_field = compatibility_policy.get("historical_identity_registry_field")
    if not isinstance(identity_field, str) or identity_field != _IDENTITY_REGISTRY_FIELD:
        return _compatibility_result(
            compatible=False,
            mode="STRICT_MISMATCH_IDENTITY_POLICY_FIELD_INVALID",
            passport_revision=passport_revision,
            canonical_revision=canonical_revision,
            allowlist_field=revision_field,
            identity_field=identity_field,
        )

    allowed_raw = central.get(revision_field)
    if (
        not isinstance(allowed_raw, list)
        or any(not isinstance(value, str) or not value for value in allowed_raw)
    ):
        return _compatibility_result(
            compatible=False,
            mode="STRICT_MISMATCH_MALFORMED_ALLOWLIST",
            passport_revision=passport_revision,
            canonical_revision=canonical_revision,
            allowlist_field=revision_field,
            identity_field=identity_field,
        )

    allowed = list(dict.fromkeys(allowed_raw))
    if not passport_revision or passport_revision not in allowed:
        return _compatibility_result(
            compatible=False,
            mode="STRICT_MISMATCH_NOT_ALLOWLISTED",
            passport_revision=passport_revision,
            canonical_revision=canonical_revision,
            allowlist_field=revision_field,
            identity_field=identity_field,
            allowed_historical_revisions=allowed,
        )

    identities_raw = central.get(identity_field)
    if not isinstance(identities_raw, list) or any(not isinstance(item, dict) for item in identities_raw):
        return _compatibility_result(
            compatible=False,
            mode="STRICT_MISMATCH_MALFORMED_IDENTITY_LIST",
            passport_revision=passport_revision,
            canonical_revision=canonical_revision,
            allowlist_field=revision_field,
            identity_field=identity_field,
            allowed_historical_revisions=allowed,
        )

    identities: list[dict[str, Any]] = []
    for identity in identities_raw:
        if any(
            field not in identity
            or not isinstance(identity.get(field), str)
            or not identity.get(field)
            for field in _REQUIRED_IDENTITY_FIELDS
        ):
            return _compatibility_result(
                compatible=False,
                mode="STRICT_MISMATCH_MALFORMED_IDENTITY_RECORD",
                passport_revision=passport_revision,
                canonical_revision=canonical_revision,
                allowlist_field=revision_field,
                identity_field=identity_field,
                allowed_historical_revisions=allowed,
            )
        if not _is_full_git_sha(identity["pinned_head_sha"]) or not _is_full_git_sha(identity["passport_blob_sha"]):
            return _compatibility_result(
                compatible=False,
                mode="STRICT_MISMATCH_MALFORMED_IDENTITY_SHA",
                passport_revision=passport_revision,
                canonical_revision=canonical_revision,
                allowlist_field=revision_field,
                identity_field=identity_field,
                allowed_historical_revisions=allowed,
            )
        identities.append(identity)

    expected_branch = central.get("branch")
    expected_path = central.get("passport_path")
    if (
        not isinstance(audited_program, str)
        or not audited_program
        or not isinstance(expected_branch, str)
        or not expected_branch
        or not isinstance(expected_path, str)
        or not expected_path
        or central.get("program") != audited_program
        or observed_branch != expected_branch
        or observed_passport_path != expected_path
        or passport.get("program") != audited_program
        or passport.get("branch") != expected_branch
    ):
        return _compatibility_result(
            compatible=False,
            mode="STRICT_MISMATCH_OBSERVED_IDENTITY_CONTEXT_MISMATCH",
            passport_revision=passport_revision,
            canonical_revision=canonical_revision,
            allowlist_field=revision_field,
            identity_field=identity_field,
            allowed_historical_revisions=allowed,
            observed_head_sha=observed_head_sha,
            observed_passport_blob_sha=observed_passport_blob_sha,
        )

    if not _is_full_git_sha(observed_head_sha) or not _is_full_git_sha(observed_passport_blob_sha):
        return _compatibility_result(
            compatible=False,
            mode="STRICT_MISMATCH_OBSERVED_GIT_IDENTITY_UNRESOLVED",
            passport_revision=passport_revision,
            canonical_revision=canonical_revision,
            allowlist_field=revision_field,
            identity_field=identity_field,
            allowed_historical_revisions=allowed,
            observed_head_sha=observed_head_sha,
            observed_passport_blob_sha=observed_passport_blob_sha,
        )

    matches = [
        identity
        for identity in identities
        if identity["program"] == audited_program
        and identity["branch"] == expected_branch
        and identity["passport_path"] == expected_path
        and identity["architecture_revision"] == passport_revision
        and identity["pinned_head_sha"] == observed_head_sha
        and identity["passport_blob_sha"] == observed_passport_blob_sha
    ]
    if len(matches) != 1:
        return _compatibility_result(
            compatible=False,
            mode=(
                "STRICT_MISMATCH_HISTORICAL_IDENTITY_NOT_PINNED"
                if not matches
                else "STRICT_MISMATCH_HISTORICAL_IDENTITY_AMBIGUOUS"
            ),
            passport_revision=passport_revision,
            canonical_revision=canonical_revision,
            allowlist_field=revision_field,
            identity_field=identity_field,
            allowed_historical_revisions=allowed,
            matching_historical_identities=len(matches),
            observed_head_sha=observed_head_sha,
            observed_passport_blob_sha=observed_passport_blob_sha,
        )

    return _compatibility_result(
        compatible=True,
        mode="EXPLICIT_HISTORICAL_IDENTITY_ALLOWED",
        passport_revision=passport_revision,
        canonical_revision=canonical_revision,
        allowlist_field=revision_field,
        identity_field=identity_field,
        allowed_historical_revisions=allowed,
        matching_historical_identities=1,
        observed_head_sha=observed_head_sha,
        observed_passport_blob_sha=observed_passport_blob_sha,
    )


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

    branch_ref = _core.remote_ref(branch)
    passport = _core.load_branch_json(branch_ref, passport_path)
    if passport is None:
        return result

    observed_head_sha = ""
    observed_passport_blob_sha = ""
    canonical_revision = registry.get("architecture_revision")
    passport_revision = passport.get("architecture_revision")
    if passport_revision != canonical_revision:
        observed_head_sha = _core.git("rev-parse", branch_ref, allow_fail=True)
        observed_passport_blob_sha = _core.git(
            "rev-parse", f"{branch_ref}:{passport_path}", allow_fail=True
        )

    decision = evaluate_passport_architecture_compatibility(
        central,
        registry,
        passport,
        policy,
        audited_program=key,
        observed_branch=branch,
        observed_passport_path=passport_path,
        observed_head_sha=observed_head_sha,
        observed_passport_blob_sha=observed_passport_blob_sha,
    )
    result["architecture_compatibility"] = decision
    if not decision["compatible"] or decision["mode"] == "EXACT_CANONICAL_REVISION":
        return result

    result["findings"] = [
        finding
        for finding in result.get("findings", [])
        if not (
            isinstance(finding, dict)
            and finding.get("code") == "ARCHITECTURE_REVISION_MISMATCH"
        )
    ]
    _recompute_health(result)
    return result


_core.audit_program = audit_program
main = _core.main


if __name__ == "__main__":
    raise SystemExit(main())
