from __future__ import annotations

import json

from tools.research.seamless.i2.directory import (
    CasStatus,
    MutationAuthorizationStatus,
    MutationAuthorityClaim,
    OwnershipDirectory,
    OwnershipRecord,
)


def record(
    *,
    owner: str,
    epoch: int,
    fence: int,
    generation: int,
    incarnation: int,
) -> OwnershipRecord:
    return OwnershipRecord(
        subject_or_domain_id="domain/i2-2-demo",
        owner_authority_id=owner,
        authority_epoch=epoch,
        fencing_token=fence,
        directory_generation=generation,
        authority_incarnation=incarnation,
        state_revision=1,
        lease_state="ACTIVE",
        route_revision=1,
    )


def main() -> int:
    directory = OwnershipDirectory()
    a_i1 = record(owner="authority-a", epoch=10, fence=50, generation=1, incarnation=1)
    a_i2 = record(owner="authority-a", epoch=10, fence=51, generation=2, incarnation=2)

    directory.create(a_i1)
    before = directory.authorize_ownership_tuple(MutationAuthorityClaim.from_record(a_i1))
    replacement = directory.compare_and_swap(a_i1, a_i2)
    stale_after = directory.authorize_ownership_tuple(MutationAuthorityClaim.from_record(a_i1))
    current_after = directory.authorize_ownership_tuple(MutationAuthorityClaim.from_record(a_i2))

    passed = (
        before.status is MutationAuthorizationStatus.AUTHORIZED
        and replacement.status is CasStatus.CAS_OK
        and stale_after.status is MutationAuthorizationStatus.FENCED
        and current_after.status is MutationAuthorizationStatus.AUTHORIZED
        and stale_after.mismatched_fields == ("fencing_token", "authority_incarnation")
        and directory.lookup(a_i1.subject_or_domain_id) == a_i2
    )

    report = {
        "schema": "distributed_world_simulator.sm1_i2_2_authorization_report.v1",
        "checkpoint": "SM1-I2.2",
        "research_only": True,
        "accepted_i2_1_base": "f1fd65ad73da8c95612a641be0ad52048c90169a",
        "before_replacement": before.status.value,
        "replacement_cas": replacement.status.value,
        "old_incarnation_after_replacement": stale_after.status.value,
        "old_incarnation_mismatched_fields": list(stale_after.mismatched_fields),
        "new_incarnation_after_replacement": current_after.status.value,
        "final_record": directory.lookup(a_i1.subject_or_domain_id).to_mapping(),
        "authorization_evidence": [
            event for event in directory.evidence()
            if event["kind"] == "OWNERSHIP_AUTHORIZATION"
        ],
        "result": "PASS" if passed else "FAIL",
    }
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
