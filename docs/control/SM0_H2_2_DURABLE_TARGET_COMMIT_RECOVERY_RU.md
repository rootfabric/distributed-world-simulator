# SM0-H2.2 — durable target-commit recovery — Design Brief

Status: `DESIGN_BRIEF / CRITICAL / BOUNDED_SM0_LAB`

Base:

`b9a4667c536287af3b182a589835eb57bd703556`

This work must not be treated as V0-S1 acceptance, main promotion, or a new global authority foundation. `SERVER_HANDOFF` remains outside V0-S1 and cross-server authority is CRITICAL-risk work.

## Problem statement

H2.1 proved a real target process crash before PREPARED. That crash point is recoverable without persistence because source authority has not retired yet: source remains the owner, stays frozen, retries PREPARE, and a fresh target can reconstruct the proposal from the repeated package.

The next unsafe boundary is later:

1. target accepted PREPARE;
2. source retired its local writer and published the new directory;
3. target imported the player and accepted COMMIT;
4. target process crashes before the successful COMMITTED acknowledgement and before client activation completes.

At this point a fresh target cannot safely start from empty memory. Source has already retired, so rolling back to source ownership would be a second authority decision. Losing `_committed_transfers`, `_directory`, and target gameplay state leaves the client retrying ACTIVATE against a target that no longer remembers the accepted commit.

## Current behavior

SM0 handoff transaction state is process memory:

- `_prepared_transfers`;
- `_committed_transfers`;
- `_directory`;
- active transport/session routing.

The underlying canonical `NetworkedGameplayService` already has durable and replay state APIs. Its durable export deliberately clears transient transport connectivity while preserving player identity, ownership epoch, position, velocity, inventory and canonical item graph. Therefore SM0 must reuse that canonical durable state rather than create another player-state truth.

## Desired behavior

For an explicitly recovery-enabled SM0 authority:

- before a successful target `PLAYER_HANDOFF_COMMITTED` ACK can leave the process, the accepted target commit decision is durably recorded;
- the durable snapshot contains canonical gameplay durable state + replay state and a small SM0 handoff journal;
- the SM0 journal contains transaction metadata only: directory, transfer/package records, target session id, phase and generation;
- no second authoritative player position/inventory truth is introduced in the SM0 journal;
- after process restart on the same recovery directory, target restores the latest valid committed decision before processing UDP packets;
- the restored canonical player is disconnected by durable-state design, then is rebound to the committed target session only when the client retries ACTIVATE;
- player entity identity remains stable;
- source remains retired; recovery never reactivates the old writer;
- duplicate source COMMIT after restart returns the already accepted decision instead of importing a second time.

## Selected design

Add an opt-in recovery layer above healthy V2:

`sm0_authority_server_node_recovery.gd`

It is selected only when `--recovery-dir` is present. The normal healthy V2 path remains unchanged.

A separate H2.2 recovery-fault subclass is used only for deterministic process-crash acceptance. Existing H1 transport-chaos and H2.1 pre-PREPARED fault paths remain unchanged.

### Durable snapshot

Append-style generation files:

`recovery-00000001.json`
`recovery-00000002.json`
...

Each final file is written through a unique `.tmp` file, flushed, closed and renamed to the final generation name. Startup ignores `.tmp` files and scans newest-to-oldest until it finds a valid snapshot.

Snapshot sections:

- schema / generation / authority / zone;
- recovery phase and transfer id;
- canonical SM0 directory;
- transfer counter;
- prepared handoff packages;
- committed handoff metadata (`package`, `directory`, `session_id`), but not a second persisted player record;
- `NetworkedGameplayService.export_durable_state()` through the existing authority wrapper;
- `NetworkedGameplayService.export_replay_state()`;
- checksum.

### Commit-before-ack ordering

The recovery layer intercepts only a successful target `PLAYER_HANDOFF_COMMITTED` send. At that point base V2 has already imported the target player and populated the target commit record, but the acknowledgement has not yet left the process.

Ordering becomes:

`target import -> committed record -> durable snapshot flush/rename -> COMMITTED ACK`

If persistence fails, the successful ACK is not sent. The process fails closed and emits a recovery persistence invariant.

### Restart/session rebind

