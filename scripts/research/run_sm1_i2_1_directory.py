from __future__ import annotations

import json

from tools.research.seamless.i2.directory import OwnershipDirectory, OwnershipRecord


def _record(*, owner: str, epoch: int, fence: int, generation: int, incarnation: int) -> OwnershipRecord:
    return OwnershipRecord(
        subject_or_domain_id="domain/i2-1-demo",
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
    initial = _record(owner="authority-a", epoch=10, fence=100, generation=50, incarnation=1)
    to_b = _record(owner="authority-b", epoch=11, fence=101, generation=51, incarnation=1)
    stale_to_c = _record(owner="authority-c", epoch=11, fence=102, generation=52, incarnation=1)

    directory.create(initial)
    first = directory.compare_and_swap(initial, to_b)
    second = directory.compare_and_swap(initial, stale_to_c)
    final = directory.lookup(initial.subject_or_domain_id)

    report = {
        "schema": "distributed_world_simulator.sm1_i2_1_directory_report.v1",
        "checkpoint": "SM1-I2.1",
        "research_only": True,
        "first_cas": first.status.value,
        "stale_cas": second.status.value,
        "final_record": final.to_mapping() if final else None,
        "evidence": directory.evidence(),
        "result": "PASS" if first.succeeded and not second.succeeded and final == to_b else "FAIL",
    }
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0 if report["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
