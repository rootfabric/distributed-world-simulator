from __future__ import annotations

import json
import threading
import unittest
from pathlib import Path

from tools.research.seamless.i2.directory import (
    MutationAuthorizationStatus,
    MutationAuthorityClaim,
    OwnershipDirectory,
    OwnershipRecord,
)
from tools.research.seamless.i2.incarnation_replacement import (
    IncarnationReplacementCoordinator,
    IncarnationReplacementRequest,
    IncarnationReplacementStatus,
)


def record(*, inc=1, fence=50, generation=1, epoch=10, owner="authority-a", subject="domain/player-42"):
    return OwnershipRecord(subject, owner, epoch, fence, generation, inc, 200, "ACTIVE", 30)


def coordinator_with_initial():
    directory=OwnershipDirectory(); initial=record(); directory.create(initial)
    return directory, IncarnationReplacementCoordinator(directory), initial


class I23IncarnationReplacementTests(unittest.TestCase):
    def test_01_valid_same_authority_replacement_commits(self):
        d,c,i1=coordinator_with_initial(); i2=record(inc=2,fence=51,generation=2)
        r=c.replace(IncarnationReplacementRequest(i1,i2))
        self.assertEqual(IncarnationReplacementStatus.REPLACED,r.status); self.assertTrue(r.converged); self.assertEqual(i2,d.lookup(i1.subject_or_domain_id))
    def test_02_ambiguous_response_retry_converges_without_second_rotation(self):
        d,c,i1=coordinator_with_initial(); i2=record(inc=2,fence=51,generation=2); req=IncarnationReplacementRequest(i1,i2)
        first=c.replace(req); second=c.replace(req)
        self.assertEqual(IncarnationReplacementStatus.REPLACED,first.status); self.assertEqual(IncarnationReplacementStatus.ALREADY_COMMITTED,second.status); self.assertEqual(i2,second.current); self.assertEqual(51,d.lookup(i1.subject_or_domain_id).fencing_token); self.assertEqual(2,d.lookup(i1.subject_or_domain_id).directory_generation)
    def test_03_concurrent_duplicate_request_one_commit_one_replay_convergence(self):
        d,c,i1=coordinator_with_initial(); i2=record(inc=2,fence=51,generation=2); req=IncarnationReplacementRequest(i1,i2); barrier=threading.Barrier(3); results=[]; lock=threading.Lock()
        def worker():
            barrier.wait(); r=c.replace(req)
            with lock: results.append(r.status)
        ts=[threading.Thread(target=worker) for _ in range(2)]
        [t.start() for t in ts]; barrier.wait(); [t.join(2) for t in ts]
        self.assertCountEqual([IncarnationReplacementStatus.REPLACED,IncarnationReplacementStatus.ALREADY_COMMITTED],results); self.assertEqual(i2,d.lookup(i1.subject_or_domain_id))
    def test_04_competing_replacements_only_one_canonical_incarnation(self):
        d,c,i1=coordinator_with_initial(); i2=record(inc=2,fence=51,generation=2); i3=record(inc=3,fence=52,generation=3); barrier=threading.Barrier(3); results=[]; lock=threading.Lock()
        def worker(desired):
            barrier.wait(); r=c.replace(IncarnationReplacementRequest(i1,desired))
            with lock: results.append((desired,r.status,r.current))
        ts=[threading.Thread(target=worker,args=(x,)) for x in (i2,i3)]
        [t.start() for t in ts]; barrier.wait(); [t.join(2) for t in ts]
        self.assertEqual(1,sum(s is IncarnationReplacementStatus.REPLACED for _,s,_ in results)); self.assertEqual(1,sum(s is IncarnationReplacementStatus.STALE_REPLACEMENT for _,s,_ in results)); winner=next(x for x,s,_ in results if s is IncarnationReplacementStatus.REPLACED); self.assertEqual(winner,d.lookup(i1.subject_or_domain_id))
    def test_05_old_incarnation_is_fenced_after_replacement(self):
        d,c,i1=coordinator_with_initial(); i2=record(inc=2,fence=51,generation=2)
        self.assertEqual(MutationAuthorizationStatus.AUTHORIZED,d.authorize_ownership_tuple(MutationAuthorityClaim.from_record(i1)).status)
        c.replace(IncarnationReplacementRequest(i1,i2))
        self.assertEqual(MutationAuthorizationStatus.FENCED,d.authorize_ownership_tuple(MutationAuthorityClaim.from_record(i1)).status); self.assertEqual(MutationAuthorizationStatus.AUTHORIZED,d.authorize_ownership_tuple(MutationAuthorityClaim.from_record(i2)).status)
    def test_06_unchanged_authority_id_and_epoch_do_not_rescue_old_incarnation(self):
        d,c,i1=coordinator_with_initial(); i2=record(inc=2,fence=51,generation=2,epoch=10); c.replace(IncarnationReplacementRequest(i1,i2)); r=d.authorize_ownership_tuple(MutationAuthorityClaim.from_record(i1)); self.assertEqual(MutationAuthorizationStatus.FENCED,r.status); self.assertEqual(("fencing_token","authority_incarnation"),r.mismatched_fields)
    def test_07_old_local_snapshot_restart_remains_fenced(self):
        d,c,i1=coordinator_with_initial(); stale_local=MutationAuthorityClaim.from_record(i1); i2=record(inc=2,fence=51,generation=2); c.replace(IncarnationReplacementRequest(i1,i2)); restarted_claim=MutationAuthorityClaim(stale_local.subject_or_domain_id,stale_local.owner_authority_id,stale_local.authority_epoch,stale_local.fencing_token,stale_local.authority_incarnation); self.assertEqual(MutationAuthorizationStatus.FENCED,d.authorize_ownership_tuple(restarted_claim).status)
    def test_08_replay_after_later_replacement_is_stale_not_already_committed(self):
        d,c,i1=coordinator_with_initial(); i2=record(inc=2,fence=51,generation=2); i3=record(inc=3,fence=52,generation=3); req12=IncarnationReplacementRequest(i1,i2); c.replace(req12); c.replace(IncarnationReplacementRequest(i2,i3)); replay=c.replace(req12); self.assertEqual(IncarnationReplacementStatus.STALE_REPLACEMENT,replay.status); self.assertEqual(i3,replay.current)
    def test_09_missing_record_returns_not_found(self):
        d=OwnershipDirectory(); c=IncarnationReplacementCoordinator(d); i1=record(); i2=record(inc=2,fence=51,generation=2); r=c.replace(IncarnationReplacementRequest(i1,i2)); self.assertEqual(IncarnationReplacementStatus.NOT_FOUND,r.status); self.assertIsNone(r.current)
    def test_10_owner_change_rejected_as_wrong_operation_kind(self):
        d,c,i1=coordinator_with_initial(); b=record(owner="authority-b",inc=2,fence=51,generation=2,epoch=11); before=d.snapshot(); r=c.replace(IncarnationReplacementRequest(i1,b)); self.assertEqual(IncarnationReplacementStatus.INVALID_REPLACEMENT,r.status); self.assertEqual(before,d.snapshot())
    def test_11_same_incarnation_rejected(self):
        d,c,i1=coordinator_with_initial(); desired=record(inc=1,fence=51,generation=2); r=c.replace(IncarnationReplacementRequest(i1,desired)); self.assertEqual(IncarnationReplacementStatus.INVALID_REPLACEMENT,r.status); self.assertEqual(i1,d.lookup(i1.subject_or_domain_id))
    def test_12_reused_fence_is_invalid_and_mutation_free(self):
        d,c,i1=coordinator_with_initial(); bad=record(inc=2,fence=50,generation=2); r=c.replace(IncarnationReplacementRequest(i1,bad)); self.assertEqual(IncarnationReplacementStatus.INVALID_REPLACEMENT,r.status); self.assertEqual(i1,d.lookup(i1.subject_or_domain_id))
    def test_13_nonincreasing_generation_is_invalid_and_mutation_free(self):
        d,c,i1=coordinator_with_initial(); bad=record(inc=2,fence=51,generation=1); r=c.replace(IncarnationReplacementRequest(i1,bad)); self.assertEqual(IncarnationReplacementStatus.INVALID_REPLACEMENT,r.status); self.assertEqual(i1,d.lookup(i1.subject_or_domain_id))
    def test_14_evidence_is_emission_order_not_claimed_directory_linearization(self):
        d,c,i1=coordinator_with_initial(); i2=record(inc=2,fence=51,generation=2); req=IncarnationReplacementRequest(i1,i2); c.replace(req); c.replace(req); ev=c.evidence(); self.assertEqual([1,2],[x['emission_sequence'] for x in ev]); self.assertEqual(['REPLACED','ALREADY_COMMITTED'],[x['status'] for x in ev]); self.assertEqual(['CAS_OK','CAS_MISMATCH'],[x['directory_cas_status'] for x in ev])
    def test_15_directory_cas_evidence_proves_single_commit_for_duplicate_retry(self):
        d,c,i1=coordinator_with_initial(); i2=record(inc=2,fence=51,generation=2); req=IncarnationReplacementRequest(i1,i2); c.replace(req); c.replace(req); cas=[x for x in d.evidence() if x['kind']=='CAS_RESULT']; self.assertEqual(['CAS_OK','CAS_MISMATCH'],[x['status'] for x in cas]); self.assertEqual([1,2],[x['linearization_sequence'] for x in cas])

if __name__=='__main__': unittest.main()
