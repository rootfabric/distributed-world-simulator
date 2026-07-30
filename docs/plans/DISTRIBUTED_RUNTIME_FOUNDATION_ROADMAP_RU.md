> **Current post-A2 gate:** `M1 — Unified Networked Gameplay Core`. B1/B2 перенесены после A3. Основной порядок: `M1 → M2 → M3 → M4 → M5 → M6 → A3 → B1 → B2 → N3–N6`. Подробности: [`SINGLE_SERVER_MULTIPLAYER_ROADMAP_RU.md`](SINGLE_SERVER_MULTIPLAYER_ROADMAP_RU.md).

# План развития distributed runtime PlanetSimulator

**Текущий принятый runtime checkpoint:** `v16.9.3-runtime-h3-dedicated-multiplayer`
**Принятая architecture-база:** `v16.9.4-architecture-a2-networked-gameplay`
**Текущий roadmap candidate:** `v16.9.5-roadmap-single-server-multiplayer-first`
**Следующий основной gate:** `M1 — Unified Networked Gameplay Core`
**Стратегия:** сначала доказать единый graphical gameplay path в трёх топологиях, затем подключать broker infrastructure и несколько authorities.

## 1. Принцип выполнения

Каждый этап должен:

- закрывать одну архитектурную границу;
- иметь наблюдаемый пользовательский или process-level результат;
- сохранять один domain/gameplay path;
- добавлять negative, replay и bypass tests;
- проходить полный relevant regression;
- не вводить скрытую зависимость presentation от canonical state;
- не создавать второй writer на aggregate.

Основной track выполняется последовательно. Исследования будущих этапов допустимы, но не должны создавать параллельный production implementation.

## 2. Принятый foundation

### A0 — Distributed runtime architecture

```text
checkpoint: v16.7.1-architecture-a0-distributed-runtime
status: accepted
```

Зафиксированы runtime topologies, authority/compute separation, transport families, spatial/shard model, listen-host policy и dependency roadmap.

### H0 — Listen-host foundation

```text
checkpoint: v16.8.0-runtime-h0-listen-host
status: accepted
```

Доказано разделение embedded authority и client runtime через DTO/loopback boundary. Полный graphical gameplay ещё не мигрирован — это scope H1.

### A1 — Generic Aggregate Foundation

```text
checkpoint: v16.8.1-architecture-a1-generic-aggregate
status: accepted
```

Item и non-item aggregates используют strict identity, authority, spatial scope, snapshot/delta и adapter contracts.

### S0 — Spatial Simulation Substrate

```text
checkpoint: v16.8.2-simulation-s0-spatial-substrate
status: accepted
```

Реализованы stable hierarchical cells, explicit shard bindings, neighbour topology и boundary summaries. Cell identity не определяет authority owner.

### T1 — Multi-peer Transport v2

```text
checkpoint: v16.8.3-network-t1-multi-peer
status: accepted
```

Listener и peer lifecycle разделены. Есть targeted delivery, route generations, per-peer queues/backpressure и реальный двухклиентский ENet process scenario.

### B0 — Transport-independent Message Bus Contracts

```text
checkpoint: v16.8.4-data-plane-b0-message-bus-contracts
status: accepted
```

Request/reply, events, jobs, replication и bulk transfer выражены разными semantic ports. Broker SDK не попадает в domain/application код.

### M0 — Multi-aggregate Transactions and Outbox

```text
checkpoint: v16.8.5-domain-m0-aggregate-transactions
status: accepted
```

Create/update/delete над несколькими aggregates выполняются атомарно. Result, operation ledger и outbox восстанавливаются crash-safe и replay-safe.

### S1 — Distributed Compute Contracts

```text
checkpoint: v16.9.0-simulation-s1-distributed-compute-fix1
status: accepted
```

Authority выдаёт checksum-bound immutable job. Worker получает exact projected state и capability-scoped budget, возвращает proposal, а authority проверяет read/write scope, staleness, determinism и commit’ит через M0.

## 3. Почему H1 выполняется перед B1

Foundation уже поддерживает listen-host, dedicated process, multi-peer transport, transactions и compute proposals. H1 переводит существующую реальную игру на этот путь и находится в статусе candidate.

Без H1–H3 можно построить NATS и World Directory вокруг непроверенных assumptions о:

- Player Aggregate;
- player/session identity;
- graphical client composition;
- movement command semantics;
- inventory/container contention;
- reconnect behaviour;
- relevance и remote player presentation.

Поэтому ближайшая обязательная последовательность:

```text
H1 → H2 → H3 → A2
```

## 4. H1 — Playable listen-host

```text
checkpoint: v16.9.1-runtime-h1-playable-listen-host
branch: feature/h1-playable-listen-host
status: candidate
```

