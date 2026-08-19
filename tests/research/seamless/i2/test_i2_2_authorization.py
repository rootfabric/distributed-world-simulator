from __future__ import annotations

import json
import threading
import unittest
from pathlib import Path

from tools.research.seamless.i2.directory import (
    CasStatus,
    DirectoryContractError,
    MutationAuthorizationStatus,
    MutationAuthorityClaim,
    OwnershipDirectory,
    OwnershipRecord,
)


def record(
    *,
    owner: str = "authority-a",
    epoch: int = 10,
    fence: int = 50,
    generation: int = 1,
    incarnation: int = 1,
    lease_state: str = "ACTIVE",
) -> OwnershipRecord:
    return OwnershipRecord(
        subject_or_domain_id="domain/player-42",
        owner_authority_id=owner,
        authority_epoch=epoch,
        fencing_token=fence,
        directory_generation=generation,
        authority_incarnation=incarnation,
        state_revision=200,
        lease_state=lease_state,
        route_revision=30,
    )


def claim(
    *,
    owner: str = "authority-a",
    epoch: int = 10,
    fence: int = 50,
    incarnation: int = 1,
) -> MutationAuthorityClaim:
    return MutationAuthorityClaim(
        subject_or_domain_id="domain/player-42",
        owner_authority_id=owner,
        authority_epoch=epoch,
        fencing_token=fence,
        authority_incarnation=incarnation,
    )