Canonical durable restore intentionally removes transport session connectivity. Therefore restored committed records are marked `needs_session_rebind` in memory.

On retry `CLIENT_ACTIVATE` for the exact current committed transfer:

- validate that committed directory still matches current directory;
- rejoin `player/a` to the persisted target session using a recovery-specific operation id;
- verify stable `player_entity_id` and preserved spatial/input state;
- update only the in-memory committed projection;
- then run the existing V2 activation path and send ACTIVATE_ACK.

Replay state may be restored safely because recovery rebind uses a new operation id rather than replaying the pre-crash import-join operation.

## Deterministic H2.2 crash profile

Profile:

`h2-target-crash-after-commit-persist-v1`

The target:

1. accepts COMMIT;
2. persists `TARGET_COMMITTED` generation;
3. emits `SM0_H2_CRASH_POINT` with `TARGET_AFTER_COMMIT_PERSIST_BEFORE_ACK`;
4. suppresses successful COMMITTED and ACTIVATE responses while the doomed process is alive;
5. external Windows supervisor force-kills the target;
6. target restarts healthy with the same recovery directory;
7. latest valid snapshot is restored;
8. source COMMIT retry and client ACTIVATE retry converge without a second import decision.

## Alternatives considered

### Persist only `_committed_transfers`

Rejected. A remembered transaction without canonical gameplay durable state would not restore player position/ownership state and would create temptation to treat the handoff package as a second player-state database.

### Re-run `_activate_imported_player(package)` after restart

Rejected. Replaying the old import-join operation against restored replay state can return a historical success without recreating transient session ownership. It also mixes transaction replay with session recovery.

### Roll back target and let source resume

Rejected. Source already retired. Re-creating source ownership after target COMMIT would introduce a second authority decision and dual-writer risk.

### Persist every movement immediately in H2.2

Deferred. H2.2 proves durability of the target COMMIT decision boundary. Arbitrary active-owner crash with latest-movement durability is a later bounded stage; it must not be silently claimed here.

## Affected canonical owners

- SM0 lab handoff/recovery layer: changed;
- canonical `NetworkedGameplayService` durable truth: reused, not replaced;
- healthy V2 handoff protocol: not redesigned;
- global architecture ownership: unchanged.

## Files expected

- `scripts/runtime/host_client/multiplayer_gameplay_authority.gd` — expose existing durable/replay APIs only;
- new `scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery.gd`;
- new `scripts/runtime/seamless/sm0/sm0_authority_server_node_recovery_fault.gd`;
- `scripts/runtime/seamless/sm0/sm0_authority_server_process.gd` — opt-in node selection / recovery-dir plumbing;
- new Windows H2.2 runner;
- focused validation/documentation.

## Non-goals

H2.2 does not claim:

- source-process crash after retirement but before target COMMIT durability;
- arbitrary crash during active movement with zero lost movement;
- multi-player or multi-zone consensus;
- database replication;
- global server orchestration;
- production-ready distributed consensus;
- V0-S1 server handoff activation.

## Risks

- accidentally restoring a stale directory and reactivating a non-owner;
- transport session state being mistaken for durable ownership state;
- replay ledger causing a false-success join without actual session rebind;
- persistence ACK ordering being reversed;
- committed transaction metadata becoming a second player truth;
- old committed transfer being accepted under a newer directory epoch.

The implementation must fail closed for all of these.

## Validation plan

1. exact Godot 4.7.1 double compile-smoke for new/changed GDScript;
2. focused recovery snapshot write/restore smoke using the attached exact Linux double build;
3. unchanged normal SM0 acceptance remains green;
4. H1 transport fault acceptance remains structurally untouched;
5. H2.1 fault class/path remains structurally untouched;
6. Windows process-level H2.2 gate:
   - real target PID killed after durable target commit and before ACK;
   - new target PID starts on same ports;
   - `SM0_RECOVERY_RESTORED` references the exact crash transfer;
   - `SM0_RECOVERY_SESSION_REBOUND` occurs;
   - source transfer completes;
   - client completes requested handoffs;
   - `identity_changes == 0`;
   - no invariant violation / split writer;
7. Final gate continues multiple handoffs after recovery.

Independent review is still required before any broader acceptance/promotion.
