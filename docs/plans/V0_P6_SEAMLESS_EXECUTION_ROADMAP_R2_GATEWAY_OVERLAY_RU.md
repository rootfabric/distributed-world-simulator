# V0 P6 + Seamless — R2 Edge Gateway Fabric Overlay

Статус: **CONTROL CANDIDATE / NORMATIVE OVERLAY OVER R1 / NO RUNTIME AUTHORITY**

Canonical main base:

`1d9de3c479c60045d613660b2a5c5db0374963f8`

Accepted P5 product lineage / declared P6 execution base:

`491ca7d058690d3de5fcea5e41aaee230a31b3ab`

Base detailed roadmap:

`docs/plans/V0_P6_SEAMLESS_EXECUTION_ROADMAP_RU.md`

Normative network specification:

`docs/network/EDGE_GATEWAY_FABRIC_SPEC_RU.md`

Executable research/test plan:

`docs/network/EDGE_GATEWAY_TEST_IMPLEMENTATION_PLAN_RU.md`

Machine companions:

- `config/control/harness/v0-p6-seamless-execution-roadmap.v1.json`
- `config/control/harness/v0-edge-gateway-fabric-test-plan.v1.json`

This R2 overlay does not authorize P6 runtime mutation, does not rotate the V0 mutation lease, does not activate production SM1, and does not make Seamless Research or Edge Gateway lab ancestry a product base.

---

## 1. R2 architectural decision

R1 correctly introduced topology-neutral identity, OperationId continuity, seam-ready mutation admission, PlayerAuthorityDomain-ready closure, Gateway-ready routing and WARM/SHADOW compatibility.

R2 fixes the remaining ambiguity and defines the product network shape:

```text
PLAYER CONNECTS TO THE WORLD, NOT TO A SIMULATION SERVER.
```

Normal V0 client topology:

```text
Client
  |
  | exactly one normal world transport
  v
Edge Gateway
  |
  +---- shared/multiplexed links ----> Authority A ACTIVE
  |
  +---- shared/multiplexed links ----> Authority B WARM/PROJECTION
  |
  +---- shared/multiplexed links ----> Macro/other projection source
```

The client does not open simulation-server connections and does not receive simulation-server endpoints for normal world routing.

For normal A -> B authority crossing:

```text
client transport remains stable
Gateway backend route changes
```

---

## 2. Multi-Gateway edge fabric

Production target contains many geographically distributed Gateway POPs and multiple Gateway instances per POP.

Client initially reaches the best healthy Edge Gateway by network quality, not by simple geographic distance.

Production discovery may use Anycast, latency-aware DNS, a managed global accelerator, or a custom Edge Locator. Vendor choice is not part of gameplay/domain contract.

The V0 lab uses a deterministic `EdgeLocator + bounded RTT/loss probe` model.

Hard distinction:

```text
SIMULATION HANDOFF:
    same Gateway
    backend authority A -> B

EDGE REHOME:
    Gateway G1 -> G2
    rare recovery/network event
```

Routine movement across world/server boundaries MUST NOT rehome the client to another Gateway.

---

## 3. One client-facing connection includes projections

The previous R2 draft allowed direct `ProjectionPublisher -> Client` sockets. That is no longer the V0 baseline.

New baseline:

```text
canonical gameplay:   Client -> Gateway -> ACTIVE authority
read-only projection: Projection source -> Gateway -> Client
```

Therefore:

```text
client_active_world_transports == 1
```

for normal gameplay, including neighboring-world projection fan-in.

Direct projection transports may be researched only later as a separate optimization after the single-connection Gateway path is accepted. They are not required and are not allowed to weaken V0 acceptance.

Projection remains read-only and cannot authorize mutation.

---

## 4. Shared Gateway -> Server links

Gateway MUST NOT create one backend transport per player as the default architecture.

Introduce:

```text
GatewayServerLinkPool
```

Conceptually:

```text
Gateway G1
  |
  +-- LinkPool -> Sim A
  |      physical tunnel 1: Player sessions 1..N
  |      physical tunnel 2: Player sessions ...
  |
  +-- LinkPool -> Sim B
         physical tunnel 1: Player sessions ...
```

MVP hard proof:

```text
2+ clients
1 Gateway
1 physical Gateway->Sim A backend link
multiple logical player sessions multiplexed over it
```

Production uses `1..K` tunnels per GatewayInstance/ServerInstance, not one unbounded global tunnel. Pool size is transport tuning.

Required safety:

- per-session bounded queues;
- per-link bounded queues;
- traffic priorities;
- fair scheduling;
- stale unreliable drop policy;
- reliable-operation backpressure;
- no cross-session packet/state leakage;
- one slow/flooding client cannot starve another.

---

## 5. Auth / session / placement

Target connect sequence:

```text
Client
  -> discover nearest healthy Gateway
  -> connect Gateway
  -> authenticate
  -> create/resume logical ClientSession
  -> resolve player/world placement
  -> Directory/AUTHORITY current owner lookup
  -> Gateway ensures shared backend link
  -> attach logical player session
  -> Authority reconstructs/loads player domain
  -> WorldReady through same Gateway connection
```

Client never needs the selected simulation server address.

Identity separation remains mandatory:

```text
TransportConnectionId != GatewaySessionId
GatewaySessionId       != ClientSessionId
ClientSessionId        != PlayerId
PlayerId               != PlayerEntityId
GatewayInstanceId      != AuthorityId
ServerInstanceId       != AuthorityId
RouteRevision          != AuthorityEpoch
```

---

## 6. Gateway responsibility boundary

Gateway may own:

- public ingress endpoint;
- client transport termination;
- logical Gateway session attachment;
- auth/session integration;
- ephemeral route cache;
- shared backend link pools;
- multiplex/demultiplex;
- projection aggregation;
- route revision fencing;
- per-session queues/backpressure;
- network metrics;
- stable client-facing session while backend authority changes.

Gateway MUST NOT own:

- PlayerId/PlayerEntityId truth;
- Item Graph;
- Inventory/Equipment truth;
- Construction truth;
- Persistence truth;
- OperationId dedup truth;
- Authority ownership truth;
- AuthorityEpoch assignment;
- Directory linearization;
- cross-authority transaction commit;
- mutation authorization merely from Gateway/session/route identity.

Hard rule:

```text
GATEWAY ROUTES
DIRECTORY / AUTHORITY DECIDES OWNERSHIP
DOMAIN OWNERS DECIDE CANONICAL MUTATION
```

---

## 7. P6 product changes relative to R1

P6 remains a single-authority product checkpoint. Production A<->B ownership transfer remains post-P6 SM1 scope.

### P6.2 — topology-neutral identity

Required proof:

```text
GatewaySessionId insertion does not alter PlayerId/PlayerEntityId
backend route identity does not become gameplay identity
Gateway peer id is not PlayerId
```

### P6.3 — OperationId continuity

Required invariant:

```text
OperationId remains end-to-end stable through
Client -> Gateway boundary -> Authority -> canonical owner
```

Gateway retry/forwarding does not mint a replacement OperationId for the same logical operation.

### P6.4 — mutation admission

Gateway/session/route identity is insufficient to authorize canonical mutation.

Future server-side admission resolves SessionBinding plus Directory/AUTHORITY owner/epoch/fence/incarnation and domain authorization.

### P6.6 — Edge-Gateway-compatible gameplay ingress

R1 stage name remains `GATEWAY_READY_COMMAND_SESSION_ROUTING`, but R2 exit is strengthened to:

```text
EDGE_GATEWAY_INGRESS_COMPATIBLE_GAMEPLAY_SURFACE
```

Target abstraction:

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

P6 direct single-server handlers MUST NOT assume:

```text
network peer id == PlayerId
socket endpoint == canonical authority identity
direct server address == gameplay semantic owner
```

### P6.9 — WARM compatibility

