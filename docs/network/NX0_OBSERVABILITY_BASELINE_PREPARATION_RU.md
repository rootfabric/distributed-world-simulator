# NX0 — подготовка Observability Baseline

**Checkpoint candidate:** `v16.10.7-network-nx0-observability-preparation`
**Base:** commit `69bd7fc`
**Branch:** `feature/nx0-observability-baseline-preparation`
**Поведение production runtime:** не изменяется

## 1. Назначение checkpoint

Этот этап создаёт проверяемую границу перед первым изменением realtime path. Он не исправляет движение и не подключает network simulator. Вместо этого он:

- фиксирует подтверждённые болевые точки M7 как baseline probes;
- вводит versioned build fingerprint;
- вводит JSON-safe telemetry sample contract;
- вводит bounded telemetry collector;
- вводит versioned network-condition profiles и восемь presets;
- определяет точные integration points NX0;
- гарантирует, что следующий патч сможет измерить эффект, а не оценивать его субъективно.

## 2. Добавленные контракты

### `network_build_fingerprint.gd`

Поля:

```text
schema
build_id
git_commit
protocol_hash
world_id
session_token
checksum
```

`session_token` допускает только `session-id/<public-id>` для публичного несекретного binding ID либо `sha256/<64-lowercase-hex>` для SHA-256 digest. Любая иная строка, включая Raw bearer token, пароль и иной credential, отклоняется контрактом до сериализации в fingerprint, логи или telemetry.

`compare()` возвращает отдельные коды:

```text
BUILD_ID_MISMATCH
GIT_COMMIT_MISMATCH
PROTOCOL_HASH_MISMATCH
WORLD_ID_MISMATCH
SESSION_TOKEN_MISMATCH
```

`protocol_hash` строится из canonical contract versions и channel policy. В NX0 implementation он должен вычисляться одинаково launcher, server и client, а не задаваться вручную разными строками.

### `network_observability_sample.gd`

Sample содержит fingerprint, counters, gauges, bounded distribution summaries и per-channel packet/byte totals. Contract запрещает non-finite numbers, отрицательные counters и произвольные runtime objects.

### `network_telemetry_collector.gd`

Collector:

- не зависит от `Node` или `SceneTree`;
- имеет ограниченный sample window `1..4096`;
- считает p50/p95/p99 из bounded window;
- не хранит authoritative object references;
- публикует immutable JSON-safe sample;
- может очищать distribution window, сохраняя cumulative counters.

### `network_condition_profile.gd`

Profile валидирует latency ranges, percentages, queue/bandwidth limits, lag spike, disconnect duration и положительный deterministic seed. Production adapter в этом checkpoint отсутствует намеренно.

## 3. Integration map для следующего NX0 implementation

### 3.1 Launcher и session identity

Точки подключения:

- `scripts/runtime/launch_options.gd` — новые CLI options для session token и ожидаемого protocol hash;
- `scripts/runtime/runtime_descriptor.gd` — fingerprint в runtime descriptor;
- `PLAY_M7_NETWORKED_PLAYGROUND.ps1/.sh` — один session token для server и всех clients;
- M3 process tools — передача fingerprint в setup.

До JOIN client и server сравнивают build ID, commit, protocol hash, world и session token. Старые клиенты должны получать явный `FINGERPRINT_REQUIRED`, а не неясный timeout.

### 3.2 Transport boundary

`network_transport_boundary_v2.gd` должен публиковать telemetry hooks после:

```text
queue admission
queue rejection
dispatch success
dispatch failure
receive event
peer connect/disconnect
route generation change
```

Нельзя вычислять bytes по размеру Dictionary. Используется реальный encoded packet size из ENet adapter.

### 3.3 ENet adapter

`enet_multi_peer_transport_port.gd` должен сообщать:

- channel index;
- delivery mode;
- encoded packet bytes;
- packets sent/received;
- queue state, доступный через ENet API;
- RTT/packet loss statistics, если они доступны у `ENetPacketPeer`;
- peer-specific counters.

Сбор statistics не должен менять transfer mode, target peer или packet order.

### 3.4 M3 server

В `m3_dedicated_server_runtime.gd` instrumentируются:

- input receive time и input age;
- movement result count;
- delta/full snapshot publication count;
- server tick duration;
- movement checkpoint duration;
- command persistence duration;
- per-peer message amplification.

NX0 только измеряет текущую схему. Подавление result/snapshot относится к NX2.

### 3.5 M3 client

В `m3_graphical_client_runtime.gd` instrumentируются:

- send timestamp каждого input sequence;
- RTT до authoritative ACK/correction;
- async command result count;
- snapshot age;
- pending blocking operations;
- per-channel traffic.

В `playground_runtime.gd` instrumentируются текущая authoritative target error, hard snaps и smoothing distance. Это baseline, а не prediction.

## 4. Почему simulator ещё не подключён

Текущий ENet adapter работает через `ENetMultiplayerPeer`. Application-level wrapper, который просто удалит reliable frame до `put_packet()`, нарушит обещание reliable delivery. Для NX1 сначала нужно выбрать один из безопасных вариантов:

1. low-level ENet packet peer interception с сохранением retransmission semantics;
2. deterministic delay/queue на application frame и loss/reorder только для unreliable channels;
3. отдельный test transport adapter для process tests;
4. controlled OS-level netem outside Godot как supplementary gate.

До этого решения profiles служат единым контрактом параметров и CI matrix.

## 5. Порядок реализации NX0

1. Вычислять protocol hash из фактических contract versions и channel policy.
2. Передавать один session token launcher → server → clients.
3. Включить fingerprint в M7 reports и pre-JOIN exchange.
4. Отклонять mismatch до создания logical player session.
5. Добавить telemetry collector в server/client composition.
6. Подключить transport queue/packet hooks.
7. Подключить simulation/persistence/item timings.
8. Записать baseline для всех presets без fault injection сначала через реальные LOCAL runs.
9. Зафиксировать budgets и только затем начинать NX1/NX2.

## 6. Acceptance первого implementation checkpoint NX0

```text
fingerprint mismatch tests              PASS
fingerprint visible in every report     PASS
transport packet/byte counters          match encoded events
telemetry authoritative checksum        unchanged
telemetry memory window                  bounded
30-minute LOCAL soak                     no queue/memory growth
M7 focused regression                    PASS
full network regression                  PASS
```

## 7. Текущий результат подготовки

Подготовка считается готовой к независимому review, если:

- новые contracts проходят focused test;
- восемь presets проходят validation;
- baseline probes подтверждают существующее M7 поведение;
- Godot editor import проходит double-сборкой;
- M7 focused tests остаются зелёными;
- production runtime files M3/M7/ENet не изменены.
