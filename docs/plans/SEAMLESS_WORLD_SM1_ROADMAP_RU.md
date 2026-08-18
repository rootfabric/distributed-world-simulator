# Seamless World SM1 Roadmap

Status: `RESEARCH ROADMAP CANDIDATE — NOT ACTIVATED`

Architecture: `../architecture/SEAMLESS_WORLD_ARCHITECTURE_R1_RU.md`

Rationale/provenance: `../architecture/SEAMLESS_WORLD_PROVENANCE_AND_RATIONALE_RU.md`

## 1. Program objective

Build a production-capable **static seamless multi-authority world** first, using the authority correctness proven in SM0 plus a durable Ownership Directory, a geographically scalable Edge Gateway layer, read-only projections/AOI, explicit cross-authority operations and bounded InteractionIsland semantics.

Only after static SM1 is accepted should the project attempt dynamic placement, split/merge or interaction-aware dynamic meshing.

## 2. Activation rule

This roadmap is research-only until Project Control explicitly activates it.

The current V0/P sequential product train continues independently. Architecture research does not make a successor checkpoint eligible and cannot substitute for acceptance of its predecessor.

When SM1 is activated:

```text
production branch base = exact accepted predecessor declared by current main
```

Not:

```text
old SM0 branch
research/seamless-world-architecture-r1
research/edge-gateway-architecture
```

Those branches are donors/evidence only.

## 3. Smooth continuation strategy

The safest transition is deliberately gradual:

```text
Current product line
      |
      | continues unchanged to required gate
      v
Accepted predecessor
      |
      +---- import contracts/evidence, not branch history
      |
      v
SM1-H0 contract freeze
      |
      v
SM1-H1 ownership directory
      |
      v
SM1-H2 generic static authority transfer
      |
      v
SM1-H3 single edge gateway transparency
      |
      v
SM1-H4 primary/observer composition
      |
      v
SM1-H5 gateway-mediated player handoff
      |
      v
SM1-H6 multi-region gateway selection
      |
      v
SM1-H7 gateway rehome/failure
      |
      v
SM1-H8 production AOI/interest
      |
      v
SM1-H9 cross-authority interaction
      |
      v
SM1-H10 interaction islands
      |
      v
SM1-H11 static N-authority world
      |
      v
SM1-H12 static mesh hardening/acceptance
```

Then and only then:

```text
SM-D1 dynamic domain placement
SM-D2 dynamic split/merge
SM-D3 interaction-aware dynamic meshing
```

## 4. Milestone naming

`SM1-H*` means static/production hardening milestones.

`SM-D*` means dynamic placement/meshing milestones.

Names are roadmap labels, not acceptance authorization.

---

# PRE-ACTIVATION — Architecture closure

## Goal

Close the architecture/research decision without touching runtime production code.

## Scope

- fresh independent review of Architecture R1;
- check consistency with current Project Control/product train;
- verify provenance and non-claims;
- decide whether prior Edge Gateway PR is superseded;
- create/approve Work Order only when predecessor eligibility exists.

## Acceptance

```text
architecture internally consistent
+ no production runtime mutation
+ no control bypass
+ donor branches explicitly non-production
+ roadmap stages have bounded claims/tests
```

---

# SM1-H0 — Production Seamless Contracts

## Goal

Reintroduce the proven semantics on the fresh accepted product baseline as generic runtime contracts, without yet implementing a distributed production world.

## Contracts

### Identity

```text
AuthorityId
AuthorityIncarnation
EntityId / SubjectId
ClientSessionId
GatewayId
TransferId
OperationId
InteractionIslandId
AuthorityDomainId
```

### Ownership

```text
OwnershipRecord
AuthorityEpoch
FencingToken
DirectoryGeneration
RouteRevision
LeaseState
```

### Transfer

```text
TransferEnvelope
TransferState
PreparedProof
CommitProof
RetirementProof
```

### Projection

```text
ProjectionEnvelope
source_authority_id
source_epoch
state_revision
read_only=true
checksum
```

### Gateway route

