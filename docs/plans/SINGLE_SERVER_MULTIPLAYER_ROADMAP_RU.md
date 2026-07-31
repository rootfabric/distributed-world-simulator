# PlanetSimulator — FULL SINGLE-SERVER MULTIPLAYER FIRST

**Статус:** официальный принятый post-A2 roadmap
**Checkpoint:** `v16.9.5-roadmap-single-server-multiplayer-first`
**База:** принятый `v16.9.4-architecture-a2-networked-gameplay` (`FROZEN_WITH_GATES`)
**Принятая реализация:** `M1 — Unified Networked Gameplay Core`
**Текущая реализация:** `M2 — Dedicated + 1 graphical client`

## 1. Стратегическое решение

Ближайшая основная цель PlanetSimulator:

> Один headless dedicated server и минимум два обычных графических клиента Godot, использующих единый production gameplay path.

Главный порядок:

```text
M1 → M2 → M3 → M4 → M5 → M6 → A3 → B1 → B2 → N3 → N4 → N5 → N6
```

```text
A2 ACCEPTED / FROZEN_WITH_GATES
│
├─ M1  Unified Networked Gameplay Core
├─ M2  Dedicated + 1 graphical client
├─ M3  Dedicated + 2 graphical clients
├─ M4  Canonical shared gameplay over ENet
├─ M5  Graphical multiplayer acceptance
├─ M6  Dedicated persistence and recovery
│
├─ A3  Single-server multiplayer audit/freeze
│
├─ B1  NATS Core adapter
├─ B2  JetStream/outbox delivery
│
└─ N3 → N4 → N5 → N6
```

`M1–M6` — новый single-server multiplayer track. Исторический `M0` остаётся принятым checkpoint multi-aggregate transactions и не переименовывается.

## 2. Почему B1 перенесён

A2 разрешает B1 архитектурно, но NATS не закрывает A2-D01…D04 и не создаёт двух обычных игровых клиентов. ENet уже является realtime transport между graphical client и одним dedicated server.

Поэтому:

```text
graphical single-server multiplayer
→ dedicated stability and recovery
→ A3 freeze
→ server-to-server B1/B2
→ multi-authority N3–N6
```

NATS используется только для service/server communication. NATS не используется для обычного graphical realtime traffic, не заменяет ENet и не создаёт новый gameplay path.

## 3. M1 — Unified Networked Gameplay Core

Checkpoint: `v16.10.0-runtime-m1-unified-networked-gameplay-core`
Branch: `feature/m1-unified-networked-gameplay-core`

Статус: **accepted**. Закрывает `A2-D01` и `A2-D02`.

Реализация и доказательства: `docs/architecture/M1_UNIFIED_NETWORKED_GAMEPLAY_CORE_RU.md` и `config/network/networked-gameplay-core.v1.json`.

```text
NetworkedGameplayService
├── PlayerRegistry
├── PlayerOwnershipService
├── PlayerMovementService
├── ItemGraphService
├── ContainerInteractionService
├── MountInteractionService
├── CommandResultRouter
└── ReplicationPublisher
```

Один сервис используется в listen-host, dedicated server и automated multiplayer tests. Меняются только transport adapters: loopback или ENet.

Общие DTO/validators:

```text
PlayerJoinCommand
PlayerLeaveCommand
PlayerInputCommand
PlayerOwnershipSnapshot
PlayerStateSnapshot
PlayerStateDelta
ItemCommand
ItemGraphSnapshot
ItemGraphDelta
CommandResult
```

Acceptance:

- H1 loopback и dedicated ENet используют один gameplay service;
- одинаковая команда приводит к одинаковому canonical state;
- validators versioned, JSON-safe, exact-field и checksum-bound;
- authority/ownership epoch и revision fencing общие;
- старые H1–H3 tests переведены на общий service;
- client/UI не получают authoritative references.

## 4. M2 — Dedicated + 1 graphical client

Checkpoint: `v16.10.1-runtime-m2-dedicated-graphical-client`
Branch: `feature/m2-dedicated-graphical-client`

