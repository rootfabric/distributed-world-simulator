# Checkpoint готовности PlanetSimulator к distributed runtime

**Дата ревизии:** 29 июля 2026 года
**Runtime checkpoint candidate:** `v16.8.5-domain-m0-aggregate-transactions`
**Архитектурная база:** `v16.7.1-architecture-a0-distributed-runtime`

## 1. Что доказано кодом

### N0

- strict versioned DTO;
- canonical JSON/checksums;
- authority owner/epoch;
- revision/tick fences;
- snapshot/delta;
- handoff state machine contracts;
- presentation/runtime object rejection.

### N1

- ENet handshake;
- initial snapshot;
- remote authoritative item command;
- result/delta;
- logical session и transport session separation;
- reconnect/replay без второй mutation.

### N2

- multi-process orchestration;
- isolated user state;
- dynamic ports;
- readiness/timeouts;
- fault classification;
- cleanup;
- JSON/JUnit reports.

### R3.1

- strict authoritative checkpoint;
- active/previous/pending atomic layout;
- staged recovery;
- command/replay state recovery;
- crash after commit и crash before commit;
- fail-closed corruption/rollback handling.

### H0/A1/S0/T1/B0

- single-process listen-host с client replica boundary;
- generic item/non-item aggregate contracts;
- stable hierarchical SimulationCellAddress;
- explicit cell descriptors, shards и neighbour topology;
- independent spatial and authority addresses;
- monotonic boundary summaries;
- multi-peer listener/session separation и targeted delivery;
- real per-peer outbound queues/backpressure;
- transport-independent request/reply, event, job, replication и bulk ports;
- strict versioned timeout/backpressure/acknowledgement results.

## 2. К чему база готова

Высокая готовность:

- dedicated server;
- localhost server/client;
- first listen-host implementation;
- generic aggregate contracts;
- spatial cell/shard substrate;
- multiple peers и targeted transport;
- transport-independent semantic message-bus ports.

Средняя готовность:

- NATS Core adapter;
- JetStream/outbox;
- population fields;
- multi-aggregate transactions;
- local compute-worker contracts.

Пока не готово:

- executable World Directory;
- live authority leases;
- generic cross-server handoff;
- ghosts/interest streaming;
- dynamic region split;
- safe dynamic rule runtime.

## 3. Выявленные архитектурные ограничения

### Listen-host foundation реализован, gameplay migration ещё не завершена

H0 уже создаёт отдельные `ClientRuntime`, `ClientCommandGateway` и `ClientReplicaStore`, а loopback и ENet дают одинаковый итоговый checksum. Default F5 и существующий gameplay UI пока остаются `offline`; их вертикальный перенос выполняется последовательно после принятия H0.

### Current aggregate is item-backed

Нужен A1 generic descriptor/adapter, а не снятие item invariants.

### Multi-peer transport foundation реализован

T1 разделяет listener и peer lifecycle, использует strict ProtocolFrame v2 и реальные per-peer outbound queues. Миграция N1 session services на v2 может выполняться постепенно через compatibility adapter.

### Semantic bus ports реализованы без broker SDK

B0 разделяет request/reply, events, jobs, replication и bulk transfer. Реальный NATS/JetStream adapter и durable outbox ещё не реализованы.

### Current command is single-aggregate

Нужен M0 staged mutation batch.

### Current persistence has no general outbox

R3.1 должен быть расширен atomic outbox, не заменён.

## 4. Решение о N3

World Directory не отменён, но перенесён после:

```text
H0 listen-host
A1 generic aggregate
S0 spatial substrate
T1 multi-peer transport
B0 message bus contracts
```

Это позволяет Directory маршрутизировать generic aggregate/shard и transport-neutral route, а не только item/ENet endpoint.

## 5. Текущий и следующий gate

```text
H0 — listen-host runtime — accepted
A1 — Generic Aggregate Foundation — accepted
S0 — Spatial Simulation Substrate — accepted
T1 — Multi-peer Transport v2 — accepted
B0 — Transport-independent Message Bus Contracts — accepted
M0 — Multi-aggregate Transactions/Outbox Foundation — current candidate
S1 — Distributed Compute Contracts — next
```

M0 реализует staged multi-aggregate mutation, обязательные cross-aggregate validators, atomic persistence, stable replay result и outbox records. Следующий foundation gate — S1: immutable simulation jobs, declared read/write sets и MutationProposal.

## 6. Что пока не начинать

- NATS adapter до принятия M0/S1 contracts;
- Population Field до A1/S0/M0;
- generated rule runtime;
- World Directory до принятия M0/S1 и последующих bus adapters;
- cross-server handoff до N3/M0;
- production orchestration;
- massive entity-per-grass representation.

## 7. Связанные документы

- [`../architecture/DISTRIBUTED_RUNTIME_AND_SIMULATION_FOUNDATION_RU.md`](../architecture/DISTRIBUTED_RUNTIME_AND_SIMULATION_FOUNDATION_RU.md);
- [`../plans/DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md`](../plans/DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md);
- [`../checkpoints/2026-07-29_V16_7_1_ARCHITECTURE_A0_DISTRIBUTED_RUNTIME_RU.md`](../checkpoints/2026-07-29_V16_7_1_ARCHITECTURE_A0_DISTRIBUTED_RUNTIME_RU.md);
- [`../checkpoints/2026-07-29_V16_8_0_RUNTIME_H0_LISTEN_HOST_RU.md`](../checkpoints/2026-07-29_V16_8_0_RUNTIME_H0_LISTEN_HOST_RU.md).

## 8. A1 gate

- strict aggregate identity/authority/spatial scope;
- strict generic snapshot/delta;
- adapter registry;
- item and non-item vertical tests;
- EntitySnapshotEnvelope v1 remains stable.
