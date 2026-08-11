# T1B — Composition / Failure / Recovery

**Branch:** `feature/t1b-composition-failure-recovery`  
**Parent checkpoint:** `T1A.7 Runtime Recovery / Interest / Scale — ACCEPTED`  
**Architecture:** `GLOBAL-P0-2026-08-10-R2`  
**Control:** `PC0-2026-08-10-R1`

## 1. Назначение

T1B закрывает failure/recovery composition перед heterogeneous station scale в T2.0.

```text
T composition             TS scale/visual
     |                         |
    T1B                      TS0.4
     |                         |
     +-----------+-------------+
                 v
               T2.0
```

T1B не заменяет TS0.4 и не снимает PC0 blocker T2.0.

## 2. Принятая база

```text
T1A.7 Runtime Recovery / Interest / Scale         ACCEPTED
T1B.0 Runtime Failure Contract                    ACCEPTED
T1B.1 Dependency Failure Propagation              ACCEPTED
T1B.2 Runtime Command Failure Semantics           ACCEPTED
```

Accepted Windows heads:

```text
T1B.0  1f08defe57f592f5e2698da71a1e3180b0875014
T1B.1  faff5f10f42d30a8769ee796fce26d93b8d24bcf
T1B.2  067fa6d8440ecc52771a5b8b5bb7a1e66b075192
```

T1B.2 full world/core regression прошёл на том же preserved checkout: MW9/MW10, RL0-RL3, `main_scene_cli_all 6 PASS / 0 FAIL`, lifecycle `STOPPED`, exit 0 и финальный NX4 marker.

## 3. Архитектурная формула

```text
canonical Construction runtime subjects
        + utility/dependency availability
        ↓ T1B.0/T1B.1 pure projection
proposed failure/recovery state
        ↓ existing ConstructionRuntimeStateStore
canonical runtime truth
        ↓
T1B.2 command operability policy
        ↓
existing executor / ledger / effect rollback
        ↓
existing T1A.7 M0 durability
        ↓
existing ConstructionRuntimeSnapshot / replica / interest-session binding
```

Запрещённые подмены:

```text
failure identity != construct identity
dependency edge != global world dependency identity
failure status != authority route
failure status != presentation truth
interest/session != persistent Construction runtime truth
network delivery order != gameplay correctness
```

## 4. T1B.0 — Runtime Failure Contract — ACCEPTED

Canonical runtime subject получает derived failure fields:

```text
operability: ONLINE / DEGRADED / OFFLINE
failure_codes: POWER_UNAVAILABLE / DATA_UNAVAILABLE / DEPENDENCY_UNAVAILABLE
```

`NONE / OPTIONAL / REQUIRED` requirements определяют OFFLINE/DEGRADED/ONLINE. Projection pure; commit остаётся у существующего runtime store.

## 5. T1B.1 — Dependency Failure Propagation — ACCEPTED

Bounded deterministic propagation только внутри одного canonical construct по существующим runtime IDs.

Правила:

- OFFLINE upstream => dependency unavailable;
- DEGRADED upstream остаётся dependency-available;
- required outage => OFFLINE cascade;
- optional outage => DEGRADED;
- recovery => deterministic ONLINE;
- cycle/duplicate/self/missing/mixed-construct rejected;
- default bounds: 1024 nodes / 4096 edges;
- propagator proposals-only, canonical commit не принадлежит propagator.

## 6. T1B.2 — Runtime Command Failure Semantics — ACCEPTED

Failure-aware handler-policy встроен в существующую executor handler boundary без изменения executor core.

```text
REQUIRE_ONLINE
ALLOW_DEGRADED
ALLOW_OFFLINE
```

Rejection происходит до gameplay handler/effect work, terminal result хранится существующим operation ledger, replay idempotent, exactly-once effect и rollback остаются принятым T1A.5 transaction boundary.

Accepted checkpoint:

```text
docs/checkpoints/2026-08-11_T1B2_RUNTIME_COMMAND_FAILURE_SEMANTICS_ACCEPTED_RU.md
```

