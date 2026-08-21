# V0 Edge Gateway Fabric — Network Specification

Статус: **CONTROL/NETWORK SPEC CANDIDATE / NO RUNTIME AUTHORITY**

Репозиторий: `rootfabric/distributed-world-simulator`

Canonical planning base: `main @ 1d9de3c479c60045d613660b2a5c5db0374963f8`

Связанные планы:

- `docs/plans/V0_P6_SEAMLESS_EXECUTION_ROADMAP_RU.md`
- `docs/plans/V0_P6_SEAMLESS_EXECUTION_ROADMAP_R2_GATEWAY_OVERLAY_RU.md`
- `config/control/harness/v0-p6-seamless-execution-roadmap.v1.json`

Этот документ уточняет сетевую архитектуру Gateway. При конфликте с ранней R2 формулировкой о прямых `ProjectionPublisher -> Client` соединениях этот документ имеет приоритет для V0 baseline: **в нормальном V0 gameplay клиент держит один client-facing transport только с Edge Gateway; projections агрегируются через Gateway**.

Документ не активирует P6 runtime mutation, не переносит ownership из NX/AUTHORITY, не делает Gateway каноническим владельцем состояния и не выбирает окончательный production transport.

---

## 1. Цель

Спрятать от клиента физическую топологию distributed world.

Для клиента существует один логический объект:

```text
WorldConnection
```

и в нормальной игре один активный transport:

```text
Client <-> Edge Gateway
```

Клиент не должен:

- выбирать simulation server;
- знать публичные адреса simulation servers;
- открывать новый gameplay transport при переходе между authority domains;
- выполнять cross-server handoff;
- координировать transfer;
- решать, какая server copy является canonical;
- подключаться напрямую к neighboring projection servers.

Gateway и server-side control plane должны скрыть:

- server discovery;
- auth/session attachment;
- player placement;
- server route changes;
- projection fan-in;
- ACTIVE/WARM/DRAIN routing;
- backend server failure/retry;
- normal authority handoff.

---

## 2. Целевая топология

```text
                         Global Edge / Locator
                                 |
               +-----------------+-----------------+
               |                                   |
        Edge Gateway POP 1                  Edge Gateway POP 2
        +-------------+                    +-------------+
Client->| Gateway G1  |                    | Gateway G2  |<-Client
        | Gateway G2  |                    | Gateway G3  |
        +------+------+                    +------+------+
               |                                   |
               +---------------+-------------------+
                               |
                  private/optimized WAN fabric
                               |
             +-----------------+-------------------+
             |                 |                   |
        Authority A       Authority B         Authority C
        ACTIVE/WARM       ACTIVE/WARM         ACTIVE/WARM
             |                 |                   |
             +-----------------+-------------------+
                               |
                   Directory / AUTHORITY truth
                               |
                   Session / Placement / IAM
```

Gateway POP — географическая/сетевая точка присутствия. В одном POP может работать несколько Gateway instances.

Simulation servers могут физически находиться далеко от Gateway и друг от друга.

---

## 3. Инварианты

### 3.1 Client-facing

В нормальной активной сессии:

```text
client_active_world_transports == 1
```

Для обычного authority pivot A -> B:

```text
public endpoint changes     = 0
gameplay reconnects         = 0
re-authentication           = 0
respawns                    = 0
PlayerId changes            = 0
PlayerEntityId changes      = 0
```

### 3.2 Gateway authority

Gateway:

```text
routes packets
terminates/owns transport session
aggregates projections
maintains ephemeral route/session cache
```

Gateway НЕ владеет:

```text
PlayerId truth
PlayerEntityId truth
Item Graph
Inventory / Equipment
Construction
Persistence
OperationId dedup truth
Authority ownership truth
AuthorityEpoch assignment
Directory linearization
Cross-authority transaction commit
```

Hard rule:

```text
GATEWAY ROUTES
DIRECTORY / AUTHORITY OWNS ROUTING TRUTH
DOMAIN OWNERS OWN CANONICAL MUTATION
```

### 3.3 Single writer

В любой момент:

```text
count(canonical ACTIVE writers for PlayerAuthorityDomain) == 1
```

WARM/PROJECTION/DRAIN не могут применять canonical writes.

---

## 4. Gateway discovery и выбор ближайшего Edge

"Ближайший" означает не географически ближайший, а лучший healthy network path.

