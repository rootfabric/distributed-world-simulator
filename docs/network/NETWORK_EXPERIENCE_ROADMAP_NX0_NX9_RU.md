# PlanetSimulator — дорожная карта комфортного сетевого взаимодействия NX0–NX9

**Дата решения:** 1 августа 2026 года
**База анализа:** commit `69bd7fc`, M7 candidate `v16.10.6.1-testing-m7-playable-networked-playground`
**Целевая модель:** server authority + client prediction + reconciliation + remote interpolation + optimistic item presentation
**Машиночитаемый источник:** `config/network/network-experience-roadmap.v1.json`

**Текущий статус (2 августа 2026):** NX0 и NX1 приняты; NX2 находится на delivery `fix2` candidate `v16.12.0-network-nx2-realtime-traffic-separation` в ветке `feature/nx2-realtime-traffic-separation`. Fix2 изолирует физическое channel/mode нарушение на offending peer и сохраняет listener/healthy peers. NX3 fixed-tick simulation остаётся следующим этапом.

## 1. Зачем появился отдельный NX-roadmap

Принятые A3 и M1–M6 доказали правильность единственного authoritative gameplay path, replay, reconnect и recovery. M7 доказал, что два обычных графических клиента способны играть через dedicated authority. Однако M7 остаётся архитектурным доказательством, а не комфортным realtime-netcode.

Новый NX-roadmap не заменяет `NetworkedGameplayService`, Item Graph, A3 wire contracts, ENet boundary или M6 persistence. Он добавляет поверх них realtime-слой, который скрывает RTT и jitter, уменьшает amplification трафика и отделяет durable state от частого движения.

B1 NATS Core остаётся допустимым server-to-server adapter после A3, но по продуктовому приоритету откладывается до стабилизации клиентского realtime-пути. NX не меняет B0/B1 contracts и не создаёт второй authority runtime.

## 2. Подтверждённое состояние M7

Аудит текущего кода подтвердил:

1. `scripts/runtime/networked_gameplay/m3/m3_dedicated_server_runtime.gd` вычисляет authoritative `delta_seconds` из разницы времени прихода двух пакетов (`now_ms - previous_ms`). Значит jitter напрямую меняет длину simulation step.
2. Каждый успешный `PLAYER_INPUT` вызывает `_send_result(...)`, затем `_broadcast_delta(...)` и `_broadcast_snapshot(...)`. Один input превращается минимум в три server messages для одного клиента и примерно в пять при двух клиентах.
3. Клиентский `submit_movement_intent_nonblocking()` не ждёт result, но сервер всё равно его отправляет. Поэтому `m3_graphical_client_runtime.gd` считает такие ответы в `async_command_results`.
4. Movement state помечается dirty и примерно каждые `1500 ms` проходит через полный M6 checkpoint.
5. Весь M3 gameplay traffic создаётся как `COMMAND` или `STATE`, а текущий ENet v2 adapter имеет только три канала. Item operations, movement и snapshots не имеют окончательной независимой channel policy.
6. Локальный игрок сейчас не предсказывается. Presentation лишь сглаживает движение к последней authoritative target position.

Это объясняет наблюдаемые симптомы: задержку собственного управления, рост количества сообщений, периодические checkpoint spikes и ухудшение поведения при jitter.

## 3. Неподвижные архитектурные правила

- Сервер остаётся источником истины для canonical player state, Item Graph, контейнеров, экономики и установленных объектов.
- Клиент никогда не получает право записывать canonical transform персонажа.
- Prediction изменяет только локальную predicted state/presentation до подтверждения.
- LOOPBACK и ENet продолжают использовать один gameplay service и одинаковые команды.
- Все новые сетевые DTO остаются versioned, JSON-safe, replay-safe и presentation-free.
- Double coordinates сохраняются на canonical boundary; quantization разрешена только как отдельная wire policy с явной областью применения.
- Realtime telemetry не может менять authoritative state или durable revision.

## 4. Целевые authority profiles

| Категория | Профиль |
|---|---|
| Собственный персонаж | client prediction, server authority |
| Другие игроки | server snapshots + interpolation |
| Камера | полностью локальная |
| Inventory | optimistic UI, server authority |
| Pickup | predicted presentation, server authority |
| Drop | predicted spawn, server authority |
| Placement | local ghost, server-confirmed spawn |
| Ценные физические объекты | server authority + выборочная prediction |
| Косметика | client-only |
| Контейнеры и экономика | только server authority |

