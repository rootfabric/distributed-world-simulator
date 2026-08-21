# V0 Edge Gateway Fabric — Test Implementation Plan

Статус: **RESEARCH/TEST IMPLEMENTATION CANDIDATE / DONOR-ONLY / NO PRODUCTION AUTHORITY**

Связанная спецификация:

`docs/network/EDGE_GATEWAY_FABRIC_SPEC_RU.md`

Цель — получить исполняемый multi-process prototype до/параллельно P6 так, чтобы P6.6 и P6.9 могли опираться на проверенный Gateway contract, а post-P6 SM1 не начинал проектирование прокси с нуля.

---

## 1. Стратегия внедрения сейчас

Не переносить full distributed Gateway runtime внутрь P6 product branch.

Разделить работу:

```text
PRODUCT P6
  |
  +-- topology-neutral identity
  +-- OperationId continuity
  +-- mutation admission boundary
  +-- GatewayIngress-compatible command/session port
  +-- WARM read-only compatibility
  |
  +---------------- convergence ----------------+
                                                |
SEAMLESS RESEARCH / EDGE GATEWAY LAB            |
  |                                             |
  +-- real Gateway process                      |
  +-- shared backend tunnels                    |
  +-- auth/session/placement                    |
  +-- projection fan-in                         |
  +-- nearest-edge selection                    |
  +-- A->B backend pivot                        |
                                                |
                                                v
                                         POST-P6 V0-SM1
```

P6 не блокируется на production-ready global network, но P6 API не имеет права закрепить direct-client-to-server assumptions.

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

client-graphical-1
client-graphical-2

client-bots (configurable)

test-orchestrator
```

Все процессы должны запускаться локально. Geo/WAN моделируется `tc/netem`.

---

## 3. Reference implementation choice

Для первого prototype:

```text
Godot client
    ENet/project DTO
        |
Godot headless Gateway
        |
    ENet/GatewayEnvelope
        |
Godot headless Simulation Server
```

Причины:

- минимальный новый stack;
- уже существующие Godot/headless test patterns;
- можно иметь client-facing и backend MultiplayerAPI/ENet peers в одном Gateway process;
- wire DTO остаются проектными;
- легко fault-inject через netem.

Python/pytest orchestration управляет процессами и evidence.

Production QUIC spike выполняется отдельно после semantics proof.

---

## 4. Work breakdown

### EG0 — contracts and fixtures

Deliver:

- `ClientWorldFrame`;
- `GatewayIngressEnvelope`;
- `GatewayEgressEnvelope`;
- `GatewaySessionBinding`;
- `GatewayRouteBinding`;
- `ProjectionSubscription`;
- `GatewayDescriptor`;
- canonical JSON fixtures;
- schema validation;
- protocol glossary update.

Exit:

```text
all DTO roundtrip tests pass
no DTO field equates transport peer id with PlayerId
```

### EG1 — single Gateway pass-through

Topology:

```text
Client -> Gateway G1 -> Sim A
```

Implement:

- one client-facing listener;
- one backend connection;
- channel forwarding;
- route/session table;
- metrics;
- no canonical gameplay logic inside Gateway.

Run direct vs Gateway canonical-equivalence scenario.

Exit:

```text
same canonical result
Gateway writes = 0
```

### EG2 — Auth / Session / Placement

Flow:

```text
connect Gateway
authenticate
create/resume session
resolve placement
attach Sim A
WorldReady
```

Implement minimal test services/adapters using existing project identity/control contracts.

Exit:

```text
client receives no Sim A endpoint
PlayerId/PlayerEntityId stable across reconnect/resume
```

### EG3 — shared multiplexed Gateway->Server tunnel

Topology:

```text
Client A --\
Client B --- Gateway G1 === one physical tunnel === Sim A
Client C --/
```

Implement:

- ephemeral `session_slot`;
- per-session queues;
- channel scheduler;
- demux on server;
- egress remux;
- per-session fairness metrics.

Tests:

1. 2 clients minimum share exactly one backend link.
2. one client floods unreliable input; other client still receives control/snapshot traffic.
3. reliable world operation for one client does not corrupt another session.
4. disconnect one client; backend tunnel remains for other clients.
5. reconnect client gets new ephemeral slot but same logical identity.

Exit:

```text
backend physical link count independent of client count for MVP
cross-session leakage = 0
unbounded queue growth = 0
```

### EG4 — projection aggregation through one client connection

Topology:

```text
             Sim A ACTIVE
            /
