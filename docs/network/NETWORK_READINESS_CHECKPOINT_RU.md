> **Current readiness decision:** H1–H3 и A2 приняты. Следующий gate — M1, не B1. Production multi-authority work заблокирован до M1–M6 и A3; B1/B2 выполняются после A3.

# Checkpoint готовности PlanetSimulator к distributed runtime

**Дата ревизии:** 30 июля 2026 года
**Принятый runtime checkpoint:** `v16.9.3-runtime-h3-dedicated-multiplayer`
**Принятый architecture checkpoint:** `v16.9.4-architecture-a2-networked-gameplay`
**Текущий roadmap candidate:** `v16.9.5-roadmap-single-server-multiplayer-first`
**Следующий gate:** `M1 — Unified Networked Gameplay Core`

## 1. Что уже доказано кодом

### Network and recovery foundation

- strict versioned DTO и canonical checksums;
- authority owner/epoch, revision и tick fences;
- snapshot/delta и command result contracts;
- ENet server/client vertical slice;
- logical session отдельно от transport session;
- reconnect/replay без второй mutation;
- multi-process orchestration, isolated user state и process reports;
- authoritative persistence и crash recovery до/после commit.

### Runtime and aggregate foundation

- embedded listen-host с отдельными client runtime/replica store;
- generic item/non-item aggregate contracts;
- stable hierarchical cells и explicit shards;
- spatial identity отделена от authority ownership;
- multi-peer listener с targeted delivery и per-peer backpressure;
- request/reply, events, jobs, replication и bulk transfer как разные B0 ports;
- atomic multi-aggregate create/update/delete;
- stable replay result и transactional outbox;
- immutable compute jobs и exact projected read state;
- capability-scoped worker;
- authority-issued job checksum binding;
- proposal validation и M0 authoritative commit.

## 2. Уровни фактической готовности

### Готово как foundation

- offline/tools runtime;
- listen-host composition;
- headless dedicated server process;
- localhost ENet client/server;
- минимум два transport peers;
- generic aggregate replication;
- persistence/recovery;
- local semantic bus adapters;
- local transaction/outbox path;
- local distributed-compute path.

### Требует игровой вертикали H1–H3

- default F5 playable listen-host;
- graphical client, читающий только replica store;
- authoritative player movement;
- Player Aggregate и player identity;
- сетевой inventory/container UI;
- pickup/drop/stack/split/mount через commands;
- отдельный dedicated server для graphical single-player;
- два одновременных graphical players;
- deterministic multiplayer contention;
- remote player presentation и базовая relevance.

### Требует B1–N6

- NATS Core discovery/request-reply;
- JetStream durable delivery;
- remote compute worker;
- executable World Directory;
- authority leases двух servers;
- generic cross-server handoff;
- seamless player handoff;
- ghosts и interest management;
- dynamic region split/merge.

## 3. Главный текущий архитектурный риск

Foundation уже достаточно широк. Главный риск — продолжать добавлять infrastructure, не доказав, что реальный graphical gameplay работает через client/server boundary.

Поэтому H1–H3 предшествуют B1:

```text
H1 playable listen-host
→ H2 dedicated + 1 graphical client
→ H3 dedicated + 2 graphical clients
→ A2 architecture checkpoint
→ B1 NATS Core adapter
```

## 4. Текущий и последующие gates

```text
S1 — Distributed Compute Contracts — accepted
H1 — Playable listen-host — next
H2 — Dedicated server + 1 graphical client — planned
H3 — Dedicated server + 2 graphical clients — planned
A2 — Networked gameplay architecture checkpoint — planned
B1 — NATS Core adapter — planned after A2
B2 — JetStream/outbox delivery — planned
P0/D1 — Population Field and remote worker — planned
N3–N6 — multi-server and seamless world — planned
```

## 5. Что нельзя обходить в H1–H3

- graphical client не получает live aggregate/repository references;
- listen-host не создаёт отдельный domain path;
- movement и interactions не подтверждаются локально как canonical state;
- reconnect не создаёт вторую player entity;
- два peers не делят global outbound queue;
- contested item/container operation commit’ится максимум один раз;
- offline path не остаётся неявным production fallback;
- UI не хранит собственную authoritative копию inventory.

## 6. Решение о World Directory

N3 остаётся обязательным, но начинается после:

```text
H1 → H2 → H3 → A2 → B1
```

К этому моменту Directory будет маршрутизировать доказанные player/aggregate/shard routes, а не абстрактную инфраструктуру без полноценного graphical client.

## 7. Связанные документы

- [`../plans/PLAYABLE_NETWORK_MILESTONES_RU.md`](../plans/PLAYABLE_NETWORK_MILESTONES_RU.md);
- [`../checkpoints/2026-07-29_POST_S1_PLAYABLE_NETWORK_ROADMAP_RU.md`](../checkpoints/2026-07-29_POST_S1_PLAYABLE_NETWORK_ROADMAP_RU.md);
- [`SEAMLESS_WORLD_ROADMAP_RU.md`](SEAMLESS_WORLD_ROADMAP_RU.md);
- [`../plans/DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md`](../plans/DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md);
- [`../checkpoints/2026-07-29_V16_9_0_SIMULATION_S1_DISTRIBUTED_COMPUTE_FIX1_RU.md`](../checkpoints/2026-07-29_V16_9_0_SIMULATION_S1_DISTRIBUTED_COMPUTE_FIX1_RU.md).
