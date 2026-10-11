# NET-SMOOTH1 R4.1-P1 — подключение pending-ACK gate к production durable-командам

Статус: **IMPLEMENTED / IMPLEMENTER-VALIDATED / NOT_VERIFIED**. База: exact HEAD `fea60fcf58cc413c8d4c4eebec5c9d919d4e9dd9` (PR #755, tree `39b16dd95a8f7be8a3acff5995e174a2cc781a1f`). Ветка: `repair/net-smooth1-r41-p1-durable-ack-integration-r1`. Никакого merge; VERIFIED требует независимого Reviewer/Verifier.

## Что изменено

Единственный изменённый runtime-файл: `scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime_p2.gd`. Proof kernel `scripts/persistence/m6_pending_durable_ack_gate.gd` не изменён.

1. **Инициализация**: gate создаётся в `_setup_recovery()` после recovery/seed и конфигурируется фактическим `_checkpoint_generation` с диска. Рестарт создаёт новый instance; идемпотентность retry по operation_id остаётся за каноническим M6 replay (gate в replay не участвует).
2. **Escrow durable-команд**: `_persist_command_result()` получил optional identity (`peer_id`, `session_id`, `ownership_epoch`). Для успешных результатов: `stage()` → `mark_submitted()` до checkpoint, `complete(EXACT generation, success from repository)` только после `persisted.success`. Поколение команды берётся после барьера `_complete_async_movement_checkpoint(true)`, поэтому конфликт с async movement writer невозможен; наблюдение периодических поколений pending-толерантно.
3. **Наблюдение всех путей публикации поколений**: командный checkpoint (escrow-путь), командный checkpoint неуспешного результата (observe как periodic), periodic movement checkpoint (sync и async writer), seed/shutdown checkpoint. Single-owner поколения сохранён: gate никогда не пишёт checkpoint.
4. **Fencing**: все мутирующие handler'ы (JOIN, MOVE, PRESENTATION, ITEM_COMMAND, LEAVE, DISCONNECT) проверяют `can_accept_mutation()` до применения мутации; backpressure/fatal → reject без публикации. NX2/NX3 realtime movement input остаётся вне durable-контракта (документированное исключение R4.0).
5. **Асимметричная публикация**: успешный result/JOIN_ACK/LEAVE_ACK отправляется только после durable commit; `mark_delivered()` только после фактической успешной постановки в надёжную очередь. Broadcast delta/snapshot/item snapshot публикуются только после `persisted.success` (инвариант сохранён и усилен escrow). Construction snapshot игроку отправляется после durable JOIN commit.
6. **Fail-closed**: `_enter_persistence_failure()` вызывает `gate.fail_closed()` — новые мутации и новые ACK замораживаются; частичный отказ диска не даёт ложного ACK.
7. **Reconnect/disconnect**: `_handle_disconnect()` вызывает `discard_stale_session(peer, session)` — недоставленный ACK старой session карантинится, commit остаётся durable; retry старого operation_id разрешается через M6 replay (один outcome), повторной мутации нет. Строгая проверка session/epoch в `peek_ack`/`mark_delivered` наследуется от kernel; ownership epoch хранится с JOIN и используется при LEAVE/DISCONNECT.
8. **Отчётность**: `durable_ack_gate` добавлен в `_persistence_report()` для evidence.

## M6 recovery и durable-before-ACK не ослаблены

- Синхронный `persist_checkpoint` → atomic repository commit остаётся барьером перед любым ACK.
- `_complete_async_movement_checkpoint(true)` перед командным checkpoint сохранён.
- Replay ledger, outbox checksum, seed checkpoint не изменены; focused-набор `test_m6_dedicated_recovery_contracts` 126/126, `test_v0_p3_m6_resource_replay_outbox` 22/22, `test_net_smooth1_async_checkpoint` 38/38 на интеграционном HEAD.

## Что НЕ сделано в этом slice (честно)

- Persist остаётся синхронным на main thread: этот slice подключает контракт escrow/fencing/fail-closed, но **не** устраняет фризы и не переводит checkpoint в async. Производительность всё ещё ожидается FAIL против порогов 25/50/100 мс.
- Performance-пороги не менялись. Сравнение p99 с R4.0 и 24+ durable-команды на Windows GUI, crash/fault matrix и независимый Reviewer/Verifier — обязательные следующие шаги до какого-либо VERIFIED.

## Durable workload, Windows GUI exact (этот HEAD)

Запуск: `run_net_smooth1.py --mode gui --scenario durable-commands --duration 120`, артефакты `artifacts/net-smooth1/r41-p1-durable-commands-r3/` (r1 — без внешних Quaternius-ассетов, r2 — cold-import ERROR на отсутствующих gltf-текстурах `T_*_png.png`, добавлены локальные alias-копии; ассеты gitignored, tree не изменён).

- Функционально: 2 GUI Quaternius клиента (QUATERNIUS_RETARGET), **24/24 успешных durable-команд** (`inventory.select_hotbar`, `inventory.permission_probe`), duplicate operation_id — идемпотентный replay без повторной мутации, item graph revision монотонно растёт, 0 rejections, 0 persistence failures, сервер вне fail-stop.
- Функциональная crash/recovery-матрица покрыта process-наборами: M6 force-kill crash+restart+M6 replay+reconnect, M7 reconnect+ownership epoch+continuation, NX2 physical channel (21/21 focused).
- Производительность: FAIL, как и предсказано для R4.1-P1 (persist всё ещё синхронный). Server frame p99 ≈ 1782 мс, message_ms p99 ≈ 1515 мс, frame p999/max ≈ 6348/9543 мс; client p99 ≈ 36–44 мс с редкими >5 с gap'ами при 20 Гц movement snapshot. Профиль того же порядка, что R4.0 (frame p99 1274 мс, message p99 883 мс); пороги 25/50/100 мс и 59 Гц не изменялись. Парные A/B прогоны R4.0/R4.1 (3×) — задача Windows Verifier, не implementer self-accept.

## Валидация implementer (этот HEAD)

- Analyzer unittest: 20/20 OK.
- Focused baseline (base HEAD, Windows exact): 20/21 PASS, единственный FAIL `test_m6_dedicated_recovery_processes` — документированный ENet force-kill observation timing-flake («A observed dedicated crash»); recovery при этом прошёл (replacement server recovered, continued gameplay, no persistence failure).
- Полный focused набор на интеграционном HEAD (Windows exact, Godot 4.7.1 double): **21/21 PASS**, включая 4 process-набора: `test_m6_dedicated_recovery_processes`, `test_m7_playable_networked_processes` (54/54), `test_m7_playable_networked_recovery_processes` (36/36), `test_nx2_physical_channel_processes`. Артефакты: `artifacts/net-smooth1/r41-p1-integration-focused-r2/`.
- Зафиксированные в ходе интеграции дефекты и их исправление: (1) fencing ошибочно отклонял JOIN при выключенной persistence (M7 playable) — gate теперь активен только при persistence-enabled; (2) потеря наблюдения поколения, когда async movement checkpoint завершался внутри командного барьера при escrow-нутой команде (`DURABLE_GATE_GENERATION_OUT_OF_ORDER`, replacement server) — async writer теперь drain'ится до escrow, поколение staging всегда совпадает со следующим свободным.