```text
ClientAuthorityRoute
role = PRIMARY | OBSERVER | WARM
route_state
expected owner/epoch
interest anchor
```

### Interaction island

Schema only at this stage:

```text
InteractionIslandId
membership_generation
members[]
owner authority / epoch
placement constraints
```

## Explicit non-scope

- no dynamic allocator;
- no global deployment;
- no automatic island formation;
- no new gameplay feature.

## Tests

- exact schema/field tests;
- invalid/stale epoch tests;
- stable identity tests;
- conflicting transfer ID/replay tests;
- projection `read_only` bypass tests;
- gateway route cannot grant ownership;
- island ID/cell ID/authority ID independence tests.

## Acceptance result

The system can express the production architecture without A/B fixture assumptions.

---

# SM1-H1 — Durable Ownership Directory

## Goal

Build the canonical owner/epoch/fencing service before production handoff depends on it.

## Minimum behavior

```text
register authority incarnation
publish health/draining metadata
lookup owner route
CAS owner A/N/F -> B/N+1/F+1
reject stale CAS
persist/recover ownership record
fence stale authority after restart
```

## Important rule

NATS/broker/discovery delivery may carry events or hints, but it is not itself the ownership commit.

## Tests

### Contract

- monotonic epoch/fencing;
- invalid owner/incarnation rejection;
- atomic expected-state transition;
- no duplicate active owner record.

### Restart

```text
A owns E @ epoch 10
A becomes partitioned
Directory commits B @ epoch 11
A restarts from snapshot claiming epoch 10
A mutation -> FENCED
B remains writer
```

### Crash points

- directory process restart before CAS;
- restart immediately after durable CAS;
- duplicate commit request;
- delayed stale route result.

## Acceptance result

There is exactly one canonical ownership oracle independent of simulation process memory.

---

# SM1-H2 — Generic Static Authority Transfer

## Goal

Port SM0 transfer semantics to the current production architecture with the real Ownership Directory.

Start with a generic non-player aggregate or bounded test entity to keep gameplay concerns out of the first proof.

## Flow

```text
source active
-> target warm
-> source frozen
-> target durable prepared shadow
-> directory CAS commit
-> target active
-> source retired/read-only
```

## Tests

- 20+ repeated A↔B transfers;
- duplicate TransferId;
- conflicting TransferId;
- stale source packet after directory commit;
- target crash before prepare;
- target crash after durable prepare;
- source crash before commit;
- source crash after commit;
- process incarnation change;
- recovery converges to one owner;
- global writer analyzer `<= 1`.

## Acceptance result

SM0 authority-transfer semantics are proven on the fresh production baseline and real ownership oracle.

---

# SM1-H3 — Single Edge Gateway Transparency

## Goal

Insert one non-authoritative gateway without changing canonical gameplay result.

Topology:

```text
Client -> Gateway -> Authority A
```

## Requirements

- client identity unchanged by gateway;
- gateway is not a canonical aggregate owner;
- OperationId survives gateway forwarding;
- client result/delta semantics match direct baseline;
- transport and logical route state are distinct;
- no gateway world object can be used as canonical mutation source.

## Tests

Run equivalent scenarios:

```text
direct client -> authority
client -> gateway -> authority
```

Canonical results must match.

Include movement, at least one item mutation, duplicate operation and reconnect/session tests.

## Acceptance result

Gateway insertion is semantically transparent.

---

# SM1-H4 — PRIMARY / OBSERVER Multi-Authority Gateway

## Goal

One gateway consumes canonical state from the current owner and read-only state from another authority.

Topology:

```text
Client -> Gateway
           | PRIMARY -> A
           | OBSERVER -> B
```

## Requirements

- observer cannot receive canonical mutation routing;
- source epoch rollback rejected;
- same revision conflicting checksum rejected;
- observer loss degrades only that source;
- gateway can compose both sources for presentation;
- cached/observer state never becomes owner.

## Tests

- delayed projection after newer epoch;
- reordered revisions;
- duplicate identical projection;
- conflicting identical revision;
- B unavailable while A continues;
- A unavailable does not promote B without ownership commit.

