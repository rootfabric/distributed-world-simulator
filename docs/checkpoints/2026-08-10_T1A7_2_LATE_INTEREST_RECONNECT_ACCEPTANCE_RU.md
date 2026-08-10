# T1A.7.2 — Late-Interest Baseline + Reconnect — ACCEPTED

**Дата:** 2026-08-10  
**Ветка:** `feature/t1a7-runtime-recovery-interest-scale`  
**Accepted runtime head:** `d41d3d3721b61cc0464e1c5693ccaa4521b7819a`  
**Final gate checkout/control head:** `a851d1f8e680c253109e7ddb86ef8032276b17fb`  
**Engine:** `Godot 4.7.1.stable.double.custom_build.a13da4feb`

## Решение

`T1A.7.2 Late-Interest Baseline + Reconnect` принят.

```text
SOURCE_ACCEPTED       true
MAIN_INTEGRATED       false
COMPOSITION_VERIFIED  true
PRODUCTION_READY      false
```

## Что доказано

```text
fresh client outside interest -> no Construction runtime baseline
enter interest -> current authoritative full baseline
late client -> current runtime state, not historical initial state
leave interest -> unrelated runtime mutation suppressed
re-enter interest -> current authoritative baseline
transport reconnect -> retained logical interest bound to new session
old transport session -> cannot bypass selection fence
```

Correctness path остаётся существующим:

```text
ConstructionRuntimeSnapshot
  -> M3/NX RESYNC
  -> RELIABLE_ORDERED
  -> ConstructionRuntimeReplicaStore
```

Новых global interest identity, authority registry, persistence repository, network channel или transport boundary не создано.

## Первый Windows run и FIX1

Первый run прошёл все inherited gates через T1A.6, но новый binding test упал `18 / 34` из-за локальной ошибки чтения common result envelope. `_normalize_construct_ids()` возвращал `construct_ids` в `details`, а два caller-а читали top-level key.

FIX1 `d41d3d3721b61cc0464e1c5693ccaa4521b7819a` изменил только эти два чтения. Interest/reconnect semantics и архитектура не менялись.

## Финальная проверка

FIX1 focused gate выполнен перед full regression и прошёл; точные assertion totals новых T1A.7.2 тестов не переносились в финальный пользовательский transcript, поэтому здесь они не выдумываются.

Поставленный пользователем финальный world/core regression:

```text
RL3 representation-aware network streaming    PASS 175
RL3 representation streaming processes        PASS 37
main_scene_cli_all                             6 PASS / 0 FAIL
lifecycle                                      STOPPED
exit_code                                      0
All world/core regression tests through NX4 client prediction and reconciliation passed.
```

## Архитектурный итог

T1A.7.2 использует:

```text
MW7 pattern
  revisioned logical selection
  session fence separated from logical state
  reconnect retention

M3/NX
  existing peer/session ownership
  existing reliable RESYNC path

T1A.6
  authoritative full runtime snapshot
  replica stale/revision fence
```

Construction хранит только domain projection interest state и не становится владельцем global query/spatial fabric.

## Следующий этап

`T1A.7.3 Dirty / Selective Runtime Replication`.

Цель:

```text
canonical runtime mutation
  -> dirty construct/runtime-id detection
  -> per-client relevant construct projection
  -> exact reliable update only to relevant active sessions
  -> full baseline/resync remains correctness fallback
```

На T1A.7.3 нельзя делать runtime truth lossy, вводить новый network channel namespace или превращать interest/LOD/camera identity в permanent Construction identity.
