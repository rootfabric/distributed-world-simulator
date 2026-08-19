from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from threading import Lock
from typing import Any

from .directory import CasStatus, OwnershipDirectory, OwnershipRecord


class IncarnationReplacementStatus(str, Enum):
    REPLACED = "REPLACED"
    ALREADY_COMMITTED = "ALREADY_COMMITTED"
    STALE_REPLACEMENT = "STALE_REPLACEMENT"
    INVALID_REPLACEMENT = "INVALID_REPLACEMENT"
    NOT_FOUND = "NOT_FOUND"


@dataclass(frozen=True)
class IncarnationReplacementRequest:
    expected: OwnershipRecord
    desired: OwnershipRecord


@dataclass(frozen=True)
class IncarnationReplacementResult:
    status: IncarnationReplacementStatus
    request: IncarnationReplacementRequest
    directory_cas_status: CasStatus | None
    observed: OwnershipRecord | None
    current: OwnershipRecord | None
    error: str | None = None

    @property
    def converged(self) -> bool:
        return self.status in {
            IncarnationReplacementStatus.REPLACED,
            IncarnationReplacementStatus.ALREADY_COMMITTED,
        }


class IncarnationReplacementCoordinator:
    """Research-only I2.3 same-AuthorityId replacement helper.

    Canonical ownership remains entirely Directory-owned. The coordinator does
    not allocate fences or generations and never writes canonical state except
    through the accepted Directory compare_and_swap() operation.
    """

    EVIDENCE_SCHEMA = "distributed_world_simulator.sm1_i2_3_incarnation_replacement_evidence.v1"

    def __init__(self, directory: OwnershipDirectory) -> None:
        self._directory = directory
        self._evidence_lock = Lock()
        self._emission_sequence = 0
        self._evidence: list[dict[str, Any]] = []

    def replace(self, request: IncarnationReplacementRequest) -> IncarnationReplacementResult:
        structural_error = self._validate_scope(request)
        if structural_error is not None:
            current = self._directory.lookup(request.expected.subject_or_domain_id)
            result = IncarnationReplacementResult(
                status=IncarnationReplacementStatus.INVALID_REPLACEMENT,
                request=request,
                directory_cas_status=None,
                observed=current,
                current=current,
                error=structural_error,
            )
            self._record_evidence(result)
            return result

        cas = self._directory.compare_and_swap(request.expected, request.desired)
        if cas.status is CasStatus.CAS_OK:
            status = IncarnationReplacementStatus.REPLACED
            error = None
        elif cas.status is CasStatus.CAS_MISMATCH:
            if cas.current == request.desired:
                status = IncarnationReplacementStatus.ALREADY_COMMITTED
                error = None
            else:
                status = IncarnationReplacementStatus.STALE_REPLACEMENT
                error = "canonical Directory state no longer matches this replacement"
        elif cas.status is CasStatus.NOT_FOUND:
            status = IncarnationReplacementStatus.NOT_FOUND
            error = cas.error
        else:
            status = IncarnationReplacementStatus.INVALID_REPLACEMENT
            error = cas.error

        result = IncarnationReplacementResult(
            status=status,
            request=request,
            directory_cas_status=cas.status,
            observed=cas.observed,
            current=cas.current,
            error=error,
        )
        self._record_evidence(result)
        return result

    def evidence(self) -> list[dict[str, Any]]:
        with self._evidence_lock:
            return [dict(event) for event in self._evidence]

    @staticmethod
    def _validate_scope(request: IncarnationReplacementRequest) -> str | None:
        expected = request.expected
        desired = request.desired
        if expected.subject_or_domain_id != desired.subject_or_domain_id:
            return "same-AuthorityId replacement cannot change subject_or_domain_id"
        if expected.owner_authority_id != desired.owner_authority_id:
            return "same-AuthorityId replacement cannot change owner_authority_id"
        if expected.authority_incarnation == desired.authority_incarnation:
            return "same-AuthorityId replacement requires a new authority_incarnation"
        return None

    def _record_evidence(self, result: IncarnationReplacementResult) -> None:
        with self._evidence_lock:
            self._emission_sequence += 1
            self._evidence.append(
                {
                    "schema": self.EVIDENCE_SCHEMA,
                    "kind": "INCARNATION_REPLACEMENT_RESULT",
                    "emission_sequence": self._emission_sequence,
                    "status": result.status.value,
                    "directory_cas_status": (
                        result.directory_cas_status.value
                        if result.directory_cas_status is not None
                        else None
                    ),
                    "expected": result.request.expected.to_mapping(),
                    "desired": result.request.desired.to_mapping(),
                    "observed": result.observed.to_mapping() if result.observed else None,
                    "current": result.current.to_mapping() if result.current else None,
                    "error": result.error,
                }
            )