## Acceptance result

Multi-authority visibility exists without multi-writer semantics.

---

# SM1-H5 — Gateway-Mediated Seamless Player Handoff

## Goal

Prove the central architecture claim:

```text
client connection remains stable
while canonical player authority changes A -> B
```

## Preconditions

SM1-H1/H2/H3/H4 accepted.

## Flow

```text
Gateway:
A PRIMARY
B OBSERVER/WARM

SM transfer:
A/N -> B/N+1 through Directory CAS

Only after committed owner state:
A PRIMARY  -> OBSERVER
B OBSERVER -> PRIMARY
```

## Tests

### Core

- stable PlayerEntityId;
- stable ClientSessionId;
- client transport session unchanged;
- input/operation sequence continuity;
- no duplicate spawn/inventory;
- writer count <= 1.

### Route-fencing

- gateway receives B/N+1 state before directory commit -> must not flip primary;
- stale A/N arrives after commit -> rejected for canonical route;
- delayed directory response cannot roll back newer route revision.

### Repetition

- A↔B repeated handoff loops;
- simultaneous independent crossings;
- opposite-direction crossings.

## Acceptance result

Authority handoff no longer requires client-server topology handoff.

---

# SM1-H6 — Multi-Region Gateway Selection

## Goal

Make multiple gateways a first-class topology.

Local process lab is sufficient initially; real worldwide deployment is not required.

## Candidate topology

```text
G1 simulated EU
G2 simulated US
G3 simulated AP
```

## Selection signals

- smoothed RTT;
- jitter;
- loss;
- gateway health;
- gateway load;
- hysteresis/cooldown.

## Tests

### Basic

```text
G1 20 ms
G2 45 ms
G3 90 ms
=> select G1
```

### Quality beats raw ping

```text
G1 18 ms + high loss
G2 25 ms + no loss
=> deterministic policy chooses better score
```

### Anti-flap

Small alternating RTT differences must not cause repeated migration.

### Load/health

Overloaded/unhealthy gateway receives penalty or is removed from candidate set.

## Acceptance result

Client ingress can be geographically distributed without changing authority semantics.

---

# SM1-H7 — Gateway Rehome / Failure

## Goal

Prove that gateway failure is a transport/session problem, not a canonical gameplay ownership change.

## Core scenario

```text
Client -> G1 -> A
OperationId op-100 forwarded to A
G1 dies before result reaches client
Client reconnects/re-homes through G2
Client retries op-100
canonical commit count = 1
```

## Requirements

- same PlayerEntityId;
- same logical ClientSessionId or controlled resumed session identity;
- no player duplicate;
- no ownership transfer merely because gateway changed;
- exactly-once canonical operation semantics survive path change;
- route state can be reconstructed from Directory/current authority.

## Tests

- gateway crash before forwarding;
- after forwarding/before result;
- after result persisted but before delivery;
- repeated rehome;
- old gateway restarts with stale route state;
- two gateways temporarily receive client retry traffic with same OperationId.

## Acceptance result

The edge tier can fail without becoming part of canonical gameplay truth.

---

# SM1-H8 — Production Projection / AOI / Interest Aggregation

## Goal

Turn research view composition into bounded production relevance behavior.

## Requirements

- explicit client interest anchors;
- per-authority projection subscriptions;
- fine/coarse representation levels;
- bandwidth budgets;
- stale/degraded policy;
- merged upstream interest where many clients request the same source;
- subscription teardown when no longer needed.

## Tests

- 1/10/100 clients with overlapping interests;
- verify upstream subscription count does not grow linearly when mergeable;
- bandwidth budget deterministic downgrade;
- source loss with stale coarse cache;
- rapid enter/leave without projection leak;
- authority epoch change invalidates incompatible cached projection.

## Acceptance result

Borders can be visually hidden without full-world replication or one subscription per client/object.

---

# SM1-H9 — Cross-Authority Interaction Foundation

## Goal

Prove explicit semantics for operations involving state owned by another authority.

Start with bounded cases, not Construction/Matter-wide distributed transactions.