## 5. NX0 — Observability Baseline

### Цель

До изменения поведения получить измеримый baseline и гарантировать, что клиент и сервер действительно запущены из одной сборки и одного protocol contract set.

### Обязательные identity поля

```text
build_id
git_commit
protocol_hash
world_id
session_token
```

Соединение должно отклоняться до gameplay join при несовпадении любого обязательного поля.
`session_token` допускает только два формата: `session-id/<public-id>` для публичного несекретного binding ID либо `sha256/<64-lowercase-hex>` для SHA-256 digest. Raw bearer token, пароль и другие credentials запрещено помещать в handshake fingerprint и telemetry.

### Метрики

- server/client tick;
- RTT, jitter, packet loss;
- packets/bytes по каждому channel;
- reliable queue depth;
- pending operation count;
- input age и snapshot age;
- prediction error и corrections;
- server tick duration;
- persistence duration;
- item command latency;
- checkpoint generation;
- movement result/snapshot suppression counters.

### Acceptance

- fingerprint mismatch даёт точный error code;
- telemetry bounded и JSON-safe;
- сбор метрик не меняет checksum/revision authoritative state;
- 30-минутный soak не показывает роста telemetry buffers;
- отчёт всегда содержит build fingerprint и profile identity.

## 6. NX1 — Deterministic Network Condition Simulator

### Цель

Воспроизводить интернет-условия локально и в CI с фиксированным seed.

### Параметры

```text
outgoing/incoming latency ranges
jitter
packet loss
burst loss probability and duration
duplication
reordering
bandwidth cap
queue byte limit
lag spike
disconnect duration
random seed
```

### Presets

`LOCAL`, `GOOD_BROADBAND`, `AVERAGE_BROADBAND`, `MOBILE`, `BAD_MOBILE`, `EXTREME`, `LAG_SPIKE`, `ASYMMETRIC`.

### Важное ограничение реализации

Simulator нельзя наивно ставить над reliable application message и просто удалять такой message: это обойдёт retransmission ENet и превратит reliable traffic в unreliable. NX1 adapter должен моделировать условия на уровне, сохраняющем семантику reliable delivery, либо явно различать datagram fault injection и application queue delay. Именно поэтому текущий checkpoint добавляет только валидируемые profiles, а не подключает незавершённый wrapper к production ENet.

## 7. NX2 — Realtime Traffic Separation

- movement success не создаёт `COMMAND_RESULT`;
- rejection остаётся targeted reliable result;
- full snapshot не отправляется после каждого input;
- server публикует максимум один movement snapshot на network tick;
- input и snapshots переходят на отдельные unreliable-ordered каналы;
- item commands и control traffic остаются reliable и не блокируют movement;
- input packet содержит несколько последних sequences;
- Item Graph full snapshot используется только для join/reconnect/resync/checksum mismatch;
- network client больше не запускает `item.save`.

Начальная channel policy:

| Channel | Delivery | Назначение |
|---:|---|---|
| 0 | reliable | handshake, join, leave, control |
| 1 | unreliable ordered | player input |
| 2 | unreliable ordered | player/world snapshots |
| 3 | reliable ordered | inventory and Item Graph commands |
| 4 | reliable | full resync/bulk snapshot |
| 5 | unreliable | diagnostics/telemetry |

## 8. NX3 — Fixed-Tick Authoritative Simulation

Сервер симулирует movement на фиксированных 60 Hz. Пакеты только обновляют per-player input queue. Packet arrival delta больше не используется как physics delta.

Input command:

```text
sequence
client_tick
move_x / move_z
look_yaw / look_pitch
jump_edge
sprint
```

Сервер возвращает `last_processed_input_sequence`, ограничивает возраст и sequence window, восстанавливает кратковременную потерю input redundancy и не повторяет jump как held flag.

## 9. NX4 — Client Prediction and Reconciliation

Один `PlayerMovementKernel` используется сервером и predicted client path. Клиент хранит bounded ring buffer input/state, немедленно применяет input, а после snapshot:

1. находит подтверждённый sequence;
2. сравнивает predicted и authoritative state;
3. удаляет подтверждённые inputs;
4. устанавливает authoritative state;
5. повторно проигрывает оставшиеся inputs;
6. визуально сглаживает correction.

Начальная correction policy:

