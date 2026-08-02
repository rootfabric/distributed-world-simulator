# NX2 Realtime Traffic Separation

## Статус

```text
checkpoint: v16.12.0-network-nx2-realtime-traffic-separation
build_id: nx2-realtime-traffic-separation
base checkpoint: v16.11.0-network-nx1-deterministic-condition-simulator / fix2
base commit: f1abeca
branch: feature/nx2-realtime-traffic-separation
status: implementation candidate
```

Машиночитаемый контракт: `config/network/nx2-realtime-traffic-separation.v1.json`.

## Цель

NX2 устраняет amplification realtime-трафика, не меняя server-authoritative модель и не смешивая этап с будущими fixed-tick/prediction работами.

До NX2 production M7 input создавал отдельный успешный `COMMAND_RESULT`, player delta и полный snapshot. Item-команды, movement и full resync конкурировали в недостаточно разделённом transport path.

После NX2:

```text
client input sample
→ transition-based redundancy batch
→ INPUT / raw ENet unreliable
→ authoritative server apply
→ без success result и per-input snapshot
→ compact snapshot максимум один раз за 50 ms
→ SNAPSHOT / raw ENet unreliable
```

## Каналы

| Канал | ENet index | Delivery contract | Назначение |
|---|---:|---|---|
| `CONTROL` | 0 | `RELIABLE_ORDERED` | handshake, join/leave, rejection/control |
| `INPUT` | 1 | `UNRELIABLE_SEQUENCED` | movement input batches |
| `SNAPSHOT` | 2 | `UNRELIABLE_SEQUENCED` | compact player/world snapshots |
| `ITEM` | 3 | `RELIABLE_ORDERED` | inventory, pickup, drop, placement, mount |
| `RESYNC` | 4 | `RELIABLE_ORDERED` | join state, full Item Graph snapshot, explicit resync |
| `TELEMETRY` | 5 | `UNRELIABLE_SEQUENCED` | optional debug/metrics traffic |

`UNRELIABLE_SEQUENCED` является application-level контрактом. В ENet он передаётся через raw `TRANSFER_MODE_UNRELIABLE`; latest-wins, gap tolerance и stale suppression выполняются единожды в `NetworkTransportBoundaryV2`. Это исключает двойную sequencing-политику и зависимость ENet ordered от размера соседних пакетов.

Семантика версионируется в `protocol_hash`:

```text
RAW_ENET_UNRELIABLE_APPLICATION_SEQUENCED_V1
DELIVERY_CLASS_ENET_CHANNEL_V1
```

## Независимые outbound streams

Boundary больше не хранит один общий peer FIFO. Очередь разделена по:

```text
peer × delivery class × logical/ENet channel
```

Политики:

```text
reliable: FIFO_PER_STREAM_V1
realtime: LATEST_PENDING_TRANSACTIONAL_REPLACEMENT_PER_STREAM_V1
flush:    PRIORITY_ROUND_ROBIN_V1
```

Новый input или snapshot заменяет только ещё не отправленный кадр того же realtime-stream. Замена транзакционна: если новый кадр не проходит queue byte/message limits, прежний pending-кадр и его reservation остаются неизменными. Reliable item/control/resync FIFO не удаляется и не блокируется stale realtime-состоянием.

## Movement input batching

Клиент читает input с render/physics частотой, но отправляет не чаще одного пакета за `33 ms`.

`PlayerInputBatch` содержит до трёх переходов состояния:

```text
idle → movement → idle
```

Одинаковые подряд состояния не создают новые записи. Последняя sequence обновляется, а длительность активного движения ограниченно накапливается. Благодаря этому длинная серия idle-samples не вытесняет ещё не подтверждённый movement transition.

Политика:

```text
TRANSITION_SEGMENTS_V1
max entries: 3
max segment delta: 0.25 s
```

Пакет имеет compact wire-поля и проходит обязательный JSON encode/decode round-trip до checksum. Целевой размер realtime frame — менее `1200 bytes`, без unreliable fragmentation.

## Server-side movement budget

NX2 ещё не реализует NX3 fixed tick. Сервер сохраняет ограниченный authoritative budget из времени между прибытием packet batches:

```text
clamp(packet_arrival_delta, 1/60 s, 0.25 s)
```

Клиентские segment durations используются только как веса распределения этого уже ограниченного budget. Они не могут увеличить пройденную дистанцию.

Политика:

```text
PACKET_ARRIVAL_BUDGET_WEIGHTED_BY_SEGMENT_V1
```

Это переходная схема: jitter всё ещё влияет на server movement step. Полное устранение зависимости относится к NX3.

## Подавление amplification

Для успешного `PLAYER_INPUT_BATCH` сервер:

- не отправляет `COMMAND_RESULT`;
- не отправляет per-input player delta;
- не отправляет per-input full snapshot;
- помечает movement snapshot dirty;
- публикует compact snapshot не чаще одного раза за `50 ms`.

Rejection остаётся reliable и содержит точный error code.

Runtime telemetry/report публикует:

```text
movement_batches_received
movement_inputs_received/applied/redundant/rejected
movement_results_suppressed
movement_deltas_suppressed
movement_full_snapshots_suppressed
movement_snapshots_published
compact_movement_snapshots_published/failures
```

## Compact gameplay snapshots

`CompactGameplaySnapshot` сохраняет authoritative position, velocity, orientation, revision, ownership epoch, connection state и `last_input_sequence`, но использует короткие wire-ключи.

Client:

1. проверяет outer protocol frame;
2. проверяет compact snapshot checksum;
3. разворачивает canonical player snapshot;
4. применяет его в replica store;
5. удаляет подтверждённые input transitions по `last_input_sequence`.

