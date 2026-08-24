# V0 — Current Primary Work Map

**Статус:** `POST-P6 / SM1 ACTIVATION CONTROL CANDIDATE R6`  
**Canonical accepted product baseline:** `main @ 9ade3233f8d9f16b77edcc8cf273fe8e649d5637`  
**Accepted checkpoint:** `V0_P6_PERSISTENT_SHARED_OUTPOST`

P6 завершён и принят. Pre-P6 Edge Gateway Foundation также принят и остаётся foundation, а не текущей кампанией.

Текущая основная работа V0:

```text
P6 ACCEPTED
    |
    v
POST-P6 CONTROL RECONCILIATION
    |
    +--> formal P6 acceptance record
    +--> current-work-map / scheduler / product-train refresh
    +--> EG5 telemetry+hysteresis repair before runtime dispatch
    |
    v
ACTIVATE V0-SM1
    |
    v
production A <-> B authority handoff on accepted P6
    |
    v
P7 bounded terrain mutation
    |
    v
P8 first mobile construct
```

## Current normative plan

Human plan:

`docs/plans/V0_SM1_PRODUCTION_HANDOFF_EXECUTION_RU.md`

Machine plan:

`config/control/harness/v0-sm1-production-handoff-plan.v1.json`

Activation candidate:

`config/control/harness/activation/V0-SM1-R1-ACTIVATION-001.v1.json`

Fresh epoch / Work Order:

```text
E2026-08-24-V0-SM1-R1
V0-SM1-R1-WO-001
```

## Exact product base

SM1 starts only from the accepted P6 main composition:

`9ade3233f8d9f16b77edcc8cf273fe8e649d5637`

Historical SM0 and research/SM1 branches are capability donors only. They must never become the product base and must not be merged wholesale.

## First production target

The first bounded SM1 checkpoint proves:

```text
2 graphical clients
1 stable Edge Gateway endpoint per client
2 authority processes A/B
A ACTIVE + B WARM
A -> B handoff
B ACTIVE + A retired/drain
B -> A return handoff
```

Hard invariants:

```text
exactly one active canonical writer
stable logical_player_id
stable player_entity_id
monotonic authority epoch
OperationId continuity
input sequence continuity
one Item Graph
one Construction truth
one persistence owner
WARM/SHADOW cannot write
stale source fails closed
normal crossing does not reconnect/respawn
client Gateway endpoint does not change during authority pivot
```

## Pre-dispatch repair

Before SM1 runtime dispatch, EG5 must receive a separate reviewed repair:

- `probe_failures` counter increments exactly by one per failed probe;
- hysteresis compares fresh current-gateway score against fresh candidate score;
- returned health/score metadata always belongs to the actually selected gateway.

This is a bounded Edge locator correctness repair, not part of SM1 authority semantics.

## Runtime authorization rule

This pointer records direction only. Runtime mutation remains forbidden until:

```text
post-P6 control candidate reviewed PASS
-> integrated to main
-> post-merge Project Control NON_RED
-> mutation lease rotated to V0_SM1
-> Director DISPATCHED event
```

Do not start P7 before SM1 is accepted or an explicit later main-owned defer decision supersedes this route.
