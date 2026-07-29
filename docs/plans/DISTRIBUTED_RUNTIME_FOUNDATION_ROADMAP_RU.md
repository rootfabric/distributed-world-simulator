# План укрепления distributed runtime PlanetSimulator

**Текущий runtime checkpoint:** `v16.8.1-architecture-a1-generic-aggregate`
**Архитектурная база:** `v16.7.1-architecture-a0-distributed-runtime`
**Принятый runtime:** `v16.8.0-runtime-h0-listen-host`
**Стратегия:** сначала композиционные и контрактные основания, затем сложные симуляционные объекты и многосерверный runtime.

## 1. Почему N3 перенесён

Прямой переход к World Directory сейчас закрепил бы слишком узкие предположения:

- route только к item entity или region;
- один transport peer;
- ENet как неявный межсерверный transport;
- отсутствие generic aggregate kind;
- отсутствие shard/spatial scope;
- отсутствие compute worker semantics;
- отсутствие self-host client replica boundary.

Directory остаётся важной целью, но будет построен после фиксации того, **что именно он маршрутизирует и какими transport semantics пользуется**.

## 2. Принцип выполнения

Работа идёт последовательными небольшими checkpoint, каждый из которых:

- закрывает одну архитектурную границу;
- имеет самостоятельный наблюдаемый результат;
- не требует всей будущей системы;
- сохраняет принятый regression;
- добавляет negative/bypass tests;
- не создаёт параллельный альтернативный domain path.

Нельзя одновременно начинать H0, A1, NATS, Population Field и Directory. В каждый момент основной foundation-track закрывает один checkpoint.

## 3. A0 — distributed runtime architecture

```text
checkpoint: v16.7.1-architecture-a0-distributed-runtime
branch: feature/a0-distributed-runtime-architecture
scope: documentation / ADR / machine-readable roadmap
```

Результат:

- runtime topology model;
- self-host/listen-host решение;
- generic aggregate boundary;
- authority vs compute separation;
- transport families;
- NATS adapter policy;
- spatial cell/shard model;
- multi-aggregate transaction direction;
- обновлённая dependency roadmap.

Acceptance:

- документация не противоречит N0–R3.1;
- все ссылки и JSON корректны;
- runtime-код не изменён;
- следующий кодовый checkpoint однозначен.

## 4. H0 — listen-host runtime — принят

```text
checkpoint: v16.8.0-runtime-h0-listen-host
branch: feature/h0-listen-host-runtime
status: accepted
```

H0 доказал single-process network-first composition: клиентская реплика и embedded authority разделены DTO/loopback boundary, а итоговый checksum совпадает с отдельным ENet server/client path. Полный UI ещё не мигрирован на replica store — это выполняется отдельными вертикальными этапами.

## 5. A1 — Generic Aggregate Foundation — реализован, candidate

```text
checkpoint: v16.8.1-architecture-a1-generic-aggregate
branch: feature/a1-generic-aggregate-foundation
status: candidate
```

### Scope

- `DynamicTypeReference`;
- `AggregateIdentity`;
- `AggregateAuthorityState`;
- `AggregateSpatialScope`;
- `AggregateDescriptor`;
- `AggregateSnapshotEnvelope`;
- `AggregateDeltaEnvelope`;
- `AggregateAdapterPort`;
- `AggregateAdapterRegistry`;
- `GenericAggregateStore`;
- compatibility adapter for existing item-backed `WorldEntityAggregate`.

### Acceptance

- item aggregate сохраняет прежние identity/authority/revision/tick/domain semantics;
- non-item aggregate проходит snapshot/delta/replica path без `item_instance_id`, physics и point position;
- exact schemas, checksums, replay и stale fences проверены;
- `EntitySnapshotEnvelope v1` и `WorldEntityAggregate` не ослаблены.

### Не включено

- Population Field gameplay;
- PartGraph;
- multi-aggregate transaction;
- NATS;
- Directory;
- worker execution.

## 6. S0 — Spatial Simulation Substrate

```text
proposed checkpoint: v16.8.2-simulation-s0-spatial-substrate
branch: feature/s0-spatial-simulation-substrate
```

### Scope

