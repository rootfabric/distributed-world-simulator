from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from threading import Lock
from typing import Any

from .directory import (
    MutationAuthorizationResult,
    MutationAuthorizationStatus,
    MutationAuthorityClaim,
    OwnershipDirectory,
    OwnershipRecord,
)


class DirectoryReachability(str, Enum):
    CONNECTED = "CONNECTED"
    PARTITIONED = "PARTITIONED"


class MutationGateStatus(str, Enum):
    AUTHORIZED = "AUTHORIZED"
    FENCED = "FENCED"
    NOT_FOUND = "NOT_FOUND"
    DIRECTORY_UNREACHABLE = "DIRECTORY_UNREACHABLE"


@dataclass(frozen=True)
class AuthorityRuntimeClaim:
    """Process-local ownership claim carried across a simulated/replayed restart.

    `process_instance_id` and `restart_generation` are harness metadata only.
    They are never ownership authority and never override the canonical Directory.
    """

    process_instance_id: str
    restart_generation: int
    claim: MutationAuthorityClaim

    def __post_init__(self) -> None:
        if not self.process_instance_id.strip():
            raise ValueError("process_instance_id must be non-empty")
        if self.restart_generation < 0:
            raise ValueError("restart_generation must be >= 0")

    def restarted(self, *, process_instance_id: str) -> "AuthorityRuntimeClaim":
        return AuthorityRuntimeClaim(
            process_instance_id=process_instance_id,
            restart_generation=self.restart_generation + 1,
            claim=self.claim,
        )

    def to_mapping(self) -> dict[str, Any]:
        return {
            "process_instance_id": self.process_instance_id,
            "restart_generation": self.restart_generation,
            "claim": self.claim.to_mapping(),
        }


@dataclass(frozen=True)
class MutationGateResult:
    status: MutationGateStatus
    operation_id: str
    runtime_claim: AuthorityRuntimeClaim
    observed: OwnershipRecord | None
    mismatched_fields: tuple[str, ...] = ()
    error: str | None = None

    @property
    def admitted(self) -> bool:
        return self.status is MutationGateStatus.AUTHORIZED


class PartitionFencingGate:
    """Research-only I2.5 fail-closed canonical mutation prerequisite.

    The gate contains no owner cache and never mutates Directory ownership. Every
    connected attempt asks the canonical Directory to authorize the exact tuple.
    A simulated partition fails closed without consulting stale local state.
    """

    EVIDENCE_SCHEMA = "distributed_world_simulator.sm1_i2_5_partition_fencing_evidence.v1"

    def __init__(
        self,
        directory: OwnershipDirectory,
        *,
        reachability: DirectoryReachability = DirectoryReachability.CONNECTED,
    ) -> None:
        self._directory = directory
        self._reachability = reachability
        self._evidence_lock = Lock()
        self._attempt_sequence = 0
        self._evidence: list[dict[str, Any]] = []

    @property
    def reachability(self) -> DirectoryReachability:
        return self._reachability

    def partition(self) -> None:
        self._reachability = DirectoryReachability.PARTITIONED

    def heal(self) -> None:
        self._reachability = DirectoryReachability.CONNECTED

    def attempt(
        self,
        *,
        operation_id: str,
        runtime_claim: AuthorityRuntimeClaim,
    ) -> MutationGateResult:
        operation = str(operation_id).strip()
        if not operation:
            raise ValueError("operation_id must be non-empty")

        if self._reachability is DirectoryReachability.PARTITIONED:
            result = MutationGateResult(
                status=MutationGateStatus.DIRECTORY_UNREACHABLE,
                operation_id=operation,
                runtime_claim=runtime_claim,
                observed=None,
                error="canonical Directory is unreachable; mutation admission fails closed",
            )
        else:
            authorization = self._directory.authorize_ownership_tuple(runtime_claim.claim)
            result = self._from_authorization(
                operation_id=operation,
                runtime_claim=runtime_claim,
                authorization=authorization,
            )

        self._record_evidence(result)
        return result

    def evidence(self) -> list[dict[str, Any]]:
        with self._evidence_lock:
            return [dict(event) for event in self._evidence]

    @staticmethod
    def _from_authorization(
        *,
        operation_id: str,
        runtime_claim: AuthorityRuntimeClaim,
        authorization: MutationAuthorizationResult,
    ) -> MutationGateResult:
        if authorization.status is MutationAuthorizationStatus.AUTHORIZED:
            status = MutationGateStatus.AUTHORIZED
        elif authorization.status is MutationAuthorizationStatus.FENCED:
            status = MutationGateStatus.FENCED
        else:
            status = MutationGateStatus.NOT_FOUND
        return MutationGateResult(
            status=status,
            operation_id=operation_id,
            runtime_claim=runtime_claim,
            observed=authorization.observed,
            mismatched_fields=authorization.mismatched_fields,
            error=authorization.error,
        )

    def _record_evidence(self, result: MutationGateResult) -> None:
        with self._evidence_lock:
            self._attempt_sequence += 1
            self._evidence.append(
                {
                    "schema": self.EVIDENCE_SCHEMA,
                    "kind": "AUTHORITY_MUTATION_GATE_RESULT",
                    "attempt_sequence": self._attempt_sequence,
                    "reachability": self._reachability.value,
                    "operation_id": result.operation_id,
                    "status": result.status.value,
                    "admitted": result.admitted,
                    "process_instance_id": result.runtime_claim.process_instance_id,
                    "restart_generation": result.runtime_claim.restart_generation,
                    "claim": result.runtime_claim.claim.to_mapping(),
                    "observed": result.observed.to_mapping() if result.observed else None,
                    "mismatched_fields": list(result.mismatched_fields),
                    "error": result.error,
                }
            )
