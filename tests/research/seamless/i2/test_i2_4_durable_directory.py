from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

from tools.research.seamless.i2.directory import (
    CasStatus,
    MutationAuthorizationStatus,
    MutationAuthorityClaim,
    OwnershipRecord,
)
from tools.research.seamless.i2.durable_directory import (
    DurableCommitFaultPoint,
    DurableDirectoryCorruption,
    DurableDirectoryUnavailable,
    DurableOwnershipDirectory,
)
from tools.research.seamless.i2.incarnation_replacement import (
    IncarnationReplacementCoordinator,
    IncarnationReplacementRequest,
    IncarnationReplacementStatus,
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


class InjectedCrash(RuntimeError):
    pass


class I24DurableDirectoryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "ownership-directory.json"

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_i2_4_dur_01_create_survives_reopen(self) -> None:
        initial = record()
        first = DurableOwnershipDirectory(self.path)
        self.assertTrue(first.create(initial).created)
        self.assertEqual(1, first.storage_revision)

        reopened = DurableOwnershipDirectory(self.path)
        self.assertEqual(initial, reopened.lookup(initial.subject_or_domain_id))
        self.assertEqual(1, reopened.storage_revision)

    def test_i2_4_dur_02_owner_transfer_survives_reopen_and_fences_old_owner(self) -> None:
        initial = record()
        to_b = record(owner="authority-b", epoch=11, fence=51, generation=2, incarnation=7)
        directory = DurableOwnershipDirectory(self.path)
        directory.create(initial)
        self.assertEqual(CasStatus.CAS_OK, directory.compare_and_swap(initial, to_b).status)

        reopened = DurableOwnershipDirectory(self.path)
        self.assertEqual(to_b, reopened.lookup(initial.subject_or_domain_id))
        self.assertEqual(
            MutationAuthorizationStatus.FENCED,
            reopened.authorize_ownership_tuple(MutationAuthorityClaim.from_record(initial)).status,
        )
        self.assertEqual(
            MutationAuthorizationStatus.AUTHORIZED,
            reopened.authorize_ownership_tuple(MutationAuthorityClaim.from_record(to_b)).status,
        )

    def test_i2_4_dur_03_same_authority_replacement_survives_reopen(self) -> None:
        i1 = record()
        i2 = record(fence=51, generation=2, incarnation=2)
        directory = DurableOwnershipDirectory(self.path)
        directory.create(i1)
        result = IncarnationReplacementCoordinator(directory).replace(
            IncarnationReplacementRequest(i1, i2)
        )
        self.assertEqual(IncarnationReplacementStatus.REPLACED, result.status)

        reopened = DurableOwnershipDirectory(self.path)
        self.assertEqual(i2, reopened.lookup(i1.subject_or_domain_id))
        self.assertEqual(
            MutationAuthorizationStatus.FENCED,
            reopened.authorize_ownership_tuple(MutationAuthorityClaim.from_record(i1)).status,
        )
        self.assertEqual(
            MutationAuthorizationStatus.AUTHORIZED,
            reopened.authorize_ownership_tuple(MutationAuthorityClaim.from_record(i2)).status,
        )

    def test_i2_4_dur_04_precommit_failure_reopens_old_state_and_retry_commits(self) -> None:
        initial = record()
        desired = record(fence=51, generation=2, incarnation=2)
        DurableOwnershipDirectory(self.path).create(initial)

        def crash(point: DurableCommitFaultPoint) -> None:
            if point is DurableCommitFaultPoint.AFTER_TEMP_FSYNC_BEFORE_REPLACE:
                raise InjectedCrash("before canonical replace")

        doomed = DurableOwnershipDirectory(self.path, fault_hook=crash)
        with self.assertRaises(InjectedCrash):
            doomed.compare_and_swap(initial, desired)
        with self.assertRaises(DurableDirectoryUnavailable):
            doomed.authorize_ownership_tuple(MutationAuthorityClaim.from_record(initial))

        reopened = DurableOwnershipDirectory(self.path)
        self.assertEqual(initial, reopened.lookup(initial.subject_or_domain_id))
        self.assertEqual(CasStatus.CAS_OK, reopened.compare_and_swap(initial, desired).status)

    def test_i2_4_dur_05_postcommit_lost_response_reopens_new_state_and_retry_converges(self) -> None:
        initial = record()
        desired = record(fence=51, generation=2, incarnation=2)
        DurableOwnershipDirectory(self.path).create(initial)

        def crash(point: DurableCommitFaultPoint) -> None:
            if point is DurableCommitFaultPoint.AFTER_DURABLE_COMMIT_BEFORE_RETURN:
                raise InjectedCrash("after durable commit before response")

        doomed = DurableOwnershipDirectory(self.path, fault_hook=crash)
        with self.assertRaises(InjectedCrash):
            IncarnationReplacementCoordinator(doomed).replace(
                IncarnationReplacementRequest(initial, desired)
            )
        with self.assertRaises(DurableDirectoryUnavailable):
            doomed.lookup(initial.subject_or_domain_id)

        reopened = DurableOwnershipDirectory(self.path)
        self.assertEqual(desired, reopened.lookup(initial.subject_or_domain_id))
        retry = IncarnationReplacementCoordinator(reopened).replace(
            IncarnationReplacementRequest(initial, desired)
        )
        self.assertEqual(IncarnationReplacementStatus.ALREADY_COMMITTED, retry.status)
        self.assertEqual(2, reopened.storage_revision)

    def test_i2_4_dur_06_failed_cas_is_storage_mutation_free(self) -> None:
        initial = record()
        directory = DurableOwnershipDirectory(self.path)
        directory.create(initial)
        before_bytes = self.path.read_bytes()
        before_revision = directory.storage_revision

        stale = record(generation=99)
        desired = record(owner="authority-b", epoch=11, fence=51, generation=2, incarnation=3)
        result = directory.compare_and_swap(stale, desired)

        self.assertEqual(CasStatus.CAS_MISMATCH, result.status)
        self.assertEqual(before_revision, directory.storage_revision)
        self.assertEqual(before_bytes, self.path.read_bytes())

    def test_i2_4_dur_07_invalid_transition_is_storage_mutation_free(self) -> None:
        initial = record()
        directory = DurableOwnershipDirectory(self.path)
        directory.create(initial)
        before_bytes = self.path.read_bytes()
        invalid = record(epoch=9, generation=2)

        result = directory.compare_and_swap(initial, invalid)

        self.assertEqual(CasStatus.INVALID_TRANSITION, result.status)
        self.assertEqual(1, directory.storage_revision)
        self.assertEqual(before_bytes, self.path.read_bytes())

    def test_i2_4_dur_08_multiple_subjects_survive_single_subject_cas(self) -> None:
        a = record(subject="domain/a")
        b = record(subject="domain/b", fence=70, generation=4, incarnation=9)
        directory = DurableOwnershipDirectory(self.path)
        directory.create(a)
        directory.create(b)
        a2 = record(subject="domain/a", fence=51, generation=2, incarnation=2)
        self.assertEqual(CasStatus.CAS_OK, directory.compare_and_swap(a, a2).status)

        reopened = DurableOwnershipDirectory(self.path)
        self.assertEqual(a2, reopened.lookup("domain/a"))
        self.assertEqual(b, reopened.lookup("domain/b"))
        self.assertEqual(3, reopened.storage_revision)

    def test_i2_4_dur_09_checksum_corruption_fails_closed(self) -> None:
        initial = record()
        DurableOwnershipDirectory(self.path).create(initial)
        envelope = json.loads(self.path.read_text(encoding="utf-8"))
        envelope["records"][0]["fencing_token"] = 999
        self.path.write_text(json.dumps(envelope), encoding="utf-8")

        with self.assertRaises(DurableDirectoryCorruption):
            DurableOwnershipDirectory(self.path)

    def test_i2_4_dur_10_malformed_snapshot_fails_closed_not_empty(self) -> None:
        self.path.write_bytes(b'{"schema":')
        with self.assertRaises(DurableDirectoryCorruption):
            DurableOwnershipDirectory(self.path)

    def test_i2_4_dur_11_stale_temp_file_is_not_canonical_truth(self) -> None:
        initial = record()
        DurableOwnershipDirectory(self.path).create(initial)
        stale_temp = self.path.with_name(f".{self.path.name}.tmp-stale")
        stale_temp.write_text('{"forged":"newer"}', encoding="utf-8")

        reopened = DurableOwnershipDirectory(self.path)
        self.assertEqual(initial, reopened.lookup(initial.subject_or_domain_id))

    def test_i2_4_dur_12_storage_revision_is_durable_and_monotonic_across_reopen(self) -> None:
        initial = record()
        d1 = DurableOwnershipDirectory(self.path)
        d1.create(initial)
        self.assertEqual(1, d1.storage_revision)
        d2 = DurableOwnershipDirectory(self.path)
        desired = record(fence=51, generation=2, incarnation=2)
        self.assertEqual(CasStatus.CAS_OK, d2.compare_and_swap(initial, desired).status)
        self.assertEqual(2, d2.storage_revision)
        self.assertEqual(2, DurableOwnershipDirectory(self.path).storage_revision)

    @unittest.skipUnless(os.name == "posix", "I2.4 backend is a POSIX durability prototype")
    def test_i2_4_dur_13_real_process_exit_before_replace_recovers_old_state(self) -> None:
        initial = record()
        desired = record(fence=51, generation=2, incarnation=2)
        DurableOwnershipDirectory(self.path).create(initial)
        proc = self._run_crash_child(
            point="AFTER_TEMP_FSYNC_BEFORE_REPLACE",
            exit_code=71,
        )
        self.assertEqual(71, proc.returncode)
        reopened = DurableOwnershipDirectory(self.path)
        self.assertEqual(initial, reopened.lookup(initial.subject_or_domain_id))
        self.assertEqual(1, reopened.storage_revision)
        self.assertEqual(CasStatus.CAS_OK, reopened.compare_and_swap(initial, desired).status)

    @unittest.skipUnless(os.name == "posix", "I2.4 backend is a POSIX durability prototype")
    def test_i2_4_dur_14_real_process_exit_after_durable_commit_recovers_new_state(self) -> None:
        initial = record()
        desired = record(fence=51, generation=2, incarnation=2)
        DurableOwnershipDirectory(self.path).create(initial)
        proc = self._run_crash_child(
            point="AFTER_DURABLE_COMMIT_BEFORE_RETURN",
            exit_code=72,
        )
        self.assertEqual(72, proc.returncode)
        reopened = DurableOwnershipDirectory(self.path)
        self.assertEqual(desired, reopened.lookup(initial.subject_or_domain_id))
        self.assertEqual(2, reopened.storage_revision)
        retry = IncarnationReplacementCoordinator(reopened).replace(
            IncarnationReplacementRequest(initial, desired)
        )
        self.assertEqual(IncarnationReplacementStatus.ALREADY_COMMITTED, retry.status)

    def test_i2_4_dur_15_durability_evidence_distinguishes_open_and_commits(self) -> None:
        initial = record()
        desired = record(fence=51, generation=2, incarnation=2)
        directory = DurableOwnershipDirectory(self.path)
        directory.create(initial)
        directory.compare_and_swap(initial, desired)
        events = directory.evidence()
        kinds = [event["kind"] for event in events]
        self.assertIn("DURABLE_DIRECTORY_OPENED", kinds)
        self.assertIn("DURABLE_CREATE_COMMITTED", kinds)
        self.assertIn("DURABLE_CAS_COMMITTED", kinds)
        durable_cas = next(event for event in events if event["kind"] == "DURABLE_CAS_COMMITTED")
        self.assertEqual(2, durable_cas["storage_revision"])
        self.assertEqual(
            DurableOwnershipDirectory.DURABILITY_EVIDENCE_SCHEMA,
            durable_cas["schema"],
        )

    def _run_crash_child(self, *, point: str, exit_code: int) -> subprocess.CompletedProcess[str]:
        repo_root = Path(__file__).resolve().parents[4]
        script = textwrap.dedent(
            f"""
            import os
            from tools.research.seamless.i2.directory import OwnershipRecord
            from tools.research.seamless.i2.durable_directory import DurableOwnershipDirectory, DurableCommitFaultPoint

            path = {str(self.path)!r}
            initial = OwnershipRecord('domain/player-42','authority-a',10,50,1,1,200,'ACTIVE',30)
            desired = OwnershipRecord('domain/player-42','authority-a',10,51,2,2,200,'ACTIVE',30)
            target = DurableCommitFaultPoint.{point}
            def hook(actual):
                if actual is target:
                    os._exit({exit_code})
            directory = DurableOwnershipDirectory(path, fault_hook=hook)
            directory.compare_and_swap(initial, desired)
            os._exit(99)
            """
        )
        env = dict(os.environ)
        env["PYTHONPATH"] = str(repo_root)
        return subprocess.run(
            [sys.executable, "-c", script],
            cwd=repo_root,
            env=env,
            text=True,
            capture_output=True,
            check=False,
        )


if __name__ == "__main__":
    unittest.main()
