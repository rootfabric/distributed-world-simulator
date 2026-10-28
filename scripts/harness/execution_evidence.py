"""Fail-closed validation for Harness execution evidence strength.

Evidence has independent dimensions. A clean/fresh process is not an independent
reviewer, parser success is not behavioral success, and exact top-level files are
not a canonical carrier until the complete transitive executable closure is exact.
"""
from __future__ import annotations

from typing import Any


class ExecutionEvidenceError(ValueError):
    """Raised when an evidence record overclaims or violates carrier policy."""


EXECUTION_ORDER = {
    "STATIC_INSPECTION": 0,
    "PARSER_PRELOAD": 1,
    "BEHAVIORAL_EXECUTION": 2,
}


def validate_execution_evidence(record: dict[str, Any]) -> None:
    claims = record.get("claims")
    if not isinstance(claims, dict):
        raise ExecutionEvidenceError("CLAIMS_REQUIRED")

    level = record.get("execution_level")
    if level not in EXECUTION_ORDER:
        raise ExecutionEvidenceError("EXECUTION_LEVEL_INVALID")

    if claims.get("parser_pass") and EXECUTION_ORDER[level] < EXECUTION_ORDER["PARSER_PRELOAD"]:
        raise ExecutionEvidenceError("PARSER_CLAIM_WITHOUT_PARSER_LEVEL")
    if claims.get("behavioral_pass") and level != "BEHAVIORAL_EXECUTION":
        raise ExecutionEvidenceError("BEHAVIORAL_CLAIM_WITHOUT_BEHAVIORAL_EXECUTION")

    fresh = record.get("process_freshness") == "FRESH_PROCESS"
    if claims.get("fresh_process_pass") and not fresh:
        raise ExecutionEvidenceError("FRESH_PROCESS_CLAIM_WITHOUT_FRESH_PROCESS")

    exact_closure = record.get("carrier_integrity") == "EXACT_TRANSITIVE_EXECUTABLE_CLOSURE"
    if claims.get("canonical_carrier_pass") and not exact_closure:
        raise ExecutionEvidenceError("CANONICAL_CARRIER_CLAIM_WITHOUT_EXACT_TRANSITIVE_CLOSURE")
    if level == "BEHAVIORAL_EXECUTION" and claims.get("canonical_carrier_pass"):
        _validate_closure_manifest(record)

    canonical_runner = bool(record.get("canonical_runner_executed"))
    equivalent = bool(record.get("equivalent_execution_executed"))
    transport = record.get("transport")
    if canonical_runner and transport != "CANONICAL_RUNNER":
        raise ExecutionEvidenceError("CANONICAL_RUNNER_FLAG_TRANSPORT_MISMATCH")
    if equivalent:
        if transport != "DECLARED_EQUIVALENT_EXECUTION":
            raise ExecutionEvidenceError("EQUIVALENT_EXECUTION_FLAG_TRANSPORT_MISMATCH")
        if not record.get("equivalent_execution_allowed"):
            raise ExecutionEvidenceError("EQUIVALENT_EXECUTION_NOT_EXPLICITLY_ALLOWED")
        if not record.get("equivalent_predicates_complete"):
            raise ExecutionEvidenceError("EQUIVALENT_PREDICATE_MANIFEST_INCOMPLETE")
        predicates = record.get("equivalent_predicates")
        if not isinstance(predicates, list) or not predicates:
            raise ExecutionEvidenceError("EQUIVALENT_PREDICATES_REQUIRED")
    if canonical_runner and equivalent:
        raise ExecutionEvidenceError("RUNNER_TRANSPORT_MUST_BE_SINGLE_CLASS")

    authority = record.get("role_authority")
    independent = bool(record.get("role_independent"))
    if claims.get("independent_reviewer_pass"):
        if authority != "INDEPENDENT_REVIEWER" or not independent:
            raise ExecutionEvidenceError("INDEPENDENT_REVIEWER_CLAIM_WITHOUT_INDEPENDENT_ROLE")
    if claims.get("independent_verifier_pass"):
        if authority != "INDEPENDENT_VERIFIER" or not independent:
            raise ExecutionEvidenceError("INDEPENDENT_VERIFIER_CLAIM_WITHOUT_INDEPENDENT_ROLE")
    if authority == "IMPLEMENTER_SELF_CHECK" and (
        claims.get("independent_reviewer_pass") or claims.get("independent_verifier_pass")
    ):
        raise ExecutionEvidenceError("IMPLEMENTER_SELF_CHECK_CANNOT_UPGRADE_TO_INDEPENDENT_ROLE")

    if record.get("post_freeze_executable_drift") and (
        claims.get("behavioral_pass")
        or claims.get("canonical_carrier_pass")
        or claims.get("independent_reviewer_pass")
        or claims.get("independent_verifier_pass")
    ):
        raise ExecutionEvidenceError("POST_FREEZE_EXECUTABLE_DRIFT_REQUIRES_REBIND_AND_REVERIFY")


