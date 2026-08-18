# Seamless World Architecture R1

Status: `RESEARCH / ARCHITECTURE CANDIDATE`

Branch: `research/seamless-world-architecture-r1`

Base: `main @ c58339c30e6d7e708a06c41e59208bd45f0709a4`

This document defines the target architecture for a production-capable seamless distributed world. It does **not** activate production SM1 work by itself, does not reopen the frozen SM0 runtime branch, and does not bypass the sequential V0/P product train or Project Control.

## 1. Why this architecture exists

SM0 proved that stable identity, one active writer, epoch fencing, prepared shadow state, durable handoff evidence, read-only foreign projections and fault-oriented testing can make authority transfer correct across multiple processes.

The next problem is no longer “can A hand a player to B?”. The next problem is how to turn those proven semantics into a scalable world where:

- clients do not need to understand server topology;
- many geographically distributed edge gateways can provide a stable client ingress point;
- ownership is decided by a canonical directory, not by packet arrival;
- visual overlap never becomes a second writer;
- objects that must interact closely can remain on one simulation authority even when they cross spatial cells;
- cross-authority operations have explicit semantics;
- static multi-authority correctness is proven before dynamic balancing;
- later balancing uses interaction cost, not only CPU/player count;
- the reusable networking/runtime boundary remains separable from simulator gameplay semantics.

## 2. Core model

The architecture deliberately separates four questions that must never collapse into one abstraction:

```text
WHERE IS IT?
    Spatial Cell / Spatial Address

WHO MAY MUTATE IT?
    Canonical Authority / OwnershipRecord

WHAT MUST BE SIMULATED TOGETHER?
    InteractionIsland

HOW DOES A CLIENT ENTER THE WORLD?
    Edge Gateway
```

Therefore:

```text
SpatialCellId != AuthorityId != InteractionIslandId != GatewayId
```

A spatial boundary is not automatically an authority boundary. An authority boundary is not automatically an interaction boundary. A client network endpoint is not a canonical owner.

## 3. Target topology

```text
                          Gateway Discovery
                         /       |        \
                        /        |         \
                  Edge EU    Edge US    Edge AP
                     |           |          |
                     +---- client ingress --+

Client
  |
  | one stable client session
  v
+-----------------------------+
| Edge Gateway                |
| non-authoritative           |
| routing + view composition  |
+-----------------------------+
    | PRIMARY   | OBSERVER/WARM   | projection
    v           v                 v
 Authority A  Authority B      Authority C
      \          |               /
       \         |              /
        +-----------------------+
                    |
                    v
          +--------------------+
          | Ownership Directory|
          | CAS + fencing      |
          +--------------------+
                    |
          placement / ownership
                    |
          +---------+----------+
          |                    |
     Spatial Model       Interaction Model
      cells/scopes        islands/domains
```

## 4. Non-negotiable invariants

### 4.1 Stable identity

Process identity and canonical entity identity are independent.

A player, item, vehicle, structure, reference frame or interaction island keeps stable canonical identity across process changes.

### 4.2 Exactly one canonical writer

For every canonical mutable subject, at any observable instant accepted by the ownership system:

```text
active_writer_count(subject) <= 1
```

A projection, cache, observer route, warm route or gateway representation is never a writer.

### 4.3 Epoch and fencing semantics

Every authoritative mutation is checked against canonical ownership metadata. At minimum:

```text
subject_id
owner_authority_id
authority_epoch
fencing_token
directory_generation
```

A stale authority process may be healthy, reachable and internally convinced it owns state, but it must still be unable to commit a mutation after its fencing token has been superseded.

### 4.4 Directory commit is the ownership linearization point

Target import, PREPARE success, network ACK, broker delivery and gateway route change do not transfer ownership.

The ownership transition occurs only when the canonical ownership record is atomically changed, conceptually:

```text
CAS(
  expected = { owner:A, epoch:N, fence:F },
  desired  = { owner:B, epoch:N+1, fence:F+1 }
)
```

`DIRECTORY_COMMITTED` is the formal system-wide linearization point.

Before it, source remains the canonical writer. After it, the old source is permanently fenced from further canonical mutation for that generation.

### 4.5 Presentation cannot create canonical truth

All gateway-composed state, cached representations, observer projections, ghosts and LOD products are explicitly non-authoritative.

```text
presentation_only = true
canonical_write_allowed = false
```

Stale visual state may be shown under an explicit degraded/stale policy; it may never authorize mutation.

### 4.6 Operation identity survives routes and gateways

Client operation identity is independent of the transport path.

A retry through another gateway must not create a second canonical mutation.

```text
OperationId is end-to-end
GatewayId is transport metadata
```

### 4.7 Client session identity survives gateway choice

```text
ClientSessionId != GatewaySessionId
PlayerEntityId   != GatewaySessionId
```

