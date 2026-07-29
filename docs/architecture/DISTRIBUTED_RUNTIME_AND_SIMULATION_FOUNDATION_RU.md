# Distributed Runtime и фундамент масштабируемой симуляции PlanetSimulator

**Статус:** архитектурное решение A0
**Документационный checkpoint:** `v16.7.1-architecture-a0-distributed-runtime`
**Runtime checkpoint candidate:** `v16.8.4-data-plane-b0-message-bus-contracts`
**Архитектурная база:** `v16.7.1-architecture-a0-distributed-runtime`
**Назначение:** зафиксировать устойчивую основу для self-host, multiplayer, сложных агрегатов, compute workers, сменяемых транспортов и будущего горизонтального масштабирования мира.

## 1. Причина появления A0

К checkpoint R3.1 проект доказал важные свойства первого сетевого vertical slice:

- строгие сетевые DTO и canonical JSON;
- authority owner/epoch, revision и server tick fencing;
- реальный ENet handshake, snapshot, command, delta и reconnect/replay;
- multi-process harness с fault scenarios;
- атомарный authoritative checkpoint;
- crash/restart recovery без повторной предметной мутации.

Эта база правильная, но пока выражает узкий сценарий:

```text
один authoritative simulation-server
+ один client
+ item-backed WorldEntityAggregate
+ single-aggregate command
+ ENet transport
```

Следующая цель — не добавлять отдельные механики поверх узкой формы, а расширить фундамент так, чтобы одна система могла работать:

- одним F5 без выделенного сервера;
- двумя локальными процессами;
- на dedicated server;
- как локальный мини-кластер;
- как распределённый мир с несколькими authority nodes;
- с ENet, loopback, NATS или другим adapter;
- с индивидуальными сущностями, популяционными полями, environment cells, сложными структурами и процессами;
- с несколькими compute workers, не нарушающими single-writer authority.

A0 не меняет runtime-код. Он фиксирует обязательные границы до начала следующих реализаций.

## 2. Главная архитектурная формула

```text
одна каноническая доменная система
+ несколько runtime-композиций
+ несколько логических транспортных семантик
+ сменяемые transport adapters
+ один authoritative writer на aggregate
+ много read-only compute workers
```

Ключевые разделения:

```text
canonical state ≠ presentation
client replica ≠ server aggregate
authority ownership ≠ compute assignment
spatial location ≠ authority routing
protocol DTO ≠ transport subject/channel
logical object ≠ physical shard
content type ≠ executable arbitrary script
```

Нарушение любого из этих разделений создаст скрытую зависимость, которая проявится при переходе от локального режима к отдельным процессам или нескольким серверам.

## 3. Runtime topology вместо жёсткой роли процесса

Существующие роли сохраняются как совместимые launch-профили:

```text
offline
client
simulation-server
bot-client
```

Но целевая архитектура описывает не только роль процесса, а топологию размещения логических runtime-компонентов.

### 3.1 Логические runtime-компоненты

```text
ClientRuntime
RegionAuthorityRuntime
SimulationWorkerRuntime
DirectoryRuntime
ContentRegistryRuntime
RepositoryRuntime
PresentationRuntime
```

Один процесс может включать несколько компонентов, если их границы сохраняются.

### 3.2 Поддерживаемые топологии

#### Offline tools

```text
один процесс
├── authoritative domain
├── tools/generators/migrations
└── optional presentation
```

Назначение:

- unit и domain tests;
- editor tools;
- генераторы;
- миграция и recovery;
- диагностика;
- изолированное исследование алгоритмов.

Этот режим не является эталоном сетевой gameplay-семантики.

#### Listen-host

```text
один процесс Godot
├── RegionAuthorityRuntime
├── Loopback transport pair
└── ClientRuntime + PresentationRuntime
```

Обязательное правило: клиентская часть не имеет прямой ссылки на authoritative aggregates, registries и services.

Даже в одном процессе путь должен быть:

