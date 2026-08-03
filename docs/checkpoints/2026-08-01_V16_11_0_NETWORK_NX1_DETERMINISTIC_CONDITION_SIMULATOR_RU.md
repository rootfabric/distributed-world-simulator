# Checkpoint v16.11.0 — NX1 Deterministic Network Condition Simulator

## Решение

```text
checkpoint: v16.11.0-network-nx1-deterministic-condition-simulator
build_id: nx1-deterministic-network-condition-simulator
branch: feature/nx1-deterministic-network-condition-simulator
base checkpoint: v16.10.8-network-nx0-observability-baseline
base commit: f1abeca
status: implementation candidate fix2
```

## Реализовано

- production `NetworkConditionSimulatorPort` между boundary и ENet;
- deterministic PRNG streams по seed/direction/channel/effect;
- real/manual clock;
- outgoing/incoming latency и jitter;
- unreliable loss, duplication и reorder;
- reliable retransmission delay без application-drop;
- burst loss windows;
- bandwidth serialization и bounded queues;
- periodic/manual lag spike;
- periodic/manual transport blackout;
- runtime profile switching;
- восемь JSON presets;
- CLI и manual playground integration;
- simulator telemetry и runtime reports;
- gap-tolerant latest-wins для `UNRELIABLE_SEQUENCED`;
- независимые sequence-cursors по delivery class и ENet channel;
- удержание уже queued frames во время manual blackout и lag spike;
- удержание уже готовых `MESSAGE_RECEIVED` в `_ready_events` при active incoming blackout/spike;
- lifecycle events проходят active incoming block, FIFO сообщений сохраняется;
- unit/property/integration и real ENet process tests.

## Границы

`disconnect_duration_ms` моделирует транспортный blackout, а не закрытие ENet socket. Уже queued frames удерживаются до завершения blackout; новые unreliable frames внутри активного blackout теряются, новые reliable сохраняются. Manual lag spike удерживает уже queued frames до deadline. Готовые `MESSAGE_RECEIVED` также блокируются до deadline, тогда как lifecycle events остаются доступными. Физический restart/reconnect остаётся в M7 recovery profile.

Профиль применяется на одном endpoint. Одинаковые профили на обоих концах складывают воздействие.

NX1 не изменяет movement amplification, snapshot cadence, fixed-tick simulation или persistence.

## Acceptance gate

До решения `ACCEPTED` требуется независимый managed-MCP прогон после editor import:

```text
NX1 focused
network non-process regression
ENet process regression
M3 graphical multiplayer
M7 playable network
M7 restart/reconnect recovery
unexpected exits = 0
remaining Godot processes = 0
```

Фактические результаты implementation candidate фиксируются в
`validation/v16.11.0-network-nx1-deterministic-condition-simulator-validation.json`.

## Implementation validation

Прямой controlled headless-прогон через приложенный Godot 4.7.1 double завершён:

```text
Editor import:                     PASS
NX1 focused:                       6/6 PASS
NX0 preparation contracts:        115 assertions
NX0 baseline contracts:           150 assertions
NX1 contracts:                    282 assertions, 0 failures
NX0 compatibility handshake:       31 assertions, 0 failures
NX1 conditioned ENet:              27 assertions, 0 failures
Network non-process:               49/49 PASS
ENet process regression:            4/4 PASS
M3 graphical multiplayer:          previous fix1 managed 56 assertions
M7 playable network:               previous fix1 managed 34 assertions
M7 restart/reconnect recovery:     previous fix1 managed 36 assertions
```

Focused, non-process и ENet process результаты являются fix2 implementation evidence. M3/M7 значения относятся к независимому review fix1 и должны быть повторно подтверждены для fix2. Окончательное решение `ACCEPTED` принимается после независимого managed-MCP прогона. Перед process suites обязателен
editor import, чтобы сформировать Godot class/import cache.
