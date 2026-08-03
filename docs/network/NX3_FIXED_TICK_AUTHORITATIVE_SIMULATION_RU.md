# NX3 Fixed-Tick Authoritative Simulation

## Статус

```text
checkpoint: v16.13.0-network-nx3-fixed-tick-authoritative-simulation
build_id: nx3-fixed-tick-authoritative-simulation
base checkpoint: v16.12.0-network-nx2-realtime-traffic-separation / fix2
base commit: f1abeca
branch: feature/nx3-fixed-tick-authoritative-simulation
status: implementation candidate
```

Машиночитаемый контракт: `config/network/nx3-fixed-tick-authoritative-simulation.v1.json`.

## Цель

NX3 отделяет authoritative movement simulation от времени прихода UDP-пакетов и FPS клиента.

До NX3 сервер применял movement непосредственно при обработке batch и использовал переходный packet-arrival budget. При jitter два одинаковых input-потока могли разбиваться на разные movement steps.

После NX3 production M7 path работает так:

```text
PLAYER_INPUT_BATCH arrival
→ validation / ownership / sequence window
→ per-player FixedTickInputBuffer
→ server scheduler 60 Hz
→ consume at most one new state transition per tick
→ shared PlayerMovementService with delta = 1/60
→ compact authoritative snapshot at 20 Hz
```

Пакетный callback больше не изменяет положение игрока.

## Fixed-tick scheduler

`FixedTickScheduler` имеет неизменяемый production-профиль:

```text
tick_rate_hz:              60
fixed_delta_seconds:       1/60
max_catch_up_ticks:        8
max_frame_delta_seconds:   0.25
```

Свойства:

- server tick монотонен;
- simulation delta не зависит от render/process FPS;
- отрицательный, NaN и infinite frame delta отклоняется;
- catch-up ограничен, чтобы пауза процесса не создавала неограниченный spiral of death;
- отброшенное из-за лимита время и catch-up batches отражаются в telemetry;
- после recovery scheduler продолжает durable server tick, а не начинает с нуля.

Dedicated server не использует packet arrival delta как physics delta.

## Per-player input buffer

Для каждого подключённого peer создаётся отдельный `FixedTickInputBuffer`.

Контракт:

```text
selection:        FIFO_STATE_TRANSITIONS_ONE_PER_FIXED_TICK_V1
jump:             EDGE_ON_CONSUMED_INPUT_V1
hold:             LAST_INPUT_WITH_250MS_FAILSAFE_V1
max pending:      64
sequence window:  2048
max queue age:    120 server ticks
```

Input принимается только при совпадении:

- transport session;
- logical player;
- ownership epoch;
- canonical batch checksum;
- допустимого sequence window.

Устаревшие, повторные и слишком далёкие sequence не изменяют authoritative state. Sequence использует диапазон `1..2147483647` и единое wrap-aware сравнение во всём пути: client ACK/pruning, input batch, server buffer и movement kernel. Batch, пересекающий границу `2147483647 → 1`, сохраняет корректный порядок.

## Transition history и redundancy

NX2 latest-wins transport может заменить несколько ещё не отправленных input frames последним frame. Поэтому клиент хранит не последние три render-сэмпла, а до трёх переходов состояния:

```text
idle → movement → idle
```

Политика:

```text
LAST_THREE_STATE_TRANSITIONS_FIXED_TICK_V1
```

Повторяющееся непрерывное состояние обновляет sequence и camera orientation последней записи, но не создаёт новую запись и не накапливает клиентскую длительность. Jump всегда остаётся отдельным edge.

Это гарантирует, что финальный idle frame не уничтожит короткий movement transition. При этом клиент не может ускорить игрока, передав завышенную `delta_seconds`: сервер её игнорирует.

## Movement simulation

`PlayerMovementService.apply_fixed_tick()` получает только канонический server delta `1/60`.

Начальные параметры полигона:

```text
walk:      6 m/s
sprint:   12 m/s
gravity: 1.62 m/s²
jump:    3.6 m/s
```

Одинаковый input replay даёт одинаковую дистанцию при client FPS 30, 60 и 144. Десять секунд walk дают 60 метров независимо от packet jitter и batching.

Jump применяется один tick как edge. Если новые input временно не приходят, последнее состояние удерживается максимум 15 ticks (`250 ms`), после чего движение fail-safe переходит в idle.

## Tick и revision

`server_tick` увеличивается только scheduler-ом. Join, item и presentation команды в fixed-tick profile могут увеличивать state revision, но не симуляционное время.

Movement state revision увеличивается только при фактическом изменении position, velocity, yaw или acknowledged input sequence.

NX3 не создаёт full snapshot или delta внутри каждого simulation tick. Snapshot собирается только replication cadence NX2:

```text
snapshot interval: 3 fixed ticks
snapshot rate:     20 Hz
```

Snapshot содержит `last_input_sequence`, поэтому NX2 unreliable acknowledgement/retransmission остаётся работоспособным.

## Telemetry

Server report публикует:

```text
fixed_tick_simulation.server_tick
fixed_tick_simulation.tick_rate_hz
fixed_tick_simulation.tick_delta_seconds
fixed_tick_simulation.ticks_simulated
fixed_tick_simulation.catch_up_batches
fixed_tick_simulation.failures
fixed_tick_simulation.pending_input_count
fixed_tick_simulation.input_buffers
fixed_tick_simulation.stale_input_drops
fixed_tick_simulation.input_hold_expirations
fixed_tick_simulation.last_tick_duration_ms
```

Также сохраняются NX0/NX1/NX2 метрики каналов, RTT, queues, movement suppression и snapshot retransmission.

## Безопасность и ограничения

NX3 не передаёт transform authority клиенту. Клиент задаёт только нормализованный intent.

Сервер проверяет:

- finite numeric values;
- диапазон movement vector;
- yaw/pitch;
- boolean jump/sprint;
- session/ownership;
- sequence freshness/window;
- bounded queue age/size.

Legacy `MOVE` API сохранён только для старых M1/M3 contract probes и не является production M7 realtime path. Production player movement использует `PLAYER_INPUT_BATCH` и fixed tick.

NX3 намеренно не реализует:

- локальную client-side prediction;
- rollback/replay predicted state;
- remote snapshot interpolation buffer;
- physics ownership transfer;
- async persistence.

Эти задачи относятся к NX4, NX5, NX7 и NX9.

## Приёмочные проверки

Focused runner:

```text
RUN_NX3_FIXED_TICK_AUTHORITATIVE_SIMULATION_TESTS.ps1
RUN_NX3_FIXED_TICK_AUTHORITATIVE_SIMULATION_TESTS.sh
```

Обязательные свойства:

- 600 ticks за 10 секунд при client FPS 30/60/144;
- identical distance для individual и batched input;
- jitter не изменяет authoritative speed;
- client `delta_seconds` игнорируется;
- jump не повторяется при hold;
- stale input не применяется;
- sequence wrap корректен сквозным образом, включая batch `2147483647 → 1`, ACK/pruning и movement kernel;
- M7 playable и restart/reconnect проходят;
- NX0/NX1/NX2 contracts остаются зелёными;
- protocol fingerprint не совместим с предыдущим NX2 wire contract.
