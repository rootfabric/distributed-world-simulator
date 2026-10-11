# NET-SMOOTH1 R4.1 — шлюз отложенного ACK: proof kernel, не production integration

Статус: **IMPLEMENTED_KERNEL_ONLY / NOT_WIRED / NOT_VERIFIED**. Основа: R4.0 evidence HEAD `8be119ccca55ea0db3958e762c511edeb0c760bf` (PR #754, далее родитель PR #753 и #751). Новая stacked branch `repair/net-smooth1-r41-pending-ack-proof-r1`. Никакого merge.

## Доказанное основание

R4.0 exact Windows: 24 успешных durable-коммита, checksum player/item p50 0.48/0.74 мс, outbox p50 122.27 мс, ожидание предыдущего периодического writer до 1417 мс, полный синхронный persist p50 846.02 мс, до 1601.97 мс. Server `message_ms` p99 883 мс, frame p99 1274 мс; частота 23 Гц. Воспроизводимое нарушение текущих LOCAL-порогов; понижать их запрещено. `test_m6_dedicated_recovery_processes` временами не успевает наблюдать ENet force-kill за 45 секунд под нагрузкой и остаётся отдельным timing-flake.

## Скоуп этой поставки

- `scripts/persistence/m6_pending_durable_ack_gate.gd`: чистый однопоточный **escrow/state machine**, не пишет на диск и не рассылает пакеты. Хранит только один незафиксированный command generation, ограниченный готовый ACK буфер, строгую монотонность поколений и session + logical-player + ownership-epoch fence.
- `tests/runtime/test_net_smooth1_r41_pending_durable_gate.gd`: 66 детерминированных assert (локально Godot Linux 4.7.1 double PASS), включая no early ACK, out-of-order generation, duplicate, backpressure, lost peer during worker commit, failure closed, M6-restart semantics и периодический writer generation.
- Добавить тест в `tools/net_smooth1/run_net_smooth1.py`: ожидается **21** focused tests (17 обычных + 4 process), до полноценного Windows подтверждения тест считается Implementer-only.
- Живой runtime `m3_dedicated_server_runtime_p2.gd` в R4.1-core **не изменён**. Не приписывать данному PR устранение фризов или перевод команд на async.

## Формальный контракт шлюза

`stage() -> STAGED` (ACK нет) → `mark_submitted() -> COMMIT_PENDING` (ACK нет) → `complete(EXACT generation + success from repository) -> ACK_ELIGIBLE` → `peek_ack()` → `mark_delivered()` только после успешной реальной постановки ответа в надёжную очередь. При записанной ошибке `fail_closed`: замораживаются новые команды и ACK. При disconnect ещё не доставленный ACK старой session отбрасывается, но уже успешный commit остаётся в M6-долговечном состоянии; retry по старому operation_id должен возвращаться через M6 replay, а не вызывать новую мутацию.

`observe_periodic_commit()` принимает только следующее поколение при отсутствии неполного command checkpoint; checkpoint generation на диске остаётся single-owner. `can_accept_mutation()` блокирует вход при pending и при полном ready queue. Шлюз не знает о сетевых пакетах, поэтому интеграция **обязана** проверять его перед всеми мутирующими handler'ами и ограничить публикацию uncommitted state.

## Следующий обязательный product integration slice R4.1-P1

1. Заморозить R4.0 HEAD и составить **схему всех call sites**, в том числе `JOIN_ACK`, `ITEM_COMMAND`, `PRESENTATION`, `MOVE` compatibility, `LEAVE`, `DISCONNECT`, mining, Construction, world mutations и NX3 fixed-tick side effects. Не ограничиваться одним `_send_result`: `JOIN_ACK` и broadcast обходят этот helper.
2. После `stage_committed` на main thread снимок authority+replay должен быть detached и согласован по revision/tick/quiescence; foreground `_complete_async_movement_checkpoint(true)` убрать только при event-driven single-writer progression. Нельзя одновременно писать periodic и command checkpoint в один repository; пока periodic busy — poll и выдержка, а не busy-spin.
3. Асимметричный результат: **не публиковать** неподтверждённый успешный result, Item Graph delta, Construction delta, full snapshot, новый JOIN state или authority transfer, пока committed checkpoint generation не подтверждён. Временные мутации при отказе восстанавливать из последнего durable generation либо перейти в fail-closed stop; исключить видимость незаписанной мутации другим игрокам. Нельзя продолжать конфликтующие canonical mutations во время pending commit.
4. При успехе разрешить ACK, outbox delivery, связанные broadcasts **в исходном causal порядке**. ACK с устаревшей session запрещён; после reconnect использовать canonical M6 replay (один outcome по operation_id), не произвольное удаление ledger.
5. Fault injection **сначала в unit/process**: before stage; after mutation; after staged outbox; while prior periodic writer busy; after frozen checkpoint; during worker write; before atomic replace; after replace before ACK; after ACK before delivered; crash+restart+retry; stale epoch/session; two clients ordering. Проверить поколение, checksum, item graph, no-double-spend, crash recovery. Без такой матрицы называть R4.1 реальным durable repair нельзя.
6. Windows exact 2 GUI Quaternius + 24 durable-команды + sprint/movement/reconnect/restart. Сравнить 3 парных прогона R4.0/R4.1, p50/p95/p99/p99.9/max (frame, `message_ms`, `persistence_ms`, `wait_async_ms`, command latency, durable throughput, ledger growth). Те же пороги 25/50/100 мс, 59 Гц. Не «перекрашивать» FAIL.

## Open control-plane blocker

GitHub Project Control на предыдущих R3/R3.1/R4 кандидатах: `CANDIDATE_MAIN_DRIFT`, observed `3d7672cb…` != canonical `fc69771a…`. Main-owned registry не переписывать из этой feature-ветки; собирать exact отчёт и независимый verdict. WARNING ECO/FABRIC family-local не означает runtime fail. Reviewer/Verifier обязателен, implementer cannot self-accept.