Blocking movement helper теперь ожидает authoritative snapshot acknowledgement, а не успешный `COMMAND_RESULT`.

## Item Graph traffic

Item-команды идут по `ITEM`, независимо от realtime streams.

Успешная мутация публикует `CanonicalItemGraphDelta` с:

```text
base_revision/base_checksum
target_revision/target_checksum
canonical target snapshot payload
```

Если base revision/checksum клиента не совпадает, клиент отправляет `ITEM_GRAPH_RESYNC_REQUEST` по `RESYNC`. Полный snapshot используется только для join/resync и не вкладывается в обычную movement/item rejection.

Delta-контракт требует integer-valued JSON revision/tick и lowercase SHA-256. Если после уже durable-committed мутации delta по внутренней причине не строится, сервер не превращает состоявшуюся операцию в ложный rejection: он сохраняет успешный result и публикует полный Item Graph resync всем подключённым клиентам.

`item.save` подавляется только для bridge, который явно объявляет:

```gdscript
uses_server_authoritative_persistence() == true
```

Это сохраняет H1 listen-host command bridge, где authority и persistence находятся в том же процессе, и запрещает бессмысленный network `item.save` в M7.

## Сохранённые ограничения

NX2 намеренно не реализует:

- fixed 60 Hz authoritative simulation;
- client-side prediction/reconciliation;
- delayed remote snapshot interpolation buffer;
- async persistence;
- interest management;
- quantized far-world replication.

Movement checkpoint interval `1500 ms` и packet-arrival budget остаются baseline для NX3/NX9.

## Тестирование

Focused runner:

```bash
bash RUN_NX2_REALTIME_TRAFFIC_SEPARATION_TESTS.sh /path/to/godot.linuxbsd.editor.double.x86_64
```

Он выполняет:

1. editor import;
2. NX0 preparation contracts;
3. NX0 baseline contracts;
4. NX1 contracts;
5. NX2 contracts;
6. compatibility handshake process;
7. conditioned ENet process;
8. real-ENet physical channel/mode regression с двумя клиентами;
9. M7 graphical realtime process с двумя клиентами.

NX2 contracts проверяют:

- шесть каналов и protocol fingerprint;
- независимые stream queues;
- latest-wins transactional coalescing и rollback reservation при queue-limit отказе;
- reliable FIFO;
- compact input/snapshot MTU;
- transition redundancy;
- Item Graph delta/resync;
- отсутствие сетевого `item.save` в M7;
- machine-readable architecture config;
- production wiring.

M7 process дополнительно доказывает:

```text
successful movement results = 0
per-input deltas = 0
per-input full snapshots = 0
suppressed counters == applied inputs
snapshot publication is bounded
INPUT/SNAPSHOT/ITEM/RESYNC all carry traffic
pending command results = 0
```

## Acceptance gate

Окончательное решение `ACCEPTED` требует независимого managed-MCP прогона после editor import:

```text
NX2 focused 9/9
network non-process 50/50
ENet regression 4/4
M3 graphical
M7 playable realtime
M7 restart/reconnect
unexpected exits = 0
remaining Godot processes = 0
```

## Review fix1: повторяемое подтверждение движения и физическая привязка ENet

После независимого review исправлены два блокирующих дефекта.

1. Redundant `PLAYER_INPUT_BATCH` теперь является запросом повторной публикации текущего authoritative snapshot. Это сохраняет модель без успешного reliable `COMMAND_RESULT`, но не позволяет blocking-клиенту зависнуть после потери unreliable snapshot.
2. Dirty-флаг movement snapshot сбрасывается только после успешной постановки snapshot всем текущим target peer. Ошибка enqueue сохраняет dirty-состояние и учитывается telemetry.
3. ENet adapter строго проверяет соответствие `frame.channel` физическому `packet_channel` и `frame.delivery_mode` физическому `packet_mode`. Application frame с несовпадением не доставляется.
4. Политика `STRICT_CHANNEL_AND_TRANSFER_MODE_V1` входит в protocol manifest и меняет protocol hash.

Проверки fix1 включают real-ENet пакеты с намеренно ложной декларацией канала и режима, M7 playable и restart/reconnect recovery.


## Review fix2: peer-local quarantine физического нарушения

Независимый review выявил, что fix1 корректно отклонял mismatched frame, но оформлял нарушение как глобальный `TRANSPORT_ERROR`. Boundary переходил в `FAILED`, поэтому один ошибочный или намеренно некорректный peer мог остановить listener и всех здоровых клиентов.

Fix2 вводит политику:

```text
PEER_LOCAL_QUARANTINE_V1
```

При `PHYSICAL_CHANNEL_MISMATCH` или `PHYSICAL_DELIVERY_MODE_MISMATCH`:

1. application frame отклоняется;
2. offending ENet peer принудительно отключается;
3. его `NetworkPeerSession` переходит в `FAILED` с точным кодом нарушения;
4. только очередь нарушителя очищается;
5. server boundary остаётся `LISTENING`;
6. healthy peers сохраняют connection и logical peer ID;
7. глобальный `TRANSPORT_ERROR` не создаётся.

`TRANSPORT_ERROR` сохраняется только для действительно port-wide отказов, где продолжение работы listener невозможно.

Real-ENet regression теперь сначала регистрирует два обычных клиента, затем один из них отправляет физически несовместимый frame. Тест доказывает, что нарушитель изолирован, его session отмечена `FAILED`, второй клиент после quarantine продолжает обмен сообщениями с прежним peer ID, а listener не имеет глобального failure code. Проверка выполняется отдельно для mismatch канала и transfer mode.

PowerShell focused runner приведён в соответствие с shell runner и фактически выполняет девять шагов, включая `test_nx2_physical_channel_processes.gd`.
