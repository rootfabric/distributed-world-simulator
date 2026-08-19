from __future__ import annotations

import json
import tempfile
from pathlib import Path

from tools.research.seamless.i2 import (
    AuthorityRuntimeClaim,
    CasStatus,
    DurableOwnershipDirectory,
    IntegratedOneWriterProbe,
    MutationAuthorityClaim,
    OneWriterProbeAttempt,
    OneWriterRoundStatus,
    OwnershipRecord,
    PartitionFencingGate,
)


def record(*, owner: str, epoch: int, fence: int, generation: int, incarnation: int) -> OwnershipRecord:
    return OwnershipRecord(
        subject_or_domain_id="domain/i2-6-demo",
        owner_authority_id=owner,
        authority_epoch=epoch,
        fencing_token=fence,
        directory_generation=generation,
        authority_incarnation=incarnation,
        state_revision=100,
        lease_state="ACTIVE",
        route_revision=10,
    )


def runtime(value: OwnershipRecord, pid: str, restart: int = 0) -> AuthorityRuntimeClaim:
    return AuthorityRuntimeClaim(pid, restart, MutationAuthorityClaim.from_record(value))


def probe_attempt(directory, value, participant, restart=0):
    return OneWriterProbeAttempt(participant, PartitionFencingGate(directory), runtime(value, participant, restart))


def main() -> int:
    a = record(owner="authority-a", epoch=10, fence=50, generation=1, incarnation=1)
    b = record(owner="authority-b", epoch=11, fence=51, generation=2, incarnation=7)

    with tempfile.TemporaryDirectory() as temp:
        path = Path(temp) / "ownership-directory.json"
        directory = DurableOwnershipDirectory(path)
        directory.create(a)
        probe = IntegratedOneWriterProbe(directory)

        initial = probe.probe_round(
            round_id="initial",
            operation_id="op-initial",
            subject_or_domain_id=a.subject_or_domain_id,
            attempts=[
                probe_attempt(directory, a, "current-a"),
                OneWriterProbeAttempt("stale-a", PartitionFencingGate(directory), runtime(a, "stale-a", 3)),
            ],
        )

        partitioned_gate = PartitionFencingGate(directory)
        partitioned_gate.partition()
        partitioned = probe.probe_round(
            round_id="partitioned",
            operation_id="op-partitioned",
            subject_or_domain_id=a.subject_or_domain_id,
            attempts=[OneWriterProbeAttempt("partitioned-a", partitioned_gate, runtime(a, "partitioned-a", 4))],
        )

        transfer = directory.compare_and_swap(a, b)

        after_transfer = probe.probe_round(
            round_id="after-transfer",
            operation_id="op-after-transfer",
            subject_or_domain_id=a.subject_or_domain_id,
            attempts=[
                probe_attempt(directory, a, "old-a", restart=5),
                probe_attempt(directory, b, "current-b"),
            ],
        )

        reopened = DurableOwnershipDirectory(path)
        after_restart = IntegratedOneWriterProbe(reopened).probe_round(
            round_id="after-directory-restart",
            operation_id="op-after-directory-restart",
            subject_or_domain_id=a.subject_or_domain_id,
            attempts=[
                probe_attempt(reopened, a, "old-a-after-restart", restart=6),
                probe_attempt(reopened, b, "current-b-after-restart"),
            ],
        )

        clone_violation = IntegratedOneWriterProbe(reopened).probe_round(
            round_id="clone-detection",
            operation_id="op-clone-detection",
            subject_or_domain_id=a.subject_or_domain_id,
            attempts=[
                probe_attempt(reopened, b, "clone-1"),
                probe_attempt(reopened, b, "clone-2"),
            ],
        )

        passed = (
            initial.status is OneWriterRoundStatus.EXACTLY_ONE_AUTHORIZED
            and initial.authorized_participants == ("current-a",)
            and partitioned.status is OneWriterRoundStatus.ZERO_AUTHORIZED
            and transfer.status is CasStatus.CAS_OK
            and after_transfer.authorized_participants == ("current-b",)
            and after_transfer.one_writer_safe
            and after_restart.authorized_participants == ("current-b-after-restart",)
            and after_restart.one_writer_safe
            and clone_violation.status is OneWriterRoundStatus.MULTIPLE_AUTHORIZED_VIOLATION
            and not clone_violation.one_writer_safe
        )

        report = {
            "schema": "distributed_world_simulator.sm1_i2_6_integrated_one_writer_report.v1",
            "checkpoint": "SM1-I2.6",
            "research_only": True,
            "accepted_i2_5_base": "f430bef4b8c942e860ba228e0a5c62fb9ac4eb9d",
            "initial_authorized": list(initial.authorized_participants),
            "partitioned_status": partitioned.status.value,
            "transfer_status": transfer.status.value,
            "after_transfer_authorized": list(after_transfer.authorized_participants),
            "after_directory_restart_authorized": list(after_restart.authorized_participants),
            "duplicate_exact_tuple_oracle": clone_violation.status.value,
            "result": "PASS" if passed else "FAIL",
        }
        print(json.dumps(report, indent=2, sort_keys=True))
        return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
