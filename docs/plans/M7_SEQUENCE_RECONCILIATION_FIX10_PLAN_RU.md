# M7 FIX10 — Sequence-Aware Prediction Reconciliation

## Причина фикса

FIX9 подтвердил, что оставшееся ощущение «подпружиненного» локального движения не связано с frame budget, UI или серверными stalls. В длинном двухклиентском LOCAL-прогоне сервер сохранял нулевой backlog и небольшой input pending, а обычный клиентский hot path оставался в миллисекундном диапазоне. При этом локальные клиенты накопили 141 и 155 soft corrections, `history_miss_resets = 13`, с максимальной ошибкой примерно 0.30 м и 0.498 м. Предметы при этом не терялись.

Корневая проблема — смешение двух временных осей:

- клиент предсказывает движение фиксированно на 60 Hz;
- movement intent отправляется примерно на 30 Hz и имеет `input_sequence` + уже существующий `client_tick`;
- сервер применяет этот sequence на своём будущем `server_tick`, после транспортной задержки;
- старый reconciliation в основном сравнивает состояние по абсолютному server tick.

Одинаковый `input_sequence` поэтому может соответствовать разным wall-clock ticks на клиенте и сервере. Нормальный transport lead превращался в 0.1–0.5 м ложной positional divergence, затем FIX8 visual-offset compositor плавно отрабатывал её. Частые корректировки и ощущались как резинка.

## Цель

Перейти от «server tick как acknowledgement boundary» к семантической точке командного потока:

`input sequence S + original client prediction tick C + authoritative post-input state`.

Сервер должен сохранить состояние сразу после первого применения S и вернуть его клиенту как маленький sidecar. Клиент сверяет эту authority baseline с локальной историей именно в C, затем детерминированно переигрывает локальные ticks после C до текущего predicted tick.

## Инварианты

FIX10 не меняет:

- server authority;
- 60 Hz authoritative simulation;
- частоту movement snapshots;
- canonical gameplay snapshot schema/checksum;
- Item Graph authority/prediction;
- FIX8 correction bounds;
- FIX9 frame-budget instrumentation;
- NX3 queue selection/hold/jump/pressure-compaction semantics.

Sidecar находится вне canonical snapshot, поэтому не меняет его checksum. На каждый peer отправляется только acknowledgement его собственного локального игрока.

## Реализация

### 1. Server input timeline metadata

`fixed_tick_input_buffer_fix10.gd` наследует текущий input buffer и сохраняет `client_tick` выбранного нового sequence. После consumption доступны:

- `fix10_client_tick`;
- `fix10_input_applied_server_tick`;
- `fix10_input_sequence`.

Сама очередь и порядок consumption не меняются.

### 2. Authoritative post-input baseline

После server fixed tick, в котором впервые применён новый sequence, dedicated runtime захватывает для этого игрока:

- `input_sequence`;
- исходный `client_tick`;
- `applied_server_tick`;
- position;
- velocity;
- orientation yaw;
- state revision.

Это состояние соответствует тому же логическому месту потока, которое клиент имел сразу после локального применения этого input sequence.

### 3. Snapshot sidecar

`GAMEPLAY_SNAPSHOT` и `COMPACT_GAMEPLAY_SNAPSHOT` получают внешние поля:

- `prediction_ack_policy = SERVER_ECHOED_POST_INPUT_BASELINE_V1`;
- `prediction_ack = {...}`.

Canonical snapshot внутри сообщения не изменяется.

### 4. Client routing

FIX10 graphical client runtime извлекает sidecar только из full/compact gameplay snapshots и перед reconciliation регистрирует его в prediction reconciler. При отсутствии/ошибке sidecar остаётся существующий FIX8 fallback.

### 5. Client input timeline

FIX10 reconciler ведёт отдельный bounded timeline до 512 prediction ticks. Запись содержит:

- client prediction tick;
- active input sequence;
- canonical intent;
- resulting predicted state.

Timeline независим от старого NX4 `_history`, который может очищаться при предыдущих reconciliations.

### 6. Ack-baseline replay

Если acknowledgement валиден:

1. находится local state на `client_tick C`;
2. проверяется тот же `input_sequence S`;
3. authority post-input state становится baseline;
4. все локальные ticks `C+1 ... current_prediction_tick` детерминированно переигрываются shared movement kernel;
5. correction считается уже между старым current predicted state и reconstructed current state.

