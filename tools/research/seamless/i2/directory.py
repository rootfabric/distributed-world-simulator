from __future__ import annotations

from dataclasses import asdict, dataclass
from enum import Enum
from threading import Lock, RLock
from typing import Any, Mapping


class DirectoryContractError(ValueError):
    """Raised when an I2.1 ownership-directory contract is violated."""


class CasStatus(str, Enum):
    CAS_OK = "CAS_OK"
    CAS_MISMATCH = "CAS_MISMATCH"
    INVALID_TRANSITION = "INVALID_TRANSITION"
    NOT_FOUND = "NOT_FOUND"


class CreateStatus(str, Enum):
    CREATED = "CREATED"
    ALREADY_EXISTS = "ALREADY_EXISTS"


class MutationAuthorizationStatus(str, Enum):
    AUTHORIZED = "AUTHORIZED"
    FENCED = "FENCED"
    NOT_FOUND = "NOT_FOUND"


ALLOWED_LEASE_STATES = frozenset({"ACTIVE", "DRAINING", "UNAVAILABLE"})


@dataclass(frozen=True)
class OwnershipRecord:
    subject_or_domain_id: str
    owner_authority_id: str
    authority_epoch: int
    fencing_token: int
    directory_generation: int
    authority_incarnation: int
    state_revision: int
    lease_state: str
    route_revision: int

    def __post_init__(self) -> None:
        if not self.subject_or_domain_id.strip():
            raise DirectoryContractError("subject_or_domain_id must be non-empty")
        if not self.owner_authority_id.strip():
            raise DirectoryContractError("owner_authority_id must be non-empty")
        if self.authority_epoch < 1:
            raise DirectoryContractError("authority_epoch must be >= 1")
        if self.fencing_token < 1:
            raise DirectoryContractError("fencing_token must be >= 1")
        if self.directory_generation < 1:
            raise DirectoryContractError("directory_generation must be >= 1")
        if self.authority_incarnation < 1:
            raise DirectoryContractError("authority_incarnation must be >= 1")
        if self.state_revision < 0:
            raise DirectoryContractError("state_revision must be >= 0")
        if self.route_revision < 0:
            raise DirectoryContractError("route_revision must be >= 0")
        if self.lease_state not in ALLOWED_LEASE_STATES:
            raise DirectoryContractError(
                f"lease_state must be one of {sorted(ALLOWED_LEASE_STATES)}"
            )

    def to_mapping(self) -> dict[str, Any]:
        return asdict(self)

    @classmethod
    def from_mapping(cls, raw: Mapping[str, Any]) -> "OwnershipRecord":
        return cls(
            subject_or_domain_id=str(raw["subject_or_domain_id"]),
            owner_authority_id=str(raw["owner_authority_id"]),
            authority_epoch=int(raw["authority_epoch"]),
            fencing_token=int(raw["fencing_token"]),
            directory_generation=int(raw["directory_generation"]),
            authority_incarnation=int(raw["authority_incarnation"]),
            state_revision=int(raw["state_revision"]),
            lease_state=str(raw["lease_state"]),
            route_revision=int(raw["route_revision"]),
        )


