# SM0 H3.2 — runtime evidence: simultaneous dual-authority total outage

Date: 2026-08-15

Track: experimental SM0 two-authority seamless handoff lab

Classification: BRANCH-LOCAL RUNTIME EVIDENCE ONLY. This document does not declare global/project acceptance and does not remove `SERVER_HANDOFF` from the V0-S1 stop-before boundary.

## Exact tested implementation

Branch:

`feature/sm0-two-authority-seamless-handoff-lab`

Exact runtime-tested HEAD:

`f08b0e913514b965fa5d9f16038d51a5cf9a3728`

Godot runtime:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`

Canonical Windows worktree:

`C:\distributed-world-simulator\worktrees\sm0-two-authority-seamless-handoff-lab`

## H3.2 goal

Prove a bounded total-outage recovery case after a completed A -> B handoff:

1. A has already retired and is non-writer.
2. B is the active owner inside EAST.
3. B persists an ACTIVE_OWNER movement boundary before MOVE_ACK.
4. Both authority processes are force-killed before either one is restarted.
5. The same client process remains alive through the zero-authority interval.
6. A restores the retired/non-writer durable viewpoint.
7. B restores the active-owner durable viewpoint and rebounds the exact duplicate input without applying movement twice.
8. The same session continues seamless handoffs with identity unchanged.

This is intentionally distinct from H3.1 sequential crashes and from a crash inside an unfinished handoff transaction.

## Default gate evidence

Command:

```powershell
.\RUN_V0_SM0_DUAL_AUTHORITY_OUTAGE_ACCEPTANCE.ps1 -Restart
```

Result: PASS.

Observed bounded facts:

- same client PID: `15012`
- outage after crossing: `A -> B (#1)`
- killed A PID: `24224`
- killed B PID: `6924`
- restarted A PID: `21768`
- restarted B PID: `9692`
- kill request gap: `0 ms`
- A retired generation: `12`
- B active generation / input sequence / x: `3 / 12 / 0.5`
- B ownership epoch: `1 -> 2`
- handoffs: `2 / 2`
- final directory epoch: `3`
- identity changes: `0`
- SM0 log analysis: PASS
- analyzed events: `96`

Runtime evidence directory:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH32\logs\20260815-205100`

Summary:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH32\logs\20260815-205100\h32-summary.json`

## Final gate evidence

Command:

```powershell
.\RUN_V0_SM0_DUAL_AUTHORITY_OUTAGE_ACCEPTANCE.ps1 -Final -Restart
```

Result: PASS.

Observed bounded facts:

- exact HEAD remained `f08b0e913514b965fa5d9f16038d51a5cf9a3728`
- same client PID: `26232`
- outage after crossing: `A -> B (#1)`
- killed A PID: `21832`
- killed B PID: `3648`
- restarted A PID: `20624`
- restarted B PID: `6920`
- kill request gap: `0 ms`
- A retired generation: `12`
- B active generation / input sequence / x: `3 / 12 / 0.5`
- B ownership epoch: `1 -> 2`
- handoffs: `6 / 6`
- final directory epoch: `7`
- identity changes: `0`
- SM0 log analysis: PASS
- analyzed events: `188`

Runtime evidence directory:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH32\logs\20260815-210546`

Summary:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH32\logs\20260815-210546\h32-summary.json`

## What this evidence proves

Within the exact SM0 lab scope and exact tested implementation:

- there is a real interval in which both authority server processes are dead before restart;
- the client process survives that interval;
- the two recovered processes do not both become writers;
- retired A remains retired/non-writer;
- B restores the exact ACTIVE_OWNER durable movement boundary;
- the outstanding duplicate client input is classified as durable replay and does not apply the movement twice;
- canonical player identity remains stable;
- directory epochs continue monotonically through subsequent handoffs;
- the system converges through six handoffs after the total outage.

## Explicit non-claims

This evidence does NOT prove:

- production HA readiness;
- multi-host/network-partition safety;
- quorum/consensus semantics;
- durability under physical disk/power-loss/fsync failure;
- both authorities crashing inside one unfinished handoff transaction;
- arbitrary simultaneous faults involving persistence corruption;
- global V0 or project checkpoint acceptance.

The next materially different failure boundary is dual-authority loss inside one in-progress handoff transaction, where recovery must resolve one durable transfer decision rather than merely restore a stable post-handoff owner state.