### 4.1 Production direction

Клиент использует стабильное публичное имя:

```text
world.<product-domain>
```

Production deployment может использовать:

- Anycast;
- latency-aware DNS;
- managed global accelerator;
- собственный Edge Locator.

Vendor не является частью domain contract.

### 4.2 MVP / test direction

Для тестовой реализации используется `EdgeLocator`:

```text
EdgeLocatorResponse {
    locator_revision
    gateways[]
}
```

Каждый candidate содержит:

```text
gateway_pop_id
gateway_endpoint
health_revision
capacity_class
optional_region_hint
```

Клиент делает bounded RTT/loss probe и выбирает лучший healthy candidate.

MVP scoring:

```text
score =
    measured_rtt
  + loss_penalty
  + jitter_penalty
  + health_penalty
  + capacity_penalty
```

Не использовать только geo-distance.

### 4.3 Stability rule

Gateway не меняется при каждом переходе между simulation servers.

Разделять:

```text
SIMULATION HANDOFF:
    Gateway remains stable
    backend authority changes

EDGE REHOME:
    Gateway instance/POP changes
    rare event: gateway failure, network relocation, overload, maintenance
```

Обычный A -> B world handoff не является Edge rehome.

---

## 5. Connect / Auth / Placement flow

### 5.1 New or resumed session

```text
Client
  |
  | 1. discover/probe nearest Gateway
  v
Gateway
  |
  | 2. ClientHello + access credential
  v
IAM/Auth
  |
  | 3. verified identity
  v
Gateway
  |
  | 4. create/resume ClientSession + GatewaySession
  v
Session/Placement
  |
  | 5. resolve player/world placement
  v
Directory / AUTHORITY
  |
  | 6. current owner + AuthorityEpoch + ServerInstance
  v
Gateway
  |
  | 7. ensure backend tunnel to Authority A
  | 8. attach logical session
  v
Authority A
  |
  | 9. reconstruct/load player domain
  | 10. ready snapshot
  v
Gateway
  |
  | 11. WorldReady
  v
Client
```

Client does not receive Authority A public endpoint.

### 5.2 Identity separation

```text
TransportConnectionId != GatewaySessionId
GatewaySessionId       != ClientSessionId
ClientSessionId        != PlayerId
PlayerId               != PlayerEntityId
GatewayInstanceId      != GatewayPopId
GatewayInstanceId      != AuthorityId
ServerInstanceId       != AuthorityId
RouteRevision          != AuthorityEpoch
```

---

## 6. Client protocol surface

Client sees one stable transport and logical channels.

Recommended V0 channel model, aligned with NX separation:

```text
C0 SESSION_CONTROL        reliable
C1 INPUT_MOVEMENT         unreliable ordered
C2 AUTHORITATIVE_SNAPSHOT unreliable ordered
C3 WORLD_OPERATION        reliable ordered
C4 WORLD_PROJECTION       unreliable ordered
C5 RECOVERY_FULL_STATE    reliable ordered
C6 TELEMETRY              unreliable/best effort
```

Client API must be topology-neutral:

```text
WorldConnection.send_input(...)
WorldConnection.submit_operation(...)
WorldConnection.receive_authoritative_state(...)
WorldConnection.receive_projection(...)
WorldConnection.resume(...)
```

No client API:

```text
connect_to_server_b(...)
switch_authority(...)
commit_handoff(...)
```

---

## 7. Gateway <-> Simulation shared tunnel model

### 7.1 Core decision

Не создавать backend connection на каждого player.

Gateway instance поддерживает `GatewayServerLinkPool` для каждого ServerInstance:

```text
Gateway G1
  |
  +-- LinkPool -> Authority A
  |      tunnel 1: sessions 1,2,3,4,...
  |      tunnel 2: sessions ...
  |
  +-- LinkPool -> Authority B
         tunnel 1: sessions ...
```

MVP обязан доказать:

```text
2+ clients
1 Gateway
1 physical Gateway->Authority tunnel
multiple logical sessions multiplexed over that tunnel
```

### 7.2 Production pool

Production baseline:

```text
1..K physical tunnels per GatewayInstance <-> ServerInstance
```

Причины не делать ровно один tunnel навсегда:

- congestion coupling;
- failure blast radius;
- per-connection congestion control;
- maintenance;
- scaling;
- head-of-line risk for reliable traffic.

