# T1A.7.5 — Composition Acceptance — ACCEPTED

Дата: 2026-08-11  
Ветка: `feature/t1a7-runtime-recovery-interest-scale`  
Architecture: `GLOBAL-P0-2026-08-10-R2`  
Control: `PC0-2026-08-10-R1`

## Решение

`T1A.7.5 Composition Acceptance` принят.

```text
SOURCE_ACCEPTED       true
MAIN_INTEGRATED       false
COMPOSITION_VERIFIED  true
PRODUCTION_READY      false
```

Production runtime dependency head:

```text
cab2e1cdcafd831ab9c0cb09123383bf96f5dfe0
```

Exact Windows focused + full-regression checkout:

```text
1430284c3e523d9292804be2fc347ac1f70d39a6
```

Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

## Focused acceptance

После test-harness FIX1 `a76afddd1d82e7d11bf1e72819580cd90db60448` полный composition runner прошёл:

```text
T1A.4                                  PASS 153
C5B                                    PASS 32
T1A.5                                  PASS 67
T1A.5 transactional                    PASS 36
T1A.7 recovery                         PASS 60
NX0                                    PASS 150
M3 graphical                           PASS 77
C5C                                    PASS 29
T1A.6 multiplayer                      PASS 25
T1A.7.2 interest binding               PASS 34
T1A.7.2 late-interest/reconnect        PASS 35
T1A.7.3 dirty/selective planner        PASS 44
T1A.7.3 selective processes            PASS 35
T1A.7.4 scale/soak                     PASS 2394 / 2 cases
T1A.7.5 composition                    PASS 56
final focused marker                   PASS
```

T1A.7.5 composition подтверждает связку:

```text
recovered canonical runtime state
  -> authoritative runtime snapshot
  -> logical interest + transport-session fence
  -> selective replication planner
  -> relevant replica mutation
  -> leave interest / zero irrelevant mutation
  -> re-entry current full baseline
  -> reconnect new transport session
  -> retained logical interest revision
  -> authoritative replica convergence
```

## Scale evidence

Большой synthetic case:

```text
canonical runtime subjects      10,000
broadcast baseline messages     32,000
projected baseline messages        800
broadcast baseline bytes   147,228,480
projected baseline bytes      3,680,627
mutation iterations                256
targeted deliveries              1,024
avoided peer deliveries          7,168
planner failures                     0
interest moves                     512
interest-move memory delta     133,036 B
reconnect                    FULL_AUTHORITATIVE_BASELINE
mutation replay-history bound         0
Node3D per subject required         false
```

Это evidence bounded projection/fan-out, а не claim production-ready 10k gameplay scene.

## Full world/core regression

На том же checkout без fetch/reset пользователь выполнил `RUN_WORLD_REGRESSION_TESTS.ps1`.

В предоставленном финальном tail:

```text
RL3 representation streaming processes PASS 37
main_scene_cli_all                      6 PASS / 0 FAIL
lifecycle                               STOPPED
exit_code                               0
All world/core regression tests through NX4 client prediction and reconciliation passed.
```

Финальный pasted tail не повторял строку RL3 representation-aware `175`, поэтому этот checkpoint не реконструирует этот счётчик из предыдущих прогонов.

## Non-blocking debt

T1A.7.2 acceptance harness всё ещё может один раз залогировать transient `JSON.parse_string` error при чтении result file в окно его перезаписи. В финальном focused run это произошло, но сам T1A.7.2 завершился `PASS (35 assertions)`. Это logging/test-harness debt, а не runtime semantic failure.

## Архитектурная граница

T1A.7.5 не создаёт:

- новый canonical Construction truth;
- новый persistence repository/coordinator;
- authority registry;
- global interest identity;
- network channel или transport boundary;
- compact delta DTO;
- global scheduler / WORLD_WORK_BUDGET.

## Следующий переход

T1A.7.5 закрывает весь `T1A.7 Runtime Recovery / Interest / Scale`.

`T2.0` не активируется автоматически: PC0 требует до него C22 `MAIN_INTEGRATED`, TS0.4 1M ceiling classification и convergence audit. Следующий T-side этап — readiness/convergence preflight, который может готовить контракт T2 без присвоения себе TS или P1 foundations.