## 7. T1B.3 — Recovery / Reconnect Composition — IMPLEMENTED CANDIDATE

Цель:

```text
failure
  -> command rejected + ledgered
  -> runtime checkpoint
  -> server/runtime restart
  -> exact failure truth recovered from existing M0
  -> logical interest re-projected by external authoritative source
  -> new reconnect session receives full recovered baseline
  -> late-interest client receives same full recovered baseline
  -> dependency restored
  -> canonical state returns ONLINE
  -> replicas converge
  -> command becomes executable again
  -> second checkpoint/restart preserves recovery and command replay
```

Новый lab-only adapter:

```text
scripts/labs/t1/t1b/t1b3_recoverable_failure_runtime.gd
```

Он только соединяет принятые блоки:

- `T1A.7` recoverable D0 runtime;
- `T1B.1` bounded failure planner;
- `T1B.2` failure-aware command handler;
- existing `ConstructionRuntimeStateStore`;
- existing `ConstructionRuntimeSnapshot`;
- existing `ConstructionRuntimeReplicaStore`.

Он не создаёт новый persistence format, reconnect protocol, network channel, authority registry или persistent interest truth.

Acceptance:

```text
tests/construction/t1b3_recovery_reconnect_composition_acceptance.gd
RUN_T1B3_RECOVERY_RECONNECT_TESTS.ps1
validation/t1b3-recovery-reconnect-composition-validation.json
```

Scenario:

```text
generator --required--> console --required--> door
     |
     +--optional-----------------------------> lamp
```

Outage:

```text
generator OFFLINE  POWER_UNAVAILABLE
console   OFFLINE  DEPENDENCY_UNAVAILABLE
door      OFFLINE  DEPENDENCY_UNAVAILABLE
lamp      DEGRADED DEPENDENCY_UNAVAILABLE
```

После checkpoint/restart эти состояния должны восстановиться byte/semantic-equivalent через существующий runtime persistence checksum. Старый rejected command replay должен остаться terminal и не менять revision.

Interest после server restart **не объявляется T1B persistence**. Test восстанавливает `client_state` через существующий `restore_client_state()` как projection от внешнего authoritative interest/world-query owner, затем bind нового session должен получить recovered full baseline. Старый session остаётся invalid.

После восстановления dependency все четыре subjects переходят в ONLINE, A/B replicas принимают новый authoritative snapshot, door command снова проходит, а второй checkpoint/restart сохраняет ONLINE + gameplay state + successful command replay.

## 8. Следующий stage после T1B.3

```text
T1B.4 Composition Acceptance
  - production-shaped multi-fixture outage/recovery
  - real M3/ENet clients
  - presentation remains derived
  - full T1B composition acceptance
```

T1B.4 не стартует до focused + full acceptance T1B.3.

## 9. Stop gates

STOP и перенос в owner-program/P0, если потребуется:

- новый authority registry;
- новый persistence repository/coordinator;
- private transaction coordinator;
- global dependency/world-query identity;
- новый network channel/protocol foundation;
- WORLD_WORK_BUDGET scheduler;
- private material ontology;
- correctness через RPC ordering;
- persistent client/session/interest state внутри Construction runtime aggregate.

## 10. Validation protocol T1B.3

Standalone:

```powershell
& $Godot --headless --path . --script res://tests/construction/t1b3_recovery_reconnect_composition_acceptance.gd
```

Focused:

```powershell
.\RUN_T1B3_RECOVERY_RECONNECT_TESTS.ps1 -GodotPath $Godot
```

Runner сначала повторяет accepted T1B.2/T1B.1/T1B.0/T1A.7 chain, затем T1B.3 acceptance.

Если focused green, на том же checkout без fetch/reset:

```powershell
.\RUN_WORLD_REGRESSION_TESTS.ps1
```

Только green pair принимает T1B.3 и открывает T1B.4.

## 11. T2.0 gate остаётся закрытым

```text
C22 MAIN_INTEGRATED
T runtime/composition evidence
TS0.4 1M ceiling classification
PC0 convergence
```