This is required so a future gateway crash/rehome can preserve gameplay identity and exactly-once operation semantics.

## 5. Ownership Directory

The production ownership directory is more than service discovery.

A conceptual `OwnershipRecord` contains:

```text
OwnershipRecord {
    subject_id
    owner_authority_id
    authority_epoch
    fencing_token
    directory_generation
    authority_incarnation
    state_revision
    lease_state
    route_revision
    updated_at
}
```

The exact persistence technology is deliberately not selected here. The contract requires strong ownership CAS/fencing behavior; it does not require that ordinary NATS delivery, a server heartbeat or an in-memory coordinator become the ownership truth.

Required behaviors:

- atomic owner transition;
- monotonic authority epoch/fencing token;
- stale mutation rejection;
- process incarnation tracking;
- explicit `ACTIVE`, `DRAINING`, `UNAVAILABLE` semantics;
- restart recovery;
- partition behavior that fails closed;
- route lookup separated from ownership mutation;
- observable history/evidence for transfer and recovery.

## 6. Authority transfer protocol

The production protocol should preserve the semantics already proven in SM0, while moving them into generic reusable runtime contracts.

Conceptual flow:

```text
ACTIVE_SOURCE
    |
    v
TARGET_ROUTE_WARM
    |
    v
SOURCE_FROZEN
    |
    v
TARGET_PREPARED_SHADOW
    |
    v
DIRECTORY_COMMITTED      <-- linearization point
    |
    v
TARGET_ACTIVE
    |
    v
SOURCE_RETIRING_READ_ONLY
    |
    v
SOURCE_RETIRED
```

Requirements:

- stable `TransferId`;
- replay-safe preparation and commit evidence;
- exact source/target authority identity;
- source/target epoch expectation;
- state revision and checksum fencing;
- durable proof where progress correctness depends on restart survival;
- stale and conflicting replay fail-closed;
- old owner can never resurrect after directory commit;
- retry must converge to one canonical outcome.

The generic transfer layer should carry an opaque domain payload. The networking/runtime framework decides **who owns**, **where to route**, **when ownership changes**, **which epoch/revision is valid** and **how replay/recovery works**. Domain code decides what the payload means and whether the requested gameplay operation is valid.

## 7. Edge Gateway layer

### 7.1 Purpose

The Edge Gateway is a non-authoritative network edge. It provides a stable client endpoint and absorbs the complexity of multi-authority routing, projection subscriptions and authority changes.

The gateway may decide:

- which authority route should receive an operation according to canonical routing metadata;
- which projections/representations a client should receive;
- which LOD/budget to use;
- which authority routes need to be warm;
- how to multiplex logical client routes over shared upstream transports.

It may **not** decide canonical ownership or mutate simulator truth.

### 7.2 Multiple geographic gateways

The architecture assumes many gateways from the beginning.

Clients discover a candidate set and probe them. Selection is primarily latency driven but must consider quality and health:

```text
GatewayScore =
    smoothed_rtt
  + loss_penalty
  + jitter_penalty
  + gateway_load_penalty
  + health_penalty
```

Exact coefficients remain an implementation checkpoint, not an architecture constant.

Selection must use hysteresis/cooldown so tiny RTT variation does not cause gateway flapping.

### 7.3 One stable client route

The client should normally maintain one active gameplay route to its selected gateway.

The client should not need direct authoritative sessions to every server that can contribute to the visible world.

Future gateway rehome/failover is a separate controlled transition and must not change canonical player identity.

### 7.4 Primary and observer authority routes

For one client session, the gateway can maintain logical routes such as:

```text
PRIMARY
OBSERVER
WARM
DEGRADED
DRAINING
CLOSED
```

`PRIMARY` means “current route for canonical operations according to the current ownership record”. It does not grant ownership.

An `OBSERVER` may feed read-only state. `WARM` may prepare for likely handoff. Neither can accept canonical writes unless ownership changes through the directory.

### 7.5 Authority handoff versus client transport handoff

These are different operations.

Normal authority handoff:

```text
Client -> Gateway   remains stable
Authority A -> B    changes under the gateway
```

Gateway route flip is triggered only by committed canonical ownership state.

This allows authority movement without forcing a player reconnect/despawn/new identity cycle.

### 7.6 Interest-driven upstream connectivity

Do not connect each gateway to every authority in the world.

A gateway opens/retains upstream connectivity when needed for:

- a current primary route;
- an observer/projection source;
- a warm handoff candidate;
- a cross-authority interaction;
- a reference-frame dependency;
- a required world representation stream.

Idle upstream connections/subscriptions may be retired according to policy.

### 7.7 Physical transport != logical client route

A gateway-authority physical connection should be shareable by many logical client routes.

```text
Gateway EU ---- one/few transport sessions ---- Authority A
                    |
                    + logical client route 1
                    + logical client route 2
                    + logical client route 3
                    + projection subscriptions
                    + operation streams
```

