# SM0 H4.1 — runtime evidence: repeated alternating activation-outage campaign

Статус: **BRANCH-LOCAL EXPERIMENTAL RUNTIME EVIDENCE**.

Это не global acceptance, не production acceptance и не разрешение включать `SERVER_HANDOFF` в V0-S1. Cross-server authority остаётся CRITICAL-risk областью, а V0-S1 по-прежнему не должен интерпретировать этот документ как acceptance server handoff.

## Проверенный runtime SHA

Exact HEAD, на котором выполнены оба успешных Windows-прогона H4.1:

`c9a441452a2a501f962163844f14200cda9e266b`

Branch:

`feature/sm0-two-authority-seamless-handoff-lab`

Godot:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`

Windows executable:

`C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe`

Primary runner:

`RUN_V0_SM0_REPEATED_ACTIVATION_OUTAGE_ACCEPTANCE.ps1`

Windows PowerShell FIX1 launcher:

`RUN_V0_SM0_REPEATED_ACTIVATION_OUTAGE_ACCEPTANCE_FIX1.ps1`

Fault profile:

`h4-repeated-activation-dual-outage-v1`

## Scope H4.1

H4.1 проверяет накопительную устойчивость recovery state между ownership epochs в одной непрерывной client process session.

В отличие от H3.5, total outage происходит не один раз. Для каждого handoff:

1. текущий owner начинает реальный handoff на противоположный authority;
2. target durably сохраняет `ACTIVE_OWNER` до успешного `ACTIVATE_ACK`;
3. fresh `ACTIVATE_ACK` намеренно подавляется;
4. source сохраняет durable `SOURCE_RETIRED`;
5. оба authority process принудительно завершаются;
6. тот же client process остаётся жив;
7. target восстанавливает `ACTIVE_OWNER`;
8. source восстанавливает stale `SOURCE_RETIRED` и replay старого tracking должен быть idempotent;
9. crossing завершается ровно один раз;
10. следующий handoff идёт в противоположном направлении и повторяет тот же outage boundary.

Target authority должен чередоваться `B, A, B, A, ...`.

Campaign запрещает повторный target commit/import одного transfer, identity change, пропуски directory epoch и premature client exit.

## PowerShell FIX1

Первый H4.1 process-level runtime на SHA `68130774b7921c495102249f40b6caa527f667c4` фактически прошёл оба outage cycle и base analyzer `2 / 2`, но runner завершился уже после semantic/runtime проверок при построении итогового summary с PowerShell ошибкой `Argument types do not match`.

Причиной была коллекция:

`New-Object System.Collections.Generic.List[object]`

с последующим array-subexpression `@($Cycles)`.

Commit `c9a441452a2a501f962163844f14200cda9e266b` добавил только fail-closed PowerShell FIX1 launcher. Он создаёт временную копию primary runner и заменяет ровно одну construction expression на:

`[System.Collections.Generic.List[object]]::new()`

Godot runtime/recovery protocol этим commit не изменялся. Оба acceptance-прогона ниже выполнены на exact HEAD `c9a441452a2a501f962163844f14200cda9e266b` через FIX1 launcher.

## Focused preflight

Перед live campaign exact Windows gate успешно выполнил:

- base SM0 compile-smoke: PASS (9 scripts);
- handoff motion import regression: PASS (22 assertions);
- SM0 contracts: PASS (15 assertions);
- target prepare / transaction recovery: PASS (32 assertions);
- active-owner recovery: PASS (41 assertions);
- source-retire recovery: PASS (37 assertions).

Cold metadata import создавал отсутствующие `.uid` sidecars из Godot cache; runner удалял созданные этим запуском sidecars.

## DEFAULT — 2 outages / 2 handoffs — PASS

Локальная дата Windows запуска: 2026-08-16.

Exact HEAD:

`c9a441452a2a501f962163844f14200cda9e266b`

Same client PID:

`10172`

### Cycle 1 — A -> B

- transfer: `handoff/sm0/a/2/1`;
- target: B;
- B durable `ACTIVE_OWNER` generation: `3`;
- source A durable `SOURCE_RETIRED` generation: `12`;
- old A PID: `20456`;
- old B PID: `9140`;
- restarted B PID: `25052`;
- restarted A PID: `10772`;
- kill request gap: `0 ms`;
- crossing #1 completed exactly once.

### Cycle 2 — B -> A

- transfer: `handoff/sm0/b/3/1`;
- target: A;
- A durable `ACTIVE_OWNER` generation: `15`;
- source B durable `SOURCE_RETIRED` generation: `6`;
- old A PID: `10772`;
- old B PID: `25052`;
- restarted A PID: `13916`;
- restarted B PID: `3388`;
- kill request gap: `0 ms`;
- crossing #2 completed exactly once.

Final facts:

- outages: `2 / 2`;
- target sequence: `B,A alternating`;
- handoffs: `2 / 2`;
- base analyzer: PASS, `124` events;
- final directory epoch: `3`;
- identity changes: `0`.

Logs:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH41\logs\20260816-015211`

