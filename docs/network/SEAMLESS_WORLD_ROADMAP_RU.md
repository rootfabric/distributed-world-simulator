# Дорожная карта бесшовного сетевого мира PlanetSimulator

## Статус на checkpoint v16.4.1-foundation-inventory-merge

Foundation Gate и N0 приняты. В проекте уже существуют server-safe runtime,
`SimulationKernel`, `WorldEntityAggregate`, строгие versioned DTO, authority
lease/route contracts, handoff state machine, golden fixtures и loopback
command/replication paths. Fix1 дополнительно закрывает owner/epoch, revision/tick
fencing, неканонические delta paths и поддельные kernel ports.

Следующий исполняемый сетевой этап — N1: один authoritative Godot server,
отдельный bot client и реальный transport adapter.

Связанные планы:

- `../plans/V16_4_FOUNDATION_GATE_PLAN_RU.md`;
- `N0_NETWORK_CONTRACTS_PLAN_RU.md`;
- `../checkpoints/2026-07-28_V16_4_0_FOUNDATION_N0_FIX1_RU.md`;
- `../checkpoints/2026-07-27_V16_3_FOUNDATION_AND_NETWORK_CHECKPOINT_RU.md`.


## Принцип декомпозиции

Каждая стадия должна:

- иметь один наблюдаемый результат;
- выполняться локально;
- запускаться одной командой;
- иметь автоматический тест без ручного игрока;
- не требовать следующей стадии;
- сохранять offline режим;
- не менять UUID и канонические координаты.

Шкала сложности:

```text
S   — несколько маленьких задач
M   — самостоятельная итерация
L   — несколько итераций
XL  — отдельная программа работ
```

## N0 — сетевые контракты без сети

**Сложность:** M
**Статус:** выполнено в `v16.4.0-foundation-n0`, усилено в `v16.4.0-foundation-n0-fix1`.

### Реализация

Добавить pure-domain типы:

```text
NetworkCommandEnvelope
EntitySnapshotEnvelope
AuthorityLease
AuthorityRoute
SimulationNodeDescriptor
SimulationSpaceDescriptor
AuthorityRegionDescriptor
GhostReplicaState
HandoffTicket
HandoffResult
ClientRoute
```

Обязательные поля команды:

```text
schema
protocol_version
message_id
operation_id
entity_id
command_type
payload
expected_revision
authority_epoch
client_tick
sent_at_monotonic_ms
```

### Тесты

- canonical JSON round-trip;
- неизвестная version отклоняется;
- один payload даёт один hash;
- тот же message дважды идемпотентен;
- старый authority epoch отклоняется;
- DTO не содержит `Node`, `Resource`, `RID`, `Callable` и `NodePath`.

### Критерий выхода

```text
RUN_NETWORK_CONTRACT_TESTS
→ PASS
```

Никакие сокеты ещё не открываются.

---

## N1 — один authoritative Godot server и один bot client

**Сложность:** M

### Реализация

Роли запуска:

```text
--role=simulation-server
--role=network-client
--node-id=sim-local-01
--listen-port=19001
--connect=127.0.0.1:19001
--instance-id=network-test-001
```

Использовать `ENetMultiplayerPeer`.

Первый вертикальный сценарий:

1. server создаёт один маяк;
2. client получает snapshot;
3. client отправляет `item.move_to_container`;
4. server проверяет revision и authority epoch;
5. server применяет существующий domain service;
6. client получает новый snapshot;
7. checksum обоих состояний совпадает.

### Не делать

- prediction;
- второй server;
- player handoff;
- ghosts;
- автоматический SceneTree spawn всего мира.

### Критерий выхода

Один и тот же тест проходит:

- in-process loopback;
- двумя отдельными Godot-процессами.

---

## N2 — локальный multi-process network lab

**Сложность:** M

### Реализация

Добавить Python harness:

```text
tools/network_lab/network_lab.py
tools/network_lab/process.py
tools/network_lab/log_reader.py
tests/network_py/conftest.py
tests/network_py/test_single_authority.py
```

Функции harness:

- выделить свободные порты;
- создать отдельный `user://` для каждого процесса;
- запустить Godot;
- дождаться JSONL `node_ready`;
- отправить тестовые команды;
- собрать логи;
- корректно завершить процессы;
- сохранить общий JSON/JUnit report.

### Первый набор

```text
1 server + 1 client
1 server + 2 clients
server restart + reconnect
client disconnect + reconnect
duplicate command delivery
```

### Критерий выхода

```text
python -m pytest tests/network_py -m network_smoke
→ PASS
```

---

## N3 — World Directory и authority leases

**Сложность:** L

### Реализация

Сначала in-memory Directory:

```text
node registration
node heartbeat
space registration
static region assignment
entity route lookup
authority lease acquire/renew/release
epoch increment
```

Lease:

```text
lease_id
entity_or_region_id
owner_node_id
epoch
issued_at
expires_at
renew_after
state_revision
```

### Инварианты

- один active lease;
- epoch монотонно растёт;
- истёкший lease не может писать;
- restart node не восстанавливает старый epoch;
- directory loss не создаёт второго authority.

### Критерий выхода

Два server-процесса зарегистрированы, но каждый статически владеет своим набором сущностей. Handoff пока отсутствует.

---

## N4 — handoff одного объекта между двумя серверами

**Сложность:** L
**Первый настоящий шаг бесшовности.**

### Сценарий

```text
SpaceServer A
MoonServer B
Stone entity
```

### State machine

```text
IDLE
→ PREPARING
→ TARGET_READY
→ SOURCE_FROZEN
→ COMMITTING
→ COMMITTED
→ SOURCE_GHOST
→ FINALIZED
```

