from __future__ import annotations

import json
import tempfile
from pathlib import Path

from tools.research.seamless.i2 import (
    DurableCommitFaultPoint,
    DurableOwnershipDirectory,
    IncarnationReplacementCoordinator,
    IncarnationReplacementRequest,
    IncarnationReplacementStatus,
    MutationAuthorizationStatus,
    MutationAuthorityClaim,
    OwnershipRecord,
)


class LostResponse(RuntimeError):
    pass


def record(*, fence: int, generation: int, incarnation: int) -> OwnershipRecord:
    return OwnershipRecord(
        subject_or_domain_id="domain/i2-4-demo",
        owner_authority_id="authority-a",
        authority_epoch=10,
        fencing_token=fence,
        directory_generation=generation,
        authority_incarnation=incarnation,
        state_revision=1,
        lease_state="ACTIVE",
        route_revision=1,
    )


def main() -> int:
    i1 = record(fence=50, generation=1, incarnation=1)
    i2 = record(fence=51, generation=2, incarnation=2)

    with tempfile.TemporaryDirectory() as temp:
        path = Path(temp) / "ownership-directory.json"
        DurableOwnershipDirectory(path).create(i1)

        def lose_response(point: DurableCommitFaultPoint) -> None:
            if point is DurableCommitFaultPoint.AFTER_DURABLE_COMMIT_BEFORE_RETURN:
                raise LostResponse("simulated process loss after durable commit")

        lost = False
        doomed = DurableOwnershipDirectory(path, fault_hook=lose_response)
        try:
            IncarnationReplacementCoordinator(doomed).replace(
                IncarnationReplacementRequest(i1, i2)
            )
        except LostResponse:
            lost = True

        reopened = DurableOwnershipDirectory(path)
        retry = IncarnationReplacementCoordinator(reopened).replace(
            IncarnationReplacementRequest(i1, i2)
        )
        old_auth = reopened.authorize_ownership_tuple(MutationAuthorityClaim.from_record(i1))
        new_auth = reopened.authorize_ownership_tuple(MutationAuthorityClaim.from_record(i2))

        passed = (
            lost
            and reopened.lookup(i1.subject_or_domain_id) == i2
            and retry.status is IncarnationReplacementStatus.ALREADY_COMMITTED
            and old_auth.status is MutationAuthorizationStatus.FENCED
            and new_auth.status is MutationAuthorizationStatus.AUTHORIZED
            and reopened.storage_revision == 2
        )

        report = {
            "schema": "distributed_world_simulator.sm1_i2_4_durable_directory_report.v1",
            "checkpoint": "SM1-I2.4",
            "research_only": True,
            "accepted_i2_3_base": "2e709249b5854e1bd0584041c3731e5bf102bde6",
            "lost_response_after_durable_commit": lost,
            "recovered_record": reopened.lookup(i1.subject_or_domain_id).to_mapping(),
            "replacement_retry": retry.status.value,
            "old_incarnation_after_reopen": old_auth.status.value,
            "new_incarnation_after_reopen": new_auth.status.value,
            "storage_revision": reopened.storage_revision,
            "result": "PASS" if passed else "FAIL",
        }
        print(json.dumps(report, indent=2, sort_keys=True))
        return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