```text
input/UI
→ client command gateway
→ canonical DTO serialization boundary
→ loopback adapter
→ authority validation/commit
→ snapshot/delta
→ canonical DTO serialization boundary
→ client replica store
→ presentation/UI
```

Это будущий основной F5 для ежедневной разработки.

#### Local dedicated

```text
процесс 1: simulation-server
процесс 2: graphical client
transport: ENet localhost
```

Пользователь получает self-host без отдельной машины, но с реальной process/network boundary.

#### Local cluster

```text
client
+ region authority
+ compute worker(s)
+ optional Directory
+ optional NATS
```

Назначение: локальные эксперименты с распределённой симуляцией без выделенной инфраструктуры.

#### Production cluster

```text
client gateways
+ World Directory
+ many region authorities
+ workers
+ repositories
+ content registry
+ transport adapters
```

Клиентская семантика не должна зависеть от выбранной топологии.

## 4. ClientRuntime и replica boundary

Клиент хранит не canonical domain, а реплику интересующей области:

```text
ClientReplicaStore
├── entity replicas
├── aggregate replicas
├── local interest state
├── prediction state (optional)
└── presentation projections
```

Запрещено:

```gdscript
client_inventory.aggregate = server_inventory.aggregate
```

Правильно:

```text
server state
→ snapshot/delta Dictionary
→ canonical JSON encode/decode
→ new client-owned data
→ replica store
```

Loopback должен проходить сериализационную границу или эквивалентную deep-copy/validate boundary. Общая ссылка на Dictionary или Object считается архитектурным bypass.

## 5. Aggregate foundation

Текущий `WorldEntityAggregate` остаётся специализированным item-backed aggregate. Его нельзя превращать в универсальный god object.

### 5.1 Общий descriptor

Все authoritative aggregates должны выражать общий набор метаданных:

```text
AggregateDescriptor
├── aggregate_id
├── aggregate_kind
├── state_schema
├── dynamic_type_reference (optional)
├── authority_owner_id
├── authority_epoch
├── state_revision
├── server_tick
├── partition_address
└── spatial_scope
```

Общие операции:

```text
validate_state
export_snapshot
stage_mutation
commit_staged_mutation
export_persistence_state
restore_persistence_state
get_authority_state
```

Это может быть набор ports/adapters, а не наследование GDScript.

### 5.2 Базовые aggregate kinds

```text
WorldItemAggregate
IndividualOrganismAggregate
PopulationFieldAggregate
EnvironmentCellAggregate
CompoundStructureAggregate
ProcessAggregate
```

Каждый kind имеет собственную state schema и validator, но использует общие authority/revision/tick/checksum invariants.

## 6. Entity и Aggregate envelopes

`EntitySnapshotEnvelope v1` остаётся для точечных индивидуальных сущностей с естественными position/orientation/physics state.

Для пространственных полей и процессов вводятся отдельные контракты:

```text
AggregateSnapshotEnvelope
AggregateDeltaEnvelope
```

Они содержат:

```text
aggregate_id
aggregate_kind
state_schema
type_reference
state_revision
authority_owner_id
authority_epoch
server_tick
partition_address
spatial_scope
state
checksum
```

`spatial_scope` поддерживает:

```text
POINT
BOUNDS
CELL
CELL_SET
REGION
NONE
```

Это позволяет не подменять поле фиктивным физическим объектом в центре области.

## 7. Стабильная адресация mutable state

В каноническом изменяемом состоянии нельзя использовать индекс массива как identity.

Нежелательно:

```text
cohorts[0]
parts[12]
berries[3]
```

Требуется:

```text
cohorts_by_id[cohort_id]
parts_by_id[part_id]
patches_by_id[patch_id]
```

Причины:

- стабильные delta paths;
- отсутствие index shift;
- воспроизводимый replay;
- удобный conflict detection;
- независимое sharding/merge;
- понятные read/write sets.

