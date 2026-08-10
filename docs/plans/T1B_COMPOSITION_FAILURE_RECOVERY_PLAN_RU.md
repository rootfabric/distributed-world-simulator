# T1B — Composition / Failure / Recovery

**Branch:** `feature/t1b-composition-failure-recovery`  
**Parent checkpoint:** `T1A.7 Runtime Recovery / Interest / Scale — ACCEPTED`  
**Architecture:** `GLOBAL-P0-2026-08-10-R2`  
**Control:** `PC0-2026-08-10-R1`

## 1. Назначение

T1B закрывает composition/failure semantics перед переходом к реальной heterogeneous station scale в T2.0.

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

T1A.7 доказал durable runtime recovery, late-interest/reconnect convergence, dirty/selective runtime fan-out и 10,000 runtime-subject scale.

T1B.0 `Runtime Failure Contract` — ACCEPTED на exact Windows checkout `1f08defe57f592f5e2698da71a1e3180b0875014`. Он ввёл pure projection `ONLINE / DEGRADED / OFFLINE` по `NONE / OPTIONAL / REQUIRED` requirements и explicit failure codes без второго aggregate/store.

T1B.1 `Dependency Failure Propagation` — ACCEPTED на required preserved checkout `faff5f10f42d30a8769ee796fce26d93b8d24bcf`. Он добавил bounded deterministic construct-local propagation по существующим runtime IDs. Финальный full regression подтвердил MW10/RL0-RL3, `main_scene_cli_all 6 PASS / 0 FAIL`, `STOPPED`, exit 0 и NX4 marker.

Принятые правила T1B.1:

- OFFLINE upstream => dependency unavailable;
- DEGRADED upstream => dependency остаётся available;
- required outage => OFFLINE cascade;
- optional outage => DEGRADED;
- recovery детерминированно возвращает ONLINE;
- cycle/duplicate/self/missing/mixed-construct rejected;
- bounds: 1024 nodes / 4096 edges;
- propagator pure: proposals only, commit остаётся у `ConstructionRuntimeStateStore`.

## 3. Архитектурная формула

```text
canonical Construction runtime subject
        +
existing utility/dependency availability
        ↓ pure policy / propagation
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

## 4. T1B.2 — Runtime Command Failure Semantics — IMPLEMENTED CANDIDATE

T1B.2 связывает canonical operability с уже существующим `ConstructionAffordanceRuntimeExecutor`, но **не изменяет transactional executor core**.

```text
command
  ↓
existing executor validation + operation ledger + revision fence
  ↓
T1B.2 failure-aware handler policy
  ↓ allowed only
existing gameplay handler
  ↓
existing runtime state commit + effect commit/rollback
```

Implementation:

```text
scripts/construction/behavior/construction_runtime_command_failure_handler.gd
tests/construction/t1b2_runtime_command_failure_semantics_acceptance.gd
RUN_T1B2_COMMAND_FAILURE_TESTS.ps1
validation/t1b2-runtime-command-failure-semantics-validation.json
```

Action policy levels:

```text
REQUIRE_ONLINE
ALLOW_DEGRADED
ALLOW_OFFLINE
```

Semantics:

- undeclared action fails closed;
- `OFFLINE + REQUIRE_ONLINE/ALLOW_DEGRADED` => `CONSTRUCTION_RUNTIME_SUBJECT_OFFLINE`;
- `DEGRADED + REQUIRE_ONLINE` => `CONSTRUCTION_RUNTIME_SUBJECT_DEGRADED`;
- `DEGRADED + ALLOW_DEGRADED` can execute and reports `degraded_execution=true`;
- `OFFLINE + ALLOW_OFFLINE` permits only deliberately declared safe operations such as diagnostic/reset-class actions;
- rejection happens before base handler/effect committer;
- terminal rejection uses the existing operation ledger and replay is idempotent;
- allowed transactional effect remains exactly-once;
- effect commit failure still rolls runtime state/revision back through the accepted T1A.5 transactional boundary;
- wrapper does not own canonical state, ledger or transaction commit.

T1B.2 не добавляет новый command bus, operation ledger, transaction coordinator, authority registry, network protocol или persistence path.

## 5. Следующие T1B stages

```text
T1B.3 Recovery / Reconnect Composition
  - fail -> checkpoint -> restart -> recover
  - current operability/dependency state survives recovery
  - reconnect/late-interest receives current failure truth
  - restore dependency -> canonical recovery transition
  - command policy remains correct after recovery

T1B.4 Composition Acceptance
  - multi-fixture outage/recovery scenario
  - real M3 replicas/presentation derived from canonical runtime
  - full world/core regression
```

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

## 7. Validation protocol T1B.2

Standalone:

```powershell
& $Godot --headless --path . --script res://tests/construction/t1b2_runtime_command_failure_semantics_acceptance.gd
```

Focused:

```powershell
.\RUN_T1B2_COMMAND_FAILURE_TESTS.ps1 -GodotPath $Godot
```

Runner повторяет accepted T1B.1/T1B.0/T1A.7 chain и затем T1B.2 acceptance.

Если focused green, на **том же checkout без fetch/reset**:

```powershell
.\RUN_WORLD_REGRESSION_TESTS.ps1
```

Только green pair принимает T1B.2 и открывает T1B.3.

## 8. T2.0 gate остаётся закрытым

Даже после T1B acceptance T2.0 нельзя объявлять active, пока PC0 не увидит:

```text
C22 MAIN_INTEGRATED
T runtime/composition evidence
TS0.4 1M ceiling classification
PC0 convergence
```

Это разделяет composition correctness и representation-scale evidence, не смешивая ownership.