Suggested first cases:

1. player@A interacts with item@B;
2. player@A targets a simple world object@B;
3. operation retries while target owner changes B->C.

## Requirements

- targeted directory route resolution;
- expected owner/epoch/revision in operation envelope;
- stale target rejection and deterministic re-resolve/retry policy;
- no gameplay broadcast-to-all;
- end-to-end OperationId;
- no second Item Graph.

## Tests

- target ownership changes between lookup and commit;
- delayed operation reaches stale owner;
- duplicate cross-authority operation through two gateways;
- target unavailable;
- observer projection says item exists but canonical owner rejects stale revision.

## Acceptance result

Cross-border gameplay exists as an explicit protocol, not accidental remote-object mutation.

---

# SM1-H10 — Bounded InteractionIsland Runtime

## Goal

Introduce one conservative, testable interaction grouping use case.

Recommended first island:

```text
vehicle/ship
+ pilot
+ passenger(s)
+ mounted component(s)
+ bounded cargo/attached object set
```

Use existing moving/nested reference-frame knowledge as a donor.

## Requirements

- `InteractionIslandId != SpatialCellId`;
- versioned membership generation;
- one owner authority for the island when co-location policy requires it;
- explicit join/leave rules;
- whole-island transfer or deterministic blocked state during transition;
- no automatic arbitrary graph partitioner yet.

## Tests

### Cell crossing

Entire island crosses a spatial boundary while remaining one authority domain.

### Membership change

Passenger enters/leaves during stable ownership.

### Handoff race

Membership change races with island transfer; outcome must be deterministic/replay-safe.

### Invalid split

A co-location-required island must never end with ship owner B, pilot owner A, attached cargo owner C.

### Restart

Owner restart and target restart during island transfer.

## Acceptance result

Simulation locality can differ from geographic cell boundaries.

---

# SM1-H11 — Static N-Authority World

## Goal

Move from bounded A/B assumptions to a real static mesh of several authorities.

Recommended progression:

```text
3 authorities
-> 4 authorities
-> configurable N in model/process harness
```

Acceptance does not require thousands of processes; it requires topology-generic contracts and absence of hardcoded A/B routing.

## Requirements

- Directory routes arbitrary authority IDs;
- gateway subscribes only to relevant authorities;
- route planning has no required full mesh;
- multiple simultaneous handoffs can occur in disjoint domains;
- fault in C does not stop unrelated A/B paths;
- N does not imply N backend connections per client.

## Tests

- A->B->C route progression;
- simultaneous A->B and B->C in independent subjects;
- authority C outage;
- new authority registration/draining;
- random deterministic topology scenarios;
- connection-count assertions.

## Acceptance result

Static server mesh is topology-generic, not an expanded two-server fixture.

---

# SM1-H12 — Static Mesh Failure / WAN / Scale Acceptance

## Goal

Close production static-mesh correctness and operational evidence before any dynamic allocator is allowed.

## Matrix dimensions

### Network

- latency;
- jitter;
- loss;
- duplicate;
- reorder;
- bandwidth limit;
- queue pressure;
- asymmetric links;
- partitions.

### Process faults

- source authority crash;
- target authority crash;
- unrelated authority crash;
- gateway crash;
- Directory restart;
- draining/restart;
- stale process incarnation.

### Concurrency

- repeated crossings;
- simultaneous crossings;
- cross-authority operations during handoff;
- gateway rehome during handoff;
- projection delay/reorder during handoff.

### Scale

- increasing clients;
- increasing logical routes;
- increasing projection subscriptions;
- bounded physical upstream connection counts;
- backpressure isolation;
- long soak.

## Static SM1 acceptance claims allowed

If all gates pass, the project may claim:

- productionized ownership/handoff semantics on current product baseline;
- durable canonical Ownership Directory;
- non-authoritative regional Edge Gateway model;
- stable client session across tested authority handoff;
- read-only multi-authority projections/AOI;
- bounded cross-authority interactions;
- bounded InteractionIsland semantics;
- static topology-generic multi-authority world;
- bounded fault/restart/WAN evidence.

