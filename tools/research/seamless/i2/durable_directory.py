from __future__ import annotations

import hashlib
import hmac
import json
import os
import uuid
from enum import Enum
from pathlib import Path
from typing import Any, Callable, Mapping

from .directory import (
    CasResult,
    CasStatus,
    CreateResult,
    CreateStatus,
    DirectoryContractError,
    MutationAuthorizationResult,
    MutationAuthorityClaim,
    OwnershipDirectory,
    OwnershipRecord,
    validate_transition,
)


class DurableDirectoryError(RuntimeError):
    """Base error for the research-only I2.4 durable Directory backend."""


class DurableDirectoryCorruption(DurableDirectoryError):
    """Raised when canonical durable state cannot be validated safely."""


class DurableDirectoryUnavailable(DurableDirectoryError):
    """Raised after an ambiguous persistence failure poisons a live instance."""


class DurableCommitFaultPoint(str, Enum):
    AFTER_TEMP_FSYNC_BEFORE_REPLACE = "AFTER_TEMP_FSYNC_BEFORE_REPLACE"
    AFTER_DURABLE_COMMIT_BEFORE_RETURN = "AFTER_DURABLE_COMMIT_BEFORE_RETURN"


CommitFaultHook = Callable[[DurableCommitFaultPoint], None]