Server wall-clock tick не используется как replay boundary.

Повторный snapshot с тем же ack классифицируется как `ACK_REPLAY` и не должен повторно двигать predicted state.

При несовпадении sequence, дырке timeline или невалидном sidecar FIX10 не угадывает состояние и использует inherited FIX8 path.

## Наблюдаемость

Server:

- ack captures;
- capture mismatches;
- snapshots with ack;
- max server-tick minus client-tick lag.

Client transport:

- sidecars received/registered/rejected.

Prediction:

- ack reconciliations;
- ack replays;
- replayed ticks;
- ack history misses/mismatches;
- baseline error;
- reconstructed-present error;
- corrections per 1000 prediction ticks.

## Acceptance

Автоматический gate должен пройти FIX10 focused test и все FIX9/FIX8/NX4 regressions. Затем нужен двухклиентский LOCAL movement/item stress не менее 5 минут.

Начальные acceptance thresholds:

- hard corrections = 0;
- server ack capture mismatches = 0;
- client sidecar rejects = 0;
- ack reconciliations > 0;
- ack mismatches/registration rejects = 0;
- ack history misses <= 5;
- corrections <= 5 на 1000 predicted ticks;
- maximum prediction error <= 0.50 м;
- reconstructed-present error <= 0.35 м;
- server process <= 75 ms;
- report build <= 25 ms;
- client >=50 ms process frames <= 2.

Главный ручной критерий: при постоянном движении/поворотах/старте/остановке исчезают или резко сокращаются периодические микрооткаты и ощущение «пружины», при этом pickup/drop/transfer продолжают сходиться и предметы не теряются.

Если FIX10 убирает phase corrections, но остаются редкие реальные divergence corrections, следующий шаг должен настраивать только подтверждённый источник расхождения, а не маскировать его увеличением smoothing duration.

## FIX10 fix2 — MTU-safe realtime snapshots

Полный Windows gate исходного FIX10 показал отдельный transport blocker, не связанный с reconciliation: `COMPACT_GAMEPLAY_SNAPSHOT` с prediction-ack sidecar иногда превышал безопасный размер ENet unreliable packet. Godot отправляет логический `UNRELIABLE_SEQUENCED` через raw unreliable/unsequenced transport. После fragmentation физический transfer-mode, наблюдаемый на приёмнике, может отличаться от ожидаемого, а принятый `STRICT_CHANNEL_AND_TRANSFER_MODE_V1` корректно карантинит peer как protocol violation.

FIX10 fix2 не ослабляет strict transport contract и не переводит snapshot channel на ordered/reliable delivery. Вместо этого сервер до `send_to_peer()` измеряет точный canonical ProtocolFrame v2 в UTF-8 — те же байты, которые затем кодирует ENet port. Для realtime movement snapshot действует политика `OPTIONAL_ACK_OMISSION_THEN_DROP_OVERSIZE_V1`:

1. если frame <= 1350 bytes — отправляется как раньше;
2. если frame > 1350 bytes и содержит optional `prediction_ack` — frame не коммитится в transport queue, sidecar удаляется и frame строится заново с тем же peer sequence;
3. если даже компактный frame без ack > 1350 bytes — этот realtime snapshot пропускается, а не отправляется fragmented;
4. reliable full/resync snapshots остаются без изменений;
5. следующий movement snapshot может снова содержать свежий acknowledgement, поэтому единичное omission не ломает FIX10 semantic boundary.

Добавлена telemetry:

- `fix10_unreliable_mtu_policy`;
- `fix10_unreliable_safe_packet_bytes`;
- `fix10_ack_omitted_for_mtu`;
- `fix10_oversized_unreliable_frames_prevented`;
- `fix10_movement_snapshots_dropped_for_mtu`;
- `fix10_max_unreliable_candidate_bytes`;
- `fix10_max_unreliable_sent_bytes`;
- `fix10_max_without_ack_bytes`.

Fix2 acceptance дополнительно требует отсутствия ENet warning об unreliable packet выше MTU, отсутствия `transport_peer_protocol_violations`/peer quarantine в нормальном LOCAL two-client прогоне и успешного M7 item/player convergence.
