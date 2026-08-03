# NX4 Client-Side Prediction and Reconciliation

## Статус

```text
checkpoint: v16.14.0-network-nx4-client-prediction-reconciliation
build_id: nx4-client-prediction-reconciliation
base checkpoint: v16.13.0-network-nx3-fixed-tick-authoritative-simulation
base commit: ac8ae0afdd47e0f290dbbc8af396add7aba60cda
branch: feature/nx4-client-prediction-reconciliation
status: implementation candidate
```

Машиночитаемый контракт: `config/network/nx4-client-prediction-reconciliation.v1.json`.

## Цель

NX4 устраняет прямое ощущение RTT при управлении собственным персонажем, сохраняя server authority.

До NX4 локальный player presentation менялся только после authoritative snapshot. После NX4 production M7 path работает так:

```text
InputMap / local intent
→ client input sequence
→ немедленный local fixed-tick prediction
→ predicted player presentation и camera
→ unreliable transition-history batch серверу
→ authoritative fixed-tick simulation NX3
→ compact snapshot + last_input_sequence
→ authoritative baseline
→ replay неподтверждённых predicted ticks
→ visual correction smoothing
```

Сервер остаётся единственным источником истины. Клиент предсказывает только presentation собственного игрока и не передаёт transform authority.

## Общий movement kernel

Клиент и сервер используют `PlayerMovementService.apply_fixed_tick()` с одним delta `1/60`.

Это исключает отдельную client-only модель скорости. Prediction не должна содержать обходы collision, acceleration или movement mode, которых нет в authoritative kernel.

`LunarPlayer` в network prediction mode не выполняет собственный `CharacterBody3D._physics_process()`. Его transform обновляется внешним prediction presentation, поэтому движение не симулируется дважды.

## Prediction history

`ClientPredictionReconciler` хранит bounded ring buffer:

```text
server/prediction tick
input sequence
canonical intent
predicted state after tick
```

Параметры:

```text
prediction tick:       60 Hz
maximum history:       256 ticks
history duration:      ~4.27 seconds
history policy:        SERVER_TICK_KEYED_RING_BUFFER_V1
sequence arithmetic:   wrap-aware
```

При переполнении удаляется самая старая запись, а overflow отражается в telemetry. Буфер не может расти в течение долгой сессии.

Если authoritative snapshot старше самой ранней сохранённой записи, частичный replay запрещён: клиент принимает authoritative state, очищает неполную историю и сбрасывает prediction clock к snapshot tick по политике:

```text
AUTHORITATIVE_RESET_WHEN_SNAPSHOT_TICK_OUTSIDE_RING_V1
```

Это аварийный путь для длительной паузы или задержки свыше примерно 4,27 секунды. Он предпочтительнее внешне убедительного, но математически неверного частичного replay.

## Reconciliation

Authoritative compact/full snapshot содержит:

```text
server_tick
position / velocity / yaw
last_input_sequence
```

Клиент:

1. находит predicted state для authoritative server tick;
2. измеряет prediction error;
3. принимает authoritative state как baseline;
4. удаляет подтверждённую историю;
5. повторно проигрывает тики после authoritative tick тем же movement kernel;
6. сохраняет текущее visual presentation через временный offset;
7. плавно сводит offset к authoritative predicted body.

Политика:

```text
AUTHORITATIVE_BASELINE_REPLAY_UNACKNOWLEDGED_TICKS_V1
```

Authoritative `last_input_sequence` продвигает локальный sequence cursor. Это важно, если ACK опережает локальное состояние после resync/reconnect или wrap.

Старый snapshot не откатывает prediction timeline. Compact snapshot с той же revision, но более новым server tick, принимается только если всё состояние кроме `server_tick/checksum` побайтно эквивалентно текущей replica. В таком случае replica revision не мутирует, но prediction clock и reconciliation продвигаются по политике:

```text
SAME_REVISION_IDENTICAL_STATE_ADVANCES_PREDICTION_CLOCK_V1
```

## Correction policy

```text
error < 0.03 m:
  IGNORE

0.03–0.15 m:
  SMOOTH, 150 ms

0.15–0.50 m:
  FAST, 80 ms

0.50–2.00 m:
  VERY_FAST, 50 ms

> 2.00 m:
  HARD
```

Correction применяется к presentation offset, а не изменяет camera резким скачком при небольшом расхождении. Hard correction используется для teleport, большого collision mismatch или серьёзного divergence.

## Camera и presentation

В M7 network playground локальная камера следует за predicted presentation. Authoritative snapshot не применяется напрямую к локальному `CharacterBody3D`.

Удалённые игроки пока сохраняют существующий presentation path. Полноценный delayed snapshot interpolation относится к NX5.

## Network conditions

Property-тест моделирует:

```text
base latency:      100 ms
jitter:            0–2 fixed ticks
snapshot loss:     deterministic
simulation:        180 ticks
```

При одинаковом shared movement kernel prediction остаётся точной, replay завершается без ошибок, history остаётся bounded, а финальный state совпадает с authority.

NX1 endpoint profiles остаются доступны для process/soak проверки реального ENet.

## Telemetry

Client report публикует:

```text
client_prediction.configured
client_prediction.prediction_tick
client_prediction.last_authoritative_tick
client_prediction.current_input_sequence
client_prediction.last_authoritative_sequence
client_prediction.history_size
client_prediction.ticks_predicted
client_prediction.ticks_replayed
client_prediction.reconciliations
client_prediction.corrections
client_prediction.hard_corrections
client_prediction.history_overflows
client_prediction.history_miss_resets
client_prediction.replay_failures
client_prediction.last_error_m
client_prediction.maximum_error_m
client_prediction.last_correction_mode
client_prediction.visual_offset_m
```

NX0 observability sample также получает prediction error, correction counts и bounded buffer size.

## Ограничения этапа

NX4 не реализует:

- delayed interpolation remote players;
- predicted pickup/drop/placement;
- rollback physics для произвольных объектов;
- owner transform authority;
- lag-compensated server rewind;
- async persistence.

Это задачи NX5, NX6, NX7 и NX9.

## Приёмка

Focused runner:

```text
RUN_NX4_CLIENT_PREDICTION_RECONCILIATION_TESTS.ps1
RUN_NX4_CLIENT_PREDICTION_RECONCILIATION_TESTS.sh
```

Обязательные свойства:

- локальный player меняет predicted state в том же render frame;
- 30/60/144 FPS дают одинаковый результат;
- общий movement kernel replay воспроизводит authority;
- 100 ms latency, jitter и snapshot loss не ломают convergence;
- ring buffer ограничен 256 тиками;
- snapshot за пределами ring buffer вызывает authoritative reset, а не частичный replay;
- sequence wrap корректен;
- server reject возвращает authoritative state;
- small correction сохраняет presentation и затухает;
- large correction выполняет hard reset;
- CharacterBody physics не выполняется параллельно prediction;
- M7 playable и restart/reconnect проходят;
- NX0–NX3 contracts остаются зелёными;
- protocol fingerprint несовместим с NX3.
