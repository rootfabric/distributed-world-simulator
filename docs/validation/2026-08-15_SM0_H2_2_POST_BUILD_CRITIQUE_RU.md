# SM0-H2.2 — post-build critique

Status: `NO_MATERIAL_REFACTOR_REQUIRED / IMPLEMENTATION_CANDIDATE`

Evidence code head before this documentation-only critique commit:

`66dec172d395a8bb23f366f432638f8ef9d4b056`

Risk: `CRITICAL` because the work concerns cross-server authority recovery. This document is implementer critique, not independent review and not acceptance.

## Duplicate truth

No new durable player-state truth was introduced.

The SM0 recovery snapshot stores transaction metadata (`directory`, transfer packages, commit metadata, phase, generation) and embeds the existing canonical `NetworkedGameplayService` durable/replay exports. The committed metadata deliberately omits a persisted `player` record. On restore, the current player projection is obtained from the restored canonical gameplay state.

## Commit ordering

The target successful `PLAYER_HANDOFF_COMMITTED` response is intercepted only after base target import/commit state exists. The recovery layer requires a successful `TARGET_COMMITTED` snapshot write before allowing that ACK to leave the process.

The deterministic H2.2 fault subclass then emits its crash point only after the same persistence requirement succeeds and suppresses both successful COMMITTED and ACTIVATE progress on the doomed process until the external supervisor kills it.

## Session recovery

Canonical durable state intentionally clears transport connectivity. H2.2 does not persist a live socket/session binding as ownership truth.

After restart, the exact committed transfer is marked `needs_session_rebind`. A retried client ACTIVATE causes a fresh recovery-specific join operation, then verifies:

- stable `player_entity_id`;
- unchanged position;
- unchanged `last_input_sequence`;
- current committed directory matches the current owner directory.

Only then does the existing activation path continue.

## Sibling paths checked

H2.2 does not modify:

- `sm0_authority_server_node_v2.gd`;
- the existing H1/H2.1 `sm0_authority_server_node_fault.gd`;
- automated client handoff logic;
- P1 manual/graphical client;
- SM0 wire contracts.

`sm0_authority_server_process.gd` selects the new recovery path only with `--recovery-dir`, and selects the new recovery-fault path only for exact profile `h2-target-crash-after-commit-persist-v1`. Other fault profiles still route to the existing fault node; no recovery options still route to healthy V2.

## Exact attached-Godot focused evidence

Exact engine:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`

Final published recovery/fault/process scripts were reproduced in the focused harness and produced:

- recovery node compile exit `0`;
- recovery fault compile exit `0`;
- process routing compile exit `0`;
- recovery focused runtime exit `0`;
- `SM0_RECOVERY_SNAPSHOT_PERSISTED` for generation `1`, phase `TARGET_COMMITTED`;
- `SM0_RECOVERY_RESTORED` for the same generation/transfer;
- `SM0_RECOVERY_SESSION_REBOUND`, stable `player/a`;
- `H22_RECOVERY_FOCUSED_PASS`;
- fault focused runtime exit `0`;
- persistence event before `SM0_H2_CRASH_POINT`;
- crash point `TARGET_AFTER_COMMIT_PERSIST_BEFORE_ACK`;
- doomed-process ACTIVATE suppression;
- `H22_FAULT_FOCUSED_PASS`.

The Windows runner file used for static critique has Git blob SHA `8ed66971fedd982362806c272f99aee82ed5b5fd`, matching the published runner blob on `66dec172...`.

## Complexity / coupling

The largest new surface is intentionally isolated in one recovery subclass rather than folded into healthy V2. This keeps the known-good H1/H2.1 path auditable while H2.2 remains a bounded candidate.

The shared `MultiplayerGameplayAuthority` change is only thin pass-through exposure of already-existing canonical durable/replay APIs. It does not implement persistence itself.

## Remaining risks / later work

These are explicit non-claims, not hidden PASS assumptions:

1. **Source crash after local retirement but before a durable source decision** is not solved by H2.2. The recovery layer can persist `SOURCE_RETIRED`, but current source ordering still contains a small retirement-to-persistence window. A later H2.3 design must move/define that decision boundary rather than claiming H2.2 covers it.
2. **Arbitrary active-owner crash with zero loss of the latest movement** is not covered. H2.2 persists the target COMMIT boundary, not every movement.
3. `FileAccess.flush()` + rename is sufficient for the process-crash laboratory gate being tested here, but this work does not claim power-loss/storage-controller durability or replicated database consensus.
4. Recovery generations are retained rather than pruned. This is acceptable for the bounded lab but needs retention policy before long-lived production use.
5. Base `SM0_SERVER_READY` is emitted during base setup before the recovery subclass emits `SM0_RECOVERY_RESTORED`. No process frame/UDP polling occurs before setup returns, so restored state is applied before normal packet processing; nevertheless production observability may later prefer a distinct `RECOVERY_READY` lifecycle state.

## Verdict of this critique

`NO_MATERIAL_REFACTOR_REQUIRED`

The next required evidence is the real Windows H2.2 process gate on the exact candidate head, followed by independent review before any broader acceptance or promotion.