class DurableOwnershipDirectory(OwnershipDirectory):
    """Single-process POSIX atomic-file prototype for SM1-I2.4.

    Canonical state is a checksummed snapshot. Mutating operations serialize on
    the accepted Directory ownership lock, write and fsync a temporary file,
    atomically replace the canonical file, fsync its parent directory, and only
    then publish CAS_OK/CREATED to the caller.

    This is deliberately a single-active-Directory-process research backend.
    Cross-process active/active Directory writer coordination is out of scope.
    """

    SNAPSHOT_SCHEMA = "distributed_world_simulator.sm1_i2_4_durable_directory_snapshot.v1"
    DURABILITY_EVIDENCE_SCHEMA = "distributed_world_simulator.sm1_i2_4_durable_directory_evidence.v1"

    def __init__(
        self,
        storage_path: str | os.PathLike[str],
        *,
        fault_hook: CommitFaultHook | None = None,
    ) -> None:
        super().__init__()
        self._storage_path = Path(storage_path)
        self._storage_path.parent.mkdir(parents=True, exist_ok=True)
        self._fault_hook = fault_hook
        self._poisoned = False
        records, revision, checksum = self._load_canonical_snapshot()
        self._records = records
        self._storage_revision = revision
        self._storage_checksum = checksum
        self._record_durability_evidence(
            "DURABLE_DIRECTORY_OPENED",
            storage_revision=self._storage_revision,
            record_count=len(self._records),
            checksum_sha256=self._storage_checksum,
        )

    @property
    def storage_path(self) -> Path:
        return self._storage_path

    @property
    def storage_revision(self) -> int:
        with self._lock:
            self._assert_healthy_locked()
            return self._storage_revision

    def durable_metadata(self) -> dict[str, Any]:
        with self._lock:
            self._assert_healthy_locked()
            return {
                "snapshot_schema": self.SNAPSHOT_SCHEMA,
                "storage_revision": self._storage_revision,
                "checksum_sha256": self._storage_checksum,
                "record_count": len(self._records),
            }

    def lookup(self, subject_or_domain_id: str) -> OwnershipRecord | None:
        with self._lock:
            self._assert_healthy_locked()
            return super().lookup(subject_or_domain_id)

    def snapshot(self) -> dict[str, OwnershipRecord]:
        with self._lock:
            self._assert_healthy_locked()
            return super().snapshot()

    def authorize_ownership_tuple(
        self,
        claim: MutationAuthorityClaim,
    ) -> MutationAuthorizationResult:
        with self._lock:
            self._assert_healthy_locked()
            return super().authorize_ownership_tuple(claim)

    def create(self, record: OwnershipRecord) -> CreateResult:
        with self._lock:
            self._assert_healthy_locked()
            current = self._records.get(record.subject_or_domain_id)
            if current is not None:
                result = CreateResult(CreateStatus.ALREADY_EXISTS, current)
            else:
                candidate = dict(self._records)
                candidate[record.subject_or_domain_id] = record
                next_revision = self._storage_revision + 1
                try:
                    checksum = self._durably_commit_snapshot_locked(
                        candidate, storage_revision=next_revision
                    )
                except Exception:
                    self._poisoned = True
                    raise
                self._records = candidate
                self._storage_revision = next_revision
                self._storage_checksum = checksum
                result = CreateResult(CreateStatus.CREATED, record)
                self._record_durability_evidence(
                    "DURABLE_CREATE_COMMITTED",
                    storage_revision=self._storage_revision,
                    subject_or_domain_id=record.subject_or_domain_id,
                    checksum_sha256=checksum,
                )

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
        with self._lock:
            self._assert_healthy_locked()
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
                    candidate = dict(self._records)
                    candidate[expected.subject_or_domain_id] = desired
                    next_revision = self._storage_revision + 1
                    try:
                        checksum = self._durably_commit_snapshot_locked(
                            candidate, storage_revision=next_revision
                        )
                    except Exception:
                        self._poisoned = True
                        raise
                    self._records = candidate
                    self._storage_revision = next_revision
                    self._storage_checksum = checksum
                    result = CasResult(
                        status=CasStatus.CAS_OK,
                        expected=expected,
                        desired=desired,
                        observed=observed,
                        current=desired,
                    )
                    self._record_durability_evidence(
                        "DURABLE_CAS_COMMITTED",
                        storage_revision=self._storage_revision,
                        subject_or_domain_id=expected.subject_or_domain_id,
                        checksum_sha256=checksum,
                    )

            self._linearization_sequence += 1
            self._record_cas_evidence(
                result, linearization_sequence=self._linearization_sequence
            )
            return result

    def _assert_healthy_locked(self) -> None:
        if self._poisoned:
            raise DurableDirectoryUnavailable(
                "Directory instance is poisoned after an ambiguous persistence failure; reopen from canonical durable state"
            )

    def _load_canonical_snapshot(
        self,
    ) -> tuple[dict[str, OwnershipRecord], int, str | None]:
        if not self._storage_path.exists():
            return {}, 0, None

        try:
            raw_bytes = self._storage_path.read_bytes()
            envelope = json.loads(raw_bytes.decode("utf-8"))
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise DurableDirectoryCorruption(
                "canonical durable Directory snapshot is unreadable"
            ) from exc

        if not isinstance(envelope, Mapping):
            raise DurableDirectoryCorruption("snapshot root must be an object")
        expected_keys = {"schema", "storage_revision", "records", "checksum_sha256"}
        if set(envelope.keys()) != expected_keys:
            raise DurableDirectoryCorruption("snapshot fields do not match the I2.4 schema")
        if envelope["schema"] != self.SNAPSHOT_SCHEMA:
            raise DurableDirectoryCorruption("snapshot schema mismatch")

        revision = envelope["storage_revision"]
        if not isinstance(revision, int) or isinstance(revision, bool) or revision < 1:
            raise DurableDirectoryCorruption("storage_revision must be an integer >= 1")
        raw_records = envelope["records"]
        if not isinstance(raw_records, list):
            raise DurableDirectoryCorruption("records must be an array")
        checksum = envelope["checksum_sha256"]
        if not isinstance(checksum, str) or len(checksum) != 64:
            raise DurableDirectoryCorruption("checksum_sha256 must be a SHA-256 hex digest")

        body = {
            "schema": self.SNAPSHOT_SCHEMA,
            "storage_revision": revision,
            "records": raw_records,
        }
        expected_checksum = self._checksum_body(body)
        if not hmac.compare_digest(checksum, expected_checksum):
            raise DurableDirectoryCorruption("snapshot checksum mismatch")

        records: dict[str, OwnershipRecord] = {}
        try:
            for raw_record in raw_records:
                if not isinstance(raw_record, Mapping):
                    raise DurableDirectoryCorruption("record entry must be an object")
                record = OwnershipRecord.from_mapping(raw_record)
                if record.subject_or_domain_id in records:
                    raise DurableDirectoryCorruption(
                        "snapshot contains duplicate subject_or_domain_id"
                    )
                records[record.subject_or_domain_id] = record
        except (KeyError, TypeError, ValueError, DirectoryContractError) as exc:
            if isinstance(exc, DurableDirectoryCorruption):
                raise
            raise DurableDirectoryCorruption("snapshot contains an invalid OwnershipRecord") from exc

        return records, revision, checksum

    def _durably_commit_snapshot_locked(
        self,
        records: Mapping[str, OwnershipRecord],
        *,
        storage_revision: int,
    ) -> str:
        body = {
            "schema": self.SNAPSHOT_SCHEMA,
            "storage_revision": int(storage_revision),
            "records": [
                records[subject].to_mapping()
                for subject in sorted(records)
            ],
        }
        checksum = self._checksum_body(body)
        envelope = {**body, "checksum_sha256": checksum}
        payload = self._canonical_json(envelope)

        temp_path = self._storage_path.with_name(
            f".{self._storage_path.name}.tmp-{os.getpid()}-{uuid.uuid4().hex}"
        )
        try:
            with temp_path.open("xb") as stream:
                stream.write(payload)
                stream.flush()
                os.fsync(stream.fileno())

            self._invoke_fault_hook(DurableCommitFaultPoint.AFTER_TEMP_FSYNC_BEFORE_REPLACE)
            os.replace(temp_path, self._storage_path)
            self._fsync_parent_directory()
            self._invoke_fault_hook(DurableCommitFaultPoint.AFTER_DURABLE_COMMIT_BEFORE_RETURN)
            return checksum
        finally:
            try:
                temp_path.unlink(missing_ok=True)
            except OSError:
                pass

    def _fsync_parent_directory(self) -> None:
        if os.name != "posix":
            raise DurableDirectoryError(
                "I2.4 atomic-file durability prototype requires POSIX directory fsync"
            )
        fd = os.open(self._storage_path.parent, os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)

    def _invoke_fault_hook(self, point: DurableCommitFaultPoint) -> None:
        if self._fault_hook is not None:
            self._fault_hook(point)

    def _record_durability_evidence(self, kind: str, **fields: Any) -> None:
        self._record_evidence(
            kind,
            schema=self.DURABILITY_EVIDENCE_SCHEMA,
            **fields,
        )

    @classmethod
    def _checksum_body(cls, body: Mapping[str, Any]) -> str:
        return hashlib.sha256(cls._canonical_json(body)).hexdigest()

    @staticmethod
    def _canonical_json(value: Mapping[str, Any]) -> bytes:
        return (
            json.dumps(
                value,
                ensure_ascii=False,
                sort_keys=True,
                separators=(",", ":"),
            )
            + "\n"
        ).encode("utf-8")