```text
< 3 см      ignore
3–15 см     smooth ~150 ms
15–50 см    smooth ~80 ms
50 см–2 м   fast correction
> 2 м       hard correction + telemetry marker
```

## 10. NX5 — Remote Player Interpolation

Remote player хранит snapshot buffer с `server_tick`, position, rotation, velocity и movement mode. Render timeline отстаёт от server time примерно на 100–125 ms и интерполирует между уже полученными snapshots. Extrapolation ограничивается примерно 100 ms, teleport marker не интерполируется.

## 11. NX6 — Predicted Item Interactions

- pickup сразу переводит presentation в pending и резервирует слот;
- inventory drag выполняется optimistic transaction с `transaction_id` и `base_revision`;
- drop создаёт provisional presentation с `prediction_id`;
- server возвращает canonical item ID и тот же prediction ID;
- placement ghost полностью локальный, canonical spawn только после server validation;
- rejection откатывает pending state без дублирования предметов.

## 12. NX7 — Physics Authority Profiles

```text
SERVER_ONLY
OWNER_PREDICTED
OWNER_AUTHORITY_VALIDATED
PREDICTED_SPAWN
CLIENT_COSMETIC
```

Owner authority допустим только с server validation скорости, acceleration, distance per tick, collision envelope, region bounds, lease generation и object type.

## 13. NX8 — Interest Management and Replication Budget

- spatial interest grid;
- always-relevant и owner-only entities;
- distance tiers и priority;
- per-client bandwidth budget;
- dormancy и dirty tracking;
- delta baselines и periodic recovery snapshot;
- starvation protection.

NX8 использует будущие grid/zones как адреса relevance, но spatial cell сама по себе не становится authority owner.

## 14. NX9 — Async Persistence and Production Hardening

```text
inventory / ownership: append-only durable journal
player position: async snapshot every 15–30 s + disconnect/shutdown
world dynamics: dirty-region snapshots
gracious shutdown: forced bounded flush
```

Movement commands не входят в durable operation ledger. Disk latency 100–500 ms не должна влиять на simulation tick.

## 15. Обязательная тестовая пирамида

1. Unit: sequence arithmetic, serializers, quantization, buffers, interpolation, prediction IDs.
2. Property/fuzz: random input, reorder, duplicates, loss, sequence wrap, malformed snapshots.
3. Runtime integration: server + in-process clients, convergence, correction, item transaction.
4. Process: dedicated server + два графических клиента + ENet + real InputMap.
5. Soak: 30 min PR, 2 h nightly, 12 h weekly, 24 h pre-acceptance.
6. Chaos: lag spike, pause, disconnect/reconnect, corrupted baseline, delayed persistence, process kill.

## 16. Приёмочная матрица

| Profile | RTT | Jitter | Loss | Ожидание |
|---|---:|---:|---:|---|
| Local | 0 ms | 0 | 0% | идеально плавно |
| Good | 40 ms | 5 ms | 0.1% | corrections незаметны |
| Average | 80 ms | 10 ms | 0.5% | комфортно |
| Mobile | 120 ms | 30 ms | 2% | играбельно |
| Bad | 200 ms | 60 ms | 5% | corrections видимы, state цел |
| Extreme | 500 ms | 100 ms | 10% | некомфортно, но без corruption |

Для каждого profile: движение, бег, прыжок, камера, два игрока, pickup, drop, inventory drag, placement, container, disconnect/reconnect, persistence и late join.

## 17. Целевые метрики

```text
local input response       <= 1 render frame
prediction correction p95  < 15 cm
hard correction            < 1 / 10 min in normal profile
server tick p95            < 8 ms
server tick p99            < 16 ms
local item feedback        < 50 ms
duplicate items            0
unresolved predictions     0
steady total bandwidth     < 30 KB/s per client (initial budget)
```

## 18. Порядок checkpoint

```text
NX0 Observability Baseline
→ NX1 Deterministic Network Emulator
→ NX2 Realtime Traffic Separation
→ NX3 Fixed-Tick Server Simulation
→ NX4 Owner Prediction and Reconciliation
→ NX5 Remote Interpolation
→ NX6 Predicted Item Interactions
→ NX7 Physics Authority Profiles
→ NX8 Interest Management
→ NX9 Async Persistence and Hardening
```

Первый действительно игровой gate — `NX4 + NX5`. Первый полный gameplay gate — `NX6`.
