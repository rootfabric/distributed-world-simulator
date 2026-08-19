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
    CasStatus,
    DurableOwnershipDirectory,
    IncarnationReplacementCoordinator,
    IncarnationReplacementRequest,
    IncarnationReplacementStatus,
    IntegratedOneWriterProbe,
    MutationAuthorityClaim,
    MutationGateStatus,
    OneWriterProbeAttempt,
    OneWriterRoundStatus,
    OwnershipRecord,
    PartitionFencingGate,
)


def rec(subject="domain/i2-6", owner="authority-a", epoch=10, fence=50, generation=1, incarnation=1):
    return OwnershipRecord(subject, owner, epoch, fence, generation, incarnation, 100, "ACTIVE", 10)


def runtime(value, pid, restart=0):
    return AuthorityRuntimeClaim(pid, restart, MutationAuthorityClaim.from_record(value))


class I26IntegratedOneWriterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "ownership-directory.json"

    def tearDown(self):
        self.temp.cleanup()

    def directory(self, initial=None):
        d = DurableOwnershipDirectory(self.path)
        if initial is not None and d.lookup(initial.subject_or_domain_id) is None:
            d.create(initial)
        return d

    @staticmethod
    def attempt(d, value, participant, *, partitioned=False, restart=0):
        gate = PartitionFencingGate(d)
        if partitioned:
            gate.partition()
        return OneWriterProbeAttempt(participant, gate, runtime(value, participant, restart))

    def probe(self, d, subject, attempts, suffix, concurrent=True):
        return IntegratedOneWriterProbe(d).probe_round(
            round_id=f"ow-{suffix}",
            operation_id=f"op-{suffix}",
            subject_or_domain_id=subject,
            attempts=attempts,
            concurrent=concurrent,
        )

    def test_i2_6_ow_01_stable_current_is_only_writer(self):
        a, stale = rec(), rec(fence=49)
        d = self.directory(a)
        r = self.probe(d, a.subject_or_domain_id, [
            self.attempt(d, a, "current"),
            self.attempt(d, stale, "stale"),
        ], "01")
        self.assertEqual(("current",), r.authorized_participants)
        self.assertTrue(r.one_writer_safe)

    def test_i2_6_ow_02_partition_is_zero_writer_fail_closed(self):
        a = rec()
        d = self.directory(a)
        r = self.probe(d, a.subject_or_domain_id, [self.attempt(d, a, "a", partitioned=True)], "02")
        self.assertEqual(OneWriterRoundStatus.ZERO_AUTHORIZED, r.status)
        self.assertEqual(MutationGateStatus.DIRECTORY_UNREACHABLE, r.results[0][1].status)
        self.assertTrue(r.one_writer_safe)

    def test_i2_6_ow_03_transfer_leaves_only_new_owner(self):
        a, b = rec(), rec(owner="authority-b", epoch=11, fence=51, generation=2, incarnation=7)
        d = self.directory(a)
        self.assertEqual(CasStatus.CAS_OK, d.compare_and_swap(a, b).status)
        r = self.probe(d, a.subject_or_domain_id, [
            self.attempt(d, a, "old-a"),
            self.attempt(d, b, "current-b"),
        ], "03")
        self.assertEqual(("current-b",), r.authorized_participants)

    def test_i2_6_ow_04_stale_process_restart_cannot_resurrect(self):
        a, b = rec(), rec(owner="authority-b", epoch=11, fence=51, generation=2, incarnation=7)
        d = self.directory(a); d.compare_and_swap(a, b)
        stale = OneWriterProbeAttempt("stale-restart", PartitionFencingGate(d), runtime(a, "a-r9", 9))
        r = self.probe(d, a.subject_or_domain_id, [stale, self.attempt(d, b, "current-b")], "04")
        self.assertEqual(("current-b",), r.authorized_participants)

    def test_i2_6_ow_05_directory_restart_preserves_one_writer(self):
        a, b = rec(), rec(owner="authority-b", epoch=11, fence=51, generation=2, incarnation=7)
        d = self.directory(a); d.compare_and_swap(a, b)
        d = DurableOwnershipDirectory(self.path)
        r = self.probe(d, a.subject_or_domain_id, [
            self.attempt(d, a, "old-a"),
            self.attempt(d, b, "current-b"),
        ], "05")
        self.assertEqual(("current-b",), r.authorized_participants)

    def test_i2_6_ow_06_same_authority_restart_rotates_incarnation(self):
        i1, i2 = rec(), rec(fence=51, generation=2, incarnation=2)
        d = self.directory(i1)
        result = IncarnationReplacementCoordinator(d).replace(IncarnationReplacementRequest(i1, i2))
        self.assertEqual(IncarnationReplacementStatus.REPLACED, result.status)
        r = self.probe(d, i1.subject_or_domain_id, [
            self.attempt(d, i1, "old-i1"),
            self.attempt(d, i2, "current-i2"),
        ], "06")
        self.assertEqual(("current-i2",), r.authorized_participants)

    def test_i2_6_ow_07_competing_restart_replacements_leave_one_winner(self):
        i1 = rec()
        i2 = rec(fence=51, generation=2, incarnation=2)
        i3 = rec(fence=52, generation=2, incarnation=3)
        d = self.directory(i1)
        c = IncarnationReplacementCoordinator(d)
        self.assertEqual(IncarnationReplacementStatus.REPLACED, c.replace(IncarnationReplacementRequest(i1, i2)).status)
        self.assertEqual(IncarnationReplacementStatus.STALE_REPLACEMENT, c.replace(IncarnationReplacementRequest(i1, i3)).status)
        r = self.probe(d, i1.subject_or_domain_id, [
            self.attempt(d, i1, "old"),
            self.attempt(d, i2, "winner"),
            self.attempt(d, i3, "loser"),
        ], "07")
        self.assertEqual(("winner",), r.authorized_participants)

    def test_i2_6_ow_08_many_stale_processes_plus_current(self):
        a, b = rec(), rec(owner="authority-b", epoch=11, fence=51, generation=2, incarnation=7)
        d = self.directory(a); d.compare_and_swap(a, b)
        attempts = [
            OneWriterProbeAttempt(f"stale-{i}", PartitionFencingGate(d), runtime(a, f"a-{i}", i))
            for i in range(64)
        ] + [self.attempt(d, b, "current")]
        r = self.probe(d, a.subject_or_domain_id, attempts, "08")
        self.assertEqual(("current",), r.authorized_participants)
        self.assertTrue(r.one_writer_safe)

    def test_i2_6_ow_09_repartition_does_not_reuse_prior_authorization(self):
        a = rec()
        d = self.directory(a)
        gate = PartitionFencingGate(d)
        p = IntegratedOneWriterProbe(d)
        first = p.probe_round(round_id="ow-09a", operation_id="op-09a", subject_or_domain_id=a.subject_or_domain_id,
                              attempts=[OneWriterProbeAttempt("a", gate, runtime(a, "a"))])
        self.assertEqual(("a",), first.authorized_participants)
        gate.partition()
        second = p.probe_round(round_id="ow-09b", operation_id="op-09b", subject_or_domain_id=a.subject_or_domain_id,
                               attempts=[OneWriterProbeAttempt("a", gate, runtime(a, "a"))])
        self.assertEqual((), second.authorized_participants)
        self.assertTrue(second.one_writer_safe)

    def test_i2_6_ow_10_missing_subject_zero_writer(self):
        d = self.directory()
        a = rec(subject="domain/missing")
        r = self.probe(d, a.subject_or_domain_id, [self.attempt(d, a, "missing")], "10")
        self.assertEqual(OneWriterRoundStatus.ZERO_AUTHORIZED, r.status)

    def test_i2_6_ow_11_future_tuple_cannot_create_writer(self):
        a, future = rec(), rec(epoch=99, fence=999, generation=99, incarnation=99)
        d = self.directory(a)
        r = self.probe(d, a.subject_or_domain_id, [
            self.attempt(d, a, "current"),
            self.attempt(d, future, "future"),
        ], "11")
        self.assertEqual(("current",), r.authorized_participants)

    def test_i2_6_ow_12_multiple_subjects_are_independent(self):
        a = rec(subject="domain/a")
        b = rec(subject="domain/b", owner="authority-b", fence=70, generation=4, incarnation=9)
        d = self.directory(a); d.create(b)
        self.assertEqual(("writer-a",), self.probe(d, "domain/a", [self.attempt(d, a, "writer-a")], "12a").authorized_participants)
        self.assertEqual(("writer-b",), self.probe(d, "domain/b", [self.attempt(d, b, "writer-b")], "12b").authorized_participants)

    def test_i2_6_ow_13_duplicate_exact_tuple_is_detected(self):
        a = rec()
        d = self.directory(a)
        r = self.probe(d, a.subject_or_domain_id, [
            self.attempt(d, a, "clone-1"),
            self.attempt(d, a, "clone-2"),
        ], "13")
        self.assertEqual(OneWriterRoundStatus.MULTIPLE_AUTHORIZED_VIOLATION, r.status)
        self.assertFalse(r.one_writer_safe)

    def test_i2_6_ow_14_canonical_move_during_round_is_indeterminate(self):
        a, b = rec(), rec(owner="authority-b", epoch=11, fence=51, generation=2, incarnation=7)
        d = self.directory(a)

        class MoveGate(PartitionFencingGate):
            def attempt(self, *, operation_id, runtime_claim):
                result = super().attempt(operation_id=operation_id, runtime_claim=runtime_claim)
                d.compare_and_swap(a, b)
                return result

        r = IntegratedOneWriterProbe(d).probe_round(
            round_id="ow-14", operation_id="op-14", subject_or_domain_id=a.subject_or_domain_id,
            attempts=[OneWriterProbeAttempt("a", MoveGate(d), runtime(a, "a"))], concurrent=False,
        )
        self.assertEqual(OneWriterRoundStatus.CANONICAL_MOVED_INDETERMINATE, r.status)
        self.assertFalse(r.one_writer_safe)

    def test_i2_6_ow_15_evidence_round_sequence_is_local(self):
        a = rec()
        d = self.directory(a)
        p = IntegratedOneWriterProbe(d)
        for i in range(3):
            p.probe_round(round_id=f"ow-15-{i}", operation_id=f"op-15-{i}", subject_or_domain_id=a.subject_or_domain_id,
                          attempts=[self.attempt(d, a, f"a-{i}")])
        self.assertEqual([1, 2, 3], [e["round_sequence"] for e in p.evidence()])

    def test_i2_6_ow_16_fault_schedule_stress_zero_violations(self):
        current = rec()
        d = self.directory(current)
        stale = []
        p = IntegratedOneWriterProbe(d)
        for i in range(200):
            if i and i % 25 == 0:
                previous = current
                stale.append(previous)
                current = rec(owner=f"authority-{i}", epoch=previous.authority_epoch + 1,
                              fence=previous.fencing_token + 1, generation=previous.directory_generation + 1,
                              incarnation=previous.authority_incarnation + 1)
                self.assertEqual(CasStatus.CAS_OK, d.compare_and_swap(previous, current).status)
            attempts = [self.attempt(d, s, f"stale-{j}", restart=i) for j, s in enumerate(stale[-8:])]
            attempts.append(self.attempt(d, current, "current", partitioned=(i % 10 == 5)))
            r = p.probe_round(round_id=f"ow-16-{i}", operation_id=f"op-16-{i}",
                              subject_or_domain_id=current.subject_or_domain_id, attempts=attempts)
            self.assertLessEqual(len(r.authorized_participants), 1)
            self.assertTrue(r.one_writer_safe)

    @unittest.skipUnless(os.name == "posix", "I2.6 subprocess proof targets POSIX")
    def test_i2_6_ow_17_two_process_old_and_current_only_current_authorizes(self):
        a, b = rec(), rec(owner="authority-b", epoch=11, fence=51, generation=2, incarnation=7)
        d = self.directory(a); d.compare_and_swap(a, b)
        root = Path(__file__).resolve().parents[4]
        child = textwrap.dedent("""
            import json, sys
            from tools.research.seamless.i2 import AuthorityRuntimeClaim, DurableOwnershipDirectory, MutationAuthorityClaim, OwnershipRecord, PartitionFencingGate
            path, which = sys.argv[1], sys.argv[2]
            a = OwnershipRecord('domain/i2-6','authority-a',10,50,1,1,100,'ACTIVE',10)
            b = OwnershipRecord('domain/i2-6','authority-b',11,51,2,7,100,'ACTIVE',10)
            value = a if which == 'old' else b
            d = DurableOwnershipDirectory(path)
            runtime = AuthorityRuntimeClaim(which, 0, MutationAuthorityClaim.from_record(value))
            result = PartitionFencingGate(d).attempt(operation_id='subprocess-op', runtime_claim=runtime)
            print(json.dumps({'which': which, 'status': result.status.value}))
        """)
        env = dict(os.environ); env["PYTHONPATH"] = str(root)
        procs = [subprocess.Popen([sys.executable, "-c", child, str(self.path), which], cwd=root, env=env,
                                  text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                 for which in ("old", "current")]
        outputs = []
        for proc in procs:
            out, err = proc.communicate()
            self.assertEqual(0, proc.returncode, err)
            outputs.append(out)
        self.assertTrue(any('"status": "FENCED"' in out for out in outputs))
        self.assertTrue(any('"status": "AUTHORIZED"' in out for out in outputs))


if __name__ == "__main__":
    unittest.main()