class I22EpochFenceIncarnationAuthorizationTests(unittest.TestCase):
    def test_i22_auth_01_exact_current_tuple_is_authorized(self) -> None:
        directory = OwnershipDirectory()
        initial = record()
        directory.create(initial)

        result = directory.authorize_ownership_tuple(MutationAuthorityClaim.from_record(initial))

        self.assertEqual(MutationAuthorizationStatus.AUTHORIZED, result.status)
        self.assertTrue(result.authorized)
        self.assertEqual(initial, result.observed)
        self.assertEqual((), result.mismatched_fields)

    def test_i22_auth_02_wrong_owner_is_fenced(self) -> None:
        directory = OwnershipDirectory()
        initial = record()
        directory.create(initial)

        result = directory.authorize_ownership_tuple(claim(owner="authority-b"))

        self.assertEqual(MutationAuthorizationStatus.FENCED, result.status)
        self.assertEqual(("owner_authority_id",), result.mismatched_fields)
        self.assertEqual(initial, result.observed)

    def test_i22_auth_03_stale_epoch_is_fenced(self) -> None:
        directory = OwnershipDirectory()
        current = record(epoch=11)
        directory.create(current)

        result = directory.authorize_ownership_tuple(claim(epoch=10))

        self.assertEqual(MutationAuthorizationStatus.FENCED, result.status)
        self.assertEqual(("authority_epoch",), result.mismatched_fields)

    def test_i22_auth_04_stale_fence_is_fenced(self) -> None:
        directory = OwnershipDirectory()
        current = record(fence=51)
        directory.create(current)

        result = directory.authorize_ownership_tuple(claim(fence=50))

        self.assertEqual(MutationAuthorizationStatus.FENCED, result.status)
        self.assertEqual(("fencing_token",), result.mismatched_fields)

    def test_i22_auth_05_stale_incarnation_is_fenced(self) -> None:
        directory = OwnershipDirectory()
        current = record(incarnation=2)
        directory.create(current)

        result = directory.authorize_ownership_tuple(claim(incarnation=1))

        self.assertEqual(MutationAuthorizationStatus.FENCED, result.status)
        self.assertEqual(("authority_incarnation",), result.mismatched_fields)

    def test_i22_auth_06_future_or_forged_values_do_not_gain_authority(self) -> None:
        directory = OwnershipDirectory()
        current = record()
        directory.create(current)

        result = directory.authorize_ownership_tuple(
            claim(epoch=11, fence=51, incarnation=2)
        )

        self.assertEqual(MutationAuthorizationStatus.FENCED, result.status)
        self.assertEqual(
            ("authority_epoch", "fencing_token", "authority_incarnation"),
            result.mismatched_fields,
        )

    def test_i22_auth_07_absent_subject_is_not_found(self) -> None:
        directory = OwnershipDirectory()

        result = directory.authorize_ownership_tuple(claim())

        self.assertEqual(MutationAuthorizationStatus.NOT_FOUND, result.status)
        self.assertFalse(result.authorized)
        self.assertIsNone(result.observed)
        self.assertEqual((), result.mismatched_fields)
        self.assertEqual({}, directory.snapshot())

    def test_i22_auth_08_same_authority_id_replacement_fences_old_incarnation(self) -> None:
        directory = OwnershipDirectory()
        i1 = record(owner="authority-a", epoch=10, fence=50, generation=1, incarnation=1)
        i2 = record(owner="authority-a", epoch=10, fence=51, generation=2, incarnation=2)
        directory.create(i1)

        before = directory.authorize_ownership_tuple(MutationAuthorityClaim.from_record(i1))
        replacement = directory.compare_and_swap(i1, i2)
        old_after = directory.authorize_ownership_tuple(MutationAuthorityClaim.from_record(i1))
        new_after = directory.authorize_ownership_tuple(MutationAuthorityClaim.from_record(i2))

        self.assertEqual(MutationAuthorizationStatus.AUTHORIZED, before.status)
        self.assertEqual(CasStatus.CAS_OK, replacement.status)
        self.assertEqual(MutationAuthorizationStatus.FENCED, old_after.status)
        self.assertEqual(
            ("fencing_token", "authority_incarnation"),
            old_after.mismatched_fields,
        )
        self.assertEqual(MutationAuthorizationStatus.AUTHORIZED, new_after.status)
        self.assertEqual(i2, new_after.observed)

    def test_i22_auth_09_owner_transfer_fences_old_owner_and_authorizes_new_owner(self) -> None:
        directory = OwnershipDirectory()
        source = record(owner="authority-a", epoch=10, fence=50, generation=1, incarnation=1)
        target = record(owner="authority-b", epoch=11, fence=51, generation=2, incarnation=7)
        directory.create(source)

        self.assertEqual(CasStatus.CAS_OK, directory.compare_and_swap(source, target).status)

        old_result = directory.authorize_ownership_tuple(MutationAuthorityClaim.from_record(source))
        new_result = directory.authorize_ownership_tuple(MutationAuthorityClaim.from_record(target))

        self.assertEqual(MutationAuthorizationStatus.FENCED, old_result.status)
        self.assertEqual(
            (
                "owner_authority_id",
                "authority_epoch",
                "fencing_token",
                "authority_incarnation",
            ),
            old_result.mismatched_fields,
        )
        self.assertEqual(MutationAuthorizationStatus.AUTHORIZED, new_result.status)

    def test_i22_auth_10_authorization_is_read_only(self) -> None:
        directory = OwnershipDirectory()
        initial = record()
        directory.create(initial)
        before = directory.snapshot()

        directory.authorize_ownership_tuple(MutationAuthorityClaim.from_record(initial))
        directory.authorize_ownership_tuple(claim(fence=49))

        self.assertEqual(before, directory.snapshot())

    def test_i22_auth_11_evidence_records_fail_closed_reason_and_sequence(self) -> None:
        directory = OwnershipDirectory()
        initial = record()
        directory.create(initial)

        directory.authorize_ownership_tuple(MutationAuthorityClaim.from_record(initial))
        directory.authorize_ownership_tuple(claim(incarnation=2))

        events = [
            event for event in directory.evidence()
            if event["kind"] == "OWNERSHIP_AUTHORIZATION"
        ]
        self.assertEqual(2, len(events))
        self.assertEqual(
            ["distributed_world_simulator.sm1_i2_2_authorization_evidence.v1"] * 2,
            [event["schema"] for event in events],
        )
        self.assertEqual([1, 2], [event["authorization_sequence"] for event in events])
        self.assertEqual(["AUTHORIZED", "FENCED"], [event["status"] for event in events])
        self.assertEqual([], events[0]["mismatched_fields"])
        self.assertEqual(["authority_incarnation"], events[1]["mismatched_fields"])
        self.assertEqual(initial.to_mapping(), events[1]["observed"])

    def test_i22_auth_12_concurrent_replacement_and_authorization_are_linearizable(self) -> None:
        for _ in range(250):
            directory = OwnershipDirectory()
            i1 = record(owner="authority-a", epoch=10, fence=50, generation=1, incarnation=1)
            i2 = record(owner="authority-a", epoch=10, fence=51, generation=2, incarnation=2)
            directory.create(i1)

            barrier = threading.Barrier(3)
            result_box: dict[str, object] = {}

            def do_replace() -> None:
                barrier.wait()
                result_box["cas"] = directory.compare_and_swap(i1, i2)

            def do_authorize_old() -> None:
                barrier.wait()
                result_box["auth"] = directory.authorize_ownership_tuple(
                    MutationAuthorityClaim.from_record(i1)
                )

            threads = [
                threading.Thread(target=do_replace),
                threading.Thread(target=do_authorize_old),
            ]
            for thread in threads:
                thread.start()
            barrier.wait()
            for thread in threads:
                thread.join(timeout=2.0)
                self.assertFalse(thread.is_alive())

            cas_result = result_box["cas"]
            auth_result = result_box["auth"]
            self.assertEqual(CasStatus.CAS_OK, cas_result.status)

            decision_events = [
                event for event in directory.evidence()
                if event["kind"] in ("CAS_RESULT", "OWNERSHIP_AUTHORIZATION")
            ]
            self.assertEqual(2, len(decision_events))

            if auth_result.status is MutationAuthorizationStatus.AUTHORIZED:
                self.assertEqual(
                    ["OWNERSHIP_AUTHORIZATION", "CAS_RESULT"],
                    [event["kind"] for event in decision_events],
                )
            else:
                self.assertEqual(MutationAuthorizationStatus.FENCED, auth_result.status)
                self.assertEqual(
                    ["CAS_RESULT", "OWNERSHIP_AUTHORIZATION"],
                    [event["kind"] for event in decision_events],
                )

            # Once replacement is definitely committed, old i1 must always be fenced.
            after = directory.authorize_ownership_tuple(MutationAuthorityClaim.from_record(i1))
            self.assertEqual(MutationAuthorizationStatus.FENCED, after.status)

    def test_i22_auth_13_machine_contract_matches_implementation(self) -> None:
        contract_path = (
            Path(__file__).resolve().parents[4]
            / "config/research/seamless/i2/i2-2-authorization-contract.v1.json"
        )
        contract = json.loads(contract_path.read_text(encoding="utf-8"))

        self.assertEqual("SM1-I2.2", contract["checkpoint"])
        self.assertEqual(
            "f1fd65ad73da8c95612a641be0ad52048c90169a",
            contract["accepted_i2_1_base"],
        )
        self.assertFalse(contract["production_activation"])
        self.assertTrue(contract["donor_only"])
        self.assertEqual(
            [
                "owner_authority_id",
                "authority_epoch",
                "fencing_token",
                "authority_incarnation",
            ],
            contract["ownership_authorization_tuple"],
        )
        self.assertIn(
            "EXACT_MATCH_ONLY_NO_GREATER_THAN_SEMANTICS",
            contract["authorization_invariants"],
        )
        self.assertIn(
            "SAME_AUTHORITY_ID_OLD_INCARNATION_FENCED_AFTER_REPLACEMENT",
            contract["authorization_invariants"],
        )
        self.assertEqual(
            "OUT_OF_SCOPE_UNTIL_AUTHORITY_BINDING_CHECKPOINT",
            contract["binding_generation"],
        )

    def test_i22_auth_14_claim_rejects_invalid_values(self) -> None:
        with self.assertRaises(DirectoryContractError):
            claim(epoch=0)
        with self.assertRaises(DirectoryContractError):
            claim(fence=0)
        with self.assertRaises(DirectoryContractError):
            claim(incarnation=0)


if __name__ == "__main__":
    unittest.main()
