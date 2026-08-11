# M7 Owner-Authoritative Locomotion Acceptance

Date: 2026-08-11
Branch: `feature/m7-sequence-aware-reconciliation-fix10-fix6-semantic-baseline`
Validated commit before this record: `464e1b8dd27fad8b4d477f6e76ca52a449893353`
Decision: **ACCEPTED — OWNER_AUTHORITATIVE_VALIDATED vertical slice**

## Accepted authority split

- Player locomotion transform: `OWNER_AUTHORITATIVE_VALIDATED`.
- Owning client authors the local realtime locomotion transform.
- Server validates submitted `PLAYER_STATE` using the existing movement plausibility boundary and relays the accepted state.
- Remote players remain server-relayed and snapshot-interpolated.
- Inventory, item ownership, item graph mutations, containers, economy, spawn/despawn, durable state and world authority remain server-authoritative.
- Item drop/place transforms are derived from the server's validated owner position/facing rather than arbitrary client item transforms.
- The legacy server-predicted FIX10 path remains preserved as a fallback/reference regression path and is not deleted by this acceptance.

## Automated validation

Command:

```powershell
.\VALIDATE_M7_SEQUENCE_RECONCILIATION_FIX10.ps1 `
    -GodotPath $Godot `
    -FocusedOnly
```

Result: **PASS**.

Relevant gates:

- Owner-authoritative movement boundary: `PASS` — 23 assertions.
- Owner-authority item drop + same-revision rollback: `PASS` — 30 assertions, 0 failures.
- FIX10 fix7b arrival-paced authority input playout: `PASS` — 36 assertions, 0 failures.
- FIX10 fix6 ACK phase semantics: `PASS` — 36 assertions, 0 failures.
- FIX10 fix8 owner ACK fast confirmation: `PASS` — 55 assertions, 0 failures.
- FIX10 fix6 semantic input latch: `PASS` — 10 assertions, 0 failures.
- FIX10 fix6 cadence/presentation: `PASS` — 12 assertions.
- FIX10 fix6 remote snapshot guard: `PASS` — 7 assertions.
- FIX10 fix7 render-rate local presentation: `PASS` — 8 assertions, 0 failures.
- FIX10 fix5 composite ACK semantic identity: `PASS` — 48 assertions.
- FIX10 fix4 ACK timeline + MTU headroom: `PASS` — 51 assertions.
- FIX10 fix3 remote continuity + ACK fallback: `PASS` — 29 assertions.
- FIX10 fix2 MTU preflight: `PASS` — 12 assertions.
- FIX10 focused reconciliation: `PASS` — 100 assertions.
- FIX9 frame-budget regression: `PASS` — 39 assertions, 0 failures.
- FIX8 prediction-clock regression: `PASS` — 50 assertions.
- NX4 prediction/reconciliation regression: `PASS` — 706 assertions.

## Manual visual diagnostic

Command:

```powershell
.\RUN_M7_OWNER_AUTHORITY_DIAGNOSTIC.ps1 `
    -GodotPath $Godot `
    -DurationSeconds 45
```

Artifact directory reported by the runner:

`artifacts/test-results/m7-owner-authority-diagnostic-20260811-123004`

Runner summary:

```text
Client A: state=COMPLETE, corrections=0, max_error=0.0000m,
          owner_states=1363, owner_send_failures=0,
          owner_snapshot_reconcile_skips=915,
          remote_gap=13, remote_underruns=0, remote_holds=0

Client B: state=COMPLETE, corrections=0, max_error=0.0000m,
          owner_states=1372, owner_send_failures=0,
          owner_snapshot_reconcile_skips=911,
          remote_gap=13, remote_underruns=0, remote_holds=0
```

Manual observation:

- Locally controlled player movement is much smoother than the server-predicted path and no longer exhibits visible correction jerks.
- A small residual spring-like feel remains attributable to controller movement/presentation behavior and was judged non-critical.
- Remote player presentation remains smooth.
- Inventory/item interactions work after the owner-authority change.
- Pickup/drop and item movement were manually verified.

## Defects closed during acceptance

1. **PowerShell diagnostic parser failure** — `${Label}` syntax now avoids `$Label:` parsing as a drive-qualified variable.
2. **Same-revision optimistic item rollback suppression** — projected item graph updates are no longer dropped merely because authoritative revision did not change. This prevents ghost inventory ownership after a rejected prediction.
3. **Owner Basis → yaw 180-degree inversion** — owner-state import now respects Godot forward `-Z`, so server-derived item drop/place direction matches the owner's actual facing.
4. **FIX9 composition identity regression** — validation now checks inheritance of the accepted FIX8/FIX9 composition chain instead of requiring the scene script to remain exactly FIX8 forever.

## Acceptance interpretation

This acceptance validates the architecture choice and the current local-network vertical slice. It does **not** claim strong anti-cheat security. Current movement validation is a plausibility guard and can be tightened later without changing the authority split.

The next promotion step should integrate `OWNER_AUTHORITATIVE_VALIDATED` into the normal runtime/profile selection and add owner-specific acceptance for non-local network conditions, reconnect/ownership epoch changes, explicit invalid-state rejection/recovery and server/item interaction consistency under latency/loss.
