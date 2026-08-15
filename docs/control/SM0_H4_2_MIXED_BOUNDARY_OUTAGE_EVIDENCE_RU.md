# SM0 H4.2 — runtime evidence: mixed-boundary dual-authority outage campaign

Статус: **BRANCH-LOCAL EXPERIMENTAL RUNTIME EVIDENCE**.

Это не global acceptance, не production acceptance и не разрешение включать `SERVER_HANDOFF` в V0-S1. Cross-server authority остаётся CRITICAL-risk областью. Этот документ фиксирует только runtime evidence экспериментальной SM0 ветки.

## Проверенный runtime SHA

Exact HEAD, на котором выполнены успешные DEFAULT и FINAL Windows-прогоны H4.2:

`3e95dd881e55784bfe15a9901e7d1fe9bac143f9`

Branch:

`feature/sm0-two-authority-seamless-handoff-lab`

Godot:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`

Windows executable:

`C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe`

Primary runner:

`RUN_V0_SM0_MIXED_BOUNDARY_OUTAGE_ACCEPTANCE.ps1`

Windows PowerShell FIX2 launcher:

`RUN_V0_SM0_MIXED_BOUNDARY_OUTAGE_ACCEPTANCE_FIX2.ps1`

Fault profile:

`h4-mixed-boundary-dual-outage-v1`

Boundary matrix:

`INFLIGHT_RETIRE -> COMMIT_DECISION -> ACTIVATION -> repeat`

## Scope H4.2

H4.2 проверяет, что один непрерывный client process может последовательно переживать total outage обоих authority не только в одном устойчивом crash boundary, а при ротации между тремя существенно различными durable состояниями handoff transaction.

Для очередного handoff campaign выбирает одну из границ:

1. `INFLIGHT_RETIRE`: source уже durably `SOURCE_RETIRED`, target только durably `TARGET_PREPARED`; COMMIT ещё не должен быть принят как durable target decision.
2. `COMMIT_DECISION`: target durably `TARGET_COMMITTED`, source остаётся durably `SOURCE_RETIRED`; успешное committed observation/ACK намеренно не доводится до нормального завершения до outage.
3. `ACTIVATION`: target durably `ACTIVE_OWNER`, source остаётся durably `SOURCE_RETIRED`; fresh activation acknowledgement не доводится до client completion до outage.

После каждой границы оба authority process завершаются с минимальным разрывом kill requests, тот же client process остаётся жив, затем target и source восстанавливаются из своих exact durable generations, и crossing должен завершиться ровно один раз. Следующий handoff идёт в противоположном направлении и на следующей boundary matrix позиции.

Campaign запрещает identity replacement, пропуск/дублирование crossing completion, потерю durable transaction state, невозможность продолжить следующий handoff после recovery и divergence directory epoch.

## Почему потребовался scoped mixed fault path

До финального SHA H4.2 выявил несколько проблем именно в test-harness/fault-evidence orchestration, а не подтверждённый production recovery defect.

- SHA `4af107a0c492269a3d71d0f9a570a40d8cb82bf8`: первый live run остановился на cycle 1 с `expected one mixed crash point ... got 0`; это была race при наблюдении crash-point evidence.
- SHA `21a7d70729a4520f40cc1fb79145585444700d52`: после успешного recovery `INFLIGHT_RETIRE` cycle runner остановился на cycle 2 с `COMMITTED ACK suppression evidence missing`.
- SHA `678e25c525a72107a98b05db942fa2fcd1e9c699`: synchronization была усилена, но cycle 2 зависел от слишком широкой/неподходящей evidence route и завершился timeout ожидания `PLAYER_HANDOFF_COMMITTED` в source log.
- SHA `3e95dd881e55784bfe15a9901e7d1fe9bac143f9`: H4.2 routed through scoped mixed fault evidence (`fix(sm0): route H4.2 through scoped fault evidence`). Именно этот exact SHA затем прошёл и DEFAULT, и FINAL.

Успешный evidence SHA поэтому должен интерпретироваться как проверка exact scoped H4.2 fault orchestration плюс существующей transaction/active-owner recovery composition. Он не расширяет область доказанного production acceptance.

## Focused preflight

Перед live campaign exact Windows gate успешно выполнил:

- base SM0 compile-smoke: PASS (9 scripts);
- handoff motion import regression: PASS (22 assertions);
- SM0 contracts: PASS (15 assertions);
- target prepare / transaction recovery: PASS (32 assertions);
- active-owner recovery: PASS (41 assertions);
- source-retire recovery: PASS (37 assertions).

Cold metadata import создавал отсутствующие `.uid` sidecars из Godot cache; runner удалял созданные этим запуском sidecars.

## DEFAULT — 3 outages / 3 handoffs — PASS

Локальная дата Windows запуска: 2026-08-16.

Exact HEAD:

`3e95dd881e55784bfe15a9901e7d1fe9bac143f9`

Same client PID:

`10776`

Observed campaign:

1. `INFLIGHT_RETIRE`, A -> B, transfer `handoff/sm0/a/2/1`: target B restored `TARGET_PREPARED gen=1`; source A restored `SOURCE_RETIRED gen=12`; kill request gap `0 ms`; crossing #1 exactly once.
2. `COMMIT_DECISION`, B -> A, transfer `handoff/sm0/b/3/1`: target A restored `TARGET_COMMITTED gen=14`; source B restored `SOURCE_RETIRED gen=5`; kill request gap `0 ms`; crossing #2 exactly once.
3. `ACTIVATION`, A -> B, transfer `handoff/sm0/a/4/2`: target B restored `ACTIVE_OWNER gen=8`; source A restored `SOURCE_RETIRED gen=17`; kill request gap `0 ms`; crossing #3 exactly once.

Final facts:

- outages: `3 / 3`;
- boundary rotation: `INFLIGHT_RETIRE, COMMIT_DECISION, ACTIVATION`;
- target sequence: `B,A,B`;
- handoffs: `3 / 3`;
- base analyzer: PASS, `158` events;
- final directory epoch: `4`;
- identity changes: `0`.

Logs:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH42\logs\20260816-021654`

