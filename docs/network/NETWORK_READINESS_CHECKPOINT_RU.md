# Checkpoint готовности PlanetSimulator к distributed runtime

**Дата ревизии:** 29 июля 2026 года
**Runtime checkpoint candidate:** `v16.8.0-runtime-h0-listen-host`
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

## 2. К чему база готова

Высокая готовность:

- dedicated server;
- localhost server/client;
- first listen-host implementation;
- generic aggregate contracts;
- transport-independent ports;
- outbox foundation;
- local compute-worker contracts.

Средняя готовность:

- multiple peers;
- NATS service bus;
- spatial shards;
- population fields;
- multi-aggregate transactions.

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

### Current transport is single-peer oriented

Нужен T1 listener/peer lifecycle и per-peer queues.

### Current wire routing is DTO allowlist-oriented

Нужен protocol frame v2 с channel/payload schema.

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
H0 — listen-host runtime — current candidate
A1 — Generic Aggregate Foundation — next
```

H0 не добавляет новых игровых механик. Он проводит существующую item-команду через настоящий client replica boundary внутри одного процесса и сравнивает результат с ENet process path. После принятия H0 следующий фундаментальный шаг — generic aggregate contracts без ослабления существующих item invariants.

## 6. Что пока не начинать

- NATS adapter до B0 ports;
- Population Field до A1/S0/M0;
- generated rule runtime;
- World Directory до T1/B0;
- cross-server handoff до N3/M0;
- production orchestration;
- massive entity-per-grass representation.

## 7. Связанные документы

- [`../architecture/DISTRIBUTED_RUNTIME_AND_SIMULATION_FOUNDATION_RU.md`](../architecture/DISTRIBUTED_RUNTIME_AND_SIMULATION_FOUNDATION_RU.md);
- [`../plans/DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md`](../plans/DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md);
- [`../checkpoints/2026-07-29_V16_7_1_ARCHITECTURE_A0_DISTRIBUTED_RUNTIME_RU.md`](../checkpoints/2026-07-29_V16_7_1_ARCHITECTURE_A0_DISTRIBUTED_RUNTIME_RU.md);
- [`../checkpoints/2026-07-29_V16_8_0_RUNTIME_H0_LISTEN_HOST_RU.md`](../checkpoints/2026-07-29_V16_8_0_RUNTIME_H0_LISTEN_HOST_RU.md).
