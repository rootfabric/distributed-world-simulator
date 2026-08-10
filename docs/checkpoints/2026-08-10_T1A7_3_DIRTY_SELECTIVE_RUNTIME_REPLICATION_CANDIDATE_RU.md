# T1A.7.3 — Dirty / Selective Runtime Replication — Implemented Candidate

**Дата:** 2026-08-10  
**Ветка:** `feature/t1a7-runtime-recovery-interest-scale`  
**Base:** T1A.7.2 ACCEPTED  
**Accepted base runtime:** `d41d3d3721b61cc0464e1c5693ccaa4521b7819a`  
**Candidate runtime/test head:** `cab2e1cdcafd831ab9c0cb09123383bf96f5dfe0`

## Цель

T1A.7.2 уже гарантирует корректный late-interest/reconnect baseline, но mutation path всё ещё концептуально начинается с broadcast-all peer iteration и только затем отбрасывает irrelevant peers.

T1A.7.3 меняет fan-out model:

```text
canonical construct runtime mutation
  -> compare previous/current authoritative snapshots
  -> dirty runtime-id set
  -> reverse projection construct_id -> selected logical clients
  -> only active relevant peer/session routes
  -> existing reliable ConstructionRuntimeSnapshot
```

Full baseline/resync остаётся correctness path.

## Что не меняется

```text
ConstructionRuntimeStateStore          unchanged
ConstructionRuntimeSnapshot            unchanged
ConstructionRuntimeReplicaStore        unchanged
M3/NX channel policy                   unchanged
protocol manifest                      unchanged
authority ownership                    unchanged
interest/spatial identity ownership    unchanged
```

Новый compact delta DTO пока не нужен. На этом checkpoint важнее убрать broadcast-all routing work, не ослабляя exact discrete runtime truth.

## Planner

`construction_runtime_selective_replication_planner.gd` поддерживает domain-local reverse projection:

```text
logical client -> selected construct ids
construct id   -> selected logical clients
```

На mutation он:

```text
validates previous/current full snapshots
checks authority epoch + construct identity
rejects stale revision
rejects same-revision different state
classifies identical same-revision snapshot as replay
compares subject checksum maps
returns sorted dirty runtime ids
returns only active routes for selected clients
counts avoided peer deliveries
```

Planner не является global interest registry или scheduler.

## M3 integration

`t1a7_3_m3_runtime_server_adapter.gd` stacked поверх accepted T1A.7.2.

Interest update сначала проходит через T1A.7.2 revision/session/baseline contract, после чего selection отражается в reverse projection planner-а.

Mutation routing:

```text
T1A.5 canonical runtime mutation
  -> inherited _broadcast_runtime_snapshot virtual call
  -> T1A.7.3 plan_mutation
  -> selected active sessions only
  -> _send_runtime_snapshot
  -> RESYNC / RELIABLE_ORDERED
```

Если planner неожиданно не может построить plan, correctness не теряется: используется fallback в accepted T1A.7.2 interest-filtered full broadcast path.

## Focused acceptance

Synthetic test:

```text
D0 selected by A,C
D1 selected by B,C
D not interested in either
D0 mutation -> targets A,C only
D1 mutation -> targets B,C only
one changed subject -> one dirty runtime id
stale revision -> reject
same revision mutation -> reject
same snapshot -> replay
selection leave/re-enter updates reverse index
```

Real M3 process test:

```text
A joins outside interest
A enters D0 -> baseline
A opens door -> selective target A
B joins outside interest -> no runtime
B enters -> current OPEN baseline
B leaves interest while still connected
A closes door -> selective target A only
B receives no mutation
planner avoided at least one peer delivery
B re-enters -> CLOSED baseline
B reconnects -> retained-interest baseline
```

## Acceptance gates

```powershell
.\RUN_T1A7_3_DIRTY_SELECTIVE_REPLICATION_TESTS.ps1 -GodotPath $Godot
```

После focused PASS на том же runtime code:

```powershell
.\RUN_WORLD_REGRESSION_TESTS.ps1
```

## Что сознательно оставлено на T1A.7.4

```text
100 / 1,000 constructs synthetic scale
10,000 runtime subjects
bytes/messages projected vs broadcast baseline
projection time
replica apply time
memory growth / repeated interest movement
soak
explicit replay-history bound under scale
```

T1A.7.3 доказывает routing semantics; T1A.7.4 должен доказать scale behavior численно.