The scale target is therefore not `clients * authorities` physical sockets.

Backpressure must be isolated so one slow client or one degraded authority does not globally stall unrelated routes.

## 8. Multi-authority view composition

The gateway is the natural place to evolve the SM0 P10 idea into a production edge composition service.

Input may include:

- local/primary authority snapshots;
- foreign read-only projections;
- coarse representations;
- cached world artifacts;
- reference-frame context;
- source health/staleness metadata.

Output is client-specific presentation state under explicit interest and bandwidth budgets.

Required protections:

- source epoch rollback rejection;
- sequence/revision monotonicity;
- same-version conflicting checksum rejection;
- stale marking after source loss;
- no promotion of cached state to canonical truth;
- deterministic prioritization where practical;
- metrics for dropped/coarsened/deferred representation.

## 9. Interest aggregation at the gateway

When many clients in one edge region need similar world data, the gateway may aggregate authority subscriptions instead of issuing identical upstream requests per client.

Example:

```text
500 client interests
        |
        v
Gateway Interest Planner
        |
        v
merged authority subscription
        |
        v
client-specific filtering / LOD
```

This is a future optimization, but the interfaces must not assume one upstream subscription per client.

## 10. InteractionIsland

### 10.1 Why it exists

Pure geographic partitioning is insufficient for a physical world. A ship, passengers, mounted items, cargo, docked modules or physically constrained objects may need low-latency mutual simulation even while their spatial addresses cross a cell boundary.

`InteractionIsland` represents a set of entities that policy says should be simulated together for a period of time.

Conceptual contract:

```text
InteractionIsland {
    interaction_island_id
    revision
    owner_authority_id
    authority_epoch
    membership_generation
    members[]
    interaction_class
    placement_constraints
}
```

The island is not a replacement for EntityId, SpatialCellId or ReferenceFrameId.

### 10.2 Example

```text
InteractionIsland ship/17
    ship hull
    pilot
    passengers
    mounted components
    cargo containers
    loose constrained physics objects
```

If co-location policy requires it, crossing a spatial cell boundary should not produce a state such as:

```text
ship -> Authority B
pilot -> Authority A
cargo -> Authority C
```

The placement/handoff mechanism may instead move the relevant island/domain as one authority unit.

### 10.3 Island membership is dynamic but explicit

Membership can change as interactions begin/end: docking, physics constraints, vehicle entry/exit, combat contact, construction coupling, etc.

Changes must be versioned. The first implementation should be conservative and bounded; arbitrary automatic island formation is a later R&D stage.

## 11. AuthorityDomain

`AuthorityDomain` is a placement/ownership grouping above individual entities and potentially above one InteractionIsland.

Conceptually:

```text
AuthorityDomain authority-domain/b {
    owner_authority_id
    generation
    islands[]
    independent_subjects[]
    spatial_coverage[]
}
```

This abstraction allows later dynamic placement to move whole existing domains before attempting fine-grained split/merge.

It also separates “the authority process currently serving this set” from “the permanent identity of world cells/entities”.

## 12. Cross-authority operations

Cross-boundary gameplay is a separate architecture problem from player handoff.

Examples:

- player on A uses item on B;
- projectile/action crosses A/B;
- vehicle on A collides/docks with object on B;
- container ownership and actor ownership differ;
- construction/matter operation spans an authority boundary.

The generic operation envelope should preserve end-to-end identity and expected ownership metadata:

```text
OperationEnvelope {
    operation_id
    client_session_id
    subject_id
    expected_authority_id
    expected_authority_epoch
    expected_state_revision
    operation_kind
    payload
    payload_hash
}
```

For multi-subject interactions, a future bounded contract may include participant ownership expectations and an interaction/coordinator policy.

The architecture deliberately does **not** prescribe one universal solution. Depending on the interaction, the correct policy may be:

- route to one canonical coordinator authority;
- temporarily co-locate an InteractionIsland;
- execute a controlled multi-aggregate/cross-authority transaction;
- defer/retry until authority alignment;
- reject when safe distributed semantics are not available.

Broadcast-to-all-authorities is not the default gameplay mechanism.

## 13. Authority seamlessness != visual seamlessness

Two independent quality dimensions must be measured.

### Authority seamlessness

- stable identity;
- single writer;
- epoch/fencing continuity;
- operation/input sequence continuity;
- correct handoff/recovery.

### Visual seamlessness

- observer projections;
- interpolation/prediction;
- LOD continuity;
- reference-frame continuity;
- stale/coarse fallback presentation;
- no visible reconnect/loading discontinuity.

Correctness gates come first. Visual techniques are allowed only on top of proven ownership semantics.

## 14. Dynamic placement model

Dynamic balancing is intentionally deferred until static N-authority correctness exists.

