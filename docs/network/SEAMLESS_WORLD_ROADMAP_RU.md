# Дорожная карта бесшовного распределённого мира PlanetSimulator

## Текущий статус

```text
runtime checkpoint candidate: v16.8.4-data-plane-b0-message-bus-contracts
architecture base: v16.7.1-architecture-a0-distributed-runtime
```

N0–N2 и R3.1 приняты. Перед Directory добавлена foundation-линия для self-host, generic aggregates, spatial shards, multi-peer transport, message bus ports, transactions и compute proposals.

## Целевая архитектура

```text
Clients
  ↓ commands / snapshots / deltas
Client Gateway or embedded ClientRuntime
  ↓ route
Region Authority — single writer
  ↕ repository + outbox
  ↕ jobs / proposals
Simulation Workers
  ↕ service/event/job adapters
Message bus implementations
  ↕
World Directory / Content Registry / other services
```

Топология может быть одним процессом, несколькими localhost processes или cluster deployment. Domain contracts не меняются.

## Этапы

### N0 — network contracts

Статус: accepted.

### N1 — one authority + client vertical slice

Статус: accepted.

### N2 — multi-process harness

Статус: accepted.

### R3.1 — persistence/recovery

Статус: accepted.

### A0 — distributed runtime architecture

Статус: accepted architecture base.

Фиксирует решения, которые предотвращают преждевременную реализацию Directory и NATS вокруг узкой модели.

### H0 — listen-host

Статус: accepted. Один процесс, но client/server разделены loopback DTO boundary; итоговый checksum эквивалентен реальному ENet process path.

### A1 — generic aggregates

Статус: accepted. Item entity остаётся существующим path; fields/cells/processes получают отдельные schemas/envelopes, adapters и generic replica store.

### S0 — cells/scopes/shards

Статус: accepted. Реализованы stable hierarchical addresses, cell descriptors, explicit shard bindings, neighbour topology и boundary summaries. Spatial index отделён от authority routing.

### T1 — multi-peer transport

Статус: accepted. Listener и peer sessions разделены; реализованы strict frame v2, targeted delivery и реальные per-peer outbound queues.

### B0 — message bus ports

Статус: current candidate. Request/reply, events, jobs, replication и bulk transfer выражены отдельными transport-independent ports; NATS/JetStream SDK отсутствуют.

### M0 — aggregate transactions/outbox

Atomic operations над несколькими aggregates.

### S1 — compute jobs/proposals

Workers рассчитывают, authority commit.

### B1/B2 — NATS Core и JetStream

Сначала discovery/request-reply, затем durable jobs/events/outbox.

### P0/D1 — Population Field и worker MVP

Первый сложный distributed simulation experiment.

### N3 — World Directory

Регистрация nodes, generic shard leases и transport-neutral routes.

### N4 — authority handoff

Generic aggregate transfer A → B.

### N5 — player dual-route handoff

Warm connection и непрерывность input/UI.

### N6 — ghosts и interest management

Read-only overlap replicas и bandwidth budgets.

### N7+ — child spaces, planetary regions, dynamic rebalance

Развиваются после доказанного generic handoff.

## Главный acceptance каждого шага

```text
one observable result
+ strict contracts
+ negative/bypass tests
+ process scenario
+ restart/replay where applicable
+ no regression of local gameplay
```

## Неподвижные правила

- single writer per aggregate;
- stable identity independent of process;
- authority epoch fencing;
- client replica independent of server object graph;
- worker proposals instead of direct mutation;
- adapter-independent domain;
- content-addressed dynamic types;
- sharding explicit, not accidental concurrent writes.

Полный foundation plan: [`../plans/DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md`](../plans/DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md).
