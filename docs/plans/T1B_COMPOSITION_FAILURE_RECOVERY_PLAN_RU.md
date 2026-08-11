# T1B — Composition / Failure / Recovery

**Branch:** `feature/t1b-composition-failure-recovery`  
**Parent checkpoint:** `T1A.7 Runtime Recovery / Interest / Scale — ACCEPTED`  
**Architecture:** `GLOBAL-P0-2026-08-10-R2`  
**Control:** `PC0-2026-08-10-R1`

## 1. Итог

T1B завершён и передан в handoff:

```text
T1B.0 Runtime Failure Contract                   ACCEPTED
T1B.1 Dependency Failure Propagation             ACCEPTED
T1B.2 Runtime Command Failure Semantics          ACCEPTED
T1B.3 Recovery / Reconnect Composition           ACCEPTED
T1B.4 Composition Acceptance                     ACCEPTED
T1B aggregate                                   HANDOFF COMPLETE
```

Accepted Windows executable heads:

```text
T1B.0  1f08defe57f592f5e2698da71a1e3180b0875014
T1B.1  faff5f10f42d30a8769ee796fce26d93b8d24bcf
T1B.2  067fa6d8440ecc52771a5b8b5bb7a1e66b075192
T1B.3  3a2a6a3e14f97e070139a00402d0cf0e19238622
T1B.4  88736b1e57a5fb96d80c8842ea983c20d8b833f3
```

T1B.4 focused live M3 process acceptance: `93 assertions, 0 failures`.

Subsequent full world/core regression was executed through the required preserved-checkout sequence and passed with RL2 real asteroid `44`, RL3 `175 + 37`, `main_scene_cli_all 6 PASS / 0 FAIL`, lifecycle `STOPPED`, exit `0`, final NX4 marker.

## 2. Архитектурная формула

```text
canonical Construction runtime subjects
        + utility/dependency availability
        ↓ T1B.0 / T1B.1
explicit ONLINE / DEGRADED / OFFLINE truth
        ↓ existing ConstructionRuntimeStateStore
canonical runtime truth
        ↓ T1B.2
explicit command operability policy
        ↓ existing executor / ledger / rollback
transaction-safe command result
        ↓ accepted T1A.7 / M0
checkpoint / restart recovery
        ↓ external interest + existing M3 snapshot path
reconnect / late-interest replicas
        ↓ derived presenter
visual state
```

Запрещённые подмены сохранены:

```text
failure identity != construct identity
dependency edge != global world dependency identity
failure status != authority route
failure status != presentation truth
interest/session != persistent Construction runtime truth
network delivery order != gameplay correctness
```

## 3. T1B.0 — ACCEPTED

Canonical runtime subjects получают deterministic:

```text
operability: ONLINE / DEGRADED / OFFLINE
failure_codes: POWER_UNAVAILABLE / DATA_UNAVAILABLE / DEPENDENCY_UNAVAILABLE
```

Requirements `NONE / OPTIONAL / REQUIRED` определяют результат. Projection pure; commit остаётся у existing runtime store.

## 4. T1B.1 — ACCEPTED

Bounded deterministic construct-local dependency propagation:

- OFFLINE upstream => dependency unavailable;
- DEGRADED upstream остаётся dependency-available;
- required outage => OFFLINE cascade;
- optional outage => DEGRADED;
- recovery => deterministic ONLINE;
- cycle/duplicate/self/missing/mixed-construct rejected;
- bounds 1024 nodes / 4096 edges;
- planner proposals-only.

## 5. T1B.2 — ACCEPTED

Failure-aware command policies:

```text
REQUIRE_ONLINE
ALLOW_DEGRADED
ALLOW_OFFLINE
```

Rejection происходит до gameplay handler/effect work; existing operation ledger хранит terminal result; replay idempotent; exactly-once effect/rollback остаются existing transaction boundary.

## 6. T1B.3 — ACCEPTED

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

Construction persistence не владеет client/session/interest state.

## 7. T1B.4 — ACCEPTED

Финальный production-shaped live M3 process gate доказал:

```text
server #1 + A/B
 -> live outage
 -> OFFLINE/DEGRADED replication
 -> OPEN_DOOR rejected over M3
 -> M0 checkpoint
 -> server process restart
 -> recovered failure truth
 -> A reconnect + C late join
 -> no Construction visibility before external interest
 -> recovered baselines
 -> terminal rejection replay
 -> dependency recovery
 -> A/C ONLINE convergence
 -> OPEN_DOOR succeeds over M3
 -> A/C presenters derive OPEN
 -> final ONLINE/OPEN checkpoint
```

Focused result:

```text
T1B.4 M3 failure/recovery composition: 93 assertions, 0 failures
```

Full world/core regression after focused PASS:

```text
RL2 real asteroid multiresolution              PASS 44
RL3 representation-aware network streaming     PASS 175
RL3 representation streaming processes         PASS 37
main_scene_cli_all                              6 PASS / 0 FAIL
lifecycle                                      STOPPED
exit_code                                      0
All world/core regression tests through NX4 client prediction and reconciliation passed.
```

## 8. Status dimensions

```text
SOURCE_ACCEPTED       true
MAIN_INTEGRATED       false
COMPOSITION_VERIFIED  true
PRODUCTION_READY      false
```

T1B больше не имеет локальных blockers.

## 9. Следующий шаг — global convergence, не T1B.5

```text
T1B accepted handoff
        │
        │             TS / C22
        │                │
        │         C22 MAIN_INTEGRATED
        │                │
        │         post-merge PC0
        │                │
        │          TS0.4 1M ceiling
        │                │
        └─────── PC0 convergence
                     │
                     ▼
             T2.0 heterogeneous
                base / station
```

Практический порядок:

1. **Не создавать T1B.5.** Зафиксировать текущую ветку как accepted handoff evidence.
2. **C22 / TS0.3:** после отдельного явного разрешения merge accepted `feature/c22-incremental-local-rebuild` в `main`.
3. Запустить post-merge Project Control и выставить `MAIN_INTEGRATED=true` для C22.
4. Создать свежую main-based ветку **TS0.4 1M Research Ceiling**.
5. Прогнать 1M ceiling и классифицировать `PASSABLE / DEGRADED / CURRENT_CEILING_EXCEEDED` с bottleneck telemetry.
6. Свести принятые T runtime/composition/scale evidence и TS0.4 classification через PC0.
7. Только после снятия canonical blocker активировать **T2.0 Real Heterogeneous Base / Station** — уже не synthetic cube, а неоднородная база со множеством типов Construction runtime subjects, зависимостей, локальных мутаций, persistence/reconnect и production proxy rebuild.

## 10. T2.0 global gate

Canonical blocker остаётся без ослабления:

```text
C22_MAIN_INTEGRATED_PLUS_T_RUNTIME_SCALE_EVIDENCE_PLUS_TS0_4_CEILING_CLASSIFICATION_AND_PC0_CONVERGENCE_REQUIRED
```

T1B acceptance закрывает T composition часть этого перехода, но **не** даёт права обходить C22/TS0.4/PC0 convergence.

## 11. Checkpoints

```text
docs/checkpoints/2026-08-11_T1B3_RECOVERY_RECONNECT_COMPOSITION_ACCEPTED_RU.md
docs/checkpoints/2026-08-11_T1B4_COMPOSITION_ACCEPTANCE_ACCEPTED_RU.md
docs/checkpoints/2026-08-11_T1B_COMPOSITION_FAILURE_RECOVERY_ACCEPTED_RU.md
```
