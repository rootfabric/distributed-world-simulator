from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from enum import Enum
from threading import Lock
from typing import Any, Sequence

from .directory import MutationAuthorityClaim, OwnershipDirectory, OwnershipRecord
from .partition_fencing import (
    AuthorityRuntimeClaim,
    MutationGateResult,
    MutationGateStatus,
    PartitionFencingGate,
)


class OneWriterRoundStatus(str, Enum):
    EXACTLY_ONE_AUTHORIZED = "EXACTLY_ONE_AUTHORIZED"
    ZERO_AUTHORIZED = "ZERO_AUTHORIZED"
    MULTIPLE_AUTHORIZED_VIOLATION = "MULTIPLE_AUTHORIZED_VIOLATION"
    CANONICAL_MOVED_INDETERMINATE = "CANONICAL_MOVED_INDETERMINATE"


@dataclass(frozen=True)
class OneWriterProbeAttempt:
    participant_id: str
    gate: PartitionFencingGate
    runtime_claim: AuthorityRuntimeClaim

    def __post_init__(self) -> None:
        if not self.participant_id.strip():
            raise ValueError("participant_id must be non-empty")


@dataclass(frozen=True)
class OneWriterRoundResult:
    round_id: str
    operation_id: str
    subject_or_domain_id: str
    before: OwnershipRecord | None
    after: OwnershipRecord | None
    results: tuple[tuple[str, MutationGateResult], ...]
    authorized_participants: tuple[str, ...]
    noncanonical_authorized_participants: tuple[str, ...]
    status: OneWriterRoundStatus
    canonical_moved: bool

    @property
    def one_writer_safe(self) -> bool:
        return (
            not self.canonical_moved
            and len(self.authorized_participants) <= 1
            and not self.noncanonical_authorized_participants
        )


class IntegratedOneWriterProbe:
    """Research-only SM1-I2.6 one-writer decision-point analyzer.

    It does not grant authority and does not commit gameplay state. Each attempt
    delegates to the accepted I2.5 PartitionFencingGate. The probe only checks
    whether a stable canonical Directory snapshot admits at most one process
    incarnation and whether every admitted claim exactly matches canonical
    ownership.

    If canonical ownership changes during a probe round, the round is explicitly
    INDETERMINATE rather than being counted as a one-writer PASS.
    """

    EVIDENCE_SCHEMA = "distributed_world_simulator.sm1_i2_6_one_writer_evidence.v1"

    def __init__(self, directory: OwnershipDirectory) -> None:
        self._directory = directory
        self._evidence_lock = Lock()
        self._round_sequence = 0
        self._evidence: list[dict[str, Any]] = []

    def probe_round(
        self,
        *,
        round_id: str,
        operation_id: str,
        subject_or_domain_id: str,
        attempts: Sequence[OneWriterProbeAttempt],
        concurrent: bool = True,
    ) -> OneWriterRoundResult:
        rid = str(round_id).strip()
        op = str(operation_id).strip()
        subject = str(subject_or_domain_id).strip()
        if not rid:
            raise ValueError("round_id must be non-empty")
        if not op:
            raise ValueError("operation_id must be non-empty")
        if not subject:
            raise ValueError("subject_or_domain_id must be non-empty")
        if not attempts:
            raise ValueError("at least one attempt is required")

        participant_ids = [attempt.participant_id for attempt in attempts]
        if len(set(participant_ids)) != len(participant_ids):
            raise ValueError("participant_id values must be unique")

        before = self._directory.lookup(subject)

        def run(attempt: OneWriterProbeAttempt) -> tuple[str, MutationGateResult]:
            return (
                attempt.participant_id,
                attempt.gate.attempt(
                    operation_id=op,
                    runtime_claim=attempt.runtime_claim,
                ),
            )

        if concurrent and len(attempts) > 1:
            with ThreadPoolExecutor(max_workers=min(len(attempts), 64)) as executor:
                observed = list(executor.map(run, attempts))
        else:
            observed = [run(attempt) for attempt in attempts]

        observed.sort(key=lambda pair: pair[0])
        after = self._directory.lookup(subject)
        canonical_moved = before != after

        authorized = tuple(
            participant_id
            for participant_id, result in observed
            if result.status is MutationGateStatus.AUTHORIZED
        )

        canonical_claim = (
            MutationAuthorityClaim.from_record(after) if after is not None else None
        )
        noncanonical = tuple(
            participant_id
            for participant_id, result in observed
            if result.status is MutationGateStatus.AUTHORIZED
            and (canonical_claim is None or result.runtime_claim.claim != canonical_claim)
        )

        if canonical_moved:
            status = OneWriterRoundStatus.CANONICAL_MOVED_INDETERMINATE
        elif len(authorized) > 1:
            status = OneWriterRoundStatus.MULTIPLE_AUTHORIZED_VIOLATION
        elif len(authorized) == 1:
            status = OneWriterRoundStatus.EXACTLY_ONE_AUTHORIZED
        else:
            status = OneWriterRoundStatus.ZERO_AUTHORIZED

        result = OneWriterRoundResult(
            round_id=rid,
            operation_id=op,
            subject_or_domain_id=subject,
            before=before,
            after=after,
            results=tuple(observed),
            authorized_participants=authorized,
            noncanonical_authorized_participants=noncanonical,
            status=status,
            canonical_moved=canonical_moved,
        )
        self._record_evidence(result)
        return result

    def evidence(self) -> list[dict[str, Any]]:
        with self._evidence_lock:
            return [dict(event) for event in self._evidence]

    def _record_evidence(self, result: OneWriterRoundResult) -> None:
        with self._evidence_lock:
            self._round_sequence += 1
            self._evidence.append(
                {
                    "schema": self.EVIDENCE_SCHEMA,
                    "kind": "ONE_WRITER_ROUND_RESULT",
                    "round_sequence": self._round_sequence,
                    "round_id": result.round_id,
                    "operation_id": result.operation_id,
                    "subject_or_domain_id": result.subject_or_domain_id,
                    "status": result.status.value,
                    "one_writer_safe": result.one_writer_safe,
                    "canonical_moved": result.canonical_moved,
                    "authorized_participants": list(result.authorized_participants),
                    "noncanonical_authorized_participants": list(
                        result.noncanonical_authorized_participants
                    ),
                    "before": result.before.to_mapping() if result.before else None,
                    "after": result.after.to_mapping() if result.after else None,
                    "attempts": [
                        {
                            "participant_id": participant_id,
                            "status": gate_result.status.value,
                            "process_instance_id": gate_result.runtime_claim.process_instance_id,
                            "restart_generation": gate_result.runtime_claim.restart_generation,
                            "claim": gate_result.runtime_claim.claim.to_mapping(),
                            "observed": (
                                gate_result.observed.to_mapping()
                                if gate_result.observed
                                else None
                            ),
                        }
                        for participant_id, gate_result in result.results
                    ],
                }
            )
