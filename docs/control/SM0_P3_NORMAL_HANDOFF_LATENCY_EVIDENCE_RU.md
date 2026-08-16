# SM0-P3 — normal healthy handoff latency evidence

Status: **BRANCH-LOCAL EXPERIMENTAL RUNTIME EVIDENCE**.

This document does not promote SM0 to production/global/canonical status. Cross-server authority remains CRITICAL risk and `SERVER_HANDOFF` remains outside V0-S1 (`stop_before`).

## Exact runtime input

- Repository: `rootfabric/distributed-world-simulator`
- Branch: `feature/sm0-two-authority-seamless-handoff-lab`
- Exact tested HEAD: `a3cd79a5688c5123a487406d0c539a0ee05e6a3c`
- Godot: `4.7.1.stable.double.custom_build.a13da4feb`
- Runner: `RUN_V0_SM0_NORMAL_HANDOFF_LATENCY_LAB.ps1 -Restart -RequireHandoffs 10`
- Windows runtime log directory: `C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0GraphicalLab\logs\20260816-122304`
- Summary: `C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0GraphicalLab\logs\20260816-122304\normal-handoff-latency-summary.json`

The operator manually crossed the x=0 authority boundary 25 times in one graphical client session and then closed the Godot window.

## Result

`SM0-P3 normal healthy handoff latency measurement: PASS`

Observed 25 client-side handoff samples:

- total latency: min `12 ms`, p50 `18 ms`, p95 `25 ms`, max `25 ms`, average `19.2 ms`;
- trigger -> redirect: p50 `12 ms`, p95 `19 ms`;
- redirect -> activate: p50 `6 ms`, p95 `13 ms`;
- all samples preserved `player/a`;
- all samples reported `identity_changes=0`;
- all samples preserved canonical movement magnitude `|v|=0.25`;
- there were no artificial fault profiles, authority kills, or recovery holds in this measurement.

The operator's direct visual observation was that the transfer felt instantaneous and no handoff interruption was perceptible.

## Directional observation

The sample set has a visible localhost direction asymmetry which is recorded as a diagnostic observation, not hidden as noise:

- A -> B: 13 samples, all `12..18 ms`, mostly `13 ms`;
- B -> A: 12 samples, one `24 ms`, the remainder `25 ms`.

This does not fail P3 because the end-to-end handoff stayed below 25 ms, identity remained stable, and motion state was preserved. The asymmetry should be isolated separately from WAN-delay experiments so a scheduling/polling artifact is not confused with protocol cost.

## Interpretation boundary

P3 answers a narrow question: what does a healthy two-authority transfer cost on the current localhost laboratory path when no crash/recovery orchestration is injected?

It does **not** claim production internet latency, packet-loss tolerance, scalability, V0 acceptance, or canonical SERVER_HANDOFF readiness. Previous multi-second graphical recovery demonstrations included deliberate process outage/restart stages and therefore must not be interpreted as normal handoff latency.
