# WORK ORDER — NET-SMOOTH1 R4.2: неблокирующий durable drain (диагностика R1)

Статус: DIAGNOSTIC COMPLETE, IMPLEMENTATION NOT AUTHORIZED IN THIS PR.
Ветке-носителю запрещено менять контракт durability; настоящий документ — отдельный
Work Order для main-owned реализации.

## 1. Наблюдение

Одиночные серверные задержки основного цикла 100–220 мс (до 287 мс) на Windows.

## 2. Причинная цепочка (подтверждено кодом и трассами)

1. Durable команда ITEM (или периодический `LEGACY_COMMAND_SYNC` fallback) требует
   durable-before-ACK: полный checkpoint до подтверждения игроку
   (`_persist_command_result` → `_persist_checkpoint`, `m3_dedicated_server_runtime_p2.gd`).
2. `_persist_checkpoint` выполняется **синхронно в главном потоке сервера**:
   `create_checkpoint` (export authority + replay + валидация checksum) и
   `repository.save_atomic` (запись + замена) — `authoritative_recovery_coordinator.gd:50`.
3. Дополнительно перед checkpoint выполняется блокирующий drain активного
   async movement writer (`_complete_async_movement_checkpoint(true)` →
   `wait_completed()`, активное ожидание с `OS.delay_msec(1)`).
4. Замер этапов (уже существующая трассировка `durable_checkpoint_stages`):
   - `persist_atomic_ms`: p50 ≈ 32 мс, **единичные 171–287 мс** (4 запуска r3c3-r2-gui);
   - `quiesce_ms`: 3.5–18 мс;
   - `wait_async_ms`: 0 (drain завершён заранее) — диск, а не writer, доминирует.
5. Отдельный второй источник: `server_loop.process_ms` ≈ 207 мс с
   `message_ms` ≈ 207 мс при обработке JOIN после reconnect (локальный прогон
   ns1-final-runs/local-r3, t=155.9s) — вычислительная, а не дисковая задержка.

Вывод: главный поток ожидает дисковый I/O (`save_atomic`), смешанный с
квесценцией состояния; вычислительная нагрузка JOIN отдельна.

## 3. Ограниченный вариант неблокирующего ожидания (предложение)

Не внедряется в текущем PR. Эскиз для отдельной реализации:

- Командный путь перевести на тот же single-worker async writer
  (`async_checkpoint_writer.gd`) с escrow-состоянием `COMMIT_PENDING`:
  ACK остаётся заблокированным до `completion` (durable-before-ACK сохраняется),
  но главный поток обрабатывает сообщения через poll, а не `wait_completed()`.
- Возврат команды клиенту — отложенный (completion delivery в следующем кадре
  после `checkpoint_complete`), operation_id и ACK escrow без изменений.
- `wait_completed()` остаётся только на shutdown drain.

## 4. Обязательные тесты отдельной реализации (Work Order)

1. Crash/restart: kill -9 сервера между `submit` и `completion`; при старте
   replay восстанавливает ровно закоммиченные операции, ни одна не потеряна и
   не применена дважды.
2. Replay ordering: строгий порядок generations; старая generation не может
   завершиться после новой (`M7_ASYNC_CHECKPOINT_GENERATION_MISMATCH` остаётся
   фатальным).
3. ACK escrow: `stage → mark_submitted → complete` только на фактически
   закоммиченной generation; отказ `complete` = PERSISTENCE_FATAL.
4. Отмена задач: остановка writer не теряет pending job; повторный старт
   возобновляет drain.
5. Позднее завершение старой generation: completion от предыдущей generation
   после staging новой не продвигает `_checkpoint_generation`.
6. Регрессия: 3× `r3-slow-item --slow-item-writer-ms 1800`, 0
   PERSISTENCE_FATAL, 0 replay/ACK violation, server ≥59 Гц, main-thread
   persistence <50 мс.

## 5. Доказательство (evidence)

- Код: `scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd:2480-2611`,
  `scripts/persistence/authoritative_recovery_coordinator.gd:50-63`,
  `scripts/persistence/async_checkpoint_writer.gd` (`wait_completed`).
- Трассы: `work/net-smooth-r3c3-r2-20261016-153700/artifacts/net-smooth1/r3c3-r2-gui*/server/trace.jsonl`
  (`durable_checkpoint_stages.persist_atomic_ms` max 171.0/287.5/181.5/172.6 мс при
  `wait_async_ms`=0); `ns1-final-runs/local-r3/server/trace.jsonl` (server_stall 207 мс,
  `message_ms` 206.9 при JOIN reconnect).
