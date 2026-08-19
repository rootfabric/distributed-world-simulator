from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
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


def record(
    *,
    subject: str = "domain/player-42",
    owner: str = "authority-a",
    epoch: int = 10,
    fence: int = 50,
    generation: int = 1,
    incarnation: int = 1,
    state_revision: int = 200,
    route_revision: int = 30,
) -> OwnershipRecord:
    return OwnershipRecord(
        subject_or_domain_id=subject,
        owner_authority_id=owner,
        authority_epoch=epoch,
        fencing_token=fence,
        directory_generation=generation,
        authority_incarnation=incarnation,
        state_revision=state_revision,
        lease_state="ACTIVE",
        route_revision=route_revision,
    )


def runtime(record_value: OwnershipRecord, *, process: str, restart: int = 0) -> AuthorityRuntimeClaim:
    return AuthorityRuntimeClaim(
        process_instance_id=process,
        restart_generation=restart,
        claim=MutationAuthorityClaim.from_record(record_value),
    )


class I25PartitionFencingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "ownership-directory.json"

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_i2_5_pf_01_connected_current_authority_is_authorized(self) -> None:
        a = record()
        directory = DurableOwnershipDirectory(self.path)
        directory.create(a)
        result = PartitionFencingGate(directory).attempt(
            operation_id="op-current-a",
            runtime_claim=runtime(a, process="a-1"),
        )
        self.assertEqual(MutationGateStatus.AUTHORIZED, result.status)
        self.assertTrue(result.admitted)

    def test_i2_5_pf_02_partition_fails_closed_without_directory_authorization(self) -> None:
        a = record()
        directory = DurableOwnershipDirectory(self.path)
        directory.create(a)
        before = len([e for e in directory.evidence() if e["kind"] == "OWNERSHIP_AUTHORIZATION"])
        gate = PartitionFencingGate(directory)
        gate.partition()
        result = gate.attempt(operation_id="op-partitioned-a", runtime_claim=runtime(a, process="a-1"))
        after = len([e for e in directory.evidence() if e["kind"] == "OWNERSHIP_AUTHORIZATION"])
        self.assertEqual(MutationGateStatus.DIRECTORY_UNREACHABLE, result.status)
        self.assertFalse(result.admitted)
        self.assertEqual(before, after)

    def test_i2_5_pf_03_transfer_while_a_partitioned_then_heal_fences_old_a(self) -> None:
        a = record()
        b = record(owner="authority-b", epoch=11, fence=51, generation=2, incarnation=7)
        directory = DurableOwnershipDirectory(self.path)
        directory.create(a)
        gate = PartitionFencingGate(directory)
        gate.partition()
        self.assertTrue(directory.compare_and_swap(a, b).succeeded)
        gate.heal()
        result = gate.attempt(operation_id="op-stale-a", runtime_claim=runtime(a, process="a-1"))
        self.assertEqual(MutationGateStatus.FENCED, result.status)
        self.assertFalse(result.admitted)
        self.assertEqual(b, result.observed)

    def test_i2_5_pf_04_stale_a_process_restart_does_not_resurrect_writer(self) -> None:
        a = record()
        b = record(owner="authority-b", epoch=11, fence=51, generation=2, incarnation=7)
        directory = DurableOwnershipDirectory(self.path)
        directory.create(a)
        stale = runtime(a, process="a-before-crash")
        gate = PartitionFencingGate(directory, reachability=DirectoryReachability.PARTITIONED)
        directory.compare_and_swap(a, b)
        restarted = stale.restarted(process_instance_id="a-after-restart")
        gate.heal()
        result = gate.attempt(operation_id="op-after-a-restart", runtime_claim=restarted)
        self.assertEqual(1, restarted.restart_generation)
        self.assertEqual(stale.claim, restarted.claim)
        self.assertEqual(MutationGateStatus.FENCED, result.status)

    def test_i2_5_pf_05_new_owner_b_is_authorized_after_transfer(self) -> None:
        a = record()
        b = record(owner="authority-b", epoch=11, fence=51, generation=2, incarnation=7)
        directory = DurableOwnershipDirectory(self.path)
        directory.create(a)
        directory.compare_and_swap(a, b)
        result = PartitionFencingGate(directory).attempt(
            operation_id="op-current-b",
            runtime_claim=runtime(b, process="b-1"),
        )
        self.assertEqual(MutationGateStatus.AUTHORIZED, result.status)

    def test_i2_5_pf_06_directory_restart_preserves_old_a_fencing(self) -> None:
        a = record()
        b = record(owner="authority-b", epoch=11, fence=51, generation=2, incarnation=7)
        first = DurableOwnershipDirectory(self.path)
        first.create(a)
        first.compare_and_swap(a, b)
        reopened = DurableOwnershipDirectory(self.path)
        stale = PartitionFencingGate(reopened).attempt(
            operation_id="op-stale-after-directory-restart",
            runtime_claim=runtime(a, process="a-restart", restart=1),
        )
        current = PartitionFencingGate(reopened).attempt(
            operation_id="op-b-after-directory-restart",
            runtime_claim=runtime(b, process="b-1"),
        )
        self.assertEqual(MutationGateStatus.FENCED, stale.status)
        self.assertEqual(MutationGateStatus.AUTHORIZED, current.status)

    def test_i2_5_pf_07_same_authority_old_incarnation_stays_fenced_after_heal(self) -> None:
        i1 = record()
        i2 = record(fence=51, generation=2, incarnation=2)
        directory = DurableOwnershipDirectory(self.path)
        directory.create(i1)
        gate = PartitionFencingGate(directory, reachability=DirectoryReachability.PARTITIONED)
        directory.compare_and_swap(i1, i2)
        gate.heal()
        old_result = gate.attempt(operation_id="op-old-i1", runtime_claim=runtime(i1, process="a-i1"))
        new_result = gate.attempt(operation_id="op-new-i2", runtime_claim=runtime(i2, process="a-i2"))
        self.assertEqual(MutationGateStatus.FENCED, old_result.status)
        self.assertEqual(MutationGateStatus.AUTHORIZED, new_result.status)

    def test_i2_5_pf_08_future_looking_claim_does_not_gain_authority(self) -> None:
        a = record()
        directory = DurableOwnershipDirectory(self.path)
        directory.create(a)
        future_claim = MutationAuthorityClaim(
            subject_or_domain_id=a.subject_or_domain_id,
            owner_authority_id=a.owner_authority_id,
            authority_epoch=999,
            fencing_token=999,
            authority_incarnation=999,
        )
        result = PartitionFencingGate(directory).attempt(
            operation_id="op-future-looking",
            runtime_claim=AuthorityRuntimeClaim("future-process", 0, future_claim),
        )
        self.assertEqual(MutationGateStatus.FENCED, result.status)

    def test_i2_5_pf_09_missing_subject_is_not_found(self) -> None:
        missing = record(subject="domain/missing")
        result = PartitionFencingGate(DurableOwnershipDirectory(self.path)).attempt(
            operation_id="op-missing",
            runtime_claim=runtime(missing, process="missing-process"),
        )
        self.assertEqual(MutationGateStatus.NOT_FOUND, result.status)
        self.assertFalse(result.admitted)

    def test_i2_5_pf_10_gate_attempts_do_not_mutate_directory_or_storage_revision(self) -> None:
        a = record()
        directory = DurableOwnershipDirectory(self.path)
        directory.create(a)
        before_snapshot = directory.snapshot()
        before_revision = directory.storage_revision
        gate = PartitionFencingGate(directory)
        gate.attempt(operation_id="op-auth", runtime_claim=runtime(a, process="a-1"))
        gate.partition()
        gate.attempt(operation_id="op-partition", runtime_claim=runtime(a, process="a-1"))
        self.assertEqual(before_snapshot, directory.snapshot())
        self.assertEqual(before_revision, directory.storage_revision)

    def test_i2_5_pf_11_restart_metadata_is_not_authority_and_cannot_self_upgrade_claim(self) -> None:
        a = record()
        b = record(owner="authority-b", epoch=11, fence=51, generation=2, incarnation=7)
        directory = DurableOwnershipDirectory(self.path)
        directory.create(a)
        directory.compare_and_swap(a, b)
        stale = runtime(a, process="a-1").restarted(process_instance_id="a-2").restarted(process_instance_id="a-3")
        result = PartitionFencingGate(directory).attempt(operation_id="op-many-restarts", runtime_claim=stale)
        self.assertEqual(2, stale.restart_generation)
        self.assertEqual(MutationAuthorityClaim.from_record(a), stale.claim)
        self.assertEqual(MutationGateStatus.FENCED, result.status)

    def test_i2_5_pf_12_multiple_stale_a_processes_are_all_fenced(self) -> None:
        a = record()
        b = record(owner="authority-b", epoch=11, fence=51, generation=2, incarnation=7)
        directory = DurableOwnershipDirectory(self.path)
        directory.create(a)
        directory.compare_and_swap(a, b)
        gate = PartitionFencingGate(directory)
        statuses = {
            gate.attempt(operation_id=f"op-stale-{index}", runtime_claim=runtime(a, process=f"a-{index}", restart=index)).status
            for index in range(1, 5)
        }
        self.assertEqual({MutationGateStatus.FENCED}, statuses)

    def test_i2_5_pf_13_repartition_after_heal_fails_closed_even_for_current_owner(self) -> None:
        a = record()
        directory = DurableOwnershipDirectory(self.path)
        directory.create(a)
        gate = PartitionFencingGate(directory)
        self.assertEqual(MutationGateStatus.AUTHORIZED, gate.attempt(operation_id="op-before", runtime_claim=runtime(a, process="a-1")).status)
        gate.partition()
        self.assertEqual(MutationGateStatus.DIRECTORY_UNREACHABLE, gate.attempt(operation_id="op-after", runtime_claim=runtime(a, process="a-1")).status)

    def test_i2_5_pf_14_evidence_distinguishes_gate_order_from_directory_linearization(self) -> None:
        a = record()
        directory = DurableOwnershipDirectory(self.path)
        directory.create(a)
        gate = PartitionFencingGate(directory)
        gate.attempt(operation_id="op-1", runtime_claim=runtime(a, process="a-1"))
        gate.partition()
        gate.attempt(operation_id="op-2", runtime_claim=runtime(a, process="a-1"))
        events = gate.evidence()
        self.assertEqual([1, 2], [event["attempt_sequence"] for event in events])
        self.assertEqual("AUTHORIZED", events[0]["status"])
        self.assertEqual("DIRECTORY_UNREACHABLE", events[1]["status"])
        self.assertNotIn("linearization_sequence", events[0])
        self.assertNotIn("authorization_sequence", events[0])

    @unittest.skipUnless(os.name == "posix", "I2.5 subprocess proof uses the POSIX I2.4 durable backend")
    def test_i2_5_pf_15_real_restarted_stale_authority_process_is_fenced(self) -> None:
        a = record()
        b = record(owner="authority-b", epoch=11, fence=51, generation=2, incarnation=7)
        directory = DurableOwnershipDirectory(self.path)
        directory.create(a)
        directory.compare_and_swap(a, b)
        repo_root = Path(__file__).resolve().parents[4]
        script = textwrap.dedent(
            f"""
            import sys
            from tools.research.seamless.i2 import (
                AuthorityRuntimeClaim,
                DurableOwnershipDirectory,
                MutationAuthorityClaim,
                MutationGateStatus,
                PartitionFencingGate,
            )
            path = {str(self.path)!r}
            stale_claim = MutationAuthorityClaim('domain/player-42','authority-a',10,50,1)
            runtime = AuthorityRuntimeClaim('authority-a-restarted-child', 1, stale_claim)
            result = PartitionFencingGate(DurableOwnershipDirectory(path)).attempt(
                operation_id='op-child-stale-a', runtime_claim=runtime
            )
            sys.exit(0 if result.status is MutationGateStatus.FENCED and not result.admitted else 91)
            """
        )
        env = dict(os.environ)
        env["PYTHONPATH"] = str(repo_root)
        proc = subprocess.run(
            [sys.executable, "-c", script],
            cwd=repo_root,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(0, proc.returncode, proc.stderr)


if __name__ == "__main__":
    unittest.main()
