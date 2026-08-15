# SM0-H2 — Design Brief: process crash / restart hardening

Status: **LAB IMPLEMENTATION CANDIDATE**  
Risk: **CRITICAL — cross-server authority / recovery semantics**  
Baseline: `827b8276564aa9846e9cd2bef01b40e143054c33`  
Scope of this increment: **H2.1 target crash before PREPARED ACK**

## Problem statement

SM0-H1 proved 20/20 handoffs under deterministic UDP drop/duplicate/reorder/delay, but both authority processes remained alive. That does not prove recovery from a real process death.

The current SM0 authority node keeps directory, prepared/committed transfer maps and gameplay authority state in memory. A crash after authority transfer has started can therefore have materially different semantics from packet loss.

## Current behavior

Healthy handoff ordering is:

```text
source freezes player
  -> PREPARE
  -> target records prepared package
  -> PREPARED
  -> source retires local writer + advances directory
  -> COMMIT
  -> target imports player + advances directory
  -> COMMITTED
  -> client redirect/activation
```

SM0-H1 already proves retry/idempotence while both processes retain their in-memory state.

## Desired H2 behavior

H2 must add real process death incrementally and fail closed around authority ownership.

H2.1 proves the first safe crash point:

```text
target receives PREPARE
  -> target validates and records prepared package
  -> before PREPARED ACK leaves the process, supervisor force-kills target
  -> source remains the directory owner and remains frozen
  -> target restarts empty on the same ports
  -> source retries PREPARE
  -> restarted target reconstructs prepared state from the canonical handoff package
  -> normal commit/activate completes
```

At this point source authority has not been retired, so loss of target-local prepared state is recoverable from source retry without introducing a durable handoff journal.

## Alternatives considered

1. **Crash target after COMMIT first.** Rejected for H2.1. Target may already own/import the player while all committed-transfer state is only in memory; restart semantics require durable recovery design.
2. **Crash source after retiring the writer first.** Rejected for H2.1. Source loses `_source_transfer` and cannot safely reconstruct whether ownership must remain retired or resume without a durable transfer record.
3. **Simulate crash as packet loss.** Rejected. H1 already covers transport faults; H2 must terminate an actual Godot authority process.
4. **Use a graceful shutdown hook.** Rejected. H2.1 uses external `Stop-Process -Force` after a deterministic crash marker so normal shutdown cannot persist or clean state.

## Selected design

Add one explicit fault profile to the existing lab-only fault node:

```text
h2-target-crash-before-prepared-v1
```

For the first successful `PLAYER_HANDOFF_PREPARED` response it:

- emits `SM0_H2_CRASH_POINT`;
- suppresses that response and all later successful PREPARED responses while the doomed process remains alive;
- does not mutate healthy V2 behavior.

A dedicated Windows supervisor runner:

```text
RUN_V0_SM0_CRASH_ACCEPTANCE.ps1
```

will start A healthy, start B with the H2.1 profile, start the real automated client, observe the crash marker, force-kill B, restart B healthy on the same ports and require end-to-end convergence.

## Canonical owners / architecture boundary

This increment does **not** declare new project-wide ownership. It stays inside the existing SM0 experimental branch.

Main-owned checkpoint catalog currently places `SERVER_HANDOFF` outside the V0-S1 checkpoint. Therefore H2 evidence is lab evidence only and must not be presented as V0-S1 acceptance or merged runtime authority without a separate project-control decision.

## Non-goals

H2.1 does not solve:

- source crash;
- target crash after COMMIT;
- crash after client redirect;
- durable directory replication;
- durable transfer journal;
- atomic target import transaction;
- production multi-server topology;
- V0-S1 promotion or runtime merge.

## Expected risks

- A crash marker that still allows a later PREPARED ACK could create a timing-dependent false test. The profile therefore suppresses every successful PREPARED response until the process is externally killed.
- Restarted target begins with empty process memory. H2.1 intentionally relies only on source-owned PREPARE retry while source ownership is still canonical.
- Later H2 crash points cannot reuse this assumption and require explicit durable recovery semantics.

## Validation plan

Focused pre-publish validation on exact attached Godot `4.7.1.stable.double.custom_build.a13da4feb`:

- compile the extended fault node;
- verify the H2 profile emits exactly one crash marker;
- verify repeated successful PREPARED attempts remain suppressed before external crash;
- verify unrelated control messages still pass through.

Windows runtime H2.1 gate on exact candidate HEAD:

```powershell
.\RUN_V0_SM0_CRASH_ACCEPTANCE.ps1 -Restart
.\RUN_V0_SM0_CRASH_ACCEPTANCE.ps1 -Final -Restart
```

Required evidence:

- target Godot process is actually force-killed;
- a new target process instance is started on the same gameplay/control ports;
- no target COMMIT occurred before crash;
- restarted target re-prepares the same transfer ID;
- target COMMIT + activation completes after restart;
- source remains frozen across crash and later records source-transfer complete;
- player identity remains unchanged;
- requested handoffs complete;
- generic SM0 invariants still pass;
- worktree remains unchanged by the test.

## Next H2 increment after H2.1

H2.2 must introduce/review durable transfer semantics before testing a source crash or target crash after authority commit. A naive rollback is not acceptable because deterministic operation IDs can replay success without recreating the intended ownership mutation.
