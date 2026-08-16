# V0-SM0 P4 — Windows + controlled WAN verification evidence

**Дата:** 2026-08-16  
**Статус:** `IMPLEMENTED CANDIDATE / LOCAL WINDOWS VERIFIED / CONTROLLED WAN VERIFIED / TARGET-RESTART FAULT PENDING / INDEPENDENT CRITICAL REVIEW PENDING / NOT ACCEPTED`  
**Ветка:** `feature/sm0-two-authority-seamless-handoff-lab`  
**PR:** `#102 — SM0: two-authority seamless handoff lab`  
**Exact runtime-tested HEAD:** `5f3f967f9be779a79d45be5b18ac78ad954f7dd4`  
**Godot:** `4.7.1.stable.double.custom_build.a13da4feb`  
**Risk:** `CRITICAL — cross-server authority transition`

> Этот checkpoint фиксирует фактический Windows runtime evidence. Он не является acceptance, merge approval или разрешением переходить к P5.

## 1. Уже подтверждённые P4 gates

### Local short P4

```powershell
.\RUN_V0_SM0_P4_ACCEPTANCE.ps1 -Handoffs 4 -Restart
```

Результат ранее подтверждён:

```text
4/4 handoffs
P4 fast = 4
legacy = 0
analyzer PASS
wrapper fast-path evidence PASS
```

### Local final stress P4

```powershell
.\RUN_V0_SM0_P4_ACCEPTANCE.ps1 -Final -Restart
```

Результат ранее подтверждён:

```text
20/20 handoffs
P4 fast = 20
legacy = 0
SM0 log analysis PASS
SM0 acceptance PASS
P4 wrapper fast-path evidence PASS
```

### Legacy final regression

```powershell
.\RUN_V0_SM0_ACCEPTANCE.ps1 -Final -Restart
```

Результат ранее подтверждён:

```text
20/20 handoffs
P4 fast = 0
legacy = 20
SM0 log analysis PASS
SM0 acceptance PASS
```

Это доказывает, что opt-in P4 path не сломал default legacy handoff.

## 2. Controlled WAN P4 matrix — OBJECTIVE PASS

Команда:

```powershell
.\RUN_V0_SM0_P4_CONTROLLED_NETWORK_LATENCY_MATRIX.ps1 -Restart -RequireHandoffs 10
```

Exact runtime-tested HEAD:

```text
5f3f967f9be779a79d45be5b18ac78ad954f7dd4
```

Matrix result:

```text
SM0-P3.1 FINAL controlled WAN latency matrix: OBJECTIVE PASS
samples: 10 handoffs/profile x 4 profiles

WAN-10: p50=37 ms   p95=49 ms
WAN-20: p50=55 ms   p95=79 ms
WAN-30: p50=85 ms   p95=97 ms
WAN-45: p50=110 ms  p95=129 ms
```

Directional medians:

```text
WAN-10: A->B 38 ms   B->A 37 ms
WAN-20: A->B 56 ms   B->A 55 ms
WAN-30: A->B 79 ms   B->A 85 ms
WAN-45: A->B 110 ms  B->A 110 ms
```

Machine matrix summary:

```text
C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0GraphicalLab\matrix\20260816-180716\controlled-network-latency-matrix-summary.json
```

## 3. P4 fast-path proof across every measured WAN transfer

Outer P4 wrapper independently matched every client-measured `transfer_id` to server evidence:

```text
SM0_P4_FAST_COMMIT_ACCEPTED
```

Final result:

```text
SM0-P4 controlled WAN matrix fast-path evidence: PASS
WAN-10: measured=10 P4-fast-evidenced=10
WAN-20: measured=10 P4-fast-evidenced=10
WAN-30: measured=10 P4-fast-evidenced=10
WAN-45: measured=10 P4-fast-evidenced=10
```

Therefore:

```text
40 measured WAN handoffs
40 P4 fast-evidenced handoffs
0 measured legacy/fallback handoffs
```

Evidence file:

```text
C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0GraphicalLab\matrix\20260816-180716\p4-fast-evidence-summary.json
```

## 4. Comparison with P3.1 legacy WAN baseline

Earlier legacy P3.1 baseline:

```text
WAN-10 p50=73 ms   p95=80 ms
WAN-20 p50=110 ms  p95=130 ms
WAN-30 p50=152 ms  p95=165 ms
WAN-45 p50=213 ms  p95=243 ms
```

P4 verified result:

```text
WAN-10 p50=37 ms   p95=49 ms
WAN-20 p50=55 ms   p95=79 ms
WAN-30 p50=85 ms   p95=97 ms
WAN-45 p50=110 ms  p95=129 ms
```

P4 therefore removes approximately half of the crossing critical-path latency at the tested WAN profiles. This is consistent with the P4 goal of removing one PREPARE/PREPARED WAN round trip from the actual crossing path.

This does **not** claim that ordinary movement is smooth under WAN delay. The existing SM0 manual lab still has stop-and-wait MOVE behavior; convergence with NX4/NX5 remains a separate concern.

## 5. Harness repair verified during this run

P4 WAN matrix now owns its sample-count lifecycle:

- profile ignores premature window close requests while `handoffs_completed < RequireHandoffs`;
- profile auto-closes only after the required confirmed crossing count;
- the successful run visibly exercised this guard (`close request ignored`) and then auto-closed at 10/10;
- all four profiles completed automatically and produced matrix + P4 evidence summaries.

The harness repair changed test UX only; authority/prewarm/fast-commit protocol semantics were not modified by that repair.

## 6. Invariants observed by the successful matrix

Across all four profiles:

```text
stable logical_player_id = a
stable player_entity_id = player/a
identity_changes = 0
monotonic authority epoch
alternating owner A/B
completed crossing evidence for every sample
P4 FAST_COMMIT evidence for every measured transfer
no reported invariant/runtime failure
```

## 7. Remaining CRITICAL blocker before acceptance

The known availability gap remains intentionally open:

```text
target sends PREWARMED ACK
-> target restarts
-> transient reservation is lost
-> source crosses before learning about restart
-> source retires writer
-> target receives FAST_COMMIT without reservation
-> fail-closed rejection
```

Current expected failure marker:

```text
SM0_P4_FAST_COMMIT_WITHOUT_PREWARM
```

This behavior preserves safety/no split-brain, but does not yet provide availability recovery for that crash window.

Therefore P4 remains:

```text
IMPLEMENTED CANDIDATE
LOCAL WINDOWS VERIFIED
CONTROLLED WAN VERIFIED
NOT ACCEPTED
```

Remaining gates:

1. target-restart/fault experiment and explicit recovery policy;
2. focused regression for the selected recovery behavior;
3. independent CRITICAL review of the exact resulting candidate.

P5 must not start merely because the normal-path WAN matrix is green.