Summary:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH41\logs\20260816-015211\h41-summary.json`

## FINAL — 6 outages / 6 handoffs — PASS

Локальная дата Windows запуска: 2026-08-16.

Exact HEAD:

`c9a441452a2a501f962163844f14200cda9e266b`

Same client PID:

`25732`

Observed campaign:

1. A -> B, transfer `handoff/sm0/a/2/1`, target B `ACTIVE_OWNER gen=3`, source A `SOURCE_RETIRED gen=12`, kill gap `0 ms`, crossing #1 exactly once.
2. B -> A, transfer `handoff/sm0/b/3/1`, target A `ACTIVE_OWNER gen=15`, source B `SOURCE_RETIRED gen=6`, kill gap `0 ms`, crossing #2 exactly once.
3. A -> B, transfer `handoff/sm0/a/4/2`, target B `ACTIVE_OWNER gen=9`, source A `SOURCE_RETIRED gen=18`, kill gap `0 ms`, crossing #3 exactly once.
4. B -> A, transfer `handoff/sm0/b/5/2`, target A `ACTIVE_OWNER gen=21`, source B `SOURCE_RETIRED gen=12`, kill gap `0 ms`, crossing #4 exactly once.
5. A -> B, transfer `handoff/sm0/a/6/3`, target B `ACTIVE_OWNER gen=15`, source A `SOURCE_RETIRED gen=24`, kill gap `0 ms`, crossing #5 exactly once.
6. B -> A, transfer `handoff/sm0/b/7/3`, target A `ACTIVE_OWNER gen=27`, source B `SOURCE_RETIRED gen=18`, kill gap `0 ms`, crossing #6 exactly once.

Final facts:

- outages: `6 / 6`;
- authority process deaths induced by campaign: `12` total, two per outage;
- target sequence: `B,A,B,A,B,A`;
- handoffs: `6 / 6`;
- base analyzer: PASS, `298` events;
- final directory epoch: `7`;
- identity changes: `0`.

Logs:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH41\logs\20260816-015330`

Summary:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH41\logs\20260816-015330\h41-summary.json`

## Вывод

На exact SHA `c9a441452a2a501f962163844f14200cda9e266b` один непрерывный client process успешно пережил шесть последовательных alternating activation-boundary total outages в ownership epochs 2..7.

Проверенная branch-local composition guarantee:

`handoff -> ACTIVE_OWNER durable -> ACTIVATE_ACK lost -> both authorities die -> target restore + source stale-retire replay -> exactly-once crossing -> opposite-direction handoff -> repeat`.

В campaign не наблюдалось identity replacement, duplicate target commit/import, directory epoch divergence или невозможности продолжить следующий handoff после предыдущего полного outage.

Этот документ фиксирует только experimental branch-local runtime evidence. Он не является самостоятельным основанием для production/global acceptance cross-server authority.