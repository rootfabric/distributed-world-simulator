"""Fail-closed exact clearance matching for PC0 directional critical watches."""
from __future__ import annotations

from typing import Any, Callable

ACCEPTED_STATUS = "ACCEPTED"
ACCEPTED_DECISION = "DEPENDENCY_REVALIDATED_NO_FOUNDATION_MUTATION"
CLEARANCE_SCHEMA = "distributed_world_simulator.directional_watch_clearance.v1"

BlobLookup = Callable[[str, str], str]
AncestorCheck = Callable[[str, str], bool]


def _target_identity_matches(clearance: dict[str, Any], producer: dict[str, Any], consumer: dict[str, Any]) -> bool:
    return (
        clearance.get("schema") == CLEARANCE_SCHEMA
        and clearance.get("kind") == "CRITICAL_WATCH_HIT"
        and clearance.get("producer_program") == producer.get("program")
        and clearance.get("producer_branch") == producer.get("branch")
        and clearance.get("consumer_program") == consumer.get("program")
        and clearance.get("consumer_branch") == consumer.get("branch")
    )


def _validate_targeted_clearance(
    clearance: dict[str, Any],
    producer: dict[str, Any],
    consumer: dict[str, Any],
    critical_hits: list[str],
    all_hits: list[str],
    blob_lookup: BlobLookup,
    ancestor_check: AncestorCheck,
) -> str | None:
    if clearance.get("status") != ACCEPTED_STATUS:
        return "STATUS_NOT_ACCEPTED"
    if clearance.get("decision") != ACCEPTED_DECISION:
        return "DECISION_NOT_ACCEPTED"
    if not str(clearance.get("review_id", "")) or not str(clearance.get("verification_id", "")):
        return "INDEPENDENT_EVIDENCE_IDS_REQUIRED"

    expected_critical = sorted({str(path) for path in clearance.get("critical_files", []) if str(path)})
    actual_critical = sorted(set(critical_hits))
    if expected_critical != actual_critical:
        return "CRITICAL_FILE_SET_MISMATCH"

    expected_watched = sorted({str(path) for path in clearance.get("watched_files", []) if str(path)})
    actual_watched = sorted(set(all_hits))
    if expected_watched != actual_watched:
        return "WATCHED_FILE_SET_MISMATCH"
    if not set(actual_critical).issubset(expected_watched):
        return "CRITICAL_FILES_NOT_FENCED"

    reviewed_head = str(clearance.get("reviewed_producer_head", ""))
    if len(reviewed_head) != 40:
        return "REVIEWED_PRODUCER_HEAD_INVALID"
    producer_ref = f"origin/{producer.get('branch', '')}"
    if not ancestor_check(reviewed_head, producer_ref):
        return "REVIEWED_HEAD_NOT_PRODUCER_ANCESTOR"

    if clearance.get("consumer_head_sha") != consumer.get("head_sha"):
        return "CONSUMER_HEAD_DRIFT"
    if clearance.get("consumer_passport_path") != consumer.get("passport_path"):
        return "CONSUMER_PASSPORT_PATH_DRIFT"
    if clearance.get("consumer_passport_blob_sha") != consumer.get("passport_blob_sha"):
        return "CONSUMER_PASSPORT_BLOB_DRIFT"

    expected_blobs = clearance.get("watched_file_blobs", {})
    if not isinstance(expected_blobs, dict) or sorted(expected_blobs) != expected_watched:
        return "WATCHED_BLOB_FENCE_INCOMPLETE"

    for path in expected_watched:
        expected_blob = str(expected_blobs.get(path, ""))
        if len(expected_blob) != 40:
            return f"WATCHED_BLOB_INVALID:{path}"
        reviewed_blob = blob_lookup(reviewed_head, path)
        if reviewed_blob != expected_blob:
            return f"REVIEWED_BLOB_MISMATCH:{path}"
        current_blob = blob_lookup(producer_ref, path)
        if current_blob != expected_blob:
            return f"PRODUCER_BLOB_DRIFT:{path}"

    return None


def resolve_critical_clearance(
    clearances: list[dict[str, Any]],
    producer: dict[str, Any],
    consumer: dict[str, Any],
    critical_hits: list[str],
    all_hits: list[str],
    blob_lookup: BlobLookup,
    ancestor_check: AncestorCheck,
) -> tuple[dict[str, Any] | None, list[dict[str, str]]]:
    """Return one exact accepted clearance or fail-closed rejection diagnostics."""
    rejections: list[dict[str, str]] = []
    for clearance in clearances:
        if not isinstance(clearance, dict) or not _target_identity_matches(clearance, producer, consumer):
            continue
        reason = _validate_targeted_clearance(
            clearance,
            producer,
            consumer,
            critical_hits,
            all_hits,
            blob_lookup,
            ancestor_check,
        )
        if reason is None:
            return clearance, rejections
        rejections.append(
            {
                "clearance_id": str(clearance.get("clearance_id", "UNKNOWN")),
                "reason": reason,
            }
        )
    return None, rejections
