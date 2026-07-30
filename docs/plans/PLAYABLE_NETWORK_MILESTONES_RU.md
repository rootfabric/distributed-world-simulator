> **Post-A2 correction (2026-07-30):** этот документ сохраняет исторический контекст H1–A2. Текущий официальный порядок заменён на `A2 → M1 → M2 → M3 → M4 → M5 → M6 → A3 → B1 → B2 → N3–N6`. См. [`SINGLE_SERVER_MULTIPLAYER_ROADMAP_RU.md`](SINGLE_SERVER_MULTIPLAYER_ROADMAP_RU.md).

# PlanetSimulator — игровые сетевые вехи после S1

**Статус решения:** утверждено 29 июля 2026 года
**Текущая принятая runtime-база:** `v16.9.3-runtime-h3-dedicated-multiplayer`
**Принятая architecture-база:** `v16.9.4-architecture-a2-networked-gameplay`
**Текущий roadmap candidate:** `v16.9.5-roadmap-single-server-multiplayer-first`
**Главный следующий gate:** `M1 — Unified Networked Gameplay Core`

## 1. Утверждённая последовательность

```text
S1 ACCEPTED
│
├─ H1  Playable listen-host — accepted
├─ H2  Host/client ownership — accepted
├─ H3  Dedicated multiplayer — accepted
├─ A2  Networked gameplay architecture — accepted
│
├─ M1 → M2 → M3 → M4 → M5 → M6
├─ A3  Single-server multiplayer freeze
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

H1–H3 имеют приоритет над дальнейшим наращиванием инфраструктуры. Они должны доказать, что принятые H0, T1, B0, M0 и S1 работают не только в контрактных fixtures, но и в реальном игровом пути.

## 2. Неподвижные правила H1–H3

Во всех трёх топологиях используется один gameplay-код:

```text
input/UI
→ ClientCommandGateway
→ versioned command DTO
→ authority command handler
→ authoritative mutation
→ snapshot/delta/result
→ ClientReplicaStore
→ presentation/UI
```

Запрещено:

- читать live authoritative aggregate из клиента или UI;
- передавать `Node`, `SceneTree`, repository port или registry port через сетевую границу;
- создавать отдельный «упрощённый» gameplay path только для listen-host;
- считать локальный объект игрока каноническим состоянием;
- обходить authority при pickup, drop, transfer, split, mount или movement;
- менять identity объекта при смене runtime topology;
- подтверждать действие игроку до authoritative result, если оно меняет канонический мир.

Обязательные свойства:

- один writer на aggregate;
- stable player/item/container identity;
- authority owner/epoch fencing;
- monotonic revision и tick;
- deterministic conflict rejection;
- replay-safe commands;
- reconnect без повторной mutation;
- одинаковые command/result semantics для loopback и ENet.

## 3. H1 — Playable listen-host

### Статус

`ACCEPTED`.

### Цель

Обычный запуск игры создаёт embedded authority и отдельный graphical client в одном процессе. Игрок не замечает сетевую границу, но весь канонический gameplay уже проходит через неё.

### Предлагаемый checkpoint

```text
checkpoint: v16.9.1-runtime-h1-playable-listen-host
branch: feature/h1-playable-listen-host
```

### Обязательный scope

- переключить основной игровой bootstrap с legacy offline path на listen-host composition;
- подключить graphical player к `ClientRuntime` и `ClientReplicaStore`;
- создать сетевой Player Aggregate или эквивалентный strict authoritative player state;
- перевести movement input в authority commands;
- реплицировать authoritative transform/velocity обратно в presentation;
- перевести inventory, hotbar и external container UI на replica data;
- провести через command boundary:
  - pickup;
  - drop;
  - transfer;
  - stacking;
  - right-drag split;
  - mount/placement interaction;
  - открытие и закрытие внешнего контейнера;
- сохранить существующую persistent world recovery;
- оставить `offline` только для явно выбранных tools, fixtures и диагностики.

### Acceptance

```text
F5 → playable listen-host
player moves through authority
inventory and container interactions work
world item appears/disappears only after authoritative result
save → restart → state restored
replay does not duplicate transfer or pickup
UI reads replicas, not live aggregates
loopback final state matches equivalent ENet scenario
```

### Обязательные негативные сценарии

- stale player revision;
- duplicate movement/input sequence;
- повторный pickup уже взятого предмета;
- transfer в недоступный контейнер;
- split с некорректным количеством;
- disconnect embedded client во время незавершённой операции;
- попытка UI получить authoritative object reference.

### Не входит

- второй graphical client;
- NATS;
- cross-server routing;
- prediction сложной физики;
- бесшовный handoff.

## 4. H2 — Dedicated server + 1 graphical client

### Цель

Тот же graphical client подключается к отдельному headless `simulation-server`. Gameplay-код и UI не знают, embedded authority используется или отдельный процесс.

### Предлагаемый checkpoint

```text
checkpoint: v16.9.2-runtime-h2-dedicated-single-player
branch: feature/h2-dedicated-single-player
```

### Обязательный scope

- экран или CLI-параметры подключения к серверу;
- graphical client process без embedded authority;
- authoritative spawn и despawn игрока;
- initial world/player/inventory snapshot;
- сетевое движение и interaction commands;
- reconnect с восстановлением logical session;
- сохранение позиции, inventory и открытого мира;
- корректная обработка server shutdown/draining;
- одинаковый client composition для H1 и H2.

### Acceptance

```text
process A: headless simulation-server
process B: graphical client

