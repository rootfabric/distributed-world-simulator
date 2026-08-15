# SM0 H3.3 — dual-authority outage inside one in-flight handoff

Date: 2026-08-15

Track: experimental SM0 two-authority seamless handoff lab

Risk: CRITICAL / cross-server authority transaction durability

Status: implementation work order / branch-local only. This does not declare V0 or project acceptance.

## Exact starting frontier

Branch:

`feature/sm0-two-authority-seamless-handoff-lab`

H3.2 runtime-tested implementation:

`f08b0e913514b965fa5d9f16038d51a5cf9a3728`

H3.2 evidence-only successor:

`81ac872e4979f5efeaa23aa07f5a626efd7e92ea`

## Failure boundary

H3.3 targets a materially different state from H3.2.

Required transaction state before outage:

1. A is source and starts transfer `T`.
2. B validates PREPARE for `T`.
3. B has durably recorded the exact prepared package before acknowledging PREPARED.
4. A receives PREPARED, retires canonical writer state, advances the directory to B, and durably records `SOURCE_RETIRED(T)`.
5. A has not successfully delivered COMMIT for `T` to B.
6. B has not committed/imported the player for `T`.
7. Client has not completed crossing #1.
8. Both A and B are force-killed before either is restarted.

Durable viewpoints at the outage must therefore be intentionally asymmetric but compatible:

- A: `SOURCE_RETIRED(T)`, directory owner B, writer_count 0;
- B: `TARGET_PREPARED(T)`, directory still at source-side pre-commit epoch, writer_count 0.

After restart, those two durable viewpoints must converge on the same transfer `T`:

- A resumes COMMIT/redirect as retired source;
- B restores PREPARE for `T` and can accept the repeated COMMIT;
- B persists `TARGET_COMMITTED(T)` before successful COMMITTED ACK;
- exactly one authority becomes canonical writer after client activation;
- no second player identity is created;
- the same client session continues subsequent handoffs.

## Repair Map

### Finding H3.3-R1 — PREPARED is volatile

Root cause:

`_handle_handoff_prepare()` stores the validated package only in `_prepared_transfers` and immediately sends successful `PLAYER_HANDOFF_PREPARED`. Existing recovery snapshots are written only for later phases. If both processes die after source retirement but before target COMMIT, B loses the only PREPARE record. Replayed COMMIT then fails with `SM0_COMMIT_WITHOUT_PREPARE`.

Files:

- `scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery.gd`
- focused recovery regression under `tests/runtime/seamless/sm0/`

Correction:

Introduce durable phase `TARGET_PREPARED` and enforce write-before-successful-PREPARED-ACK when recovery is enabled.

The snapshot must contain:

- exact `transfer_id`;
- exact validated handoff package in `prepared_transfers`;
- source-owned directory matching the package source epoch/revision;
- canonical durable gameplay/replay state;
- checksum.

On restore, `_prepared_transfers` must be reconstructed exactly and the target must remain non-writer. Duplicate PREPARE must replay without creating another transaction.

Regression:

Create target B, feed one valid PREPARE, prove `TARGET_PREPARED` persisted, destroy node, restore it, prove exact package is present and B remains non-writer, then feed the matching COMMIT and prove it succeeds and persists the later target decision.

### Finding H3.3-R2 — no process-level total-outage gate for the in-flight transaction

Root cause:

H2.3 proves source-only crash after `SOURCE_RETIRED`; H3.2 proves both processes can die only after a completed handoff. Neither proves recovery when both durable viewpoints belong to one unfinished transfer.

Files:

- new H3.3 Windows acceptance runner
- branch-local validation evidence after runtime execution

Correction:

Create a deterministic profile/gate that suppresses source COMMIT/redirect after `SOURCE_RETIRED`, waits until A and B durable snapshots for the same `transfer_id` are observable, then force-kills both processes before restart.

Regression / acceptance assertions:

- exact same transfer_id on A `SOURCE_RETIRED` and B `TARGET_PREPARED` snapshots;
- no `SM0_TARGET_AUTHORITY_COMMITTED` before outage;
- no `SM0_CROSSING_COMPLETED` before outage;
- both old PIDs dead before either new PID starts;
- same client PID remains alive;
- recovered A writer_count stays 0;
- recovered B restores prepared transfer before accepting repeated COMMIT;
- B later persists `TARGET_COMMITTED` and activates the same `player/a`;
- no `SM0_COMMIT_WITHOUT_PREPARE` and no invariant violation;
- final handoff count reaches requested count with `identity_changes = 0`.

## Explicit non-goals

H3.3 does not claim:

- quorum/consensus across more than these two authorities;
- network partition fencing between simultaneously live divergent servers;
- disk corruption or fsync/power-loss guarantees;
- production HA;
- V0/global server-handoff acceptance.
