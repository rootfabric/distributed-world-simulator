from __future__ import annotations

import json
import tempfile
from pathlib import Path

from tools.research.seamless.i2 import (
    AuthorityRuntimeClaim,
    DirectoryReachability,
    DurableOwnershipDirectory,
    MutationAuthorityClaim,
    MutationGateStatus,
    OwnershipRecord,
    PartitionFencingGate,
)


def record(*, owner: str, epoch: int, fence: int, generation: int, incarnation: int) -> OwnershipRecord:
    return OwnershipRecord(
        subject_or_domain_id="domain/i2-5-demo",
        owner_authority_id=owner,
        authority_epoch=epoch,
        fencing_token=fence,
        directory_generation=generation,
        authority_incarnation=incarnation,
        state_revision=1,
        lease_state="ACTIVE",
        route_revision=1,
    )


def runtime(record_value: OwnershipRecord, *, process: str, restart: int = 0) -> AuthorityRuntimeClaim:
    return AuthorityRuntimeClaim(
        process_instance_id=process,
        restart_generation=restart,
        claim=MutationAuthorityClaim.from_record(record_value),
    )


def main() -> int:
    a = record(owner="authority-a", epoch=10, fence=50, generation=1, incarnation=1)
    b = record(owner="authority-b", epoch=11, fence=51, generation=2, incarnation=7)

    with tempfile.TemporaryDirectory() as temp:
        path = Path(temp) / "ownership-directory.json"
        directory = DurableOwnershipDirectory(path)
        directory.create(a)
        stale_runtime = runtime(a, process="authority-a-before-crash")
        gate = PartitionFencingGate(directory, reachability=DirectoryReachability.PARTITIONED)

        during_partition = gate.attempt(
            operation_id="op-during-partition",
            runtime_claim=stale_runtime,
        )
        transfer = directory.compare_and_swap(a, b)
        restarted_a = stale_runtime.restarted(process_instance_id="authority-a-after-restart")
        gate.heal()
        after_heal = gate.attempt(
            operation_id="op-stale-a-after-heal",
            runtime_claim=restarted_a,
        )

        reopened = DurableOwnershipDirectory(path)
        reopened_gate = PartitionFencingGate(reopened)
        after_directory_restart = reopened_gate.attempt(
            operation_id="op-stale-a-after-directory-restart",
            runtime_claim=restarted_a,
        )
        current_b = reopened_gate.attempt(
            operation_id="op-current-b",
            runtime_claim=runtime(b, process="authority-b-current"),
        )

        passed = (
            during_partition.status is MutationGateStatus.DIRECTORY_UNREACHABLE
            and transfer.succeeded
            and after_heal.status is MutationGateStatus.FENCED
            and after_directory_restart.status is MutationGateStatus.FENCED
            and current_b.status is MutationGateStatus.AUTHORIZED
            and reopened.lookup(a.subject_or_domain_id) == b
            and reopened.storage_revision == 2
        )

        report = {
            "schema": "distributed_world_simulator.sm1_i2_5_partition_fencing_report.v1",
            "checkpoint": "SM1-I2.5",
            "research_only": True,
            "accepted_i2_4_base": "b4b7ea41e40cda748fc1920ebe9bb6c3c90f3f54",
            "during_partition": during_partition.status.value,
            "canonical_transfer": transfer.status.value,
            "stale_a_after_heal": after_heal.status.value,
            "stale_a_after_directory_restart": after_directory_restart.status.value,
            "current_b": current_b.status.value,
            "recovered_owner": reopened.lookup(a.subject_or_domain_id).owner_authority_id,
            "storage_revision": reopened.storage_revision,
            "result": "PASS" if passed else "FAIL",
        }
        print(json.dumps(report, indent=2, sort_keys=True))
        return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