connect
→ receive initial state
→ move
→ open container
→ transfer/drop/pickup
→ disconnect
→ reconnect
→ receive committed state without duplicate mutation
→ restart server
→ recover committed world and player state
```

### Обязательные негативные сценарии

- неверный protocol/build handshake;
- server unavailable;
- connection loss во время command result;
- stale transport session после reconnect;
- duplicate command после потерянного ответа;
- server crash до commit и после commit;
- graphical client пытается создать authority locally.

### Не входит

- одновременные graphical players;
- межсерверный transport;
- World Directory.

## 5. H3 — Dedicated server + 2 graphical clients

### Цель

Один headless server обслуживает минимум двух полноценных graphical clients, которые видят друг друга и конкурируют за одни authoritative ресурсы.

### Предлагаемый checkpoint

```text
checkpoint: v16.9.3-runtime-h3-dedicated-multiplayer
branch: feature/h3-dedicated-multiplayer
```

### Обязательный scope

- stable Player Identity и отдельный aggregate каждого игрока;
- два одновременных graphical clients;
- authoritative spawn/despawn;
- репликация player transform другим клиентам;
- базовая interpolation для remote presentation;
- отдельные inventory/permissions каждого игрока;
- authoritative contention за item/container/mount;
- targeted command results и per-peer deltas;
- disconnect одного игрока без остановки listener;
- reconnect одного игрока без нарушения второго;
- минимальный relevance scope для одной server region.

### Acceptance

```text
server + client A + client B

A and B spawn
A moves → B observes movement
B moves → A observes movement
A and B request the same item
→ exactly one authoritative success
→ one deterministic rejection
winner inventory contains one item
world contains no duplicate
A disconnects
B continues playing
A reconnects and restores state
```

### Обязательные негативные сценарии

- один медленный peer не блокирует второго;
- disconnect во время contested operation;
- duplicate pickup от разных transport sessions одной logical identity;
- spoofed player ID;
- команда игрока A к inventory игрока B;
- stale player authority epoch;
- outbound queue overflow одного peer;
- reconnect создаёт новую transport session без второй player entity.

### Не входит

- несколько authority servers;
- migration между регионами;
- production authentication;
- глобальный interest management.

## 6. A2 — Networked gameplay architecture checkpoint

A2 выполняется сразу после принятия H3 и до B1.

### Цель

Зафиксировать реально доказанную игровую client/server архитектуру, прежде чем добавлять NATS, JetStream и несколько authorities.

### Предлагаемый checkpoint

```text
checkpoint: v16.9.4-architecture-a2-networked-gameplay
branch: feature/a2-networked-gameplay-architecture
scope: documentation, ADR, contract audit, test matrix
```

### A2 должен зафиксировать

- единую композицию graphical client для H1/H2/H3;
- Player Aggregate и player-session identity model;
- command ownership и permission boundary;
- movement replication model;
- inventory/container contention semantics;
- authoritative prediction/correction policy;
- reconnect and replay model;
- peer-to-player mapping;
- relevance assumptions одной server region;
- обязательные границы перед N3–N6;
- список технического долга, который нельзя переносить в multi-server layer.

### Acceptance

- H1, H2 и H3 приняты;
- один gameplay service path используется во всех топологиях;
- нет прямого client/UI доступа к authoritative aggregates;
- нет topology-specific domain forks;
- две graphical sessions проходят полный multiplayer process scenario;
- network/world regressions зелёные;
- ADR и machine-readable roadmap согласованы;
- следующий checkpoint B1 однозначен.

A2 не добавляет новые игровые функции. Это audit/freeze checkpoint перед инфраструктурной линией.

### Реализованный результат A2

A2 замораживает target architecture и вводит machine-readable manifest `config/network/networked-gameplay-architecture.v1.json`.

Решение: `FROZEN_WITH_GATES`:

- B1 разрешён только как B0/NATS adapter stage;
- N3–N6 заблокированы до A2-D01…D04;
- H1 является доказательством full graphical Item Graph path;
- H2/H3 являются доказательствами dedicated ownership, peer isolation, movement, contention и reconnect;
- два graphical windows, единый production service и dedicated restart recovery остаются обязательным долгом до N3.

## 7. Этапы после A2

### B1 — NATS Core adapter

Подключает реальные discovery, heartbeat, health/load и request/reply только через принятые B0 semantic ports.

### B2 — JetStream/outbox delivery

Добавляет durable jobs/events, ACK/retry, outbox publisher, inbox/dedup и crash recovery доставки.

### P0 — Population Field

Вводит компактный aggregate массовой популяции вместо тысяч canonical entity nodes.

### D1 — Remote worker MVP

Доказывает удалённую compute-цепочку `job → worker proposal → authority validation → M0 commit` через B2.

### N3 — World Directory + 2 authorities

Два authority servers регистрируются, получают разные shard leases и публикуют transport-neutral routes.

### N4 — Generic object handoff

Первый cross-server transfer выполняется для item, container, vehicle или другого generic aggregate без изменения identity.

### N5 — Seamless player handoff

Клиент заранее открывает warm route к следующему authority; input, UI и player state продолжаются без reconnect screen.

### N6 — Ghosts + interest management

Read-only overlap replicas скрывают границу регионов и ограничивают replication bandwidth по interest scope.

## 8. Правило начала следующего этапа

Нельзя начинать следующий основной этап, пока текущий не имеет:

```text
focused tests
negative and replay tests
real process scenario
full relevant network regression
full world regression
main-scene smoke
updated checkpoint documentation
machine-readable report
changed-file overlay
independent local acceptance
```

Допустимы исследования будущих этапов, но они не должны создавать параллельный production path.