Статус: **accepted with gates**. Реализованы `game-client`, connection parameters, join/ownership handshake, initial sync, реальный `LunarPlayer`, authoritative movement/correction, replica inventory/hotbar и reconnect без второй entity. Автоматический process-test использует настоящий graphical display/renderer.

Acceptance:

```text
graphical client starts
→ connects to headless server
→ receives stable player identity
→ moves through authority
→ opens replicated inventory
→ disconnects and reconnects
→ receives the same player entity and committed state
```

## 5. M3 — Dedicated + 2 graphical clients

Checkpoint: `v16.10.2-runtime-m3-dedicated-graphical-multiplayer`
Branch: `feature/m3-dedicated-graphical-multiplayer`

Статус: **ACCEPTED**. Реализованы local/remote distinction, `RemotePlayerPresenter`, spawn/despawn, transform/velocity/orientation, flashlight state, interpolation и отсутствие input authority у remote presentation.

Acceptance: A и B видят движение друг друга; отключение A не останавливает B; reconnect A восстанавливает ту же identity.

## 6. M4 — Canonical shared gameplay over ENet

Checkpoint: `v16.10.3-domain-m4-canonical-shared-gameplay`
Branch: `feature/m4-canonical-shared-gameplay`

Статус: **ACCEPTED**, delivery `fix1`. Dedicated multiplayer использует полный канонический H1 Item Graph:

- inventory и hotbar;
- pickup/drop;
- stack/split;
- external containers;
- mount/detach;
- world item state;
- targeted results и permission errors.

Главный contention gate: ровно один success, один deterministic rejection, одна stable item identity и отсутствие world/inventory duplication.

## 7. M5 — Graphical Multiplayer Acceptance

Checkpoint: `v16.10.4-testing-m5-graphical-multiplayer-acceptance`
Branch: `feature/m5-graphical-multiplayer-acceptance`

Автоматический process-test запускает dedicated server и два graphical clients с отдельными user-data каталогами. Требуется renderer или virtual display; headless-only proof недостаточен.

Статус: **ACCEPTED**, delivery `fix1`. Полный сценарий включает join, взаимное движение, contention, disconnect/reconnect, canonical checksum convergence и корректное завершение процессов.

## 8. M6 — Dedicated persistence and recovery

Checkpoint: `v16.10.5-persistence-m6-dedicated-recovery`
Branch: `feature/m6-dedicated-recovery`

Статус: **candidate**. Закрывает `A2-D04` после независимой приёмки: crash/restart восстанавливает player identities/state, Item Graph, inventories/containers, operation ledgers, revisions, authority epoch и committed outbox state без дубликатов. ACK выдаётся только после atomic checkpoint; exact replay после restart не создаёт второй mutation.

## 9. A3 — Single-server multiplayer audit/freeze

Checkpoint: `v16.10.6-architecture-a3-single-server-multiplayer`
Branch: `feature/a3-single-server-multiplayer-architecture`

A3 принимается только после M1–M6 и фиксирует единственный production service, shared wire contracts, graphical client composition, local/remote presentation, canonical Item Graph over ENet, contention, reconnect/replay, dedicated recovery и two-graphical-client process proof.

## 10. После A3

```text
B1 v16.11.0 — NATS Core adapter
B2 v16.11.1 — JetStream/outbox
N3 v16.12.0 — World Directory + 2 authorities
N4 v16.12.1 — Generic object handoff
N5 v16.12.2 — Seamless player handoff
N6 v16.12.3 — Ghosts + interest management
```

До A3 запрещена production-реализация World Directory, handoff, ghosts, dynamic shard balancing и нескольких authoritative region servers. Исследования допускаются без production integration.

## 11. Критерий перехода к multi-server

> Односерверная версия воспроизводимо поддерживает два графических клиента, authoritative movement, общий канонический Item Graph, contention, disconnect/reconnect и crash recovery без topology-specific gameplay forks.
