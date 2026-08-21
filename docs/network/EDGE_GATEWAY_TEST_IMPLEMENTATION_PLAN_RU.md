# V0 Edge Gateway Fabric — Test Implementation Plan

Статус: **CURRENT PRE-P6 RESEARCH/TEST IMPLEMENTATION CANDIDATE / DONOR-ONLY / NO PRODUCTION AUTHORITY**

Связанные документы:

- `docs/plans/V0_PRE_P6_EDGE_GATEWAY_FOUNDATION_ROADMAP_RU.md`
- `docs/network/EDGE_GATEWAY_FABRIC_SPEC_RU.md`
- `config/control/harness/v0-edge-gateway-fabric-test-plan.v1.json`
- `config/control/harness/v0-p6-seamless-execution-roadmap.v1.json`

## 1. Execution decision

Текущий порядок больше не является `P6 + EG0-EG5 parallel`.

Новый обязательный порядок:

```text
EG0 -> EG1 -> EG2 -> EG3 -> EG4 -> EG5
        |
        v
EDGE_GATEWAY_FOUNDATION_ACCEPTED
        |
        v
P6 runtime activation
        |
        +---- P6.1 -> P6.11
        |
        +---- EG6 -> EG7 -> EG8 -> EG9 in parallel
```

P6 runtime mutation запрещена до отдельного accepted Gateway Foundation checkpoint.

Причина: EG0-EG5 проверяют transport/session границу, на которой потом строится весь P6 gameplay. Эти риски дешевле закрыть до роста P6.

---

## 2. Reference process topology

Минимальный integrated lab:

```text
edge-locator
auth-session
world-directory

gateway-g1
gateway-g2
gateway-g3

sim-a
sim-b
macro-projection (optional in early stages)

client-graphical-1
client-graphical-2
client-bots (configurable)

test-orchestrator
```

Все процессы должны запускаться локально.

Geo/WAN моделируется `tc/netem`, причём отдельно для:

```text
Client <-> Gateway
Gateway <-> Server A
Gateway <-> Server B / projection source
Server/Directory control path
```

---

## 3. Reference implementation for the prototype

Первый prototype:

```text
Godot client
    ENet + project DTO
        |
Godot headless Gateway
        |
    ENet + GatewayEnvelope DTO
        |
Godot headless Simulation Server
```

Оркестрация:

```text
Python + pytest + subprocess
```

Fault injection:

```text
Linux tc/netem
```

Почему сейчас не QUIC:

- сначала нужно доказать semantics;
- ENet уже входит в текущий стек проекта;
- уменьшается число одновременно меняемых переменных;
- Godot client/server/headless patterns уже существуют;
- Gateway может иметь разные client-facing и backend peers.

После semantics proof выполняется отдельный production transport spike; QUIC является сильным кандидатом, но не фиксируется этим планом.

---

# PRE-P6 FOUNDATION

## EG0 — Contracts and fixtures

Deliver:

- `ClientWorldFrame`;
- `GatewayIngressEnvelope`;
- `GatewayEgressEnvelope`;
- `GatewaySessionBinding`;
- `GatewayRouteBinding`;
- `ProjectionSubscription`;
- `GatewayDescriptor`;
- channel definitions;
- canonical JSON fixtures;
- schema validation;
- protocol glossary update.

Identity separation must hold:

```text
TransportConnectionId != GatewaySessionId
GatewaySessionId       != ClientSessionId
ClientSessionId        != PlayerId
PlayerId               != PlayerEntityId
session_slot            != PlayerId
backend_peer_id         != PlayerId
RouteRevision           != AuthorityEpoch
```

Exit:

```text
TOPOLOGY_NEUTRAL_DTOS_PASS
```

---

## EG1 — Single Gateway pass-through

Topology:

```text
Client -> Gateway G1 -> Sim A
```

Implement:

- client-facing listener;
- backend connection;
- envelope forwarding;
- route/session table;
- per-direction metrics;
- no canonical gameplay logic inside Gateway.

Run one scenario twice:

```text
DIRECT:  Client -> A
GATEWAY: Client -> G1 -> A
```

Both paths must enter the same gameplay/domain boundary and produce equivalent canonical state/result.

Exit:

```text
DIRECT_GATEWAY_CANONICAL_EQUIVALENCE_PASS
Gateway canonical writes = 0
Gateway ownership decisions = 0
```

---

## EG2 — Auth / Session / Placement

Target flow:

```text
EdgeLocator
-> connect Gateway
-> authenticate
-> create/resume ClientSession
-> resolve world/player placement
-> Directory resolves current Authority
-> Gateway ensures backend link
-> logical session attach
-> server reconstruct/load
-> WorldReady
```

Hard rules:

```text
client does not receive Sim A endpoint
Gateway session id is not PlayerId
Gateway route cache is not ownership truth
```

Reconnect/resume must preserve logical player identity.

Exit:

```text
WORLD_READY_WITHOUT_SERVER_ENDPOINT_DISCLOSURE
```