def _validate_closure_manifest(record: dict[str, Any]) -> None:
    manifest = record.get("closure_manifest")
    if not isinstance(manifest, dict):
        raise ExecutionEvidenceError("EXACT_CLOSURE_MANIFEST_REQUIRED")
    if manifest.get("target_head") != record.get("target_head"):
        raise ExecutionEvidenceError("CLOSURE_TARGET_HEAD_MISMATCH")
    roots = manifest.get("root_executables")
    files = manifest.get("transitive_files")
    if not isinstance(roots, list) or not roots:
        raise ExecutionEvidenceError("CLOSURE_ROOT_EXECUTABLES_REQUIRED")
    if not isinstance(files, list) or not files:
        raise ExecutionEvidenceError("CLOSURE_TRANSITIVE_FILES_REQUIRED")
    seen: set[str] = set()
    for item in files:
        if not isinstance(item, dict):
            raise ExecutionEvidenceError("CLOSURE_FILE_RECORD_INVALID")
        path = item.get("path")
        sha = item.get("git_blob_sha")
        if not isinstance(path, str) or not path or path in seen:
            raise ExecutionEvidenceError("CLOSURE_PATH_INVALID_OR_DUPLICATE")
        if not isinstance(sha, str) or len(sha) != 40 or any(ch not in "0123456789abcdef" for ch in sha):
            raise ExecutionEvidenceError("CLOSURE_GIT_BLOB_SHA_INVALID")
        if item.get("identity_verified") is not True:
            raise ExecutionEvidenceError("CLOSURE_IDENTITY_NOT_VERIFIED")
        seen.add(path)
    missing_roots = [root for root in roots if root not in seen]
    if missing_roots:
        raise ExecutionEvidenceError("CLOSURE_ROOT_MISSING_FROM_TRANSITIVE_FILES:" + ",".join(missing_roots))


def continuation_class(record: dict[str, Any], *, independent_role_required: bool, checkpoint_accepted: bool) -> str:
    """Return the only valid continuation class for this evidence state."""
    validate_execution_evidence(record)
    claims = record["claims"]
    if record.get("post_freeze_executable_drift"):
        return "REBIND_TARGET_AND_REVERIFY"
    if record.get("execution_level") == "BEHAVIORAL_EXECUTION" and not claims.get("behavioral_pass"):
        return "RETURN_TO_IMPLEMENTER_REPAIR_AND_REFREEZE"
    if claims.get("behavioral_pass") and not claims.get("canonical_carrier_pass"):
        return "EVIDENCE_CARRIER_REPAIR_REQUIRED"
    if independent_role_required and not (
        claims.get("independent_reviewer_pass") or claims.get("independent_verifier_pass")
    ):
        return "ROLE_BOUNDARY"
    if checkpoint_accepted:
        return "FOLLOW_EXPLICIT_NEXT_AUTHORIZATION_ONLY"
    return "CANDIDATE_AWAIT_ACCEPTANCE_POLICY"
