# T1B.1 — Dependency Failure Propagation — ACCEPTED

Дата: 2026-08-11  
Ветка: `feature/t1b-composition-failure-recovery`  
Архитектура: `GLOBAL-P0-2026-08-10-R2`  
Control plane: `PC0-2026-08-10-R1`

## Решение

```text
T1B.1 Dependency Failure Propagation — ACCEPTED
SOURCE_ACCEPTED      = true
MAIN_INTEGRATED      = false
COMPOSITION_VERIFIED = true
PRODUCTION_READY     = false
```

Formal tested checkout по обязательной последовательности запуска:

```text
faff5f10f42d30a8769ee796fce26d93b8d24bcf
```

Пользователь подтвердил, что focused и full gates проходят. Финальный предоставленный full-regression фрагмент подтверждает:

```text
MW10 cross-region Matter processes              PASS 51
RL0 representation contracts                    PASS 92
RL1 matter summary pyramid                      PASS 245
RL2 Matter multiresolution meshing              PASS 153
RL2 real asteroid multiresolution               PASS 44
RL3 representation-aware network streaming      PASS 175
RL3 representation streaming processes          PASS 37
main_scene_cli_all                               6 PASS / 0 FAIL
lifecycle                                        STOPPED
exit_code                                        0
All world/core regression tests through NX4 client prediction and reconciliation passed.
```

Assertion count самого T1B.1 в финальном присланном фрагменте не показан и поэтому не выдумывается; focused результат классифицирован как `PASS_BY_USER_EXECUTION_SEQUENCE`.

## Принятые семантики

T1B.1 использует только существующие runtime IDs внутри одного canonical construct:

```text
generator -> bus -> console -> door
              |
              +-------> lamp
```

- `OFFLINE` upstream делает dependency unavailable;
- `DEGRADED` upstream остаётся dependency-available;
- required dependency outage каскадирует `OFFLINE`;
- optional dependency outage даёт `DEGRADED`;
- recovery детерминированно возвращает runtime subjects в `ONLINE`;
- input order не влияет на результат;
- cycle / duplicate / self edge / missing runtime / mixed construct отвергаются;
- bounds: 1024 nodes / 4096 edges;
- propagator выдаёт proposals и не коммитит canonical state самостоятельно.

## Ownership

Не создано:

- global dependency graph owner;
- новый Construct/runtime store;
- persistence repository/coordinator;
- transaction coordinator;
- authority registry;
- network channel/protocol;
- WORLD_QUERY_FABRIC identity;
- WORLD_WORK_BUDGET scheduler.

Commit остаётся обязанностью существующего `ConstructionRuntimeStateStore`.

## Следующий этап

```text
T1B.2 Runtime Command Failure Semantics
```

T2.0 по-прежнему заблокирован до `C22 MAIN_INTEGRATED + TS0.4 ceiling classification + PC0 convergence`.