Массив допустим для неизменяемой упорядоченной выдачи, но не как адрес authoritative sub-object.

## 8. Лестница представлений сложного мира

Один объект может переходить между уровнями детализации:

```text
Population Field
→ Cohort
→ Materialized Individual
→ Entity Part Graph
→ Detached World Item
```

Системные переходы:

```text
MATERIALIZE
DEMATERIALIZE
ATTACH_PART
DETACH_PART
SPLIT_AGGREGATE
MERGE_AGGREGATE
```

### 8.1 Population field

Поле хранит не миллионы Entity, а:

```text
procedural seed
cohorts
patch states
exclusion representation
materialized exceptions
environment bindings
revision/authority/tick
```

Клиент визуализирует множество экземпляров процедурно.

### 8.2 Procedural instance identity

Конкретный визуальный экземпляр имеет детерминированный ключ:

```text
field_id + patch_id + local_instance_index + generation
```

При взаимодействии authority:

1. проверяет revision/epoch;
2. воспроизводит instance из seed;
3. проверяет exclusion/materialization state;
4. изменяет cohort/patch;
5. создаёт отдельный aggregate;
6. фиксирует `MaterializationRecord`;
7. публикует field delta и entity snapshot.

### 8.3 Exclusion compaction

Индивидуальные exclusions используются только для малых изменений.

При массовых изменениях применяется:

```text
patch mask
patch density multiplier
disturbance record
new generation
```

Это предотвращает бесконечный журнал удалённых травинок.

### 8.4 Entity Part Graph

Части растения, машины, животного или сооружения хранятся по stable part IDs.

При `DETACH_PART` parent aggregate и новый item должны измениться одной транзакцией.

## 9. Multi-aggregate transaction boundary

Текущий single-aggregate command сохраняется для простых операций. Для материализации, detach, split и merge нужен отдельный transaction layer:

```text
AggregateTransactionCoordinator
MutationBatch
MutationBatchResult
```

Транзакция содержит:

- operation ID;
- набор preconditions по aggregate ID/revision/epoch;
- create/update/delete operations;
- expected output schemas;
- event/outbox records;
- deterministic result checksum.

Commit:

```text
validate all inputs
→ build staged aggregates
→ validate all staged states
→ verify conservation invariants
→ persist state + ledger + result + outbox atomically
→ expose committed revisions
→ publish deltas/events asynchronously
```

Частичный commit запрещён.

R3.1 staged recovery и atomic checkpoint являются базой для этого слоя.

## 10. Пространственный substrate

Целевая адресация:

```text
Universe
└── Instance
    └── Space
        └── Region
            └── SimulationCell
```

`SimulationCell` — это:

- spatial index;
- environment sampling unit;
- interest-management unit;
- job partition hint;
- потенциальная shard boundary.

Но cell не является автоматически authority boundary.

### 10.1 Разделение адресов

```text
SpatialAddress
AuthorityAddress
```

В одной cell могут находиться aggregates с разными owners. На первом MVP разрешается один owner на region, но контракты не должны связывать это навсегда.

### 10.2 Большие логические объекты

Один логический meadow/forest/ocean physically состоит из shards:

```text
Logical Object
├── AggregateShard A
├── AggregateShard B
└── AggregateShard C
```

Shard имеет собственные revision, lease и spatial scope.

Соседям передаются boundary summaries:

```text
water flow
seed pressure
fire pressure
chemical concentration
population migration
```

## 11. Authority и compute

Главное правило:

> Один authoritative writer на aggregate; любое число read-only workers.

Worker не получает authority только потому, что выполняет расчёт.

Разные identity:

```text
authority_owner_id
compute_worker_id
job_id
job_attempt
```

Путь расчёта:

```text
Region Authority
→ immutable SimulationJob
→ worker calculation
→ MutationProposal
→ authority validation
→ staged authoritative commit
→ official snapshot/delta
```

Worker не отправляет готовый authoritative snapshot.

