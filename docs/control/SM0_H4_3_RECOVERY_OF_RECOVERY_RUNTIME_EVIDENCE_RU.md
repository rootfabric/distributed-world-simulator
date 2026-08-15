# SM0 H4.3 — runtime evidence: recovery-of-recovery same-transfer campaign

Статус: **BRANCH-LOCAL EXPERIMENTAL RUNTIME EVIDENCE**.

Это не global acceptance, не production acceptance и не разрешение включать `SERVER_HANDOFF` в V0-S1. Cross-server authority остаётся CRITICAL-risk областью. Документ фиксирует только runtime evidence экспериментальной SM0 ветки.

## Проверенный runtime SHA

Exact HEAD, на котором выполнены успешные DEFAULT и FINAL Windows-прогоны H4.3:

`1126ec53ddf036389d2d11aa5211147b5cd7e320`

Branch:

`feature/sm0-two-authority-seamless-handoff-lab`

Godot:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`

Windows executable:

`C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe`

Runner:

`RUN_V0_SM0_RECOVERY_OF_RECOVERY_ACCEPTANCE.ps1`

Fault profile:

`h4-recovery-of-recovery-same-transfer-v1`

Recovery chain:

`TARGET_PREPARED -> TARGET_COMMITTED -> ACTIVE_OWNER -> exactly-one completion`

## Scope H4.3

H4.3 проверяет более сильную композицию, чем H4.2: один и тот же exact handoff transfer должен пережить не один total outage и не разные outage на разных transfer, а три последовательных simultaneous dual-authority outage по мере продвижения recovery одного T.

Для одной chain:

1. target durably `TARGET_PREPARED`, source durably `SOURCE_RETIRED`; оба authority падают;
2. после restore тот же exact T продвигается до target `TARGET_COMMITTED`, source остаётся `SOURCE_RETIRED`; оба authority снова падают;
3. после второго restore тот же exact T продвигается до target `ACTIVE_OWNER`, source остаётся `SOURCE_RETIRED`; оба authority падают третий раз;
4. после terminal restore crossing должен завершиться ровно один раз без client restart и без identity replacement.

FINAL повторяет эту recovery-of-recovery chain в обратном направлении в той же client session.

## Runtime-discovered repair перед успешным candidate

Первый DEFAULT запуск на SHA:

`af5541f2d983cf9870a213c1644810fa416780e7`

успешно прошёл весь preflight, но live campaign остановился после запуска клиента до первого PREPARED crash point.

Причина была в test-only H4.3 fault orchestration: override `_send_source_commit()` проверял наличие durable `SOURCE_RETIRED` до вызова parent recovery path, хотя именно parent выполняет canonical write-before-send persistence. Fresh COMMIT поэтому мог пройти дальше вместо PREPARED fault.

Repair commit:

`9ffa0d9eb19d354bbf8d6b68bba7e9346188418d`

Repair не меняет production recovery algorithm. H4.3 fault node теперь сначала использует существующий `_ensure_source_retire_persisted(transfer_id)`, проверяет durable success и только после этого подавляет COMMIT/redirect на PREPARED boundary.

Work-log commit после finding:

`1126ec53ddf036389d2d11aa5211147b5cd7e320`

Именно этот exact SHA затем прошёл DEFAULT и FINAL.

## Focused preflight

Оба успешных Windows gate перед live campaign подтвердили:

- base SM0 compile-smoke: PASS (9 scripts);
- handoff motion import regression: PASS (22 assertions);
- healthy SM0 acceptance: PASS, 2 / 2 handoffs;
- SM0 contracts: PASS (15 assertions);
- H4.3 transaction/recovery compile checks: PASS;
- target prepare recovery regression: PASS (32 assertions);
- active-owner recovery regression: PASS (41 assertions);
- source-retire recovery regression: PASS (37 assertions).

Cold metadata import создавал отсутствующие `.uid` sidecars из Godot cache; runner удалял созданные этим запуском sidecars.

Project Control run #604 для runtime candidate завершён SUCCESS. Это static/control evidence и не подменяет Windows runtime evidence ниже.

## DEFAULT — one same-transfer chain / 3 outages — PASS

Локальная дата Windows запуска: 2026-08-16.

Exact HEAD:

`1126ec53ddf036389d2d11aa5211147b5cd7e320`

Same client PID:

`26228`

Transfer:

`handoff/sm0/a/2/1`

Observed chain A -> B:

1. PREPARED outage: target B `TARGET_PREPARED gen=1`, source A `SOURCE_RETIRED gen=12`, kill gap `0 ms`, client alive.
2. COMMITTED outage after first recovery: same transfer, target B `TARGET_COMMITTED gen=2`, source A `SOURCE_RETIRED gen=12`, kill gap `0 ms`, client alive.
3. ACTIVE outage after second recovery: same transfer, target B `ACTIVE_OWNER gen=3`, source A `SOURCE_RETIRED gen=12`, kill gap `0 ms`, client alive.
4. Terminal recovery: same transfer completed crossing #1 exactly once on B.

Final facts:

- chains: `1 / 1`;
- outages: `3 / 3`;
- stages per transfer: `PREPARED, COMMITTED, ACTIVE`;
- handoffs: `1 / 1`;
- base analyzer: PASS, `118` events;
- final directory epoch: `2`;
- identity changes: `0`.

Logs:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH43\logs\20260816-025910`