Required evidence shape:

```text
A ACTIVE
B WARM/SHADOW
stable logical session model
B reconstruction/hash matches
B canonical writes = 0
```

### P6.10 — fault matrix

Add/retain:

- stale Gateway route revision;
- duplicate forwarded command;
- delayed old-authority response;
- forged Gateway mutation authority;
- projection-channel write injection;
- session-slot reuse;
- slow/flooding client isolation on shared backend link;
- lost response + exact OperationId retry.

---

## 8. Seamless Research / Edge Gateway Lab

The Gateway research path is expanded into executable stages `EG0-EG9` defined in:

`docs/network/EDGE_GATEWAY_TEST_IMPLEMENTATION_PLAN_RU.md`

### SR3 / I5A = EG0-EG5

Required donor proof:

```text
EG0 contracts/fixtures
EG1 Client -> Gateway -> A pass-through
EG2 auth/session/placement
EG3 multiple clients share one backend tunnel
EG4 A+B projection fan-in through one client connection
EG5 multiple Gateways + nearest healthy edge selection
```

Hard SR3 properties:

- normal client world transport count = 1;
- Gateway canonical writes = 0;
- Gateway ownership decisions = 0;
- client receives no simulation server endpoint;
- multiple logical sessions multiplex over shared Gateway->Server connection;
- projections do not create new client transports.

### SR4 / I5B = EG6

Required topology:

```text
Client <-> Gateway = STABLE
Gateway -> A = ACTIVE
Gateway -> B = WARM
```

Required ordering:

```text
1. A ACTIVE epoch E
2. B WARM, writes=0
3. explicit input/command barrier
4. target state consistent with barrier
5. Directory commits B epoch E+1
6. Gateway observes committed ownership
7. route_revision advances
8. B ACTIVE
9. A DRAIN/READ_ONLY
10. post-barrier input routes only B
11. delayed A traffic fenced
```

Hard gates:

- no new client gameplay transport;
- no endpoint change;
- no login/respawn;
- stable player identities;
- exactly one canonical writer;
- monotonic AuthorityEpoch;
- monotonic Gateway RouteRevision;
- stable OperationId across pivot;
- lost response + retry yields exactly one canonical result.

### EG7-EG9

These prove:

- Gateway instance failure/rehome with logical session resume;
- independent Client->Gateway and Gateway->Server WAN impairments;
- scale/fairness/queue bounds/soak.

Gateway process failure may cause a physical client reconnect in V0, but must not cause new gameplay identity or canonical duplication. Zero-transport-reconnect Gateway failover is a later optimization.

---

## 9. Transport direction

Gateway/domain semantics stay transport-neutral and NX-owned.

Reference lab may use:

```text
Client <-> Gateway: Godot ENet + project DTO
Gateway <-> Simulation: Godot ENet + GatewayEnvelope DTO
Gateway: headless Godot process
Python/pytest: orchestration
netem: WAN/fault injection
```

Do not make SceneTree replication the Gateway protocol.

QUIC remains a strong later NX candidate for secure multiplexed streams/datagrams and path migration, but this R2 does not force production transport selection.

---

## 10. Production SM1 refinement

Production milestones become:

```text
SM1-H0  production seamless contracts
SM1-H1  durable Ownership Directory integration
SM1-H2  generic AuthorityDomain transfer
SM1-H2A AuthorityBinding + domain closure
SM1-H2B Player Carrying Domain
SM1-H3  production Global Edge Gateway Fabric
SM1-H4  shared backend LinkPools + ACTIVE/WARM/DRAIN routing
SM1-H5  Gateway-mediated PlayerAuthorityDomain A<->B handoff
SM1-H6  multi-region nearest-edge selection + directory routing
SM1-H7  Gateway instance failure/rehome/session resume
SM1-H8  MRPF projection/AOI aggregation through Gateway
SM1-H9  cross-authority operation foundation
SM1-H10 InteractionIsland runtime
SM1-H11 static N-authority world
SM1-H12 integrated static seamless acceptance
```