Количество tunnels — transport tuning, не gameplay contract.

### 7.3 Per-session fairness

Gateway MUST иметь:

- bounded per-session queue;
- bounded per-server queue;
- priority classes;
- fair scheduling;
- drop policy для stale unreliable frames;
- backpressure для reliable operations;
- metrics per session and per backend link.

Один медленный клиент не должен блокировать остальных.

---

## 8. Logical framing

Wire serialization может меняться. Семантические DTO должны быть versioned.

### 8.1 Client -> Gateway

```text
ClientWorldFrame {
    protocol_version
    client_session_id
    channel
    input_seq?
    operation_id?
    client_tick?
    payload_type
    payload
}
```

ClientWorldFrame не содержит server endpoint.

### 8.2 Gateway -> Simulation

```text
GatewayIngressEnvelope {
    protocol_version
    gateway_instance_id
    gateway_session_id
    session_binding_id
    session_slot
    player_id
    player_entity_id
    route_revision
    observed_authority_epoch
    channel
    input_seq?
    operation_id?
    payload_type
    payload
}
```

`session_slot` — ephemeral optimization внутри конкретного Gateway/backend relationship и не является identity.

Simulation server не должен считать поля identity из Envelope достаточными для mutation authorization. Они проверяются против SessionBinding + Directory/AUTHORITY evidence + domain rules.

### 8.3 Simulation -> Gateway

```text
GatewayEgressEnvelope {
    gateway_session_id
    session_slot
    source_role
    source_scope_id
    authority_epoch
    route_revision_seen
    channel
    stream_seq
    operation_id?
    payload_type
    payload
}
```

### 8.4 Gateway -> Client

Gateway скрывает backend server addresses/instances.

Для projection клиент может видеть только стабильный opaque `projection_stream_id` / presentation scope, необходимый для de-dup/revision ordering.

---

## 9. Auth и security boundary

### 9.1 Client edge

Gateway является public ingress security boundary:

- credential verification integration;
- rate limiting;
- protocol/version admission;
- session creation/resume;
- abuse/DDoS front-door policy;
- packet size and message budget enforcement.

### 9.2 Gateway backend

Simulation servers в production не должны требовать public client ingress.

Рекомендуемый production security direction:

```text
Gateway <-> Simulation:
    mutually authenticated encrypted tunnel
```

Конкретный transport выбирается NX.

### 9.3 Mutation security

Authenticated Gateway != canonical mutation authority.

Server-side mutation admission проверяет минимум:

```text
valid SessionBinding
player/domain binding
current Directory ownership
AuthorityEpoch/fence/incarnation
OperationId/idempotency
domain-specific authorization
```

---

## 10. Projection aggregation

V0 baseline: client получает projections через тот же Gateway transport.

### 10.1 Flow

```text
Client
  |
  v
Gateway
  |\
  | \---- ACTIVE Authority A
  |
  +------ Projection source B
  |
  +------ Macro/Celestial source C
```

Gateway получает `ProjectionManifest` / interest demand от Directory/Interest Resolver или active authority.

Conceptual demand:

```text
ProjectionSubscription {
    gateway_session_id
    projection_stream_id
    source_scope
    source_authority_or_publisher
    lod_class
    interest_revision
    projection_grant
}
```

Gateway:

1. использует существующий shared LinkPool к source;
2. при отсутствии открывает LinkPool;
3. подписывает session на projection stream;
4. принимает projection frames;
5. проверяет route/grant/revision envelope;
6. отправляет через C4 `WORLD_PROJECTION` в существующем Client<->Gateway transport.

### 10.2 Hard rules

```text
Projection is read-only.
Projection grant is not mutation authority.
Projection source cannot receive canonical client write through C4.
Projection source loss does not break Client<->Gateway gameplay session.
```

### 10.3 Future optimization

Прямой `ProjectionPublisher -> Client` transport не входит в V0 baseline.

Он может быть исследован позже как отдельная optimization после accepted seamless Gateway path и только с отдельным review, потому что нарушает простую гарантию `client_active_world_transports == 1`.

---

## 11. A -> B seamless handoff

### 11.1 Before boundary

```text
Client <-> Gateway = STABLE

Gateway -> A = ACTIVE gameplay route
Gateway -> B = PROJECTION or WARM route
```

B может уже отдавать neighboring-world projection через Gateway.

