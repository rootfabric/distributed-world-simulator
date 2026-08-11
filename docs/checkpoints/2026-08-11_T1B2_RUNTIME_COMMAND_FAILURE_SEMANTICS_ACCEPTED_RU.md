# T1B.2 Runtime Command Failure Semantics — ACCEPTED

Дата: 2026-08-11  
Ветка: `feature/t1b-composition-failure-recovery`  
Точный Windows tested checkout: `067fa6d8440ecc52771a5b8b5bb7a1e66b075192`  
Godot: `4.7.1.stable.double.custom_build.a13da4feb`

## Решение

`T1B.2 Runtime Command Failure Semantics` — **ACCEPTED**.

Статусные измерения:

```text
SOURCE_ACCEPTED       true
MAIN_INTEGRATED       false
COMPOSITION_VERIFIED  true
PRODUCTION_READY      false
```

## Что принято

T1B.2 добавляет fail-closed command operability policy поверх принятого Construction runtime executor, не меняя сам executor core.

```text
existing command validation / ledger / revision fence
        ↓
T1B.2 failure-aware handler
        ↓ allowed only
existing gameplay handler
        ↓
existing state commit + effect commit/rollback
```

Поддержаны политики:

```text
REQUIRE_ONLINE
ALLOW_DEGRADED
ALLOW_OFFLINE
```

Зафиксированные правила:

- undeclared action fail-closed;
- `OFFLINE` rejection происходит до gameplay handler/effect work;
- `DEGRADED + REQUIRE_ONLINE` rejection происходит до gameplay handler/effect work;
- `DEGRADED + ALLOW_DEGRADED` разрешён и явно маркируется `degraded_execution=true`;
- `OFFLINE + ALLOW_OFFLINE` возможен только для явно объявленного action policy;
- rejected operation terminally сохраняется существующим operation ledger;
- rejected replay не вызывает повторную работу;
- разрешённый transactional effect остаётся exactly-once;
- effect commit failure использует принятый T1A.5 rollback и не оставляет partial runtime state/revision.

## Windows acceptance

Пользователь выполнил требуемую T1B.2 последовательность на checkout `067fa6d8440ecc52771a5b8b5bb7a1e66b075192` и сообщил, что всё проходит. В предоставленном фрагменте нет строки с assertion count самого T1B.2, поэтому число не восстанавливается искусственно.

Финальный full world/core regression на том же checkout:

```text
MW9 durable handoff processes                 PASS 225
MW9 lock release retry                        PASS 12
MW10 cross-region Matter transactions         PASS 184
MW10 cross-region Matter processes            PASS 51
RL0 representation contracts                  PASS 92
RL1 matter summary pyramid                    PASS 245
RL2 Matter multiresolution meshing            PASS 153
RL2 real asteroid multiresolution             PASS 44
RL3 representation-aware network streaming    PASS 175
RL3 representation streaming processes        PASS 37
main_scene_cli_all                             6 PASS / 0 FAIL
lifecycle                                      STOPPED
exit_code                                      0
All world/core regression tests through NX4 client prediction and reconciliation passed.
```

## Архитектурные границы

T1B.2 не создаёт:

- новый canonical store;
- новый operation ledger;
- новый transaction coordinator;
- новый persistence repository;
- новый authority registry;
- новый network channel/protocol foundation;
- global dependency/world-query identity;
- WORLD_WORK_BUDGET owner.

`ConstructionAffordanceRuntimeExecutor` остаётся владельцем существующего command/ledger/revision/effect transaction flow; T1B.2 является handler-policy composition.

## Следующий этап

Разблокирован:

```text
T1B.3 Recovery / Reconnect Composition
```

Его цель: доказать `failure -> checkpoint -> restart -> recovered failure truth -> reconnect/late-interest baseline -> dependency recovery -> command re-enabled`, переиспользуя T1A.7 M0 recovery, T1A.7.2 interest/session binding и существующий ConstructionRuntimeSnapshot/replica path.

T2.0 остаётся PC0-blocked до `C22 MAIN_INTEGRATED + TS0.4 ceiling classification + PC0 convergence`.