Аварийные ветви:

```text
ABORTED
ROLLED_BACK
EXPIRED
```

### Протокол

1. A прогнозирует пересечение boundary.
2. A создаёт `HandoffTicket`.
3. B загружает read-only candidate snapshot.
4. B подтверждает `target_ready`.
5. A завершает authoritative tick.
6. A отправляет final delta.
7. Directory атомарно повышает epoch и меняет route.
8. B становится authority.
9. A оставляет ghost/proxy на grace period.

### Первый вариант

Разрешается pause до 500 мс. Полная визуальная плавность пока не требуется.

### Тесты

- success;
- duplicate prepare;
- duplicate commit;
- target crash before commit;
- source crash before commit;
- source crash after commit;
- stale epoch write;
- payload checksum mismatch;
- no duplicate entity;
- conservation of position, velocity, mass, quantity and revisions.

---

## N5 — make-before-break handoff клиента

**Сложность:** L

### Реализация

Клиент держит два сетевых контекста:

```text
primary connection → current authority
warm connection    → target authority
```

Godot позволяет назначать разные `MultiplayerAPI` разным поддеревьям. Не следует переключать весь SceneTree одним глобальным peer.

Добавить `NetworkSessionMux`:

```text
connect_primary
connect_warm
promote_warm_to_primary
demote_primary_to_grace
close_grace
```

### MVP

- объект игрока не пересоздаётся;
- UUID сохраняется;
- camera и UI не выгружаются;
- допускается короткая коррекция позиции;
- старый сервер остаётся read-only grace source.

### Тесты без игрока

Bot client должен пройти boundary 100 раз и проверить:

- не было disconnect gap;
- entity существовала ровно один раз как authority;
- input sequence не потерян;
- итоговая позиция непрерывна;
- inventory checksum не изменился.

---

## N6 — overlap, ghosts и interest management

**Сложность:** L

### Наборы

```text
AuthoritySet
InterestSet
ActivationSet
GhostSet
ProjectionSet
```

### Ghost

Содержит только нужные соседу компоненты:

```text
entity_id
source_node_id
authority_epoch
state_revision
spatial_ref
linear/angular velocity
bounds
physics proxy class
expires_at_tick
```

### Правила

- ghost не принимает domain commands;
- collision result подтверждает authority;
- stale ghost удаляется;
- interest имеет hysteresis;
- bandwidth budget фиксируется тестом.

### Критерий выхода

Два объекта видят друг друга через границу, но canonical mutation выполняет один server.

---

## N7 — вложенное пространство: Moon Cave

**Сложность:** L

### Пространства

```text
space/moon/surface
└── space/moon/cave-001
```

### Parent projection

Moon server хранит:

```text
portal bounds
portal state
child health
aggregate occupancy
visible silhouettes
large emitted events
```

Cave server хранит детальную физику и item graph внутри.

### Первый переход

Использовать шлюз/тоннель, скрывающий boundary. Прямые физические взаимодействия через портал пока запрещены.

### Критерий выхода

Bot проходит surface → cave → surface, сохраняя player UUID, inventory, velocity policy и operation ledger.

---

## N8 — статическое разбиение поверхности Земли

**Сложность:** XL

### Неизменяемое

`PartitionAddress` остаётся постоянным адресом данных.

### Динамическое

`AuthorityRegion` объединяет много zone/chunk:

```text
region/eu-001 → cube-sphere cells [...]
region/eu-002 → cube-sphere cells [...]
```

### Первая версия

- ручной JSON mapping;
- статические regions;
- boundary только в разреженных местах;
- никаких автоматических split/merge.

### Тесты

- переход через грани cube-sphere;
- 1000 последовательных handoff;
- отсутствие изменения канонического `SpatialRef`;
- одинаковый результат на Windows/Linux double server.

---

## N9 — interaction islands и динамический rebalance

**Сложность:** XL

### Interaction island

Связанные объекты мигрируют вместе:

```text
ship
players inside
cargo graph
mounted modules
joints
nearby collision-critical bodies
```

### Метрики split/merge

```text
physics_step_ms
active_rigid_bodies
contact_pairs
network_out_bps
player_count
handoff_rate
memory_bytes
```

### Правила

- region нельзя разрезать через active island;
- rebalance имеет cooldown/hysteresis;
- миграция сначала статически планируется;
- автоматический rebalance включается только после replay-тестов.

---

## N10 — production orchestration и географические регионы

**Сложность:** XL

### Компоненты

- dedicated server export;
- containers;
- NATS/JetStream control plane;
- PostgreSQL/object storage для durable snapshots;
- Agones Fleet и allocation;
- regional gateways;
- metrics, tracing и alerting.

### Ограничение физики

Игроки из разных реальных регионов, взаимодействующие в одном tight physics island, не могут одновременно иметь локальный RTT до одного authority. Нужно выбирать authority и использовать prediction/lag compensation.

---

## N11 — улучшение полной бесшовности

**Сложность:** XL, непрерывная работа

- client prediction;
- interpolation;
- lag compensation;
- adaptive overlap;
- predictive handoff по траектории;
- proxy LOD;
- cross-space visibility;
- multi-region routing;
- zero-downtime node replacement;
- live region split/merge;
- portal projection;
- replay production incidents.

## Рекомендуемый первый практический пакет

Следующая реализация должна быть **N0**, а не попытка сразу соединить Землю и Луну.

Порядок:

```text
N0 contracts
→ N1 one server/one bot
→ N2 multi-process harness
→ N3 directory/leases
→ N4 stone handoff
```

После N4 станет понятно, жизнеспособна ли выбранная архитектура. До этого любые Kubernetes и динамические регионы будут преждевременными.