Client -> Gateway
            \
             Sim B PROJECTION
```

Implement:

- ProjectionManifest/demand adapter;
- Gateway subscription;
- source stream revision;
- C4 projection channel;
- projection remux to client;
- read-only enforcement.

Test:

```text
client transport count = 1
active snapshot source = A
projection source = B
both visible in one graphical client
B write injection rejected
B loss does not disconnect gameplay session
```

Exit:

```text
MULTI_SOURCE_SINGLE_CLIENT_TRANSPORT_PASS
```

### EG5 — multi-Gateway nearest-edge selection

Topology:

```text
Client
  |
EdgeLocator
  +-- G1
  +-- G2
  +-- G3
```

Use netem to model different RTT/loss.

Implement:

- locator revision;
- health/capacity candidates;
- bounded client probes;
- deterministic scoring;
- hysteresis;
- fallback when best Gateway unhealthy.

Tests:

1. lowest healthy network score selected.
2. geographically named hint does not override measured bad path.
3. failed G1 selects G2.
4. active world session does not rehome merely because backend authority changes.

Exit:

```text
NEAREST_HEALTHY_EDGE_SELECTION_PASS
```

### EG6 — ACTIVE/WARM A->B backend pivot

Topology:

```text
Client <-> Gateway G1 stable
Gateway -> A ACTIVE
Gateway -> B WARM
```

Implement:

- WARM attach;
- handoff barrier/input watermark;
- target reconstruction;
- Directory commit integration;
- route revision pivot;
- A DRAIN;
- stale response fencing;
- exact OperationId retry.

Hard test:

```text
same client transport before/during/after
A ACTIVE -> B ACTIVE
same PlayerId
same PlayerEntityId
no reconnect
no respawn
no duplicate canonical operation
```

Return B -> A too.

Exit:

```text
STABLE_CLIENT_CONNECTION_BACKEND_PIVOT_PASS
```

### EG7 — Gateway failure and rehome

Test:

```text
Client -> G1 -> A
kill G1
Client resumes via edge endpoint -> G2 -> A
```

Implement:

- resume token;
- route reconstruction from Session + Directory;
- stale old-Gateway fencing;
- no canonical session truth only in G1 memory.

Exit:

```text
same logical session/player
no duplication
no stale G1 resurrection
```

Physical reconnect is allowed for Gateway process failure in V0.

### EG8 — WAN fault matrix

Run independent impairment:

```text
Client->Gateway
Gateway->A
Gateway->B
A/B->Directory
```

Profiles:

- RTT classes from spec;
- jitter;
- 1/5% loss;
- duplicate;
- reorder;
- asymmetric delay;
- bandwidth cap;
- temporary disconnect.

Verify correctness before smoothness.

### EG9 — scale/fairness/soak

Minimum acceptance run:

```text
2 graphical clients
32 bot clients
1 Gateway
2 simulation servers
shared backend tunnel pool
30 min
repeated A<->B pivots
projection source churn
```

Also run configurable 64/128+ bot stress when machine capacity allows.

Measure:

- sessions/tunnel;
- queue depth;
- bytes/player;
- CPU/Gateway;
- memory/session;
- handoff success;
- drops/backpressure;
- route churn;
- leaked sessions/tunnels.

No fixed production SLO is promoted until measured baseline exists.

---

## 5. Required server refactor boundary for P6.6

P6.6 should add/confirm a topology-neutral ingress layer before gameplay handlers.

Bad:

```text
multiplayer.get_remote_sender_id() -> PlayerId
socket peer -> authority identity
RPC sender address -> mutation authority
```

Target:

```text
TransportAdapter
    -> ClientGameplayPort
    -> SessionBinding
    -> MutationAdmission
    -> DomainCommand
```

Future Gateway path:

```text
GatewayIngressAdapter
    -> same ClientGameplayPort
