# T1B.0 Runtime Failure Contract — ACCEPTED

Дата: 2026-08-11

Ветка: `feature/t1b-composition-failure-recovery`

Parent: `T1A.7 Runtime Recovery / Interest / Scale — ACCEPTED`

## Решение

`ACCEPTED`

Status dimensions:

```text
SOURCE_ACCEPTED       true
MAIN_INTEGRATED       false
COMPOSITION_VERIFIED  true
PRODUCTION_READY      false
```

## Tested checkout

Один и тот же Windows checkout использован для focused и полного world/core regression:

```text
1f08defe57f592f5e2698da71a1e3180b0875014
```

Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

## Focused evidence

```text
T1A.6 multiplayer                    PASS 25
T1A.7.2 interest binding             PASS 34
T1A.7.2 late-interest/reconnect      PASS 35
T1A.7.3 dirty/selective              PASS 44
T1A.7.3 selective processes          PASS 35
T1A.7.4 scale/soak                   PASS 2394 / 2 cases
T1A.7.5 composition                  PASS 56
T1B.0 runtime failure contracts      PASS 39
```

T1B.0 доказал pure/revisioned failure semantics внутри существующего canonical Construction runtime state:

```text
ONLINE
DEGRADED
OFFLINE
```

с requirement levels `NONE / OPTIONAL / REQUIRED` и codes `POWER_UNAVAILABLE / DATA_UNAVAILABLE / DEPENDENCY_UNAVAILABLE`.

Failure projection не меняет ConstructSnapshot, не создаёт новый aggregate/store и commits через существующий `ConstructionRuntimeStateStore.update_subject()` revision fence.

## Full world/core regression

На том же checkout:

```text
RL3 representation-aware network streaming     PASS 175
RL3 representation streaming processes         PASS 37
main_scene_cli_all                              6 PASS / 0 FAIL
lifecycle                                       STOPPED
exit_code                                       0
All world/core regression tests through NX4 client prediction and reconciliation passed.
```

## Architecture ownership

T1B.0 не создаёт:

- новый authority registry;
- persistence repository/coordinator;
- transaction coordinator;
- network channel/protocol foundation;
- global dependency identity;
- material ontology;
- WORLD_WORK_BUDGET owner.

Persistence/recovery остаётся на принятом T1A.7 M0 пути, network correctness — на существующем ConstructionRuntimeSnapshot/M3/NX пути.

## Следующий stage

```text
T1B.1 Dependency Failure Propagation
```

T2.0 остаётся blocked до `C22 MAIN_INTEGRATED + TS0.4 ceiling classification + PC0 convergence`.