Direct client projection transport is not required before static SM1 acceptance.

---

## 11. Required evidence matrix

Before stable-proxy seamlessness can be claimed:

1. direct vs Gateway canonical equivalence;
2. one client-facing world transport in normal play;
3. two or more clients sharing one backend tunnel in MVP;
4. no cross-session leakage;
5. projection fan-in A+B through same client transport;
6. nearest healthy Gateway selection among at least three candidates;
7. stable PlayerId/PlayerEntityId;
8. exactly one writer;
9. OperationId continuity;
10. stale old-authority packet fencing;
11. stale Gateway route revision fencing;
12. WARM write rejection;
13. A->B and B->A pivots without client gameplay reconnect;
14. target failure before ownership commit;
15. response loss around handoff and exact retry;
16. Gateway failure logical-session rehome;
17. independent C->G and G->S latency/loss/jitter/reorder profiles;
18. bounded per-session/per-link queues;
19. slow-client isolation;
20. 30-minute multi-client soak with repeated pivots/projection churn.

Perceptual smoothness remains a later quality gate after canonical/transport correctness.

---

## 12. Integration into the current P6 campaign

Do now:

```text
1. Review/accept this control + network spec candidate.
2. Refresh PR #182 / P6 Work Order to bind the Edge Gateway spec.
3. Refresh/rebase PR #184 ownership map if required by accepted control lineage.
4. Activate P6 product work only after refreshed control is accepted.
5. Run EG0-EG5 donor-only in parallel with P6.
6. Make P6.6 consume reviewed contract shapes, not research code ancestry.
7. Complete EG6 before preferred immediate post-P6 SM1 activation, or record a concrete reviewed blocker.
8. Carry EG7-EG9 evidence into SM1 hardening.
```

Mapping:

```text
P6.2  <- EG0
P6.3  <- EG0/EG1
P6.4  <- EG1/EG2
P6.6  <- EG0-EG3
P6.9  <- EG4/EG6
P6.10 <- EG7-EG9

SR3/I5A <- EG0-EG5
SR4/I5B <- EG6
SM1-H3/H4 <- productionized EG1-EG6 contracts
SM1-H5 <- productionized EG6
SM1-H7 <- productionized EG7
```

P6 product base remains unchanged; Seamless Research remains donor-only until separately promoted.

---

## 13. Open control candidates

PR #182 and PR #184 were authored against weaker R1 semantics.

If this R2 Edge Gateway Fabric candidate is accepted, they MUST be refreshed/rebased or replaced before runtime mutation is authorized.

Do not merge an older preactivation carrier that restores:

- direct client/server gameplay coupling;
- direct projection sockets as V0 baseline;
- one-backend-connection-per-player assumptions;
- peer-id-as-player-identity assumptions.

---

## 14. Final route

```text
P5 ACCEPTED
    |
    v
P6 Seamless-Ready Product Foundation
    |
    +-------- parallel --------> EG0-EG5 Edge Gateway Fabric MVP
    |                           EG6 stable A/W pivot
    |                           I3/I4 + I8 + NX audit
    |
    v
P6 ACCEPTED
    |
    v
ACTIVATE V0-SM1
    |
    v
Global Edge Gateway Fabric
    |
    +--> shared links to Authority A/B/C
    +--> projection aggregation
    +--> nearest-edge placement
    |
    v
real A<->B handoff behind one client-facing world connection
```

Final rule:

```text
ONE CLIENT-FACING WORLD CONNECTION IN NORMAL PLAY
MANY EDGE GATEWAYS GLOBALLY
SHARED MULTIPLEXED GATEWAY->SERVER LINKS
PROJECTIONS AGGREGATED THROUGH GATEWAY
NORMAL HANDOFF CHANGES BACKEND ROUTE, NOT CLIENT TRANSPORT
GATEWAY NEVER BECOMES CANONICAL OWNERSHIP TRUTH
```
