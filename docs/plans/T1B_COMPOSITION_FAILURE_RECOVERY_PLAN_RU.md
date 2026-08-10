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

T1A.7 уже доказал:

- durable runtime recovery через существующий M0 repository/coordinator;
- late-interest/reconnect convergence;
- dirty/selective runtime fan-out;
- headless 10,000 runtime-subject scale;
- final recovery/interest/selective composition.

T1B не дублирует эти foundations. Он добавляет failure semantics и composition поведения поверх существующего runtime truth.

## 3. Архитектурная формула

```text
canonical Construction runtime subject
        +
existing dependency/utility availability
        ↓ pure policy
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
```

## 4. T1B.0 — Runtime Failure Contract

Первый stage определяет generic operability projection:

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
- failure-bearing runtime state должен переживать существующий store/M0 recovery путь;
- ConstructSnapshot не мутируется.

## 5. Следующие T1B stages

После T1B.0:

```text
T1B.1 Dependency Failure Propagation
  - fixture-to-fixture / utility dependency graph
  - bounded propagation
  - deterministic ordering

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

## 6. Stop gates

STOP и перенос в P0/owner-program, если потребуется:

- новый authority registry;
- новый persistence repository/coordinator;
- private transaction coordinator;
- global dependency/world-query identity;
- новый network channel/protocol foundation;
- WORLD_WORK_BUDGET scheduler;
- private material ontology;
- failure correctness через RPC ordering.

## 7. T1B.0 implementation

Файлы:

```text
scripts/construction/behavior/construction_runtime_failure_policy.gd
tests/construction/t1b0_runtime_failure_contracts.gd
RUN_T1B0_RUNTIME_FAILURE_TESTS.ps1
```

Focused runner сначала повторяет принятый T1A.7.5 chain, затем новый T1B.0 contract test.

## 8. T2.0 gate остаётся закрытым

Даже после T1B acceptance T2.0 нельзя объявлять active, пока PC0 не увидит:

```text
C22 MAIN_INTEGRATED
T runtime/composition evidence
TS0.4 1M ceiling classification
PC0 convergence
```

Это разделяет composition correctness и representation-scale evidence, не смешивая ownership.
