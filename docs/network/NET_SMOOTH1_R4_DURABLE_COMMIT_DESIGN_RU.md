# NET-SMOOTH1 R4 — Design Brief / Work Order: durable-команды без блокировки кадра

Статус: **PLANNED / HIGH-RISK / R4.0 BASELINE**. Это дочерний design/diagnostic кандидат поверх R3.1; **не является реализованным WAL или разрешением на merge**.

## Точный субъект

- Родитель: `53ec8c9acf7d318d3a3892722647b84bbf228925`, PR #753 (функциональный R3.1 reconnect, Windows 20/20 PASS, performance FAIL), родитель PR #751 = CHAR2.
- Новая ветка: `repair/net-smooth1-r4-durable-commit-r0`; изменения ограничены R4.0 evidence, затем отдельный implementer P1. Ни `main`, ни принятые продуктовые ветки не изменять.
- Полный продуктовый gate: Windows GUI LOCAL сервер+2 Quaternius-клиента, ≤25ms frame p99, ≤50ms p99.9, no >100ms gaps, сервер ≥59Hz, no main-thread persistence >50ms; пороги **не изменять**.
- Проблема подтверждена R3 Windows: `message_ms` p99 ≈106–119ms, `persistence_ms` p99 ≈55–64ms, server frame p99≈110–129ms. `send_and_seam` уже снижен на 30–39% после R3 и не главный хвост. GUI client p99≈31ms — **отдельный** CPU/render slice.

## Наблюдаемая цепочка и архитектура

В `m3_dedicated_server_runtime_p2.gd` путь `_persist_command_result` после успешной авторитетной мутации проверяет replay ledger, повторно делает `_service.create_snapshot()` и `_service.create_canonical_item_graph_snapshot()`, ставит outbox record, вызывает `_persist_checkpoint(operation_id)`. Он ждёт завершения предыдущего background movement checkpoint через `_complete_async_movement_checkpoint(true)` и синхронно вызывает `_recovery_coordinator.persist_checkpoint` → `authoritative_recovery_coordinator.create_checkpoint` → `authoritative_recovery_repository.save_atomic` (validate, stringify, write, verify, rename). Только после `persisted.success` отправляется успешный `*_RESULT` / `JOIN_ACK`. Это **durable-before-ACK**; убирать barrier без замены нельзя.

Наблюдаемые `message_ms`/`persistence_ms` ещё не доказывают распределение между wait, экспортом, checksum, записью и flush. Результаты Windows должны подтвердить затратность стадий по точному R4-коду, а не по предположению.

## R4.0 — доказательная инструментализация (первая поставка)

1. Ввести bounded trace `durable_command_stages`: `command_type`, `player_checksum_ms`, `item_graph_checksum_ms`, `outbox_stage_ms`, `checkpoint_total_ms`, `success`; без пользовательских идентификаторов, содержимого снапшотов или токенов.
2. Ввести `durable_checkpoint_stages`: `wait_async_ms`, `quiesce_ms`, `persist_atomic_ms`, `success`, `origin` = `command|periodic`. Ошибочный commit обязан отражаться как FAIL, не как завершённая durability.
3. Расширить диагностический анализатор так, чтобы он вычислял p50/p95/p99/p99.9/max по каждой стадии и обнаруживал malformed/nonfinite/negative traces как INCONCLUSIVE. Для специальных durable workload запусков отсутствие `durable_command_stages` считается INCONCLUSIVE, для движения без durable-команд — не требовать ложного события.
4. Провести exact Windows A/B против R3.1: тот же сервер/2 клиента, 3×120s, плюс минимум 20 документированных durable-команд разных типов, при неизменном workload, размерах мира, renderer и уровне CPU-конкуренции. Два отдельных повторения без concurrency bias.
5. Верифицировать Stage–loop корреляцию по одному process clock и `server_tick`. Не вычислять одностороннюю сетевую задержку вычитанием часов разных процессов.

## R4.1 — выбрать минимальный crash-safe asynchronous durable barrier

**Предпочтительный минимальный механизм:** переиспользовать единственный `async_checkpoint_writer.gd` и существующий M6 checkpoint/OUTBOX; вне главного цикла сериализовать и коммитить полностью *detached* checkpoint, а ответ хранить в **bounded pending-ACK** до успешного atomic commit. Команды/продуктовые побочные эффекты должны идти в согласованном порядке; нельзя публиковать незафиксированную авторитетную mutation или выполнять следующее конфликтующее изменение без сериализации. Новая порция движения может продолжаться, если она не меняет детерминированный commit-снимок и контракт допускает recovery более поздних тиков.

Стадии состояния: `RECEIVED -> APPLIED_NOT_PUBLISHED -> FROZEN_CHECKPOINT -> COMMIT_PENDING -> DURABLE -> ACK_ELIGIBLE -> DELIVERED`; при отказе `FAIL_CLOSED` без успешного ACK и без видимых чужим клиентам неподтверждённых effects. Bounded queue с отказом/обратным давлением, epoch/session fences, строгий order по generation, монотонный checkpoint progression. Запрещены busy-spin и `Thread.wait_to_finish` из `_process`.

**Fallback:** если полный checkpoint на каждую команду слишком тяжёлый даже после async, проектировать transaction journal только при наличии проверяемого deterministic redo/undo и replay/idempotency semantics. Журнал «операция записана» без канонического состояния **не** достаточен. Нельзя помечать ACK delivered до fsync/atomic durable commit.

## R4.2 — обязательная crash/failure matrix

Проверить crash перед stage, после мутации до frozen checkpoint, после записи pending, перед atomic replace, после replace до ACK, после ACK до delivered flag, во время предыдущего periodic writer, после restart/reconnect, duplicate operation и stale session/epoch. Для каждой фазы требуются: один канонический outcome, отсутствие двойного списания Item Graph/Construction/материалов, monotonic generation, корректный recovery checksum, failure не даёт ложный ACK. Стресс: 2 клиента с одновременным движением и командами, аварийная остановка сервера, fresh join и повтор старого operation_id спустя checkpoint.

## Приёмочный контур

- RED→GREEN на новых crash-injection/fault tests. Дополнительно NX2/NX3/NX4/NX5, M6 replay/recovery, USER1 seam, R3.1 reconnect, CHAR2 presentation, test_net_smooth1_*.
- **Никакого самопринятия реализатором**: независимый Reviewer и свежий Windows Verifier с exact HEAD/TREE; 4-hour soak после короткого green; сетевые jitter/loss и параллельные команды.
- CI `Project Control` на R3.1 evidence head ранее красный `CANDIDATE_MAIN_DRIFT`: snapshot `3d7672cb` vs canonical main `fc69771a`, **отдельная candidate authority issue**. Локальный `-CheckConsistency` с ok=true не подменяет `--candidate` CI. Не чинить main-owned registry из продуктовой ветки и не обнулять этот error.
- GUI/persistence/CLIENT p99 остаются FAIL до измеренной коррекции. Release/merge в main запрещён без human gate.

## Далее

Ближайшая исполнимая задача: R4.0 instrument + Windows exact measured profile. По результату выбрать R4.1 конкретный bounded async full-checkpoint/deferred-ACK алгоритм и только затем изменять семантику production ACK. Зафиксировать evidence и новые HEAD в Git; разговор не заменяет Work Order.