### Цель

Default graphical запуск использует embedded authority и separate client runtime. Игрок, UI и presentation работают только с client replicas и command gateway.

### Scope

- graphical client bootstrap;
- Player Aggregate foundation;
- authoritative movement;
- transform/velocity replication;
- inventory/hotbar/container replica models;
- pickup/drop/transfer/stack/split/mount commands;
- authoritative results и UI feedback;
- save/restart/replay;
- explicit offline tools mode.

### Acceptance

- F5 запускает playable listen-host;
- UI не читает live authoritative aggregate;
- movement и item interactions проходят через authority;
- restart восстанавливает committed world/player state;
- duplicate commands не создают вторую mutation;
- equivalent loopback и ENet scenario дают одинаковый canonical result.

## 5. H2 — Dedicated server + 1 graphical client

```text
proposed checkpoint: v16.9.2-runtime-h2-dedicated-single-player
branch: feature/h2-dedicated-single-player
status: planned
```

### Цель

Тот же graphical client работает против отдельного headless simulation server без topology-specific gameplay fork.

### Scope

- graphical connect flow;
- initial world/player snapshot;
- dedicated spawn/despawn;
- movement и interactions по ENet;
- logical-session reconnect;
- server draining/shutdown handling;
- persistence recovery.

### Acceptance

```text
headless server + graphical client
connect → play → disconnect → reconnect
server restart → committed state recovered
no duplicate player or item mutation
```

## 6. H3 — Dedicated server + 2 graphical clients

```text
proposed checkpoint: v16.9.3-runtime-h3-dedicated-multiplayer
branch: feature/h3-dedicated-multiplayer
status: planned
```

### Цель

Один server обслуживает минимум двух полноценных graphical clients.

### Scope

- stable player identities;
- authoritative spawn/despawn;
- remote player transform replication;
- basic interpolation;
- separate inventory/permissions;
- contested item/container/mount operations;
- targeted results/deltas;
- per-peer isolation;
- reconnect без второй player entity;
- минимальная relevance model одной region.

### Acceptance

- A и B видят movement друг друга;
- один item при одновременном pickup получает ровно один winner;
- loser получает deterministic rejection;
- disconnect A не останавливает B;
- reconnect A сохраняет identity/state;
- slow/backpressured peer не блокирует второго.

## 7. A2 — Networked Gameplay Architecture Checkpoint

```text
proposed checkpoint: v16.9.4-architecture-a2-networked-gameplay
branch: feature/a2-networked-gameplay-architecture
status: planned after H3
scope: documentation, ADR, audit, test matrix
```

### Цель

Зафиксировать реально доказанную client/server gameplay architecture до подключения broker/server mesh.

### Фиксируемые решения

- единая graphical client composition H1/H2/H3;
- Player Aggregate и player-session identity;
- peer-to-player mapping;
- movement replication/prediction/correction policy;
- command permissions;
- inventory/container contention;
- reconnect/replay;
- remote presentation;
- relevance assumptions одной region;
- обязательные contracts для N3–N6.

### Acceptance

- H1–H3 accepted;
- отсутствуют topology-specific domain forks;
- client/UI не имеет authoritative references;
- process tests подтверждают один и два graphical clients;
- ADR, test matrix и machine-readable roadmap согласованы;
- B1 scope однозначен.

## 8. B1 — NATS Core Adapter

```text
proposed checkpoint: v16.10.0-data-plane-b1-nats-core
branch: feature/b1-nats-core-adapter
status: planned after A2
```

### Scope

- local NATS process descriptor для N2 harness;
- B0 request/reply adapter;
- service registration;
- heartbeat, health и load;
- capability discovery;
- reconnect diagnostics;
- subject mapping только внутри adapter.

### Acceptance

```text
server A heartbeat
→ server B discovers A
→ capability request/reply
→ NATS/server restart
→ discovery recovers
```

Domain/gameplay код не импортирует NATS client API.

## 9. B2 — JetStream and Outbox Delivery

```text
proposed checkpoint: v16.10.1-data-plane-b2-jetstream-outbox
branch: feature/b2-nats-jetstream-outbox
status: planned
```

### Scope

- durable event stream;
- durable job queue;
- ACK/retry;
- consumer groups;
- M0 outbox publisher;
- inbox/dedup;
- restart recovery;
- poison-message quarantine.

### Acceptance

- committed outbox survives publisher crash;
- unacked job is redelivered;
- duplicate proposal/result is processed once;
- worker count scales without authority code change;
- lag/backpressure are observable.

## 10. P0 — Population Field

```text
proposed checkpoint: v16.11.0-simulation-p0-population-field
branch: feature/p0-population-field
status: planned
```