Summary:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH43\logs\20260816-025910\h43-summary.json`

## FINAL — two opposite-direction same-transfer chains / 6 outages — PASS

Локальная дата Windows запуска: 2026-08-16.

Exact HEAD:

`1126ec53ddf036389d2d11aa5211147b5cd7e320`

Same client PID:

`27184`

### Chain 1 — A -> B

Transfer:

`handoff/sm0/a/2/1`

1. PREPARED: target B `TARGET_PREPARED gen=1`, source A `SOURCE_RETIRED gen=12`, old A PID `13640`, old B PID `25928`, kill gap `0 ms`.
2. COMMITTED: same T, target B `TARGET_COMMITTED gen=2`, source A `SOURCE_RETIRED gen=12`, old A PID `15236`, old B PID `2584`, kill gap `0 ms`.
3. ACTIVE: same T, target B `ACTIVE_OWNER gen=3`, source A `SOURCE_RETIRED gen=12`, old A PID `3388`, old B PID `20644`, kill gap `0 ms`.
4. Terminal restore: crossing #1 completed exactly once on B.

### Chain 2 — B -> A

Transfer:

`handoff/sm0/b/3/1`

1. PREPARED: target A `TARGET_PREPARED gen=13`, source B `SOURCE_RETIRED gen=6`, old A PID `16024`, old B PID `10560`, kill gap `0 ms`.
2. COMMITTED: same T, target A `TARGET_COMMITTED gen=14`, source B `SOURCE_RETIRED gen=6`, old A PID `10404`, old B PID `27408`, kill gap `0 ms`.
3. ACTIVE: same T, target A `ACTIVE_OWNER gen=15`, source B `SOURCE_RETIRED gen=6`, old A PID `26852`, old B PID `24864`, kill gap `0 ms`.
4. Terminal restore: crossing #2 completed exactly once on A.

Final facts:

- same client PID `27184` remained alive for the full campaign;
- chains: `2 / 2`;
- outages: `6 / 6`;
- authority process deaths induced by campaign: `12` total, two per outage;
- stages per transfer: `PREPARED, COMMITTED, ACTIVE`;
- target sequence: `B,A`;
- handoffs: `2 / 2`;
- base analyzer: PASS, `199` events;
- final directory epoch: `3`;
- identity changes: `0`.

Logs:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH43\logs\20260816-030158`

Summary:

`C:\Users\root\AppData\Local\DistributedWorldSimulator\SM0SeamlessH43\logs\20260816-030158\h43-summary.json`

## Проверенные composition invariants

Успешный gate требует и тем самым подтверждает для этой exact branch-local composition:

- один exact transfer id сохраняется через PREPARED -> COMMITTED -> ACTIVE внутри каждой chain;
- target recovery generation строго растёт между тремя durable фазами;
- source остаётся exact durable `SOURCE_RETIRED` non-writer на всём recovery пути;
- canonical target import выполняется ровно один раз после PREPARED recovery;
- COMMITTED/ACTIVE recovery не создают повторный canonical import старого T;
- `SM0_COMMIT_WITHOUT_PREPARE` не наблюдается;
- invariant violation не наблюдается;
- каждый terminal crossing завершается ровно один раз;
- directory epoch остаётся contiguous;
- logical identity не заменяется;
- клиент не перезапускается между outage и между двумя FINAL chains.

## Вывод

На exact SHA `1126ec53ddf036389d2d11aa5211147b5cd7e320` один непрерывный client process успешно пережил две противоположно направленные recovery-of-recovery chains. Каждый exact transfer пережил три successive total outages обоих authority на durable фазах `TARGET_PREPARED`, `TARGET_COMMITTED` и `ACTIVE_OWNER`, после чего завершился ровно один раз.

Проверенная branch-local composition guarantee:

`same T: PREPARED durable pair -> A+B die -> restore -> COMMITTED durable pair -> A+B die -> restore -> ACTIVE durable pair -> A+B die -> restore -> exactly-one crossing`, затем тот же сценарий в обратном направлении в той же client session.

Этот документ фиксирует только experimental branch-local runtime evidence. Он не является самостоятельным основанием для production/global acceptance cross-server authority и не изменяет V0-S1 policy относительно `SERVER_HANDOFF`.
