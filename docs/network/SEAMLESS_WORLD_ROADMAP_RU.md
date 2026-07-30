> **Post-A2 priority:** сначала полный single-server graphical multiplayer (`M1–M6 → A3`), затем `B1/B2`, и только после этого `N3–N6`. Этот документ описывает долгосрочный seamless-world track, но не ближайший implementation order.

# Дорожная карта бесшовного распределённого мира PlanetSimulator

## Текущий статус

```text
runtime accepted: v16.9.3-runtime-h3-dedicated-multiplayer
architecture accepted: v16.9.4-architecture-a2-networked-gameplay
roadmap candidate: v16.9.5-roadmap-single-server-multiplayer-first
status: FULL SINGLE-SERVER MULTIPLAYER FIRST
next gate: M1 unified gameplay core
```

N0–S1, H1–H3 и A2 приняты. M1–M6 должны превратить доказанные fixtures в единый production single-server graphical multiplayer; A3 фиксирует результат перед B1/B2 и server mesh.

## Целевая архитектура

```text
Graphical clients
  ↓ commands / snapshots / deltas
ClientRuntime + ClientReplicaStore
  ↓ route
Region Authority — single writer
  ↕ repository + transactional outbox
  ↕ jobs / mutation proposals
Simulation Workers
  ↕ B0 semantic ports
NATS Core / JetStream adapters
  ↕
World Directory and other authorities
```

Топология может быть одним процессом, отдельными localhost processes или cluster deployment. Domain/gameplay contracts не должны меняться при смене topology.

## Утверждённые этапы

### Принятый foundation

```text
N0  network contracts                         accepted
N1  one authority + client vertical slice    accepted
N2  multi-process harness                    accepted
R3.1 persistence/recovery                    accepted
A0  distributed runtime architecture         accepted
H0  listen-host foundation                   accepted
A1  generic aggregates                       accepted
S0  cells/scopes/shards                      accepted
T1  multi-peer transport                     accepted
B0  semantic message-bus ports               accepted
M0  aggregate transactions/outbox            accepted
S1  compute jobs/proposals                    accepted
```

### H1 — Playable listen-host

Основной graphical gameplay запускается как embedded authority + separate client runtime. Movement, inventory, containers и world interactions идут через command/result/delta.

### H2 — Dedicated server + 1 graphical client

Тот же client подключается к отдельному headless server, переживает reconnect и получает восстановленное committed state.

### H3 — Dedicated server + 2 graphical clients

Два полноценных клиента видят друг друга, имеют разные player identities и безопасно конкурируют за один authoritative объект.

### A2 — Networked gameplay architecture checkpoint

После H3 фиксируются доказанные Player Aggregate, session, movement, permission, contention, reconnect и relevance contracts. Это обязательный gate перед broker/server-mesh track.

### B1/B2 — NATS Core и JetStream

Сначала discovery/request-reply/health, затем durable jobs/events, outbox publisher и inbox/dedup.

### P0/D1 — Population Field и remote worker MVP

Первый сложный distributed simulation experiment поверх S1 и B2.

### N3 — World Directory + 2 authorities

Два server authority регистрируются и получают разные shard leases. Directory выдаёт transport-neutral routes.

### N4 — Generic object handoff

Aggregate передаётся A → B без изменения identity и без двух одновременных writers.

### N5 — Seamless player handoff

Клиент заранее открывает warm route к B. Input sequence, UI и player state продолжаются без загрузочного экрана.

### N6 — Ghosts и interest management

Read-only overlap replicas обеспечивают визуальную непрерывность и ограничивают bandwidth.

## Практические вехи

```text
H1: игру можно запустить как host
H2: игру можно запустить на отдельном server для одного игрока
H3: на одном dedicated server играют минимум два graphical clients
N3: мир обслуживают минимум два authority servers
N4: объект безопасно переходит между servers
N5: игрок переходит между servers без reconnect screen
N6: граница regions визуально скрыта ghosts/interest streaming
```

## Главный acceptance каждого шага

```text
one observable user result
+ strict contracts
+ negative/bypass tests
+ real process scenario
+ restart/replay where applicable
+ full network/world regression
+ no alternate gameplay path
```

## Неподвижные правила

- single writer per aggregate;
- stable identity independent of process;
- authority epoch fencing;
- client replica independent of server object graph;
- presentation never becomes canonical state;
- worker proposals instead of direct mutation;
- adapter-independent domain/gameplay;
- explicit shard/route ownership;
- handoff never creates two active writers;
- topology changes do not fork gameplay semantics.

Полный ближайший план: [`../plans/PLAYABLE_NETWORK_MILESTONES_RU.md`](../plans/PLAYABLE_NETWORK_MILESTONES_RU.md).