---

## EG3 — Shared multiplexed Gateway->Server tunnel

Topology:

```text
Client A --\
Client B --- Gateway G1 === one physical tunnel === Sim A
Client C --/
```

MVP deliberately proves many logical player sessions over one physical backend link.

Implement:

- ephemeral `session_slot`;
- logical session attach/detach;
- per-session queues;
- scheduler;
- server demux;
- egress remux;
- per-session/per-link metrics.

Priority classes:

```text
P0 session / authority control
P1 reliable world operations
P2 input
P3 authoritative snapshots
P4 projections
P5 telemetry
```

Rules:

- P4/P5 backlog must not block P0/P1;
- stale unreliable snapshot/projection may be dropped;
- reliable world operation backpressures instead of silent drop;
- one client cannot monopolize tunnel;
- queues are bounded;
- session slot reuse cannot leak data between identities.

Mandatory tests:

1. 2+ clients share exactly one physical backend link.
2. One client floods input; another still receives control/operations/snapshots.
3. Reliable operation from one logical session cannot appear in another.
4. Disconnect one client; tunnel remains for the others.
5. Reconnect may receive new ephemeral slot while PlayerId/PlayerEntityId remain stable.
6. Backend tunnel drop affects sessions predictably and leaves no stale slot resurrection.

Exit:

```text
MULTI_CLIENT_ONE_BACKEND_LINK_PASS
cross_session_leakage = 0
unbounded_queue_growth = 0
```

Production is allowed to evolve from one physical tunnel to a small `1..K` pool for congestion/failure isolation. `K` is a measured tuning value, not a gameplay contract.

---

## EG4 — Projection aggregation through one client connection

Topology:

```text
             Sim A ACTIVE
            /
Client -> Gateway
            \
             Sim B PROJECTION
              \
               Macro projection (optional)
```

Client remains connected only to Gateway.

Implement:

- projection demand/subscription;
- source revision/sequence;
- projection stream role;
- Gateway fan-in;
- remux into `WORLD_PROJECTION` channel;
- read-only fencing;
- projection priority/backpressure policy.

Graphical proof:

```text
client transport count = 1
active authoritative source = A
projection source = B
both visible in same graphical client
projection write injection rejected
projection source loss does not disconnect gameplay
```

Exit:

```text
MULTI_SOURCE_SINGLE_CLIENT_TRANSPORT_PASS
```

Direct `ProjectionPublisher -> Client` sockets are not a V0 baseline dependency.

---

## EG5 — Multi-Gateway nearest-edge selection

Topology:

```text
Client
  |
EdgeLocator
  +-- Gateway G1
  +-- Gateway G2
  +-- Gateway G3
```

`tc/netem` models different RTT/loss/jitter and health.

Implement:

- locator revision;
- bounded candidate list;
- health/capacity hints;
- bounded network probes;
- deterministic network score;
- hysteresis;
- fallback selection.

"Nearest" means best healthy network path, not geographic distance.

Tests:

1. Lowest healthy network score is selected.
2. A geographically closer but poor route loses to a better path.
3. Failed preferred Gateway falls back deterministically.
4. Gateway selection and world authority selection remain separate.
5. A future routine authority change A->B does not itself cause Gateway rehome.

Exit:

```text
NEAREST_HEALTHY_EDGE_SELECTION_PASS
```

---

## 4. PRE-P6 acceptance gate

After EG5, do not immediately start P6 from chat state.

Create durable acceptance evidence for:

```text
EDGE_GATEWAY_FOUNDATION_ACCEPTED
```

Required:

- EG0 PASS;
- EG1 PASS;
- EG2 PASS;
- EG3 PASS;
- EG4 PASS;
- EG5 PASS;
- `client_active_world_transports == 1`;
- no simulation endpoint required by client;
- shared backend tunnel proven;
- auth/session/placement proven;
- projection fan-in proven;
- nearest healthy Edge selection proven;
- Gateway canonical writes = 0;
- Gateway ownership decisions = 0;
- stable PlayerId/PlayerEntityId;
- OperationId forwarding continuity;
- no cross-session leakage/starvation;
- bounded queues;
- direct and Gateway adapters converge on same `ClientGameplayPort` / domain path;
- no unresolved NX/AUTHORITY ownership conflict;
- exact candidate Project Control SUCCESS;
- fresh independent critical review PASS;
- independent verification PASS.

Only after formal acceptance can P6 preactivation be refreshed and runtime lease rotated.

---

## 5. P6 convergence boundary after Foundation acceptance

P6 must consume the proven network boundary, not invent a parallel gameplay path.

Target:

```text
TransportAdapter
    -> ClientGameplayPort
    -> SessionBinding
    -> MutationAdmission
    -> DomainCommand
```

Both:

```text
DirectTransportAdapter
GatewayIngressAdapter
```

must enter the same `ClientGameplayPort` and domain semantics.

Forbidden P6 assumptions:

```text
multiplayer.get_remote_sender_id() == PlayerId
socket peer == canonical authority identity
RPC sender address == mutation authority
client server address == gameplay owner
```

---

# PARALLEL AFTER P6 ACTIVATION

## EG6 — ACTIVE/WARM A->B backend pivot

After P6 runtime starts, run EG6 in parallel.

Topology:

```text
Client <-> Gateway G1 = stable
Gateway -> A = ACTIVE
Gateway -> B = WARM
```

Required ordering:

```text
1. A ACTIVE epoch E
2. B WARM, writes=0
3. explicit input/command barrier fixed
4. A reaches barrier
5. B reconstructs state at barrier
6. Directory commits B epoch E+1
7. Gateway observes committed ownership
8. Gateway route_revision advances
9. A -> DRAIN/READ_ONLY
10. B -> ACTIVE
11. post-barrier input routes only to B
12. delayed A traffic fenced
```

Hard test:

```text
same client transport before/during/after
same PlayerId
same PlayerEntityId
no gameplay reconnect
no respawn
same logical OperationId retry semantics
A->B and B->A pass
```

Exit:

```text
STABLE_CLIENT_CONNECTION_BACKEND_PIVOT_PASS
```

EG6 is a required donor for the preferred immediate post-P6 SM1 path unless a concrete independently reviewed blocker exists.

---

## EG7 — Gateway failure/rehome

Topology:

```text
Client -> G1 -> A
kill G1
Client resumes through edge endpoint -> G2 -> A
```

Gateway failure/rehome is distinct from normal authority handoff.

For V0 a physical reconnect to a new Gateway is allowed after Gateway process failure, but logical identity/state must survive.

Exit:

```text
LOGICAL_SESSION_REHOME_PASS
```

---

## EG8 — WAN fault matrix

Run impairments independently across network legs:

- latency;
- jitter;
- 1/5% loss;
- duplicate;
- reorder;
- asymmetric delay;
- bandwidth cap;
- temporary disconnect.

Correctness gates precede smoothness tuning.

Exit:

```text
CORRECTNESS_UNDER_SPLIT_LEG_IMPAIRMENT_PASS
```

---

## EG9 — scale/fairness/soak

Minimum:

```text
2 graphical clients
32 bot clients
1+ Gateways
2 simulation servers
shared backend tunnel pool
30 min
projection churn
repeated A<->B pivots when EG6 available
```

Also run 64/128+ bots when machine capacity allows.

Measure:

- sessions/tunnel;
- backend link count;
- queue depth;
- bytes/player;
- Gateway CPU;
- memory/session;
- drops/backpressure;
- handoff success;
- route churn;
- leaked sessions/tunnels.

No production SLO is promoted before measured baseline exists.

---

## 6. Evidence package

Each run publishes at minimum:

```text
topology.json
processes.json
network_profile.json
gateway_metrics.jsonl
route_events.jsonl
authority_events.jsonl
client_events.jsonl
assertions.json
summary.json
```

Critical correlation fields:

```text
run_id
gateway_instance_id
gateway_session_id
client_session_id
player_entity_id
operation_id
input_seq
route_revision
authority_epoch
source_role
backend_link_id
session_slot
```

---

## 7. Mandatory fault cases across the program

- stale Gateway route revision;
- forged session slot;
- session slot reuse after disconnect;
- duplicate forwarded operation;
- lost response + exact OperationId retry;
- projection source disconnect;
- malformed/oversized projection;
- one slow/flooding client;
- one backend tunnel failure with multiple sessions;
- Gateway route cache stale relative to Directory;
- WARM write attempt;
- B failure before commit;
- A failure during prepare;
- late A packet after B activation;
- Gateway failure before/after ownership commit;
- rapid A->B->A;
- client reconnect during handoff.

Not all of these block P6 start: EG0-EG5 require their relevant subset; EG6-EG9 close the later pivot/recovery/WAN/scale cases.

---

## 8. Definition of PRE-P6 success

Before P6, the lab must demonstrate at least:

```text
Client A and Client B discover/select a healthy Gateway.
Both authenticate and enter world A without learning Sim A endpoint.
Both share one Gateway->A physical backend tunnel.
Client A and B remain isolated logical sessions.
Client A approaches neighboring world B.
Gateway subscribes to B projection.
Client A sees A + B through exactly one client transport.
Multiple Gateway candidates are measured and nearest healthy Edge is selected.
Gateway owns no canonical world or authority truth.
```

This is enough to prove the transport/session foundation on which P6 can safely grow.

A real A->B authority pivot is deliberately EG6 and does not block P6 activation.

---

## 9. Final execution rule

```text
BEFORE P6:
  EG0 -> EG1 -> EG2 -> EG3 -> EG4 -> EG5
  -> EDGE_GATEWAY_FOUNDATION_ACCEPTED

THEN:
  P6.1 -> P6.11
  in parallel with
  EG6 -> EG7 -> EG8 -> EG9

AFTER P6:
  V0-SM1 productionizes accepted P6 + reviewed Gateway donors.
```
