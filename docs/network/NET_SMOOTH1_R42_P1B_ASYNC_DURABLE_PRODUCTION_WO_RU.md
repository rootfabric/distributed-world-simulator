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

## P1-B R1 — активированное safety continuation (2026-10-13)

**Текущий R1 не является завершением production wiring.** После независимого VERIFIED для PR #759 и P1-A PR #760 активирован ограниченный R1; права merge отсутствуют.

- PR #759: независимый RED→GREEN, 25/25 focused, GUI 13/13 SHA_MATCH_ONLY и 0 checksum rejects; evidence HEAD 6667fe37f789839a53af03085445d1c4a1c44a7b. В эту P1B-ветку checksum-коммиты пока НЕ скомпонованы.
- PR #760: независимый Windows proof 97/0, 25/25 focused, CI PASS, reviewer PASS, baseline HEAD 96111d027d5a0cec6fc9d72feee340979eb372a1.
- R1 исправляет reviewer advisory по пропавшему periodic completion: owner в APPLYING/COMMIT_PENDING/ACK_READY теперь fail-closed при несвоевременном periodic completion (P1B_PERIODIC_COMPLETION_OUT_OF_PHASE), generation не продвигается и ACK запрещён.
- R1 устраняет mutable alias writer completion: AsyncCheckpointWriter.poll_completed() возвращает глубокую копию метаданных под mutex.
- Новый тест tests/runtime/test_net_smooth1_r42_p1b_periodic_completion_order.gd покрывает out-of-phase и повторный completion, busy periodic и недопустимую публикацию до commit. Runner ожидает 26 focused suites (22 обычных + 4 process).
- Отдельный Windows workflow .github/workflows/net-smooth-r42-p1b-safety-windows.yml проверяет Godot SHA, cold import, новый falsifier, P1-A proof, 6 соседних регрессий, analyzer и SHA256 артефактов.

### Hard gates перед реальным переходом P1-B R2

1. Сначала exact Windows R1 + fresh independent reviewer. Не заявлять product/perf PASS, пока M3 production handlers не переведены на async worker.
2. reserve_mutation строго до canonical mutation; одновременный periodic worker -> bounded pre-mutation backpressure без wait на _process.
3. При успешной ITEM/MOVE/PRESENTATION/LEAVE операции отложить COMMAND_RESULT, SNAPSHOT, ITEM delta и другие наблюдаемые результаты до atomically committed generation. Не допустить утечки незакоммиченного ITEM через NX3 COMPACT snapshot и запрос полного resync.
4. Не скрывать непрерывные movement snapshots на сотни миллисекунд как способ обхода: это самостоятельный stutter. Нужен безопасный committed-view projection или другая проверенная visibility barrier без same-revision mutation.
5. Single writer также обслуживает periodic и canonical commands; session/epoch fence, ack FIFO, outbox replay, deferred disconnect и explicit shutdown barrier обязательны; persistent Construction остаётся fail-closed.
6. Восстановление после crash-before/after-atomic commit и fail-closed после worker error обязано проходить реальные process falsifiers. Сохранить пороги p99 <=25ms, p99.9 <=50ms, connected gap <=100ms, server >=59Hz, main-thread persistence <=50ms.
7. Канареечный opt-in в узком scope (сначала ITEM), explicit non-merge; затем extended MOVE/PRESENTATION/LEAVE, compositional SHA repair #759 и независимый Windows GUI + 4h soak.

### Команды Windows exact для R1

Использовать fresh detached worktree ветки feature/net-smooth1-r42-p1b-production-async-r1, штатный Godot C:\\Godot\\godot\\bin\\godot.windows.editor.double.x86_64.console.exe, cold import, затем:

    & $Godot --headless --path $WT --script 'res://tests/runtime/test_net_smooth1_r42_p1b_periodic_completion_order.gd'
    & $Godot --headless --path $WT --script 'res://tests/runtime/test_net_smooth1_r42_p1_async_durable_proof.gd'
    .\\RUN_NET_SMOOTH1.ps1 -Mode focused -GodotConsole $Godot -IncludeProcessTests -OutputDirectory $OutputDir

Сохранять HEAD/TREE, runner status, все логи и SHA256. Windows CI при ошибке — фиксировать точный источник RED, узкий repair, затем повторная independent проверка.
