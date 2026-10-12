# NET-SMOOTH1 R4.2-P1 — асинхронный durable-commit без фризов сервера

**Статус:** `DESIGN_ONLY / IMPLEMENTATION_NOT_STARTED / HIGH_RISK / NO_MERGE`. Bounded Work Order `NET-SMOOTH1-R42-P1-A-B`.
**Execution base:** exact P0 evidence `7ef9b80671d4ae8aa53680a0e72854e2db1a01c3` (PR #758), не `main`; `main` и ACK/GUI продуктовые интеграции остаются отдельными gate. В соседней ветке PR #759 делается checksum repair; **не смешивать её изменения с P1 без независимого подтверждения и осознанного composition**.

## Причина и цифры

- Принятый R4.2-P0 M6 diagnostic 21/21; 24 focused, analyzer 20/20; 10× durable под нагрузкой: 0 revision conflict, 0 PERSISTENCE_FATAL.
- Полный M6 `_persist_command_result -> _persist_checkpoint -> _recovery_coordinator.persist_checkpoint -> Repository.save_atomic` проходит *на главном серверном потоке*. На Windows `persist_atomic_ms` p50 ~492–617 ms; показатель нельзя поправить количеством snapshots или сетевой интерполяцией. Имеется `AsyncCheckpointWriter`, но сейчас используется только для **periodic movement**, тогда как успешные durable-команды принудительно `_complete_async_movement_checkpoint(true)` (с ожиданием) и потом синхронный commit. Отдельный join path может быть transient по USER1; авторитетные ITEM/Construction gates не подменять.
- R4.2-P0 surfaced nested `MULTIPLAYER_SNAPSHOT_CHECKSUM_MISMATCH` >=5/10 under load. Он живёт в #759. **P1 performance gains нельзя принять**, пока функциональный checksum-класс не закрыт отдельным кодовым и GUI evidence.
- Бюджет **не пересматривать**: client p99 ≤25 ms; p99.9 ≤50 ms; no connected-frame gap >100 ms; server ≥59 Hz; no main-thread persistence >50 ms. Scripted disconnect/reconnect elapsed time фиксировать отдельно от непрерывной connected-frame метрики, не списывать реальные фризы на reconnect.

## Архитектурные инварианты (hard gates)

1. Единственный M6 repository writer. Активный canonical generation строго монотонен. Detached authority/replay/outbox checkpoint *не может* изменяться после submit. Нельзя одновременно sync-write и async-write одной generation; `previous_generation` точно указывает последнюю durable.
2. Успешные `COMMAND_RESULT`, `JOIN_ACK`, `LEAVE_ACK`, ITEM/Construction delta и gameplay snapshot никогда не выходят раньше успешного atomic commit той же операции. Raw successful mutation до COMMIT_PENDING не видна другим клиентам. `M6PendingDurableAckGate` FIFO `peek_ack`, epoch/session fence и `mark_delivered` остаются обязательными.
3. Bounded `MAX_PENDING_COMMANDS`, серверный backpressure, no dropped durable ACK, no unbounded queue. Только один unresolved committing operation; команды не применяются поверх чужого pending commit. Повторные operation_id через canonical M6 replay — ровно один outcome, без повторного списания/строительства.
4. Старые sessions немедленно карантинятся, canonical leave после serialize/durable barrier (сохранить R4.1 F1/F2 queued disconnect semantics). Stale disconnect не отнимает authoritative row новой сессии. Reconnect с incremented ownership_epoch не переизлучает ACK старому peer.
5. Fail-closed при checksum, IO, generation, staging, archive или worker error — no success ACK и no speculative broadcast, сохранить evidence+старый committed checkpoint. Не расширять USER1 authority; remote A остаётся primary-global-domain + secondary-movement-only. В существующем P1 persistent Construction нет доказанного M6 durable owner: пока явно reject (из P0), не объявлять BUILD COMPLETE.
6. Не отключать Full/Compact/Protocol Frame V2 SHA, не снижать snapshot cadence, не изменять physics/inventory/Item Graph schema и performance thresholds ради PASS. Нельзя проводить `Thread.wait_to_finish`, `wait_completed()`, busy-spin или FS read на нормальном `_process` loop.

## Реализация двумя подэтапами, один высокорисковый P1

### P1-A — отдельно исполнимое доказательство single-writer pipeline (без production wire)

- Ввести owner-класс state machine, где COMMIT_PENDING хранит ровно один `operation_id + generation + previous_generation + peer/session/epoch + frozen detached authority/replay`, а payload ACK хранится в escrow `M6PendingDurableAckGate`. Phase:
  `RECEIVED → APPLY_ON_AUTHORITATIVE_THREAD → FREEZE_VALIDATED → SUBMIT_WORKER → COMMIT_PENDING → DURABLE → ACK_ELIGIBLE → DELIVERED`.
- Отдельно доказать фазу `WAIT_PRIOR_PERIODIC`: если periodic writer занят, command не мутирует глобальное состояние до завершения предыдущего writer. Возвратить управление server loop; poll опрашивает завершённую задачу в следующем frame, никаких синхронных задержек. Timeout/buffer full => bounded reject / backpressure до mutation, не самопроизвольный retry уже применённой операции.
- Доработать либо использовать **тот же** `scripts/persistence/async_checkpoint_writer.gd`, умеющий принимать detached generation и завершать `Repository.save_atomic`; не создавать второй thread/kernel, не вызывать scene/global methods из worker. `submit()` уже копирует data; измерить саму capture/duplicate цену отдельно.
- Инъекции отказов на `stage`, `freeze`, `writer submit`, `pending file`, `atomic replace`, `after replace before ACK`, `after ACK before delivered marker`, timeout during previous periodic, disconnect/reconnect при worker busy. Crash-before-commit может потерять unacked mutation; crash-after-commit должен replay один exact durable outcome. Проверить old prior generation stored intact.
- Red/Green falsifiers о реальной generation/peer/session/epoch, не тестировать одно лишь локальное `pending=true`. **P1-A не даёт продуктового разрешения и не claims p99 speedup.**

### P1-B — production wiring / deferred publication

- Переписать только M3 authoritative mutation handlers вокруг `_persist_command_result`: успешная canonical mutation не должна приводить к немедленному `_send_result`, `_broadcast_delta`, `_broadcast_snapshot`. Контейнер `PendingDurableCommand` содержит immutable result и отложенные публикации. Освободить main thread после bounded capture/submit.
- Завершение worker обрабатывать из `_process` при (обычном неблокирующем) poll; лишь после валидного `repository_generation` перевести gate в `ACK_ELIGIBLE`, затем drain FIFO с соблюдением session/epoch fence. Если peer ушёл, outbox остаётся durable, ACK карантинится и получит canonical replay на reconnect. Не блокировать игровой цикл в ожидании fsync.
- Успешный `JOIN` проверяет `requires_immediate_join_persistence`; transient USER1 join не ждать полного мира по принятому контракту, но не допускать вход в конфликтующий durable pending. Explicit `CONSTRUCTION_COMMAND` в persistent мире остаётся fail-closed до отдельного durable owner repair. Не отменять R4.1 F1/F2.
- Realtime movement может продолжаться только если его writes не попадают в `frozen` detached checkpoint и не меняют commit generation; при любом конфликте отдельно сериализовать/приостанавливать только затронутую мутацию. Не делегировать scene-state worker. В отчёте явно отличать authoritative persisted tick от newest realtime tick.
- Важная optimisation risk: M6 export/clone/canonicalization на main thread может сама превысить 50ms. Поэтому разложить trace `capture_authority_ms`, `capture_replay_ms`, `deepcopy_ms`, `submit_ms`, `worker_hash_ms`, `worker_json_ms`, `worker_io_ms`, `ack_wait_ms`, `server_loop_ms`, а не объявлять PASS по одному сокращению `persist_atomic_ms`.

## RED → GREEN и точная приёмка

1. Конкретные source unit-tests: r31 wire 121/121, R4.1 pending ACK 63/63, R4.1 FIFO/disconnect 39/39, M6 126/126, r42 revision fence 21/21 и новый P1 state machine / failure matrix; analyzer 20/20 и immutable accepted F1/F2 outcomes.
2. Windows exact 4.7.1 double, fresh worktree, cold import, focused all, 2 real Quaternius, A primary→secondary→primary, B reconnect while A remote; 3×120s clean GUI plus >=24 successful durable ITEM ops and replay per workload, unchanged schema, zero checksum rejects (в том числе D2/D7/D9/D10 D5 failure class). Per-role trace stage SHA and manifest.
3. P1 high-risk crash/failure matrix в отдельных process runs: force-kill server до/после atomic commit, pending previous periodic checkpoint, >1 concurrent canonical commands from A/B, stale session, expired ACK and repeated operation_id. На client UI не должно быть успешных effects без durable commit.
4. Следом 4-hour soak, 250ms intentional server/client stalls отдельно как отрицательные контроли (не превращать FAIL в PASS), jitter/loss, CLI/profile and fidelity. Снять контрольную baseline/repaired workload A/B на одном exclusive Windows host без конкурирующего ECO/FABRIC CI; client frame p99≤25/p99.9≤50, connected-gap ≤100, server≥59Hz, main-thread persistence≤50.
5. Freeze product HEAD/TREE, SHA256 всех raw logs и tool evidence, fresh independent Reviewer → Windows Independent Verifier → PC0/directional audit → human-gated merge только после composite acceptance. `CANDIDATE_MAIN_DRIFT` для длинной stacked branch исправляется проектным catch-up по authority контрольной main, не branch-local переписыванием registry.

## Протокол продолжения

A0: exact P0 base + зафиксированный конкурентный #759 checksum ремонт.  
A1: P1-A bounded state machine proof/falsifiers в той же P1 рабочей линии.  
A2: Windows exact для proof, свежий Reviewer.  
A3: P1-B runtime refactor только после proof; minimal adapters с прежней семантикой ACK.  
A4: живой GUI/performance/exclusive, soak, independent verifier, PC0, отдельное решение интеграции.

Этот файл **не заявляет уже внесённого кода P1**, не обходит чекпоинт/Work Order и не разрешает merge. Следующий реализатор должен дополнительно прочитать корневые `AGENTS.md`/`PROJECT_CONTROL.md`/`HARNESS_CONTROL.md`, `docs/network/NET_SMOOTH1_R4_DURABLE_COMMIT_DESIGN_RU.md`, `docs/network/NET_SMOOTH1_R42_P0_WINDOWS_EXACT_EVIDENCE_RU.md`, `docs/network/NET_SMOOTH1_R42_SEAM_FULL_CHECKSUM_REPAIR_RU.md`, получить exact current Project Epoch и пройти Harness routing.
