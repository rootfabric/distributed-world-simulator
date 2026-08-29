# SM0 H3.3 — runtime evidence: in-flight dual-authority outage

Date: 2026-08-15

Track: experimental SM0 two-authority seamless handoff lab

Classification: BRANCH-LOCAL RUNTIME EVIDENCE ONLY. This document does not declare global/project acceptance and does not remove `SERVER_HANDOFF` from the V0-S1 stop-before boundary.

## Exact tested implementation

Branch:

`feature/sm0-two-authority-seamless-handoff-lab`

Exact runtime-tested HEAD:

`205dbee4226f774b654ccb3153f7c2bfc9e2ce43`

Godot runtime:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`

Canonical Windows worktree:

`C:\distributed-world-simulator\worktrees\sm0-two-authority-seamless-handoff-lab`

## H3.3 goal

Prove recovery of one unfinished A -> B handoff transaction across complete loss of both authority processes after the target has durably prepared the transfer and after the source has durably retired, but before the target has committed the transfer and before the client has completed the crossing.

The bounded durable viewpoints at the failure boundary are intentionally asymmetric but compatible:

- A: `SOURCE_RETIRED(T)`, directory already points to B, source is non-writer and retains resumable `COMMIT_SENT` metadata;
- B: `TARGET_PREPARED(T)`, directory still points to A, target is non-writer and retains the exact prepared handoff package;
- client: crossing `T` is not yet completed.

After total outage, B must restore `TARGET_PREPARED(T)`, A must restore `SOURCE_RETIRED(T)` and resume the same COMMIT, and B must consume the restored PREPARE and persist `TARGET_COMMITTED(T)` without creating a second writer or changing canonical player identity.

This track introduced durable `TARGET_PREPARED` persistence before a successful `PLAYER_HANDOFF_PREPARED` acknowledgement because an in-memory-only prepared transfer is insufficient once both authority processes are lost before COMMIT.

## Focused recovery regression

Runner compile-checks the transaction recovery/fault composition and executes:

`res://tests/runtime/seamless/sm0/test_sm0_target_prepare_recovery.gd`

Observed on exact tested HEAD:

`SM0 target prepare recovery: PASS (32 assertions)`

The focused regression observed:

- `TARGET_PREPARED` snapshot generation `1` persisted with writer_count `0`;
- exact handoff package survived restart;
- restored target emitted `SM0_RECOVERY_TARGET_PREPARED_PENDING`;
- replayed COMMIT was accepted after restart;
- target became writer only at commit;
- `TARGET_COMMITTED` advanced recovery generation to `2`;
- player identity, input sequence and handoff velocity remained preserved.

## Default gate evidence

Command:

```powershell
.\RUN_V0_SM0_INFLIGHT_DUAL_OUTAGE_ACCEPTANCE.ps1 -Restart
```

Result: PASS.

Observed bounded facts:

- exact HEAD: `205dbee4226f774b654ccb3153f7c2bfc9e2ce43`
- same client PID: `19096`
- transfer: `handoff/sm0/a/2/1`
- crossing completed before outage: `0`
- target commit before outage: `0`
- killed A PID: `24416`
- killed B PID: `1692`
- restarted A PID: `1776`
- restarted B PID: `12960`
- kill request gap: `0 ms`
- A `SOURCE_RETIRED` generation: `12`
- B `TARGET_PREPARED` generation: `1`
- B `TARGET_COMMITTED` generation after recovery: `2`
- handoffs: `2 / 2`
- final directory epoch: `3`
- identity changes: `0`
- SM0 log analysis: PASS
- analyzed events: `92`

Runtime evidence directory:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH33\logs\20260815-223114`

Summary:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH33\logs\20260815-223114\h33-summary.json`

## Final gate evidence

Command:

```powershell
.\RUN_V0_SM0_INFLIGHT_DUAL_OUTAGE_ACCEPTANCE.ps1 -Final -Restart
```

Result: PASS.

Observed bounded facts:

- exact HEAD remained `205dbee4226f774b654ccb3153f7c2bfc9e2ce43`
- same client PID: `2560`
- transfer: `handoff/sm0/a/2/1`
- crossing completed before outage: `0`
- target commit before outage: `0`
- killed A PID: `23048`
- killed B PID: `3656`
- restarted A PID: `16024`
- restarted B PID: `14400`
- kill request gap: `0 ms`
- A `SOURCE_RETIRED` generation: `12`
- B `TARGET_PREPARED` generation: `1`
- B `TARGET_COMMITTED` generation after recovery: `2`
- handoffs: `6 / 6`
- final directory epoch: `7`
- identity changes: `0`
- SM0 log analysis: PASS
- analyzed events: `168`

Runtime evidence directory:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH33\logs\20260815-223418`

Summary:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH33\logs\20260815-223418\h33-summary.json`

## What this evidence proves

Within the exact SM0 lab scope and exact tested implementation:

- `PLAYER_HANDOFF_PREPARED` is backed by durable target state rather than only process memory;
- the target can restore the exact prepared handoff package after process loss;
- the source can restore its exact durable retired state and resume the same COMMIT;
- both old authority processes can be dead simultaneously while the same client process remains alive;
- the in-progress transfer has not already crossed or committed before the outage boundary;
- after restart the exact transfer is completed rather than recreated under a new identity;
- target becomes the unique writer at target commit;
- no `SM0_COMMIT_WITHOUT_PREPARE` failure occurs in the recovered transaction;
- canonical player identity remains stable;
- directory epochs continue monotonically through six handoffs after recovery.

## Explicit non-claims

This evidence does NOT prove:

- production HA readiness;
- multi-host/network-partition safety;
- quorum/consensus semantics;
- durability under physical disk/power-loss/fsync failure;
- safety if persistence itself is corrupted or lost;
- arbitrary concurrent clients or multiple simultaneous handoff transactions;
- every crash point after target commit but before all participants observe the commit decision;
- global V0 or project checkpoint acceptance.

The next materially different failure boundary is the commit-decision observation window: target has durably committed the transfer, while the source/client have not necessarily observed the successful commit/redirect before both authority processes are lost. That case must prove that recovery cannot resurrect the old source writer or create a second target commit decision.