## Claims still forbidden

- automatic dynamic split/merge;
- optimal global load balancing;
- arbitrary interaction-island partitioning;
- unlimited arbitrary-many-server scale;
- production global edge deployment merely from simulated WAN tests.

---

# SM-D1 — Dynamic AuthorityDomain Placement

## Preconditions

Static SM1 accepted.

## Goal

Move existing bounded authority domains between available server processes based on explicit placement policy, without changing domain boundaries.

This is Dynamic V1: **placement changes, partition structure does not**.

## Inputs

- compute load;
- memory;
- network cost;
- client latency distribution;
- interaction cut estimate;
- migration cost;
- server health/draining;
- cooldown/hysteresis.

## Tests

- beneficial move accepted;
- small/noisy benefit rejected;
- high cut-cost move rejected;
- cooldown prevents ping-pong;
- server drain reassigns domains safely;
- allocator failure cannot grant ownership itself;
- placement decision still commits through normal ownership/transfer protocol.

---

# SM-D2 — Dynamic Split / Merge

## Preconditions

SM-D1 accepted with stable placement behavior.

## Goal

Change authority-domain partition boundaries under controlled load.

This stage must define:

- split proposal;
- new domain identities/generations;
- membership cut;
- transfer ordering;
- merge proposal;
- rollback/recovery;
- projection continuity;
- operation routing while topology changes.

Do not begin this stage as an optimization patch to D1; it is a separate distributed transaction problem.

---

# SM-D3 — Interaction-Aware Dynamic Meshing

## Preconditions

SM-D2 accepted and InteractionIsland semantics mature.

## Goal

Use interaction topology as a first-class partition/placement signal.

Potential algorithmic inputs:

```text
interaction graph
collision/constraint graph
operation frequency
bandwidth between subjects
latency sensitivity
island lifetime
migration cost
server load
```

The system may dynamically form/move/split safe simulation groupings where evidence proves correctness and benefit.

This is an R&D milestone, not a near-term product promise.

---

# 5. Cross-cutting acceptance rules

Every code-bearing SM checkpoint should include, where applicable:

```text
contract tests
negative/bypass tests
replay/duplicate tests
real multi-process scenario
restart/crash tests
network-condition simulation
full network regression
full world/gameplay regression
main scene smoke
machine-readable result
exact code-under-test SHA
changed-file overlay
fresh independent review
final verifier for risk level when required by Project Control
```

A visual demo is never enough to waive an ownership/fencing failure.

# 6. Branching strategy

Research branch:

```text
research/seamless-world-architecture-r1
```

Future production branches should be created per activated checkpoint from the exact accepted predecessor lineage. Do not create one long-lived mutable `feature/sm1-everything` branch spanning the full program.

Each milestone should be independently reviewable and should leave a clear accepted carrier/evidence checkpoint.

# 7. How this roadmap changes prior plans

This roadmap does not immediately rewrite historical accepted roadmaps. It is a candidate successor architecture that should be incorporated only through the project's normal control process.

The important conceptual changes are:

1. client direct active+warm authority routes move behind Edge Gateway;
2. many geographic gateways are planned from the start;
3. production ownership gets a formal CAS/fencing Directory;
4. `DIRECTORY_COMMITTED` becomes the ownership linearization point;
5. `InteractionIsland` is independent of spatial cells;
6. `AuthorityDomain` becomes the first dynamic-placement granularity;
7. cross-authority gameplay is its own milestone;
8. static N-authority world is a complete success milestone;
9. dynamic balancing is explicitly later and interaction-cost-aware.

# 8. Program success definition

A good seamless world is not “many servers are running”. It is a world where the following remain true simultaneously:

```text
client topology is simple
canonical ownership is unambiguous
server handoff survives faults
visual overlap is read-only
physical/interaction locality can differ from map cells
cross-boundary gameplay has explicit semantics
edge/network scale does not multiply connections naively
static multi-authority world is stable
and only then dynamic placement is introduced
```

That is the development path this roadmap is designed to protect.