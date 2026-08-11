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

T1B не заменяет TS0.4 и не снимает глобальный PC0 blocker T2.0.

## 2. Принятая цепочка

```text
T1A.7 Runtime Recovery / Interest / Scale         ACCEPTED
T1B.0 Runtime Failure Contract                    ACCEPTED
T1B.1 Dependency Failure Propagation              ACCEPTED
T1B.2 Runtime Command Failure Semantics           ACCEPTED
T1B.3 Recovery / Reconnect Composition            ACCEPTED
```

Accepted Windows heads:

```text
T1B.0  1f08defe57f592f5e2698da71a1e3180b0875014
T1B.1  faff5f10f42d30a8769ee796fce26d93b8d24bcf
T1B.2  067fa6d8440ecc52771a5b8b5bb7a1e66b075192
T1B.3  3a2a6a3e14f97e070139a00402d0cf0e19238622
```

T1B.3 был принят только после FIX1. Первый candidate `373cdd4...` не является evidence из-за inherited-member parse collision и false-positive harness `PASS (0 assertions)`. FIX1 устранил обе проблемы; после этого required focused -> full world/core sequence прошла green. Показанный full tail: RL3 `175 + 37`, `main_scene_cli_all 6 PASS / 0 FAIL`, lifecycle `STOPPED`, exit 0 и финальный NX4 marker.

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
existing interest/session + ConstructionRuntimeSnapshot/replica
        ↓
derived M3 client presentation
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

Canonical runtime subject получает `operability: ONLINE / DEGRADED / OFFLINE` и deterministic `failure_codes`. `NONE / OPTIONAL / REQUIRED` requirements определяют результат. Projection pure; commit остаётся у existing runtime store.

## 5. T1B.1 — Dependency Failure Propagation — ACCEPTED

Bounded deterministic construct-local propagation по существующим runtime IDs:

- OFFLINE upstream => dependency unavailable;
- DEGRADED upstream остаётся dependency-available;
- required outage => OFFLINE cascade;
- optional outage => DEGRADED;
- recovery => deterministic ONLINE;
- cycle/duplicate/self/missing/mixed-construct rejected;
- bounds 1024 nodes / 4096 edges;
- planner proposals-only.

## 6. T1B.2 — Runtime Command Failure Semantics — ACCEPTED

Failure-aware handler-policy в существующей executor handler boundary:

```text
REQUIRE_ONLINE
ALLOW_DEGRADED
ALLOW_OFFLINE
```

Rejection происходит до gameplay handler/effect work, existing operation ledger хранит terminal result, replay idempotent, exactly-once effect/rollback остаются принятым T1A.5 boundary.

## 7. T1B.3 — Recovery / Reconnect Composition — ACCEPTED

Доказано:

```text
failure
 -> command rejected + ledgered
 -> M0 checkpoint
 -> fresh runtime restart
 -> recovered failure truth
 -> external authoritative interest projection restore
 -> reconnect + late-interest full baselines
 -> dependency recovery
 -> ONLINE replicas
 -> command re-enabled
 -> second checkpoint/restart + replay
```

Construction persistence не владеет client/session/interest state. Interest после restart подаётся отдельно внешним authoritative source.

Checkpoint:

```text
docs/checkpoints/2026-08-11_T1B3_RECOVERY_RECONNECT_COMPOSITION_ACCEPTED_RU.md
```

## 8. T1B.4 — Composition Acceptance — IMPLEMENTED CANDIDATE

T1B.4 — финальный production-shaped process gate для T1B.

Новые T1B-owned lab/process файлы:

```text
scripts/labs/t1/t1b/t1b4_m3_failure_server_adapter.gd
tools/runtime/t1b4_runtime_server.gd
tools/runtime/t1b4_runtime_client.gd
tests/construction/t1b4_m3_failure_recovery_composition_acceptance.gd
RUN_T1B4_COMPOSITION_ACCEPTANCE.ps1
validation/t1b4-composition-acceptance-validation.json
```

Server adapter наследует accepted T1A.7 interest-aware M3 adapter и меняет только runtime factory на accepted T1B.3 recoverable failure runtime. Existing M3 control/resync channels, authority/session rules и ConstructionRuntimeSnapshot остаются неизменными.

Client process использует accepted T1A.6 graphical M3 client adapter с existing `T1A6 D0 RuntimePresenter`.

### Process scenario

```text
server process #1
  + client A in interest
  + client B in interest
        ↓
construct-local outage through T1B.1/T1B.3 runtime
        ↓
A/B receive OFFLINE/DEGRADED authoritative snapshots
        ↓
A OPEN_DOOR command over real M3 => OFFLINE rejection
        ↓
M0 checkpoint
        ↓
kill server + clients
        ↓
server process #2, same durable M0 root
        ↓
recovered OFFLINE truth before clients regain Construction visibility
        ↓
A reconnect logical identity + C late join
        ↓
external interest projection re-applied explicitly
        ↓
A/C receive recovered failure baseline
        ↓
replay rejected operation remains terminal
        ↓
dependency restoration
        ↓
A/C converge ONLINE
        ↓
OPEN_DOOR succeeds over real M3
        ↓
both derived presenters converge OPEN
        ↓
final ONLINE/OPEN checkpoint
```

Critical ownership proof: after server process restart no Construction runtime snapshot may reach A/C before external interest selection is re-applied. Durable failure truth comes from M0; visibility comes from interest; transport only delivers current authoritative state.

Harness has explicit `scenario_completed` fail-closed marker; an early parse/runtime/process abort cannot emit a successful acceptance.

## 9. T1B.4 validation protocol

Focused Windows gate:

```powershell
.\RUN_T1B4_COMPOSITION_ACCEPTANCE.ps1 -GodotPath $Godot
```

Runner first reruns accepted T1B.3 parent chain, performs editor parse/import, then launches the real M3 process scenario.

A valid result must end with:

```text
T1B.4 M3 failure/recovery composition: <N> assertions, 0 failures
T1B.4 composition focused gate passed.
```

После focused PASS, **на том же checkout без fetch/reset**:

```powershell
.\RUN_WORLD_REGRESSION_TESTS.ps1
```

Только green pair закрывает T1B.4 и aggregate T1B.

## 10. После T1B.4

Если T1B.4 accepted:

```text
T1B aggregate handoff complete
SOURCE_ACCEPTED = true
COMPOSITION_VERIFIED = true
MAIN_INTEGRATED = false until explicit integration
PRODUCTION_READY = false until global convergence gates
```

Следующий Construction stage T2.0 **не стартует автоматически**.

## 11. Stop gates

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

## 12. T2.0 global gate остаётся закрытым

```text
C22_MAIN_INTEGRATED
T runtime/composition evidence
TS0.4 1M ceiling classification
PC0 convergence
```

Canonical blocker string:

```text
C22_MAIN_INTEGRATED_PLUS_T_RUNTIME_SCALE_EVIDENCE_PLUS_TS0_4_CEILING_CLASSIFICATION_AND_PC0_CONVERGENCE_REQUIRED
```