- `SpatialCellDescriptor`;
- `SpatialScope`;
- `AggregateShardDescriptor`;
- neighbour and boundary summary contracts;
- stable hierarchical cell address;
- separation SpatialAddress/AuthorityAddress;
- cell-to-aggregate index.

### Acceptance

- несколько aggregate kinds находятся в одной cell;
- один aggregate может покрывать несколько cells;
- logical object состоит из shards;
- cell address не меняется при render origin shift;
- authority owner не выводится автоматически из cell ID.

### Открытое решение

Физический размер cells не фиксируется глобально. Descriptor должен поддерживать level/resolution для поверхностей разных планет и пространств.

## 7. T1 — Multi-peer Transport v2

```text
proposed checkpoint: v16.8.3-network-t1-multi-peer
branch: feature/t1-multi-peer-transport-v2
```

### Scope

- listener lifecycle отдельно от peer lifecycle;
- `NetworkPeerSession`;
- строгий `NetworkTransportEvent`;
- `send_to_peer` и `disconnect_peer(peer_id)`;
- per-peer sequence/queues/metrics;
- protocol frame v2 с channel и payload schema;
- compatibility shim для текущих N1 tests.

### Acceptance

- server держит минимум два peer одновременно;
- disconnect одного peer не останавливает listener;
- sessions имеют разные IDs;
- queue metrics не глобальные;
- старый N1 single-peer vertical slice проходит через shim.

## 8. B0 — Transport-independent message bus contracts

```text
proposed checkpoint: v16.8.4-data-plane-b0-message-bus-contracts
branch: feature/b0-message-bus-contracts
```

### Scope

```text
ReplicationTransportPort
ServiceRequestReplyPort
EventStreamPort
JobQueuePort
BulkTransferPort
```

Добавить loopback/in-memory adapters и contract tests. NATS dependency отсутствует.

### Acceptance

- domain service не знает subject/channel implementation;
- разные semantics нельзя подменить одним несовместимым port;
- exact DTO survives adapter round-trip;
- duplicate/timeout/backpressure contracts выражены явно.

## 9. M0 — Multi-aggregate transactions и outbox foundation

```text
proposed checkpoint: v16.8.5-domain-m0-aggregate-transactions
branch: feature/m0-aggregate-transactions
```

### Scope

- `MutationBatch`;
- aggregate preconditions;
- create/update/delete staged operations;
- `MutationBatchResult`;
- conservation validation;
- `AggregateTransactionCoordinator`;
- atomic persistence integration;
- `OutboxRecord` как часть commit state.

### Acceptance

- batch изменяет два aggregates или не меняет ни одного;
- failure после staging не изменяет live state;
- crash после commit восстанавливает result/outbox;
- exact operation replay не создаёт второй aggregate;
- previous checkpoint остаётся recoverable.

## 10. S1 — Distributed compute contracts

```text
proposed checkpoint: v16.9.0-simulation-s1-distributed-compute
branch: feature/s1-distributed-compute-contracts
```

### Scope

- `SimulationJobEnvelope`;
- `SimulationJobResultEnvelope`;
- `MutationProposal`;
- read/write sets;
- execution budgets;
- deterministic result fingerprint;
- local worker adapter;
- stale proposal policy.

### Acceptance

- worker получает immutable snapshot;
- worker не имеет live registry/repository port;
- duplicate result idempotent;
- stale revision rejected;
- invalid write set/budget rejected;
- same input/package produces same result hash.

## 11. B1 — NATS Core adapter

```text
proposed checkpoint: v16.9.1-data-plane-b1-nats-core
branch: feature/b1-nats-core-adapter
```

### Scope

- local NATS process descriptor для N2 harness;
- request/reply adapter;
- service registration;
- heartbeat/health/load;
- capability discovery;
- reconnect diagnostics;
- subject mapping только внутри adapter.

### Acceptance

```text
server A heartbeat
→ server B discovers A
→ capability request/reply
→ process restart
→ discovery recovers
```

Domain-код не импортирует NATS client API.

## 12. B2 — JetStream и durable outbox

```text
proposed checkpoint: v16.9.2-data-plane-b2-jetstream-outbox
branch: feature/b2-nats-jetstream-outbox
```