## 12. Distributed compute contracts

### SimulationJob

Содержит:

```text
job_id
job_type
target aggregate IDs
from_tick / to_tick
input snapshot hashes
expected revisions
rule/content package hashes
execution budget
attempt
```

### MutationProposal

Содержит:

```text
proposal_id
job_id
base revisions
base tick
read set
write set
operations
result hash
metrics
```

Authority проверяет:

- target ownership;
- authority epoch;
- base revisions;
- base tick;
- input hashes;
- package version;
- declared read/write sets;
- budgets;
- NaN/unsafe values;
- conservation/domain invariants;
- duplicate result ID.

Stale proposal либо отклоняется, либо создаёт новую job. Он не должен автоматически «накладываться поверх» нового состояния.

## 13. Simulation phases и adaptive scheduling

Не все процессы выполняются каждый frame.

Пример частот:

```text
interaction        immediate
fire/fast process fast simulation tick
weather            game minutes
grass growth       game hour
tree lifecycle     game day
migration          several days
```

Scheduler использует:

```text
next_update_tick
update_reason
priority
read/write sets
spatial shard
```

Для dormant zone применяется coarse transition:

```text
from_tick → to_tick
```

без проигрывания каждого промежуточного tick.

Рекомендуемые фазы:

```text
Weather
Environment
Biology
Lifecycle
Commit
Replication
```

## 14. Транспортные семантики

Нельзя использовать один универсальный transport interface для потоков с разными гарантиями.

### 14.1 ReplicationTransportPort

Для snapshots, deltas, ghosts и interest updates.

Adapters:

```text
LoopbackReplicationAdapter
EnetReplicationAdapter
NatsReplicationAdapter (benchmark/optional)
```

### 14.2 ServiceRequestReplyPort

Для capability discovery, Directory queries, route lookup и health requests.

### 14.3 EventStreamPort

Для durable domain events и audit stream.

### 14.4 JobQueuePort

Для simulation jobs, migrations и background workloads.

### 14.5 BulkTransferPort

Для large snapshots, content packages и checkpoint transfer.

Domain-код зависит от semantics port, а не от ENet/NATS/HTTP.

## 15. Transport lifecycle и peer sessions

Listener lifecycle:

```text
STOPPED
STARTING
LISTENING
DRAINING
FAILED
```

Peer session lifecycle:

```text
CONNECTING
TRANSPORT_CONNECTED
HANDSHAKING
SYNCHRONIZING
READY
DRAINING
CLOSED
FAILED
```

Нужны:

```text
TransportPeerId
TransportSessionId
LogicalSessionId
NetworkPeerSession
NetworkTransportEvent
```

Server transport остаётся LISTENING при подключении peer. READY принадлежит peer session.

Outbound metrics и queues должны быть per-peer и per-channel.

## 16. Protocol frame v2

Transport core не должен содержать allowlist всех domain DTO.

Frame знает:

```text
frame identity
session/sequence
channel
delivery mode
payload schema
payload bytes/dictionary
payload checksum
```

Логические channels:

```text
CONTROL
COMMAND
STATE
EVENT
JOB
BULK
```

Protocol registry связывает `payload_schema` с validator/router. Добавление нового aggregate DTO не требует изменения transport core.

## 17. NATS как adapter

NATS рассматривается как один из adapters для межсерверной связи, но не как часть canonical domain.

Запрещено сохранять в aggregate:

```text
NATS subject
stream name
consumer name
broker connection ID
```

Domain вызывает:

```text
event_stream.publish(event)
job_queue.submit(job)
request_reply.request(query)
```

Adapter определяет subject, queue group, ACK policy и reconnect.

### 17.1 NATS Core

Первое применение:

- registration;
- heartbeat;
- capability discovery;
- request/reply;
- load and health.

### 17.2 JetStream

Для данных, которые нельзя терять:

- compute jobs;
- mutation proposal results;
- domain events;
- handoff transitions;
- audit records.

