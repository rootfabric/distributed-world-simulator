# NET-SMOOTH1 R4.2-P1-B — Production Async Durable Integration (Work Order)

**Статус:** `WORK_ORDER_DRAFT / NOT_STARTED / HIGH_RISK / NO_MERGE`.
**Предусловие:** закрытый acceptance P1-A (PR #760): single-writer proof, fault matrix и
Windows exact evidence на immutable HEAD. До VERIFIED-вердикта P1-A этот WO не активируется.

## Цель

Подключить доказанный в P1-A single-writer async durable pipeline
(`m6_async_durable_command_proof.gd` + существующий `async_checkpoint_writer.gd` +
`m6_pending_durable_ack_gate.gd`) к реальным M3-командам production-сервера, убрав
синхронную запись чекпойнта с игрового потока.

## Обязательные изменения

1. **M3 authoritative mutation handlers** (`_persist_command_result`): успешная canonical
   mutation НЕ выполняет немедленный sync `Repository.save_atomic`. Вместо этого:
   bounded capture → `reserve_mutation` → canonical mutation → `submit_frozen`
   (detached authority/replay/outbox) → освободить main thread.
2. **Отложенная публикация:** `COMMAND_RESULT`, `JOIN_ACK`, `LEAVE_ACK`, ITEM delta и
   gameplay snapshot не отправляются до валидного worker-комплита (`ACK_ELIGIBLE`).
   Drain FIFO в `_process` через неблокирующий `poll_completed()`; session/epoch fence
   и `mark_delivered` обязательны.
3. **Замер состава задержки:** трейсы `capture_authority_ms`, `capture_replay_ms`,
   `deepcopy_ms`, `submit_ms`, `worker_hash_ms`, `worker_json_ms`, `worker_io_ms`,
   `ack_wait_ms`, `server_loop_ms`. Нельзя объявлять успех по одному `persist_atomic_ms`.
4. Realtime movement не попадает в frozen detached checkpoint и не меняет commit
   generation; при конфликте сериализуется только затронутая мутация.
5. Transient USER1 join по контракту `requires_immediate_join_persistence`;
   `CONSTRUCTION_COMMAND` в persistent мире остаётся fail-closed до отдельного
   durable-owner repair.

## Приёмка (без снижения порогов)

- Client frame p99 ≤25 мс, p99.9 ≤50 мс; no connected frame gap >100 мс; server ≥59 Hz;
  main-thread persistence ≤50 мс (capture ≤50 мс на p99).
- Crash/reconnect/fault matrix в отдельных process runs: force-kill до/после atomic
  commit, pending previous periodic, >1 concurrent canonical command, stale session,
  expired ACK, repeated operation_id (ровно один canonical replay outcome).
- GUI: 2 real Quaternius клиента, 3×120s чистых прогона + ≥24 durable ITEM ops;
  0 checksum rejects; 4-hour soak; 250ms intentional stalls как отрицательные контроли.
- Freeze HEAD/TREE, SHA256 артефактов, fresh independent Reviewer → Windows Independent
  Verifier → PC0/directional audit → human-gated merge.

## Запрещено

Отключать Full/Compact/Protocol Frame V2 SHA, снижать cadence, менять схему
inventory/Item Graph, блокировать `_process` (wait_to_finish/busy-spin/FS read),
расширять USER1 authority, повторять применение уже применённой мутации при
неопределённом исходе commit (fail-closed вместо слепого retry).