### Scope

- durable event stream;
- durable job queue;
- consumer groups;
- ACK/retry;
- outbox publisher;
- inbox/dedup records;
- restart recovery;
- poison-message quarantine.

### Acceptance

- committed outbox survives publisher crash;
- unacked job redelivered;
- duplicate proposal/result processed once;
- queue group scales worker count without authority code change;
- consumer lag/backpressure observable.

## 13. P0 — Population Field Foundation

```text
proposed checkpoint: v16.10.0-simulation-p0-population-field
branch: feature/p0-population-field
```

### Scope

- `PopulationFieldAggregate`;
- `PopulationCohortState`;
- patch state;
- deterministic procedural instance keys;
- compact exclusion representation;
- `MaterializationRecord`;
- aggregate snapshot/delta;
- persistence/recovery.

### Acceptance

- поле представляет тысячи visual instances одним aggregate;
- deterministic client regeneration;
- один instance materializes once;
- replay/restart не создаёт дубль;
- массовое disturbance compacted to patch state.

## 14. D1 — первый remote compute-worker MVP

```text
proposed checkpoint: v16.10.1-simulation-d1-worker-mvp
branch: feature/d1-vegetation-worker-mvp
```

Топология:

```text
Listen-host or client
+ Location Authority
+ Vegetation Worker
+ NATS/JetStream
```

Сценарий:

```text
field revision 15
→ growth job
→ worker proposal
→ authority validates/commits revision 16
→ client aggregate delta
→ worker crash/retry without duplicate commit
```

## 15. N3 — World Directory и authority routing

```text
proposed checkpoint: v16.11.0-network-n3-world-directory
branch: feature/n3-world-directory
```

N3 начинается только после A1, S0, T1 и B1.

Directory маршрутизирует:

- node/service capabilities;
- aggregate/shard ownership;
- authority epoch/lease;
- replication endpoint;
- service bus route;
- draining state.

Acceptance:

- два authorities регистрируются;
- один shard имеет одного active writer;
- stale lease fenced;
- route lookup возвращает transport-neutral route;
- draining node не получает новую lease.

## 16. N4 — Generic cross-server handoff

```text
proposed checkpoint: v16.12.0-network-n4-authority-handoff
branch: feature/n4-authority-handoff
```

Handoff работает через aggregate adapter, а не требует exact `WorldEntityAggregate` script.

Первый объект может оставаться item, но protocol обязан поддерживать aggregate kind/schema/scope.

## 17. Дальнейшие линии

После N4:

```text
N5 client dual-route handoff
N6 ghosts and interest management
P1 EntityPartGraph and detach/attach
D0 dynamic type registry and rule IR
D2 portable content distribution
N7 child spaces
N8 planetary surface regions
N9 dynamic shard split/merge
```

Порядок может уточняться, но обязательные foundation dependencies не удаляются.

## 18. Рекомендуемый ближайший порядок

Не распараллеливать основной foundation-track:

```text
A0 documentation
→ H0 listen-host
→ A1 generic aggregates
→ S0 spatial substrate
→ T1 multi-peer transport
→ B0 bus contracts
→ M0 aggregate transactions/outbox
→ S1 compute contracts
```

После этого допускаются две контролируемые линии:

```text
Infrastructure: B1 → B2 → N3
Simulation:     P0 → D1
```

Они сходятся перед N4 и более сложными distributed scenarios.

## 19. Общий acceptance gate каждого этапа

Каждый кодовый checkpoint обязан иметь:

```text
domain/contract tests
negative schema/bypass tests
loopback test where applicable
real process scenario where applicable
restart/replay test where state is authoritative
full network profile
full world regression
main scene CLI smoke
machine-readable report
changed-file overlay
```

## 20. Что намеренно откладывается

До соответствующего foundation gate не начинать:

- произвольный generated GDScript;
- WASM runtime;
- сложную биологию;
- тысячи real entity nodes для растительности;
- dynamic region split;
- production Kubernetes/Agones;
- WAN optimization;
- direct ENet server mesh без routing contracts;
- полный NATS-only replication без benchmark.
