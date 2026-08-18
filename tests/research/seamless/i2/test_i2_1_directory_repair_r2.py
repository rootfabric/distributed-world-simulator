from __future__ import annotations

import unittest

from tools.research.seamless.i2.directory import (
    CasStatus,
    OwnershipDirectory,
    OwnershipRecord,
)


def record(
    *,
    epoch: int = 10,
    fence: int = 100,
    generation: int = 50,
) -> OwnershipRecord:
    return OwnershipRecord(
        subject_or_domain_id="domain/player-42",
        owner_authority_id="authority-a",
        authority_epoch=epoch,
        fencing_token=fence,
        directory_generation=generation,
        authority_incarnation=7,
        state_revision=200,
        lease_state="ACTIVE",
        route_revision=30,
    )


class I21OwnershipDirectoryRepairR2Tests(unittest.TestCase):
    def test_od_cas_17_not_found_wins_classification_over_invalid_desired(self) -> None:
        directory = OwnershipDirectory()
        expected = record()

        # This transition is semantically invalid relative to expected because
        # authority_epoch decreases. Since no canonical record exists, CAS
        # classification must stop at NOT_FOUND before desired validation.
        invalid_desired = record(epoch=9, generation=51)

        self.assertEqual({}, directory.snapshot())
        result = directory.compare_and_swap(expected, invalid_desired)

        self.assertEqual(CasStatus.NOT_FOUND, result.status)
        self.assertIsNone(result.observed)
        self.assertIsNone(result.current)
        self.assertEqual({}, directory.snapshot())

        cas_events = [
            event for event in directory.evidence() if event["kind"] == "CAS_RESULT"
        ]
        self.assertEqual(1, len(cas_events))
        self.assertEqual("NOT_FOUND", cas_events[0]["status"])
        self.assertEqual(1, cas_events[0]["linearization_sequence"])
        self.assertIsNone(cas_events[0]["observed"])
        self.assertIsNone(cas_events[0]["current"])


if __name__ == "__main__":
    unittest.main()