Гарантия строится как:

```text
at-least-once delivery
+ stable operation/job/result ID
+ idempotent processing
+ stored terminal result
```

### 17.3 Outbox

Authoritative state, operation result и outbox record должны сохраняться в одной транзакционной границе.

```text
commit state + ledger + outbox
→ asynchronous publisher
→ broker
→ consumer ACK
```

Падение publisher не должно терять committed event.

## 18. Dynamic content foundation

До rule runtime вводится точная ссылка на тип:

```text
package_id
package_version
package_hash
state_schema
```

Одинаковые ID/version с разным hash считаются конфликтом.

Позднее `DynamicTypeRegistry` хранит immutable packages, migrations, capabilities и activation state.

Agent-generated content не исполняется как произвольный GDScript в authority process.

Уровни расширения:

```text
parameters
→ declarative rule IR
→ reviewed trusted host operation
→ optional sandboxed component
```

Rules возвращают proposals и имеют read/write sets и budgets.

## 19. Первый сквозной эксперимент

После foundation-этапов должна быть доказана цепочка:

1. Listen-host запускается одним F5.
2. Authority создаёт `PopulationFieldAggregate`.
3. Client replica получает aggregate snapshot.
4. Клиент процедурно рисует поле.
5. Worker получает growth job.
6. Worker возвращает proposal.
7. Authority commit повышает field revision.
8. Клиент получает aggregate delta.
9. Игрок выбирает deterministic procedural instance.
10. Одна transaction изменяет field и создаёт WorldItem.
11. Replay не создаёт второй предмет.
12. Restart восстанавливает тот же checksum и terminal result.
13. Тот же сценарий проходит через loopback и реальный multi-process transport.

Этот эксперимент является архитектурным gate перед сложными экосистемами, машинами и dynamic rules.

## 20. Обязательные инварианты

1. Один aggregate имеет одного active authoritative writer.
2. Authority epoch монотонен и fenced.
3. Revision/tick не откатываются.
4. Worker не изменяет live state.
5. Client не хранит ссылку на server aggregate.
6. Offline и online используют одни domain operations.
7. Transport adapter не влияет на domain identity.
8. Aggregate kind имеет строгую state schema.
9. Multi-aggregate operation commit атомарен.
10. Persistence включает dedup/result/outbox state.
11. Mutable children адресуются stable IDs.
12. Logical object может состоять из independently owned shards.
13. Procedural instance key детерминирован.
14. Dynamic package immutable и content-addressed.
15. Любая новая authoritative gameplay-функция имеет domain, loopback и process tests.

## 21. Запрещённые обходы

Нельзя:

- обновлять canonical state из UI;
- использовать shared object reference между host client и server;
- делать NATS subject частью aggregate ID;
- разрешать нескольким workers записывать aggregate;
- подменять field миллионом active Nodes;
- использовать array index как identity;
- выполнять materialization несколькими независимыми commits;
- передавать worker готовое право authority;
- загружать arbitrary generated GDScript в authoritative process;
- строить Directory только вокруг item entity;
- считать SimulationCell постоянной authority boundary;
- использовать ENet/NATS API внутри domain service.

## 22. Решение A0

Принято:

- N0–N2 и R3.1 сохраняются без концептуального переписывания;
- N3 откладывается до generic aggregate, spatial, multi-peer и bus boundaries;
- H0, A1, S0 и T1 приняты;
- B0 transport-independent message bus contracts реализован как current candidate;
- следующим foundation-этапом становится M0 multi-aggregate transactions/outbox;
- transport, message bus, transactions и compute contracts развиваются отдельными ports;
- NATS adapter вводится только после принятия transport-independent B0;
- Population Field строится после aggregate/spatial/transaction foundations;
- World Directory строится на generic aggregate/shard routing, а не только на `world_item`.

Полная последовательность описана в [`../plans/DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md`](../plans/DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md).