```

Direct single-server P6 path and Gateway lab path must execute the same domain commands.

This is the critical convergence point between P6 and EG lab.

---

## 6. Shared tunnel scheduler

MVP priority classes:

```text
P0 session/authority control
P1 reliable world operations
P2 input
P3 authoritative snapshots
P4 projections
P5 telemetry
```

Rules:

- never allow telemetry/projection backlog to block P0/P1;
- stale unreliable snapshot/projection may be dropped;
- reliable operation must backpressure rather than silently drop;
- per-session budget prevents one client monopolizing link;
- scheduler metrics are mandatory.

Exact weights are tuning values, not canonical contract.

---

## 7. Handoff ordering proof

Required trace for every EG6 pass:

```text
1. A ACTIVE epoch E
2. B WARM epoch candidate E+1, writes=0
3. barrier/input watermark fixed
4. A reaches barrier
5. target state consistent with barrier
6. Directory commit B epoch E+1
7. Gateway observes committed ownership
8. route_revision R+1
9. B ACTIVE
10. A DRAIN/READ_ONLY
11. post-barrier input routed only B
12. delayed A traffic fenced
```

Evidence must contain timestamps/correlation IDs but ordering is logical, not wall-clock-authoritative.

---

## 8. Evidence

Each test run publishes:

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

Critical fields:

```text
run_id
gateway_instance_id
gateway_session_id
player_entity_id
operation_id
input_seq
route_revision
authority_epoch
source_role
backend_link_id
```

---

## 9. Fault cases

Mandatory before donor acceptance:

- stale Gateway route revision;
- forged session slot;
- session slot reuse after disconnect;
- duplicate forwarded operation;
- lost response + exact retry;
- late A packet after B activation;
- WARM write attempt;
- B failure before commit;
- A failure during prepare;
- Gateway failure before/after ownership commit;
- Directory stale read;
- one backend tunnel drop with multiple clients;
- one slow/flooding client;
- projection source disconnect;
- malformed oversized projection;
- rapid A->B->A;
- client reconnect during handoff.

---

## 10. Integration into current P6 campaign

Do now, before P6 runtime mutation is finally activated:

1. accept/review the Gateway architecture control update;
2. refresh P6 preactivation/Work Order so P6.6 binds this spec;
3. keep P6 product base unchanged;
4. start EG0-EG5 as donor-only Seamless Research in parallel;
5. P6 implementation consumes only reviewed contracts/adapters, not research branch ancestry;
6. complete EG6 before preferred post-P6 SM1 activation, or record a concrete reviewed blocker;
7. EG7-EG9 become SM1 readiness / production hardening donors.

Mapping:

```text
P6.2  <- EG0 identity contracts
P6.3  <- EG0/EG1 OperationId forwarding
P6.4  <- EG1/EG2 mutation admission boundary
P6.6  <- EG0-EG3 ingress/session/shared-tunnel contract
P6.9  <- EG4/EG6 WARM model
P6.10 <- EG7-EG9 fault evidence

SR3/I5A <- EG0-EG5
SR4/I5B <- EG6
SM1-H3/H4 <- reviewed EG1-EG6 donor contracts
SM1-H5 <- productionized EG6
SM1-H7 <- productionized EG7
```

---

## 11. What must change in current R2 candidate

Current R2 text allowing direct `ProjectionPublisher -> Client` is weakened for V0 baseline.

New baseline:

```text
Client -> Gateway only
Gateway -> ACTIVE server(s)
Gateway -> projection source(s)
```

Direct projection transport is deferred optimization.

Also add:

- multi-Gateway EdgeLocator/nearest selection;
- shared multiplexed GatewayServerLinkPool;
- auth/session/placement flow;
- projection aggregation;
- Gateway failure/rehome distinction;
- per-session fairness/backpressure;
- explicit EG0-EG9 executable lab.

---

## 12. Definition of successful test solution

Test solution is successful when one run can demonstrate:

```text
Client A and Client B select a healthy Gateway.
Both authenticate and enter world A.
Both share one Gateway->A physical backend tunnel.
Client A approaches world B.
Gateway subscribes to B projection for Client A.
Client A still has exactly one client-facing transport.
B becomes WARM.
Directory commits A->B for Client A.
Gateway pivots Client A backend route to B.
Client B remains on A through the same shared tunnel.
Client A continues on B without reconnect/respawn.
Gateway G1 is killed.
Client A resumes through G2 with same logical identity/state.
No duplicate canonical operation or split-brain occurs.
```

That scenario is the minimum proof that the architecture actually hides distributed-world complexity behind the Gateway.
