# T1B.4 Composition Acceptance — ACCEPTED

**Дата:** 2026-08-11  
**Branch:** `feature/t1b-composition-failure-recovery`  
**Architecture:** `GLOBAL-P0-2026-08-10-R2`  
**Control:** `PC0-2026-08-10-R1`  
**Parent:** `T1B.3 Recovery / Reconnect Composition — ACCEPTED`

## Решение

`T1B.4 Composition Acceptance` принят.

Accepted executable Windows checkout:

```text
88736b1e57a5fb96d80c8842ea983c20d8b833f3
```

Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

## Focused acceptance

`RUN_T1B4_COMPOSITION_ACCEPTANCE.ps1` / live M3 process composition:

```text
T1B.4 M3 failure/recovery composition: 93 assertions, 0 failures
```

Подтверждено process-level:

- live outage разошёлся в canonical OFFLINE/DEGRADED truth;
- `OPEN_DOOR` против OFFLINE door был отвергнут через real M3;
- M0 checkpoint выполнен до restart;
- dedicated-server process перезапущен на том же durable root;
- failure truth восстановлен из M0;
- reconnect и late-interest replicas получили recovered baseline только после external interest projection;
- terminal OFFLINE rejection replay пережил restart;
- dependency recovery вернул construct в ONLINE;
- post-recovery `OPEN_DOOR` прошёл через M3;
- A/C presenters вывели OPEN из replicated canonical runtime;
- final ONLINE/OPEN checkpoint успешен;
- failure-plan/checkpoint failures отсутствуют;
- reconnect, late join и server shutdown clean.

## Full world/core regression

Full regression был запущен **без fetch/reset после focused PASS**, то есть по обязательной preserved-checkout последовательности на том же executable checkout.

Из предоставленного финального tail:

```text
RL2 real asteroid multiresolution              PASS 44
RL3 representation-aware network streaming     PASS 175
RL3 representation streaming processes         PASS 37
main_scene_cli_all                              6 PASS / 0 FAIL
lifecycle                                      STOPPED
exit_code                                      0
All world/core regression tests through NX4 client prediction and reconciliation passed.
```

Report:

```text
C:\Godot\lunar-world-t1-construct\artifacts\test-results\world-regression-summary.json
```

## Архитектурный результат

T1B.4 не вводит новый canonical store, persistence repository/format, transaction coordinator, authority registry, network channel/protocol, reconnect protocol, global interest/dependency identity, material ontology или `WORLD_WORK_BUDGET` owner.

Ownership остаётся разделён:

```text
Construction runtime truth      -> CONSTRUCTION
persistence / recovery          -> R3 / M0 / MW
network replication policy      -> NX
interest / world query          -> P0/P1 external authoritative projection
transaction boundary            -> existing P0 model
presentation                    -> derived domain adapters
```

## Status dimensions

```text
SOURCE_ACCEPTED       true
MAIN_INTEGRATED       false
COMPOSITION_VERIFIED  true
PRODUCTION_READY      false
```

`PRODUCTION_READY=false`, потому что T2.0 всё ещё заблокирован глобальным convergence gate.

## Следующий шаг

`T1B.5` не создаётся. T1B aggregate завершён и передаётся в global convergence.

Canonical T2.0 blocker остаётся без изменений:

```text
C22_MAIN_INTEGRATED_PLUS_T_RUNTIME_SCALE_EVIDENCE_PLUS_TS0_4_CEILING_CLASSIFICATION_AND_PC0_CONVERGENCE_REQUIRED
```
