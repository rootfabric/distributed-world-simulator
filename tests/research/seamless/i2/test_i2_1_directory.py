from __future__ import annotations

import json
import threading
import unittest
from pathlib import Path

from tools.research.seamless.i2.directory import (
    CasStatus,
    CreateStatus,
    DirectoryContractError,
    OwnershipDirectory,
    OwnershipRecord,
)


def record(
    *,
    owner: str = "authority-a",
    epoch: int = 10,
    fence: int = 100,
    generation: int = 50,
    incarnation: int = 7,
    state_revision: int = 200,
    lease_state: str = "ACTIVE",
    route_revision: int = 30,
) -> OwnershipRecord:
    return OwnershipRecord(
        subject_or_domain_id="domain/player-42",
        owner_authority_id=owner,
        authority_epoch=epoch,
        fencing_token=fence,
        directory_generation=generation,
        authority_incarnation=incarnation,
        state_revision=state_revision,
        lease_state=lease_state,
        route_revision=route_revision,
    )


class I21OwnershipDirectoryTests(unittest.TestCase):
    def test_od_cas_01_initial_record_can_be_created_and_looked_up(self) -> None:
        directory = OwnershipDirectory()
        initial = record()
        result = directory.create(initial)
        self.assertEqual(CreateStatus.CREATED, result.status)
        self.assertEqual(initial, directory.lookup(initial.subject_or_domain_id))

    def test_od_cas_02_expected_state_to_desired_state_succeeds(self) -> None:
        directory = OwnershipDirectory()
        initial = record()
        desired = record(owner="authority-b", epoch=11, fence=101, generation=51, incarnation=3)
        directory.create(initial)

        result = directory.compare_and_swap(initial, desired)

        self.assertEqual(CasStatus.CAS_OK, result.status)
        self.assertTrue(result.succeeded)
        self.assertEqual(desired, directory.lookup(initial.subject_or_domain_id))

    def test_od_cas_03_stale_expected_state_is_rejected(self) -> None:
        directory = OwnershipDirectory()
        initial = record()
        winner = record(owner="authority-b", epoch=11, fence=101, generation=51, incarnation=3)
        stale_desired = record(owner="authority-c", epoch=11, fence=102, generation=52, incarnation=4)
        directory.create(initial)
        self.assertTrue(directory.compare_and_swap(initial, winner).succeeded)

        result = directory.compare_and_swap(initial, stale_desired)

        self.assertEqual(CasStatus.CAS_MISMATCH, result.status)
        self.assertEqual(winner, result.observed)
        self.assertEqual(winner, directory.lookup(initial.subject_or_domain_id))

    def test_od_cas_04_two_simultaneous_contenders_exactly_one_succeeds(self) -> None:
        directory = OwnershipDirectory()
        initial = record()
        to_b = record(owner="authority-b", epoch=11, fence=101, generation=51, incarnation=3)
        to_c = record(owner="authority-c", epoch=11, fence=102, generation=52, incarnation=4)
        directory.create(initial)

        barrier = threading.Barrier(3)
        results: list[tuple[OwnershipRecord, object]] = []
        results_lock = threading.Lock()

        def contender(desired: OwnershipRecord) -> None:
            barrier.wait()
            result = directory.compare_and_swap(initial, desired)
            with results_lock:
                results.append((desired, result))

        threads = [
            threading.Thread(target=contender, args=(to_b,)),
            threading.Thread(target=contender, args=(to_c,)),
        ]
        for thread in threads:
            thread.start()
        barrier.wait()
        for thread in threads:
            thread.join(timeout=2.0)
            self.assertFalse(thread.is_alive())

        self.assertEqual(2, len(results))
        winners = [(desired, result) for desired, result in results if result.status is CasStatus.CAS_OK]
        losers = [(desired, result) for desired, result in results if result.status is CasStatus.CAS_MISMATCH]
        self.assertEqual(1, len(winners))
        self.assertEqual(1, len(losers))

        winner_desired, winner_result = winners[0]
        _, loser_result = losers[0]
        final = directory.lookup(initial.subject_or_domain_id)

        self.assertEqual(winner_desired, winner_result.current)
        self.assertEqual(winner_desired, final)
        self.assertEqual(winner_desired, loser_result.observed)
        self.assertEqual(winner_desired, loser_result.current)

    def test_od_cas_05_failed_cas_leaves_record_unchanged(self) -> None:
        directory = OwnershipDirectory()
        initial = record()
        directory.create(initial)
        stale_expected = record(generation=49)
        desired = record(owner="authority-b", epoch=11, fence=101, generation=51, incarnation=3)

        result = directory.compare_and_swap(stale_expected, desired)

        self.assertEqual(CasStatus.CAS_MISMATCH, result.status)
        self.assertEqual(initial, directory.lookup(initial.subject_or_domain_id))

    def test_od_cas_06_epoch_cannot_decrease(self) -> None:
        directory = OwnershipDirectory()
        initial = record()
        directory.create(initial)
        desired = record(epoch=9, generation=51)

        result = directory.compare_and_swap(initial, desired)

        self.assertEqual(CasStatus.INVALID_TRANSITION, result.status)
        self.assertIn("authority_epoch", result.error or "")

    def test_od_cas_07_fence_cannot_decrease_or_be_reused_on_owner_change(self) -> None:
        directory = OwnershipDirectory()
        initial = record()
        directory.create(initial)

        decreased = record(fence=99, generation=51)
        reused_on_new_owner = record(owner="authority-b", epoch=11, fence=100, generation=51, incarnation=3)

        self.assertEqual(
            CasStatus.INVALID_TRANSITION,
            directory.compare_and_swap(initial, decreased).status,
        )
        self.assertEqual(
            CasStatus.INVALID_TRANSITION,
            directory.compare_and_swap(initial, reused_on_new_owner).status,
        )

    def test_od_cas_08_directory_generation_must_strictly_increase(self) -> None:
        directory = OwnershipDirectory()
        initial = record()
        directory.create(initial)

        result = directory.compare_and_swap(initial, record(generation=50))

        self.assertEqual(CasStatus.INVALID_TRANSITION, result.status)
        self.assertIn("directory_generation", result.error or "")

    def test_od_cas_09_owner_change_requires_epoch_increase(self) -> None:
        directory = OwnershipDirectory()
        initial = record()
        directory.create(initial)

        desired = record(owner="authority-b", epoch=10, fence=101, generation=51, incarnation=3)
        result = directory.compare_and_swap(initial, desired)

        self.assertEqual(CasStatus.INVALID_TRANSITION, result.status)

    def test_od_cas_10_same_owner_incarnation_change_requires_new_fence(self) -> None:
        directory = OwnershipDirectory()
        initial = record()
        directory.create(initial)

        invalid = record(generation=51, incarnation=8, fence=100)
        valid = record(generation=51, incarnation=8, fence=101)

        self.assertEqual(
            CasStatus.INVALID_TRANSITION,
            directory.compare_and_swap(initial, invalid).status,
        )
        self.assertEqual(
            CasStatus.CAS_OK,
            directory.compare_and_swap(initial, valid).status,
        )

    def test_od_cas_11_lookup_and_mutation_are_separate(self) -> None:
        directory = OwnershipDirectory()
        initial = record()
        desired = record(owner="authority-b", epoch=11, fence=101, generation=51, incarnation=3)
        directory.create(initial)

        observed = directory.lookup(initial.subject_or_domain_id)

        self.assertEqual(initial, observed)
        self.assertEqual(initial, directory.lookup(initial.subject_or_domain_id))
        self.assertTrue(directory.compare_and_swap(observed, desired).succeeded)

    def test_od_cas_12_machine_evidence_records_success_and_stale_rejection(self) -> None:
        directory = OwnershipDirectory()
        initial = record()
        winner = record(owner="authority-b", epoch=11, fence=101, generation=51, incarnation=3)
        stale = record(owner="authority-c", epoch=11, fence=102, generation=52, incarnation=4)
        directory.create(initial)
        directory.compare_and_swap(initial, winner)
        directory.compare_and_swap(initial, stale)

        evidence = directory.evidence()
        cas_events = [event for event in evidence if event["kind"] == "CAS_RESULT"]

        self.assertEqual(["CAS_OK", "CAS_MISMATCH"], [event["status"] for event in cas_events])
        self.assertEqual(list(range(1, len(evidence) + 1)), [event["sequence"] for event in evidence])

    def test_od_cas_13_create_does_not_overwrite_existing_record(self) -> None:
        directory = OwnershipDirectory()
        initial = record()
        other = record(owner="authority-b", epoch=11, fence=101, generation=51, incarnation=3)
        self.assertEqual(CreateStatus.CREATED, directory.create(initial).status)

        second = directory.create(other)

        self.assertEqual(CreateStatus.ALREADY_EXISTS, second.status)
        self.assertEqual(initial, second.current)
        self.assertEqual(initial, directory.lookup(initial.subject_or_domain_id))


    def test_od_cas_14_stale_expected_wins_classification_over_invalid_desired(self) -> None:
        directory = OwnershipDirectory()
        initial = record()
        winner = record(owner="authority-b", epoch=11, fence=101, generation=51, incarnation=3)
        directory.create(initial)
        self.assertEqual(CasStatus.CAS_OK, directory.compare_and_swap(initial, winner).status)

        # The desired transition is invalid relative to the stale expected
        # record (generation does not increase), but stale expected state must
        # be classified first and therefore return CAS_MISMATCH.
        invalid_desired = record(generation=50)
        result = directory.compare_and_swap(initial, invalid_desired)

        self.assertEqual(CasStatus.CAS_MISMATCH, result.status)
        self.assertEqual(winner, result.observed)
        self.assertEqual(winner, result.current)
        self.assertEqual(winner, directory.lookup(initial.subject_or_domain_id))

    def test_od_cas_15_concurrent_evidence_preserves_linearization_order(self) -> None:
        directory = OwnershipDirectory()
        initial = record()
        to_b = record(owner="authority-b", epoch=11, fence=101, generation=51, incarnation=3)
        to_c = record(owner="authority-c", epoch=11, fence=102, generation=52, incarnation=4)
        directory.create(initial)

        barrier = threading.Barrier(3)
        threads = [
            threading.Thread(target=lambda desired=desired: (barrier.wait(), directory.compare_and_swap(initial, desired)))
            for desired in (to_b, to_c)
        ]
        for thread in threads:
            thread.start()
        barrier.wait()
        for thread in threads:
            thread.join(timeout=2.0)
            self.assertFalse(thread.is_alive())

        cas_events = [event for event in directory.evidence() if event["kind"] == "CAS_RESULT"]
        self.assertEqual(2, len(cas_events))
        self.assertEqual([1, 2], [event["linearization_sequence"] for event in cas_events])
        self.assertEqual(["CAS_OK", "CAS_MISMATCH"], [event["status"] for event in cas_events])
        self.assertEqual(
            cas_events[0]["desired"],
            cas_events[1]["observed"],
        )

    def test_od_cas_16_machine_contract_matches_implementation_surface(self) -> None:
        contract_path = (
            Path(__file__).resolve().parents[4]
            / "config/research/seamless/i2/i2-1-directory-contract.v1.json"
        )
        contract = json.loads(contract_path.read_text(encoding="utf-8"))

        self.assertEqual("SM1-I2.1", contract["checkpoint"])
        self.assertFalse(contract["production_activation"])
        self.assertTrue(contract["donor_only"])
        self.assertEqual(
            "87a9ca12c38a9b15069fb49a57bfa344b8c25cfa",
            contract["architecture_base"],
        )
        self.assertIn("AT_MOST_ONE_CONTENDER_SUCCEEDS_FOR_ONE_EXPECTED_STATE", contract["transition_invariants"])
        self.assertIn("STALE_EXPECTED_CLASSIFIED_BEFORE_DESIRED_VALIDATION", contract["transition_invariants"])
        self.assertIn("CAS_EVIDENCE_PRESERVES_LINEARIZATION_ORDER", contract["transition_invariants"])
        self.assertEqual(
            "EXPECTED_FULL_RECORD_MATCH_COMPARE_FIRST",
            contract["operations"]["compare_and_swap"],
        )

    def test_record_rejects_invalid_contract_values(self) -> None:
        with self.assertRaises(DirectoryContractError):
            record(epoch=0)
        with self.assertRaises(DirectoryContractError):
            record(lease_state="MYSTERY")


if __name__ == "__main__":
    unittest.main()