When introduced, placement must not be based only on CPU or player count.

A conceptual cost model is:

```text
PlacementCost =
    compute_cost
  + memory_cost
  + network_cost
  + interaction_cut_cost
  + migration_cost
  + client_latency_cost
  + instability_penalty
```

Required stabilizers:

- hysteresis;
- cooldown;
- minimum-benefit threshold;
- migration budget;
- maximum concurrent migrations;
- failure-aware drain policy.

A placement move should be rejected when reduced CPU load would create a larger cross-authority interaction cut or excessive migration cost.

## 15. Static-first evolution

The production program must prove these layers in order:

```text
SM1 Static Production Mesh
    ownership core
    durable directory
    edge gateway
    projections/AOI
    cross-authority operations
    interaction islands (bounded)
    static N-authority world

then

SM-D1 Dynamic Domain Placement

then

SM-D2 Dynamic Split/Merge

then

SM-D3 Interaction-aware Dynamic Meshing
```

Dynamic balancing is not an acceptance condition for SM1.

## 16. Failure model

The architecture must explicitly tolerate bounded failures including:

- source crash before/after prepare;
- target crash after prewarm/prepare;
- source restart with stale durable ownership state;
- gateway crash after forwarding an operation but before delivering the result;
- directory restart;
- server process incarnation change;
- delayed/reordered/duplicated packets;
- network partition;
- stale projection after ownership transfer;
- simultaneous independent migrations;
- simultaneous opposing migrations;
- slow client and slow authority backpressure;
- gateway or authority draining.

The expected outcome is not always uninterrupted progress. Fail-closed temporary unavailability is acceptable when necessary to preserve one-writer semantics. Split-brain is not.

## 17. Security boundary

The gateway is an exposed ingress component and therefore must not be trusted as canonical simulation authority.

Future implementation must include:

- authenticated client sessions;
- authenticated/mutually authenticated gateway-authority links;
- authorization scoped by operation/session/entity;
- replay protection around operation/session credentials;
- rate limiting and abuse isolation;
- no trust in client-provided authority IDs without directory validation;
- no ability for a compromised gateway to manufacture ownership by route changes.

## 18. Observability requirements

Every production checkpoint should expose enough telemetry to reconstruct ownership/routing decisions:

- `client_session_id`;
- `gateway_id` and gateway incarnation;
- authority IDs/incarnations;
- subject/entity ID;
- `authority_epoch` and fencing token;
- directory generation/revision;
- transfer ID;
- operation ID;
- logical route state;
- upstream physical connection ID;
- projection source/epoch/revision;
- handoff timings;
- queue/backpressure metrics;
- stale/degraded presentation status.

Sensitive secrets are excluded from telemetry.

## 19. Reusable framework boundary

The architecture continues the existing network-framework-readiness direction.

Desired dependency direction:

```text
Simulator Domain
      |
Simulator Network Adapters
      |
Reusable Network Runtime
```

Reusable runtime candidates:

- authority identity/epochs/fencing;
- ownership records and route resolution contracts;
- transfer state machine;
- operation identity/replay protection;
- gateway session/route abstractions;
- transport pooling/multiplexing;
- projections/interest contracts;
- network-condition simulation;
- observability and fault injection.

Simulator-specific code remains responsible for gameplay meaning, item graph semantics, matter/construction rules, physics behavior and domain permissions.

## 20. Explicit non-goals for the first production program

Do not make SM1 depend on:

- automatic arbitrary region split/merge;
- global consensus everywhere;
- a Star Citizen-style replication layer clone;
- all-authority full mesh connections;
- one physical upstream socket per client per authority;
- Kubernetes/Agones deployment;
- real global Anycast/GeoDNS deployment;
- a second Item Graph in the gateway;
- canonical physics in the gateway;
- copying Unreal Engine source or API design verbatim;
- replacing all existing simulator networking in one migration.

## 21. Migration principle from current project state

SM0 remains frozen research evidence/capability donor. The earlier Edge Gateway research remains a design donor. Neither should be wholesale merged into a newer product baseline.

When Project Control authorizes production SM1, implementation starts from the exact accepted product predecessor declared by the current sequential product train (expected conceptually after the required P gate, not from an old research branch).

Contracts are reintroduced deliberately with fresh tests and current adapters.

## 22. Definition of architectural success

The target architecture is successful when it can eventually demonstrate:

```text
client keeps one stable edge session
+ canonical authority can change underneath it
+ one writer always
+ stale owners are fenced after restart/partition
+ foreign views remain read-only
+ interaction clusters can remain co-located
+ cross-authority gameplay has explicit semantics
+ many logical client routes share bounded upstream transports
+ gateway failure can be recovered without duplicate canonical mutation
+ static N-authority world works before dynamic placement is enabled
```

That is the baseline for a real seamless distributed world rather than a handoff demo.