Summary:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH42\logs\20260816-021654\h42-summary.json`

## FINAL — 6 outages / 6 handoffs — PASS

Локальная дата Windows запуска: 2026-08-16.

Exact HEAD:

`3e95dd881e55784bfe15a9901e7d1fe9bac143f9`

Same client PID:

`16184`

Observed campaign:

1. `INFLIGHT_RETIRE`, A -> B, transfer `handoff/sm0/a/2/1`: target B `TARGET_PREPARED gen=1`, source A `SOURCE_RETIRED gen=12`, kill gap `0 ms`, crossing #1 exactly once.
2. `COMMIT_DECISION`, B -> A, transfer `handoff/sm0/b/3/1`: target A `TARGET_COMMITTED gen=14`, source B `SOURCE_RETIRED gen=5`, kill gap `0 ms`, crossing #2 exactly once.
3. `ACTIVATION`, A -> B, transfer `handoff/sm0/a/4/2`: target B `ACTIVE_OWNER gen=8`, source A `SOURCE_RETIRED gen=17`, kill gap `0 ms`, crossing #3 exactly once.
4. `INFLIGHT_RETIRE`, B -> A, transfer `handoff/sm0/b/5/2`: target A `TARGET_PREPARED gen=18`, source B `SOURCE_RETIRED gen=11`, kill gap `0 ms`, crossing #4 exactly once.
5. `COMMIT_DECISION`, A -> B, transfer `handoff/sm0/a/6/3`: target B `TARGET_COMMITTED gen=13`, source A `SOURCE_RETIRED gen=22`, kill gap `0 ms`, crossing #5 exactly once.
6. `ACTIVATION`, B -> A, transfer `handoff/sm0/b/7/3`: target A `ACTIVE_OWNER gen=25`, source B `SOURCE_RETIRED gen=16`, kill gap `0 ms`, crossing #6 exactly once.

Final facts:

- outages: `6 / 6`;
- authority process deaths induced by campaign: `12` total, two per outage;
- boundary rotation completed twice: `INFLIGHT_RETIRE, COMMIT_DECISION, ACTIVATION, INFLIGHT_RETIRE, COMMIT_DECISION, ACTIVATION`;
- target sequence: `B,A,B,A,B,A`;
- same client PID remained alive across all six dual-authority outages;
- handoffs: `6 / 6`;
- base analyzer: PASS, `280` events;
- final directory epoch: `7`;
- identity changes: `0`.

Logs:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH42\logs\20260816-021827`

Summary:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH42\logs\20260816-021827\h42-summary.json`

## Вывод

На exact SHA `3e95dd881e55784bfe15a9901e7d1fe9bac143f9` один непрерывный client process успешно пережил шесть последовательных simultaneous dual-authority outages при двух полных ротациях трёх разных handoff crash boundaries.

Проверенная branch-local composition guarantee:

`TARGET_PREPARED / TARGET_COMMITTED / ACTIVE_OWNER durable boundary -> both authorities die -> exact target/source durable restore -> idempotent continuation -> exactly-once crossing -> opposite-direction next handoff -> next boundary -> repeat`.

В FINAL campaign не наблюдалось identity replacement, crossing duplication, directory epoch divergence или невозможности продолжить последующий handoff после предыдущего recovery.

Этот документ фиксирует только experimental branch-local runtime evidence. Он не является самостоятельным основанием для production/global acceptance cross-server authority и не изменяет V0-S1 policy относительно `SERVER_HANDOFF`.
