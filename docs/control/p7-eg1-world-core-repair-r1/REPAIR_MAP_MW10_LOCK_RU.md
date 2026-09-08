# Repair Map — MW10 cross-region repository lock lifecycle R1

Work Order: `V0-P7-MW10-CROSS-REGION-LOCK-R1`.
Status: **IMPLEMENTED CANDIDATE; NOT ACCEPTED**.

## Affected module / canonical owner

`scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_repository.gd`
— MW10 cross-region transaction checkpoint repository. The coordinator
(`matter_cross_region_transaction_coordinator.gd`) is NOT modified: it already
delegates all checkpoint mutation to `_repository.save_atomic()`.

## Entry points / callers / callees

- Entry: `Coordinator.begin_transaction()` / all phase transitions →
  `_commit_state()` → `Repository.save_atomic()` → `prepare()` +
  `commit_prepared()` → `_acquire_lock()` / `_commit_prepared_locked()` /
  `_release_lock()`.
- Concurrent callers: `tools/matter/mw10_cross_region_transaction_worker.gd`
  begin-race contenders (real separate OS processes).
- Callees: POSIX directory rename for mutual exclusion, owner.json metadata,
  `/proc/<pid>` liveness on Linux.
- Sibling surface: `scripts/simulation/matter/handoff/durable/matter_durable_handoff_repository.gd`
  uses the same lock design and already received the hardened pattern
  (commit `d1b4993812fde8e8aeef86c508530df92ea41648`, 2026-08-04). The
  cross-region repository was added 2026-08-03 (`c8358d33`) with the older
  lifecycle and never received that propagation.

## Root cause (proven)

Two holes in the pre-repair lifecycle:

1. **Fail-open staleness.** `_remove_stale_lock()` reads the owner; when
   `owner.json` is missing or unreadable the parsed owner is `{}`, so
   `pid <= 0` skips the liveness guard and `created_unix_ms <= 0` skips the
   age guard, and the code deletes a **live** lock. A contender's acquire
   retry loop calls this on every failed rename, so any transient read of an
   ownerless/partially-visible owner deletes the holder's lock.
2. **Non-atomic release.** `_release_lock()` deletes `owner.json` in place
   and only then removes the lock directory. In the ownerless window a
   contender's `rename(candidate, lock)` legitimately succeeds (POSIX rename
   onto an empty directory), installing a foreign owner. The releasing
   winner's final directory removal can delete the contender's freshly
   installed lock, or its own ownership check observes the foreign owner and
   returns `MATTER_CROSS_REGION_TRANSACTION_LOCK_OWNERSHIP_MISMATCH` after
   its checkpoint commit already became durable.

Combined observable signature (matches the preserved local suite failure
exactly): `successes == 0` — durable generation-2 checkpoint holds exactly
one begin record (the true winner's), while the true winner reports failure
(via release mismatch after commit) and the contender reports a
progression/chain failure.

Deterministic proof: focused probe
`probes/test_mw10_lock_lifecycle.gd` case `ownerless-grace-fence` performs
the exact ownerless-window artifact (live acquired lock, `owner.json`
removed) and calls `_remove_stale_lock()` on a second instance:
on the unchanged baseline it returns `true` and the live lock is gone;
the ported fail-closed implementation must return `false` and keep the lock.

## Canonical fix location and why this is not symptom patching

The defect is in the lock lifecycle itself, not in the test, workers,
barriers, timeouts or the coordinator. The fix ports the in-repo proven
pattern (MW9 `d1b49938`):

- `_release_lock()`: rename the lock directory to a token-bound
  `.matter-cross-region-transactions.lock.<token>.released` path (bounded
  retries, Windows-transient tolerant), never removing `owner.json` in
  place; accept only the token-bound released path if the platform reports
  an error after moving; cleanup afterwards.
- `_remove_stale_lock()`: `_lock_is_stale()` fail-closed decision — own live
  token never stale; ownerless directory protected by a directory-mtime
  grace fence (LOCK_STALE_AFTER_MS); well-formed owner requires age fence
  plus process liveness (STOPPED ⇒ stale; UNKNOWN ⇒ extended fence);
  reclaim by quarantine rename with token re-verification and restore when
  the lock changed between observation and quarantine.
- `_read_lock_owner_at()`, `_lock_release_rename_override` test hook:
  same contracts as the sibling.

Semantics preserved: lock acquisition order, pending-file protocol,
checkpoint progression/CAS (`validate_progression`), `commit_prepared`
release-failure propagation, all error codes already asserted by unchanged
tests. No timeout, retry-count or test change is used as the fix.

## Existing + missing tests

- Existing unchanged: `tests/matter/transactions/test_mw10_cross_region_processes.gd`
  (three crash-recovery scenarios + begin race), P7 leaf
  `mw10-process-recovery` (53 assertions),
  `tests/matter/handoff/test_mw9_lock_release_retry.gd` (sibling pattern),
  full world/core suite.
- Missing (added by this Work Order as a probe, not a suite test):
  deterministic ownerless-grace-fence and atomic-release assertions for the
  cross-region repository. The probe runs in both baseline-negative and
  candidate-positive modes inside the exact validation helper.

## History / evidence

- `c8358d33` 2026-08-03: cross-region repository introduced with the
  pre-hardened lifecycle.
- `d1b49938` 2026-08-04: MW9 sibling hardened for the identical failure
  class ("a committed winner is not reported lost").
- 2026-09-07 local Ubuntu closure run: single observed begin-race anomaly
  preserved under
  `evidence/world-83eb8e2a-mw10-race-failure.md`; 40/40 standalone campaign
  runs green (rarity proven, not absence).

## Validation

Focused probe negative/positive, unchanged MW10 process-test campaign,
unchanged EG/MW siblings, complete unchanged world/core suite, complete
29-leaf P7 train on the exact final candidate, PC0 + directional, fresh
independent Reviewer and Verifier, human merge gate. See the Work Order
validation plan.