### 11.2 Prepare

```text
A remains ACTIVE
B reconstructs PlayerAuthorityDomain
B catches up required state
B canonical writes = 0
```

Gateway продолжает отправлять canonical commands только A.

### 11.3 Cutover barrier

Не допускать dual-write.

Transfer protocol обязан иметь explicit command/input watermark:

```text
handoff_barrier_input_seq
last_applied_operation_watermark
```

A freezes canonical player-domain processing after agreed barrier.

B получает state consistent with that barrier.

### 11.4 Ownership commit

Directory/AUTHORITY linearizes:

```text
A / epoch E
    ->
B / epoch E+1
```

Только после committed ownership evidence Gateway может pivot backend route.

### 11.5 Gateway pivot

```text
route_revision R -> R+1

A -> DRAIN/READ_ONLY
B -> ACTIVE
```

New inputs/operations after the barrier route only to B.

Late A frames are fenced by role/epoch/route revision.

### 11.6 In-flight operations

Если response lost во время pivot:

```text
retry SAME OperationId
```

Gateway не mint новый OperationId.

Canonical owner/dedup layer обязан вернуть один canonical result.

### 11.7 Client view

Client не получает команду "switch server".

Допустимо получить обычную reconciliation/presentation correction, но не:

- reconnect;
- login;
- respawn;
- identity recreation;
- server endpoint change.

---

## 12. Multi-Gateway behavior

### 12.1 Gateway registry

Control plane хранит:

```text
GatewayDescriptor {
    gateway_pop_id
    gateway_instance_id
    public_endpoint
    health_revision
    capacity_state
    draining
    backend_reachability_summary
}
```

Это routing/health metadata, не gameplay truth.

### 12.2 Multiple clients

Разные клиенты могут находиться на разных Gateways и играть в одном Authority:

```text
Client A -> Gateway East ----\
                              -> Authority A
Client B -> Gateway West ----/
```

Authority должен видеть две logical sessions, а не считать Gateway peer ID player identity.

### 12.3 Gateway-to-Gateway

Normal gameplay path НЕ требует full mesh Gateway<->Gateway.

Gateway instances координируются через control plane / Session / Directory.

Direct Gateway<->Gateway data-plane relay не входит в V0 unless separately proven necessary.

---

## 13. Gateway failure / Edge rehome

Gateway не должен становиться single point of canonical truth.

Gateway session state разделяется:

```text
ephemeral:
    transport connection
    queues
    session_slot
    backend tunnel assignment
    local route cache

recoverable:
    ClientSession binding
    PlayerId/PlayerEntityId
    current authority
    AuthorityEpoch
    durable OperationId truth
    canonical world state
```

При Gateway failure:

```text
Client
  -> reconnect/resume to same public edge service
  -> lands on healthy Gateway instance
  -> presents resume token
  -> new Gateway resolves Session + Directory
  -> reconstructs backend route
  -> resumes same logical world session
```

V0 hard requirement:

- normal A -> B handoff: physical client transport remains unchanged;
- Gateway failure: physical reconnect may occur, but logical session/identity/canonical state must resume without respawn/duplication.

Transport-level zero-reconnect Gateway failover is a later optimization.

---

## 14. Distant servers and WAN

Gateway<->Simulation is a first-class WAN path.

Test matrix must separate:

```text
Client -> Gateway impairment
Gateway -> Authority impairment
Authority A -> Authority B / Directory impairment
```

Minimum WAN profiles for lab:

```text
C->G: 5 / 30 / 80 ms RTT classes
G->S: 5 / 50 / 150 / 250 ms RTT classes
loss: 0 / 1 / 5 %
jitter
duplicate
reorder
asymmetric delay
temporary disconnect
bandwidth limit
```

Do not evaluate only end-to-end latency; record each leg independently.

Gateway selection optimizes client-edge path. Backend path quality is separately observed. Optional pre-world edge rehome may be considered later if a different Gateway offers materially better total path, but world handoff must not cause routine Gateway changes.

---

## 15. Transport direction

### 15.1 Contract

Domain/gameplay contracts MUST remain transport-neutral.

Existing project rule remains:

```text
transport delivers operations
transport does not define gameplay semantics
```

### 15.2 V0 test reference

Для самого дешёвого prototype использовать существующий stack:

```text
Client <-> Gateway: Godot ENet / project DTO
Gateway <-> Simulation: Godot ENet / project GatewayEnvelope DTO
Gateway: headless Godot process or thin adapter compatible with existing harness
Python/pytest: multi-process orchestration
tc/netem: WAN/fault injection
Docker Compose: optional process topology
```

Не использовать SceneTree replication как Gateway protocol.

### 15.3 Production candidate

QUIC является сильным production candidate, но не принимается этим spec как обязательный transport.

Причины для дальнейшего NX spike:

- secure multiplexed streams;
- low-latency setup;
- path migration;
- unreliable QUIC DATAGRAM support;
- один security/congestion context для reliable и unreliable traffic.

Окончательный выбор ENet/QUIC/other остаётся NX-owned.

---

## 16. Observability

Gateway metrics required from first MVP:

```text
gateway_instance_id
gateway_pop_id
active_client_connections
active_gateway_sessions
backend_server_links
sessions_per_backend_link
bytes/packets client->gateway
bytes/packets gateway->client
bytes/packets gateway->server
bytes/packets server->gateway
per-channel queue depth
per-session queue depth
dropped_stale_datagrams
reliable_backpressure_events
route_revision
observed_authority_epoch
projection_stream_count
handoff_count
handoff_failures
gateway_rehome_count
```

Every log event involving a forwarded operation should carry correlation:

```text
gateway_session_id
player_entity_id
operation_id?
input_seq?
route_revision
authority_epoch?
```

---

## 17. V0 acceptance invariants for Gateway lab

Required:

```text
[PASS] one client-facing world transport during normal gameplay
[PASS] two clients share one Gateway->Authority physical tunnel in MVP
[PASS] multiple projection sources arrive through same client transport
[PASS] client never receives simulation server endpoint for normal routing
[PASS] Gateway canonical writes = 0
[PASS] Gateway ownership decisions = 0
[PASS] exactly one canonical authority writer
[PASS] stable PlayerId/PlayerEntityId
[PASS] OperationId continuity end-to-end
[PASS] stale route/epoch traffic fenced
[PASS] bounded queues
[PASS] no slow-client cross-session starvation
[PASS] A->B pivot with zero client gameplay reconnects
[PASS] Gateway failure resumes same logical session
```

Performance numbers are measured first and promoted to hard SLOs only after baseline evidence.

---

## 18. P6 / Seamless integration

P6 remains single-authority product checkpoint.

P6 MUST prepare:

```text
P6.2 identity not bound to transport peer/server endpoint
P6.3 OperationId survives Gateway forwarding
P6.4 Gateway/session identity cannot authorize mutation
P6.6 topology-neutral ClientGameplayPort + GatewayIngress-compatible boundary
P6.9 WARM target can exist read-only
P6.10 stale route/duplicate forwarding/fault cases
```

Parallel Seamless Research MUST prove the Gateway fabric:

```text
SR3 / I5A:
    single Gateway pass-through
    auth/session/placement attachment
    multi-client shared backend tunnel
    projection aggregation through one client connection
    multi-Gateway nearest-edge selection

SR4 / I5B:
    ACTIVE/WARM/DRAIN pivot A -> B
    one client connection remains stable
    barrier/watermark + OperationId continuity
```

Post-P6 SM1 consumes reviewed donor contracts; research branch does not become product ancestry automatically.

---

## 19. Non-goals for first test

Not required for first V0 lab:

- production BGP/Anycast deployment;
- global TLS certificate automation;
- final QUIC implementation;
- DDoS provider integration;
- dynamic world split/merge;
- hundreds of Gateway POPs;
- zero-packet-loss Gateway process failover;
- direct client projection sockets;
- final autoscaling policy.

The lab must prove semantics and connection topology first.

---

## 20. Final rule

```text
PLAYER CONNECTS TO THE WORLD, NOT TO A SIMULATION SERVER.

ONE CLIENT-FACING CONNECTION IN NORMAL PLAY.

GATEWAY HIDES SERVER TOPOLOGY AND AGGREGATES PROJECTIONS.

GATEWAY->SERVER LINKS ARE SHARED AND MULTIPLEX MANY PLAYERS.

DIRECTORY/AUTHORITY REMAINS OWNERSHIP TRUTH.

NORMAL WORLD HANDOFF CHANGES BACKEND ROUTE, NOT CLIENT CONNECTION.
```
