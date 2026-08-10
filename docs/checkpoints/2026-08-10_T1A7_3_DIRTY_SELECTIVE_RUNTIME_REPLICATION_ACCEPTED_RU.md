# T1A.7.3 — Dirty / Selective Runtime Replication — ACCEPTED

**Дата:** 2026-08-10  
**Ветка:** `feature/t1a7-runtime-recovery-interest-scale`  
**Architecture:** `GLOBAL-P0-2026-08-10-R2`  
**Control:** `PC0-2026-08-10-R1`

## Решение

`T1A.7.3 Dirty / Selective Runtime Replication` принят.

```text
accepted runtime/test boundary:
cab2e1cdcafd831ab9c0cb09123383bf96f5dfe0

focused + full-regression checkout:
c6544100564d2fa55d96b607ccd9ea61c01387b1
```

## Что доказано

Mutation routing больше не требует broadcast-all обхода как основной путь. Construction-domain planner поддерживает reverse projection:

```text
construct_id -> selected logical clients
```

и для canonical runtime mutation строит target set только из relevant active sessions. Dirty subject set определяется сравнением checksum authoritative runtime subjects между предыдущим и текущим snapshot.

Correctness path не ослаблен:

```text
canonical Construction runtime unchanged
ConstructionRuntimeSnapshot unchanged
ConstructionRuntimeReplicaStore unchanged
RESYNC / RELIABLE_ORDERED unchanged
T1A.7.2 full authoritative baseline remains reconnect/resync fallback
```

Не введены новый network channel, transport boundary, authority registry, global interest identity, scheduler foundation, private persistence owner или compact/lossy truth DTO.

## Focused Windows evidence

Godot: `4.7.1.stable.double.custom_build.a13da4feb`.

```text
T1A.4 fixture binding                 PASS 153
C5B runtime contracts                 PASS 32
T1A.5 runtime execution               PASS 67
T1A.5 transactional effects           PASS 36
T1A.7.1 recovery                      PASS 60
NX0 observability                     PASS 150
M3 graphical multiplayer              PASS 77
C5C runtime replication               PASS 29
T1A.6 runtime multiplayer             PASS 25 / 0 failures
T1A.7.2 interest binding              PASS 34
T1A.7.2 late-interest + reconnect     PASS 35
T1A.7.3 dirty selective planner       PASS 44
T1A.7.3 selective M3 processes        PASS 35
focused final marker                  PASS
```

Два transient `Parse JSON failed` сообщения возникли в polling harness при чтении report-файла во время concurrent rewrite. Следующие poll-итерации прочитали JSON успешно, оба process suites завершились PASS со всеми assertions. Это test-harness read-race noise, а не runtime/network failure.

## Full world/core regression

На том же checkout `c654410...`:

```text
RL2 real asteroid multiresolution             PASS 44
RL3 representation-aware network streaming    PASS 175
RL3 representation streaming processes        PASS 37
main_scene_cli_all                             6 PASS / 0 FAIL
lifecycle                                      STOPPED
exit_code                                      0
final marker                                   PASS through NX4
```

Финальный marker:

```text
All world/core regression tests through NX4 client prediction and reconciliation passed.
```

## Status dimensions

```text
SOURCE_ACCEPTED       true
MAIN_INTEGRATED       false
COMPOSITION_VERIFIED  true
PRODUCTION_READY      false
```

## Следующий этап

`T1A.7.4 Scale / Soak Lab`.

Минимальный scale contract:

```text
100 constructs x 10 runtime subjects
1,000 constructs x 10 runtime subjects
10,000 canonical runtime subjects
```

Измеряем targeted-vs-broadcast work/bytes, dirty work per mutation, baseline size, replica apply time, projection time, repeated interest movement/index growth и reconnect baseline cost. Текущий reconnect policy не хранит Construction mutation replay log, поэтому его явный history bound на этом этапе равен `0` и fallback является full authoritative baseline; новый replay subsystem не создаётся ради scale gate.
