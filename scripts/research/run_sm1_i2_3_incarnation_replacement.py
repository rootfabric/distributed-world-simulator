from __future__ import annotations

import json

from tools.research.seamless.i2.directory import (
    MutationAuthorityClaim,
    OwnershipDirectory,
    OwnershipRecord,
)
from tools.research.seamless.i2.incarnation_replacement import (
    IncarnationReplacementCoordinator,
    IncarnationReplacementRequest,
)


def record(*, incarnation: int, fence: int, generation: int) -> OwnershipRecord:
    return OwnershipRecord(
        subject_or_domain_id="domain/i2-3-demo",
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
    directory = OwnershipDirectory()
    coordinator = IncarnationReplacementCoordinator(directory)
    i1 = record(incarnation=1, fence=50, generation=1)
    i2 = record(incarnation=2, fence=51, generation=2)
    directory.create(i1)

    request = IncarnationReplacementRequest(i1, i2)
    first = coordinator.replace(request)
    retry = coordinator.replace(request)
    old_auth = directory.authorize_ownership_tuple(MutationAuthorityClaim.from_record(i1))
    new_auth = directory.authorize_ownership_tuple(MutationAuthorityClaim.from_record(i2))
    final = directory.lookup(i1.subject_or_domain_id)

    passed = (
        first.status.value == "REPLACED"
        and retry.status.value == "ALREADY_COMMITTED"
        and final == i2
        and final.fencing_token == 51
        and final.directory_generation == 2
        and old_auth.status.value == "FENCED"
        and new_auth.status.value == "AUTHORIZED"
    )

    report = {
        "schema": "distributed_world_simulator.sm1_i2_3_incarnation_replacement_report.v1",
        "checkpoint": "SM1-I2.3",
        "research_only": True,
        "accepted_i2_2_base": "c09a53b5c7aba10c091e8cfb2ea8307d5f6b39da",
        "first_replacement": first.status.value,
        "ambiguous_retry": retry.status.value,
        "old_incarnation_authorization": old_auth.status.value,
        "new_incarnation_authorization": new_auth.status.value,
        "final_record": final.to_mapping() if final else None,
        "replacement_evidence": coordinator.evidence(),
        "directory_cas_evidence": [
            event for event in directory.evidence() if event["kind"] == "CAS_RESULT"
        ],
        "result": "PASS" if passed else "FAIL",
    }
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
