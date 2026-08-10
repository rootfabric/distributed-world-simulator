# T1B — Composition / Failure / Recovery

**Branch:** `feature/t1b-composition-failure-recovery`  
**Parent checkpoint:** `T1A.7 Runtime Recovery / Interest / Scale — ACCEPTED`  
**Architecture:** `GLOBAL-P0-2026-08-10-R2`  
**Control:** `PC0-2026-08-10-R1`

## 1. Назначение

T1B закрывает composition/failure semantics перед переходом к реальной heterogeneous station scale в T2.0.

Canonical roadmap ведёт две параллельные линии:

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

## 2. Уже принятая база

T1A.7 доказал durable runtime recovery, late-interest/reconnect convergence, dirty/selective runtime fan-out, 10,000 runtime-subject scale и final recovery/interest/selective composition.

T1B.0 Runtime Failure Contract также ACCEPTED на exact Windows checkout `1f08defe57f592f5e2698da71a1e3180b0875014`: focused T1B.0 39 assertions PASS и полный world/core regression PASS с RL3 175 + 37, `main_scene_cli_all 6 PASS / 0 FAIL`, lifecycle `STOPPED` и финальным NX4 marker.

## 3. Архитектурная формула

```text
canonical Construction runtime subject
        +
existing dependency/utility availability
        ↓ pure policy / pure propagation planner
proposed next runtime state
        ↓ existing revision fence/store
canonical runtime commit
        ↓
existing T1A.7 persistence / replication / recovery
```

Failure state не является новым Construct aggregate.

```text
failure identity != construct identity
failure status != authority route
failure status != presentation state
failure status != network message identity
local dependency edge != global world dependency identity
```

## 4. T1B.0 — Runtime Failure Contract — ACCEPTED

Generic operability:

```text
ONLINE
DEGRADED
OFFLINE
```

Dependency classes:

```text
power
data
dependency
```

Requirement levels:

```text
NONE
OPTIONAL
REQUIRED
```

Failure codes:

```text
POWER_UNAVAILABLE
DATA_UNAVAILABLE
DEPENDENCY_UNAVAILABLE
```

Правила:

- missing REQUIRED dependency => `OFFLINE`;
- missing OPTIONAL dependency при отсутствии required failure => `DEGRADED`;
- всё доступно => `ONLINE` + empty failure codes;
- projection deterministic;
- существующие gameplay fields subject state сохраняются;
- commit проходит через existing `ConstructionRuntimeStateStore.update_subject()` и revision fence;
- failure-bearing runtime state переживает существующий store/M0 recovery путь;
- ConstructSnapshot не мутируется.

Accepted checkpoint:

```text
docs/checkpoints/2026-08-11_T1B0_RUNTIME_FAILURE_CONTRACT_ACCEPTED_RU.md
```

## 5. T1B.1 — Dependency Failure Propagation — IMPLEMENTED CANDIDATE

T1B.1 добавляет bounded deterministic propagation **только внутри одного canonical construct**.

Вход:

```text
existing runtime subjects
+ per-runtime T1B.0 requirements
+ direct power/data availability
+ local directed edges between existing runtime IDs
```

Выход:

```text
pure ordered proposal set
```

Сам propagator state не коммитит. Canonical commit по-прежнему выполняется существующим `ConstructionRuntimeStateStore.update_subject()`.

Текущий acceptance graph:

```text
generator -> bus -> console -> door
              |
              +-------> lamp
```

При потере direct power у generator:

```text
generator  OFFLINE  POWER_UNAVAILABLE
bus        OFFLINE  DEPENDENCY_UNAVAILABLE
console    OFFLINE  DEPENDENCY_UNAVAILABLE
door       OFFLINE  DEPENDENCY_UNAVAILABLE
lamp       DEGRADED DEPENDENCY_UNAVAILABLE   # optional dependency
```

После восстановления generator весь required-chain детерминированно возвращается в `ONLINE`.

Правила T1B.1:

- propagation order — deterministic topological order;
- input ordering не влияет на output;
- только `OFFLINE` upstream делает dependency unavailable;
- `DEGRADED` upstream остаётся dependency-available;
- cycle rejected;
- duplicate/self edge rejected;
- edge на отсутствующий runtime ID rejected;
- mixed-construct subject set rejected;
- default bound: `1024` nodes / `4096` edges;
- node/edge bound overflow rejected до commit;
- никаких persistent dependency IDs/registries не создаётся.

Файлы:

```text
scripts/construction/behavior/construction_runtime_dependency_failure_propagator.gd
tests/construction/t1b1_dependency_failure_propagation_acceptance.gd
RUN_T1B1_DEPENDENCY_FAILURE_TESTS.ps1
validation/t1b1-dependency-failure-propagation-validation.json
```

## 6. Следующие T1B stages

```text
T1B.2 Runtime Command Failure Semantics
  - commands against OFFLINE/DEGRADED subjects
  - explicit rejection/degraded policy
  - transactional effects remain atomic

T1B.3 Recovery / Reconnect Composition
  - fail -> checkpoint -> restart -> recover
  - late interest/reconnect receives current failure truth
  - restore dependency -> canonical recovery transition

T1B.4 Composition Acceptance
  - multi-fixture outage/recovery scenario
  - real M3 replicas/presentation derived from canonical runtime
  - full world/core regression
```

T1B может уточняться по evidence, но не имеет права создавать новый global foundation.

## 7. Stop gates

STOP и перенос в P0/owner-program, если потребуется:

- новый authority registry;
- новый persistence repository/coordinator;
- private transaction coordinator;
- global dependency/world-query identity;
- новый network channel/protocol foundation;
- WORLD_WORK_BUDGET scheduler;
- private material ontology;
- failure correctness через RPC ordering.

## 8. Validation protocol T1B.1

Focused Windows gate:

```powershell
.\RUN_T1B1_DEPENDENCY_FAILURE_TESTS.ps1 -GodotPath $Godot
```

Runner повторяет принятый T1B.0/T1A.7 focused chain и затем T1B.1 acceptance.

Если focused green, на **том же checkout без fetch/reset**:

```powershell
.\RUN_WORLD_REGRESSION_TESTS.ps1
```

Только green pair принимает T1B.1 и открывает T1B.2.

## 9. T2.0 gate остаётся закрытым

Даже после T1B acceptance T2.0 нельзя объявлять active, пока PC0 не увидит:

```text
C22 MAIN_INTEGRATED
T runtime/composition evidence
TS0.4 1M ceiling classification
PC0 convergence
```

Это разделяет composition correctness и representation-scale evidence, не смешивая ownership.