Population Field представляет массовую растительность/агентов компактным aggregate state, а не тысячами canonical scene entities.

Acceptance:

- deterministic client regeneration;
- materialization одного instance не создаёт дубль;
- disturbances сохраняются компактно;
- restart/replay сохраняют identity и revision.

## 11. D1 — Remote Worker MVP

```text
proposed checkpoint: v16.11.1-simulation-d1-worker-mvp
branch: feature/d1-vegetation-worker-mvp
status: planned
```

```text
Population Field revision N
→ durable growth job
→ remote worker proposal
→ authority validation
→ M0 commit revision N+1
→ client delta
```

Worker crash/retry не создаёт второй commit.

## 12. N3 — World Directory + 2 Authorities

```text
proposed checkpoint: v16.12.0-network-n3-world-directory
branch: feature/n3-world-directory
status: planned
```

### Dependencies

```text
A2 + B1 + A1 + S0 + T1 + M0
```

### Scope

- node/service registration;
- authority/shard leases;
- owner/epoch route;
- replication endpoint;
- draining state;
- transport-neutral route lookup.

### Acceptance

- два authorities регистрируются;
- разные shards имеют одного active writer каждый;
- stale lease fenced;
- draining server не получает новую lease;
- graphical client получает корректный route.

## 13. N4 — Generic Object Handoff

```text
proposed checkpoint: v16.12.1-network-n4-authority-handoff
branch: feature/n4-authority-handoff
status: planned
```

Первый handoff выполняется для item/container/vehicle или другого generic aggregate:

```text
A freezes mutations
→ transfer snapshot/lease intent
→ B validates and persists
→ B activates higher authority epoch
→ A retires old writer
```

Identity/revision не откатываются, двух active writers не возникает.

## 14. N5 — Seamless Player Handoff

```text
proposed checkpoint: v16.12.2-network-n5-seamless-player-handoff
branch: feature/n5-seamless-player-handoff
status: planned
```

Клиент имеет active route к A и warm route к B. Переключение authority не пересоздаёт UI, inventory или player identity и не сбрасывает input sequence.

## 15. N6 — Ghosts and Interest Management

```text
proposed checkpoint: v16.12.3-network-n6-ghosts-interest-management
branch: feature/n6-ghosts-interest-management
status: planned
```

Read-only overlap replicas и interest budgets скрывают region boundary, не создавая duplicate canonical objects.

## 16. Утверждённый общий порядок

```text
S1 ACCEPTED
│
├─ H1  Playable listen-host
├─ H2  Dedicated server + 1 graphical client
├─ H3  Dedicated server + 2 graphical clients
├─ A2  Networked gameplay architecture checkpoint
│
├─ B1  NATS Core adapter
├─ B2  JetStream/outbox delivery
│
├─ P0  Population Field
├─ D1  Remote worker MVP
│
├─ N3  World Directory + 2 authorities
├─ N4  Generic object handoff
├─ N5  Seamless player handoff
└─ N6  Ghosts + interest management
```

## 17. Общий acceptance gate каждого этапа

Каждый кодовый checkpoint обязан иметь:

```text
contract/domain tests
negative schema and bypass tests
loopback scenario where applicable
real process scenario where applicable
restart/replay test for authoritative state
full network profile
full world regression
main scene CLI smoke
machine-readable report
changed-file overlay
independent local acceptance
```

Архитектурный A2 checkpoint обязан иметь полный audit H1–H3, ADR, machine-readable roadmap и отсутствие runtime-regression.

## 18. Что намеренно откладывается

До соответствующего gate не начинать:

- production NATS/JetStream integration до A2;
- World Directory до B1 и A2;
- cross-server handoff до N3;
- player handoff до generic N4;
- ghosts до functional player handoff;
- dynamic region split/merge;
- production Kubernetes/Agones;
- WAN optimization;
- arbitrary generated GDScript/WASM rule runtime;
- massive entity-per-grass canonical representation.

## 19. Связанные документы

- [`PLAYABLE_NETWORK_MILESTONES_RU.md`](PLAYABLE_NETWORK_MILESTONES_RU.md);
- [`../network/SEAMLESS_WORLD_ROADMAP_RU.md`](../network/SEAMLESS_WORLD_ROADMAP_RU.md);
- [`../network/NETWORK_READINESS_CHECKPOINT_RU.md`](../network/NETWORK_READINESS_CHECKPOINT_RU.md);
- [`../checkpoints/2026-07-29_POST_S1_PLAYABLE_NETWORK_ROADMAP_RU.md`](../checkpoints/2026-07-29_POST_S1_PLAYABLE_NETWORK_ROADMAP_RU.md).
