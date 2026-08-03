# NX0 Observability Baseline

## Статус

```text
checkpoint: v16.10.8-network-nx0-observability-baseline
build_id: nx0-observability-baseline
base: v16.10.7-network-nx0-observability-preparation
source base commit: 69bd7fc
branch: feature/nx0-observability-baseline
status: accepted
```

## Назначение

NX0 подключает подготовленные контракты наблюдаемости к реальному M3/M7 ENet-пути. Этап не пытается исправлять движение, частоту snapshot или persistence. Его задача — сделать несовместимые запуски невозможными и получить измеримый baseline до NX1/NX2.

## Compatibility handshake

Порядок соединения теперь следующий:

```text
ENet connected
→ peer TRANSPORT_CONNECTED
→ COMPATIBILITY_HELLO по CONTROL
→ сервер сверяет fingerprint
→ COMPATIBILITY_ACK или COMPATIBILITY_REJECTED
→ peer SYNCHRONIZING/READY
→ только после этого клиент отправляет JOIN
```

Fingerprint связывает:

```text
build_id
git_commit
protocol_hash
world_id
session_token
```

Сервер выполняет проверку до вызова `NetworkedGameplayService.join()`. Любое игровое сообщение до успешного handshake отклоняется кодом `FINGERPRINT_REQUIRED`.

Коды несовместимости детерминированы:

```text
BUILD_ID_MISMATCH
GIT_COMMIT_MISMATCH
PROTOCOL_HASH_MISMATCH
WORLD_ID_MISMATCH
SESSION_TOKEN_MISMATCH
```

Повтор уже принятого HELLO идемпотентно получает ACK, учитывается как replay и не создаёт повторный JOIN.

`session_token` не является credential. Допустимы только:

```text
session-id/<public-id>
sha256/<64-lowercase-hex>
```

Bearer token, пароль, cookie или иной секрет передавать в fingerprint запрещено контрактом.

## Protocol manifest

`network_protocol_manifest.gd` вычисляет SHA-256 по версиям wire-контрактов и текущей channel policy. В manifest включены frame/event/session/boundary contracts, M3 message schema, player/item contracts, handshake schemas и observability sample.

Runtime descriptor содержит и валидирует:

```text
network_fingerprint
network_protocol_manifest
```

CLI поддерживает явную инъекцию build metadata:

```text
--network-session-token=
--network-build-id=
--network-git-commit=
--network-protocol-hash=
```

Launcher M7 генерирует единый публичный session ID на запуск и передаёт его серверу и обоим клиентам.

## Telemetry

Collector хранит cumulative counters, gauges и bounded distribution windows. Сэмпл JSON-safe, checksum-защищён и не содержит ссылок на runtime objects.

### Transport boundary

Измеряются:

```text
packets/bytes sent and received per frame channel
outbound pending messages/bytes
reliable queue depth messages/bytes
queued/dispatched/failed frames
poll duration
peer connect/disconnect/error events
```

Фактический размер ENet-пакета используется, когда adapter его возвращает; loopback использует размер канонического frame JSON.

### ENet

По каждому активному peer публикуются:

```text
rtt_ms
rtt_variance_ms
packet_loss_raw
packet_loss_percent
```

Metadata входящего пакета читается до `get_packet()`, чтобы Godot не потерял channel/mode текущего пакета.

### Dedicated server

Измеряются process iterations и duration, message processing, input age, peer statistics, handshake counters, checkpoint generation и persistence duration.

`server_tick_duration_ms` в NX0 означает длительность текущего `_process()` callback. Это ещё не fixed simulation tick; он появится в NX3.

### Graphical client

Измеряются process duration, server message/snapshot/delta age, handshake RTT, pending operation timers и latency по классам команд:

```text
movement
presentation
item
join
leave
```

Таймер операции удаляется при ACK, rejection, send failure, timeout, disconnect и stop.

## Сохранённые проблемы M7

NX0 намеренно не меняет:

- `delta_seconds`, вычисляемый по времени прихода input;
- успешный `COMMAND_RESULT` на каждый `PLAYER_INPUT`;
- delta и полный snapshot после каждого input;
- movement checkpoint каждые 1500 ms;
- текущие три ENet-канала и reliable delivery policy.

Это baseline для NX2/NX3, а не скрытая попытка реализовать их внутри наблюдаемости.

## Тесты

Focused runner:

```text
RUN_NX0_OBSERVABILITY_BASELINE_TESTS.ps1
RUN_NX0_OBSERVABILITY_BASELINE_TESTS.sh
```

Профиль выполняет:

1. editor import;
2. принятые preparation contracts;
3. NX0 manifest/handshake/descriptor/telemetry contracts;
4. настоящий ENet process-test.

Process-test запускает dedicated server и два headless probe:

- несовместимый session binding получает `SESSION_TOKEN_MISMATCH`, `joins` остаётся нулём;
- совместимый fingerprint получает ACK, но без JOIN игрок также не создаётся.

Фактическая проверка implementation candidate:

```text
focused:                       4/4 PASS
preparation contracts:        115 assertions
NX0 contracts:                150 assertions
real ENet handshake:           31 assertions
network non-process:          48/48 PASS
ENet process regression:       4/4 PASS
M3 graphical:                  56 assertions
M7 playable:                   34 assertions
M7 recovery:                   36 assertions
```

## Следующий этап

После принятого NX0:

```text
NX1 — Deterministic Network Condition Simulator
```

NX1 должен оборачивать transport boundary, сохранять reliable retransmission semantics и быть детерминированным по seed. Изменение traffic amplification относится к NX2.