@dataclass(frozen=True)
class MutationAuthorityClaim:
    subject_or_domain_id: str
    owner_authority_id: str
    authority_epoch: int
    fencing_token: int
    authority_incarnation: int

    def __post_init__(self) -> None:
        if not self.subject_or_domain_id.strip():
            raise DirectoryContractError("claim subject_or_domain_id must be non-empty")
        if not self.owner_authority_id.strip():
            raise DirectoryContractError("claim owner_authority_id must be non-empty")
        if self.authority_epoch < 1:
            raise DirectoryContractError("claim authority_epoch must be >= 1")
        if self.fencing_token < 1:
            raise DirectoryContractError("claim fencing_token must be >= 1")
        if self.authority_incarnation < 1:
            raise DirectoryContractError("claim authority_incarnation must be >= 1")

    @classmethod
    def from_record(cls, record: OwnershipRecord) -> "MutationAuthorityClaim":
        return cls(
            subject_or_domain_id=record.subject_or_domain_id,
            owner_authority_id=record.owner_authority_id,
            authority_epoch=record.authority_epoch,
            fencing_token=record.fencing_token,
            authority_incarnation=record.authority_incarnation,
        )

    def to_mapping(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class CreateResult:
    status: CreateStatus
    current: OwnershipRecord

    @property
    def created(self) -> bool:
        return self.status is CreateStatus.CREATED


@dataclass(frozen=True)
class CasResult:
    status: CasStatus
    expected: OwnershipRecord
    desired: OwnershipRecord
    observed: OwnershipRecord | None
    current: OwnershipRecord | None
    error: str | None = None

    @property
    def succeeded(self) -> bool:
        return self.status is CasStatus.CAS_OK


@dataclass(frozen=True)
class MutationAuthorizationResult:
    status: MutationAuthorizationStatus
    claim: MutationAuthorityClaim
    observed: OwnershipRecord | None
    mismatched_fields: tuple[str, ...] = ()
    error: str | None = None

    @property
    def authorized(self) -> bool:
        return self.status is MutationAuthorizationStatus.AUTHORIZED


class OwnershipDirectory:
    """
    Research-only I2.1 ownership oracle.

    It provides independent lookup() and expected-state compare_and_swap().
    The in-memory storage backend is intentionally replaceable; the semantic
    contract and machine evidence are the product of this checkpoint.
    """

    EVIDENCE_SCHEMA = "distributed_world_simulator.sm1_i2_1_directory_evidence.v1"
    AUTHORIZATION_EVIDENCE_SCHEMA = "distributed_world_simulator.sm1_i2_2_authorization_evidence.v1"
    _AUTH_FIELDS = (
        "owner_authority_id",
        "authority_epoch",
        "fencing_token",
        "authority_incarnation",
    )

    def __init__(self) -> None:
        self._records: dict[str, OwnershipRecord] = {}
        self._lock = RLock()
        self._evidence_lock = Lock()
        self._evidence_sequence = 0
        self._linearization_sequence = 0
        self._authorization_sequence = 0
        self._evidence: list[dict[str, Any]] = []

    def lookup(self, subject_or_domain_id: str) -> OwnershipRecord | None:
        subject = str(subject_or_domain_id).strip()
        if not subject:
            raise DirectoryContractError("lookup subject_or_domain_id must be non-empty")
        with self._lock:
            record = self._records.get(subject)
        self._record_evidence("LOOKUP", subject_or_domain_id=subject, found=record is not None)
        return record

    def create(self, record: OwnershipRecord) -> CreateResult:
        with self._lock:
            current = self._records.get(record.subject_or_domain_id)
            if current is not None:
                result = CreateResult(CreateStatus.ALREADY_EXISTS, current)
            else:
                self._records[record.subject_or_domain_id] = record
                result = CreateResult(CreateStatus.CREATED, record)
        self._record_evidence(
            "CREATE_RESULT",
            subject_or_domain_id=record.subject_or_domain_id,
            status=result.status.value,
            current=result.current.to_mapping(),
        )
        return result

    def compare_and_swap(
        self,
        expected: OwnershipRecord,
        desired: OwnershipRecord,
    ) -> CasResult:
        """
        Atomically compare current ownership against ``expected`` and, only
        when it matches, validate and install ``desired``.

        Classification is intentionally compare-first. A caller whose
        expected record is stale receives CAS_MISMATCH even when its desired
        transition would also be semantically invalid. This keeps stale-state
        fencing distinct from transition-policy validation.
        """
        with self._lock:
            observed = self._records.get(expected.subject_or_domain_id)

            if observed is None:
                result = CasResult(
                    status=CasStatus.NOT_FOUND,
                    expected=expected,
                    desired=desired,
                    observed=None,
                    current=None,
                    error="ownership record not found",
                )
            elif observed != expected:
                result = CasResult(
                    status=CasStatus.CAS_MISMATCH,
                    expected=expected,
                    desired=desired,
                    observed=observed,
                    current=observed,
                    error="expected ownership state is stale",
                )
            else:
                transition_error = validate_transition(expected, desired)
                if transition_error is not None:
                    result = CasResult(
                        status=CasStatus.INVALID_TRANSITION,
                        expected=expected,
                        desired=desired,
                        observed=observed,
                        current=observed,
                        error=transition_error,
                    )
                else:
                    self._records[expected.subject_or_domain_id] = desired
                    result = CasResult(
                        status=CasStatus.CAS_OK,
                        expected=expected,
                        desired=desired,
                        observed=observed,
                        current=desired,
                    )

            # This sequence is assigned while the ownership lock is held, at
            # the same serialization point that decides this CAS operation.
            # CAS_RESULT evidence is also appended before releasing that lock,
            # so machine evidence cannot invert concurrent CAS decision order.
            self._linearization_sequence += 1
            self._record_cas_evidence(
                result, linearization_sequence=self._linearization_sequence
            )
            return result

    def authorize_ownership_tuple(
        self,
        claim: MutationAuthorityClaim,
    ) -> MutationAuthorizationResult:
        """
        Validate the exact ownership-critical tuple against canonical state.

        This decision is serialized by the same ownership lock as CAS. It is
        one prerequisite for canonical mutation, not a gameplay-state commit
        and not a lease/binding admission decision.
        """
        with self._lock:
            observed = self._records.get(claim.subject_or_domain_id)
            if observed is None:
                result = MutationAuthorizationResult(
                    status=MutationAuthorizationStatus.NOT_FOUND,
                    claim=claim,
                    observed=None,
                    error="ownership record not found",
                )
            else:
                mismatched_fields = tuple(
                    field
                    for field in self._AUTH_FIELDS
                    if getattr(claim, field) != getattr(observed, field)
                )
                if mismatched_fields:
                    result = MutationAuthorizationResult(
                        status=MutationAuthorizationStatus.FENCED,
                        claim=claim,
                        observed=observed,
                        mismatched_fields=mismatched_fields,
                        error="ownership-critical tuple does not match canonical Directory state",
                    )
                else:
                    result = MutationAuthorizationResult(
                        status=MutationAuthorizationStatus.AUTHORIZED,
                        claim=claim,
                        observed=observed,
                    )

            self._authorization_sequence += 1
            self._record_authorization_evidence(
                result, authorization_sequence=self._authorization_sequence
            )
            return result

    def evidence(self) -> list[dict[str, Any]]:
        with self._evidence_lock:
            return [dict(event) for event in self._evidence]

    def snapshot(self) -> dict[str, OwnershipRecord]:
        with self._lock:
            return dict(self._records)

    def _record_cas_evidence(
        self, result: CasResult, *, linearization_sequence: int
    ) -> None:
        self._record_evidence(
            "CAS_RESULT",
            linearization_sequence=int(linearization_sequence),
            subject_or_domain_id=result.expected.subject_or_domain_id,
            status=result.status.value,
            expected=result.expected.to_mapping(),
            desired=result.desired.to_mapping(),
            observed=result.observed.to_mapping() if result.observed else None,
            current=result.current.to_mapping() if result.current else None,
            error=result.error,
        )

    def _record_authorization_evidence(
        self,
        result: MutationAuthorizationResult,
        *,
        authorization_sequence: int,
    ) -> None:
        self._record_evidence(
            "OWNERSHIP_AUTHORIZATION",
            schema=self.AUTHORIZATION_EVIDENCE_SCHEMA,
            authorization_sequence=int(authorization_sequence),
            subject_or_domain_id=result.claim.subject_or_domain_id,
            status=result.status.value,
            claim=result.claim.to_mapping(),
            observed=result.observed.to_mapping() if result.observed else None,
            mismatched_fields=list(result.mismatched_fields),
            error=result.error,
        )

    def _record_evidence(self, kind: str, **fields: Any) -> None:
        with self._evidence_lock:
            self._evidence_sequence += 1
            event = {
                "schema": self.EVIDENCE_SCHEMA,
                "sequence": self._evidence_sequence,
                "kind": str(kind),
                **fields,
            }
            self._evidence.append(event)


def validate_transition(
    expected: OwnershipRecord,
    desired: OwnershipRecord,
) -> str | None:
    """
    Validate monotonic ownership-state movement before CAS.

    This checkpoint does not yet implement durable restart recovery, but it
    freezes the transition rules later durability/fencing work must preserve.
    """
    if expected.subject_or_domain_id != desired.subject_or_domain_id:
        return "subject_or_domain_id cannot change"

    if desired.directory_generation <= expected.directory_generation:
        return "directory_generation must strictly increase"

    if desired.authority_epoch < expected.authority_epoch:
        return "authority_epoch cannot decrease"

    if desired.fencing_token < expected.fencing_token:
        return "fencing_token cannot decrease"

    if desired.state_revision < expected.state_revision:
        return "state_revision cannot decrease"

    if desired.route_revision < expected.route_revision:
        return "route_revision cannot decrease"

    owner_changed = desired.owner_authority_id != expected.owner_authority_id
    incarnation_changed = desired.authority_incarnation != expected.authority_incarnation

    if owner_changed:
        if desired.authority_epoch <= expected.authority_epoch:
            return "owner change requires authority_epoch increase"
        if desired.fencing_token <= expected.fencing_token:
            return "owner change requires fencing_token increase"

    if incarnation_changed:
        if desired.owner_authority_id == expected.owner_authority_id:
            if desired.fencing_token <= expected.fencing_token:
                return "same-owner incarnation change requires fencing_token increase"
        # Different-owner transitions are already protected by owner-change epoch/fence rules.

    return None