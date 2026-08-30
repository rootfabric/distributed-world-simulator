# ADR-021 — Non-Canonical Replication Plane

**Status:** ACCEPTED / ROADMAP-BOUNDARY ONLY  
**Date:** 2026-08-30  
**Owner:** global architecture / main  
**Runtime activation:** NONE  
**Related:** M0, M6, MW6-MW10, SM1, Edge Gateway, NX8, Representation LOD Fabric

## Context

DWS already has mature replication and recovery building blocks:

- transport-neutral `ReplicationTransportPort`;
- `ReplicationEnvelope` with SNAPSHOT/DELTA/GHOST/INTEREST kinds;
- entity and aggregate snapshot/delta envelopes with owner/epoch/revision/tick/checksum identity;
- client replica stores;
- MW6 full Matter replication;
- MW7 regional interest replication, replay-gap detection and snapshot resync;
- M0/M6 durable commit + outbox + replay/recovery semantics;
- MW8/MW9 authority handoff and crash recovery;
- P6/SM1 WARM/SHADOW read-only state;
- EG4 interest/projection aggregation;
- RL representation-aware streaming and disposable representation caches.

Therefore DWS does **not** need a second replication stack or a new canonical owner.

The remaining gap is narrower: realtime read-only replica/cache lifetime is still tied to domain-specific Authority, Gateway or consumer process paths. There is no shared topology-neutral post-commit publication boundary with a bounded reconstructable retained replica that can serve several read-only consumers.

## Decision

Introduce a logical **Replication Plane** as a semantic boundary.

The initial architecture is:

```text
canonical mutation
    ↓
Authority validation
    ↓
accepted canonical commit boundary
    ↓
ReplicationPublication
    ↓
RetainedReplicaCache
    NON-CANONICAL / BOUNDED / RECONSTRUCTABLE
    ↓
read-only consumers
```

The first implementation MUST NOT require a separate process.

Preferred semantic surfaces:

```text
CommittedReplicationBoundary
ReplicationPublication
RetainedReplicaCache
ReplicationReadPort
```

A physical `DomainReplicationPlane` service is deferred until metrics prove a process boundary is useful.

## Hard invariants

```text
REPLICATION IS NOT AUTHORITY
CACHE IS NOT PERSISTENCE
INTEREST IS NOT ACTIVATION
SERVER PROCESS IS NOT WORLD IDENTITY
SIMULATION AUTHORITY != PROJECTION PUBLISHER
```

Replication Plane MAY:

- consume already accepted committed state;
- retain latest snapshots;
- retain bounded recent deltas;
- fan out read-only state;
- serve projection consumers;
- assist reconnect/resync;
- feed WARM/standby hydration;
- assist recovery hydration;
- retain multiple representation classes.

Replication Plane MUST NOT:

- commit domain mutations;
- assign authority or leases;
- change AuthorityEpoch;
- linearize handoff;
- mint canonical OperationId truth;
- own Item Graph;
- own Construction;
- own Matter;
- own Persistence;
- own Directory truth;
- execute gameplay mutation;
- allow Simulation Workers to publish canonical state directly.

## Authority precedence

If replication evidence conflicts with canonical authority evidence:

```text
Directory / canonical Authority wins
Replication observation becomes stale
```

A stale publication from `A/epoch7` arriving after `B/epoch8` MUST be rejected.

## Commit boundary

Existing durable semantics remain authoritative.

Where a domain already uses:

```text
mutation
→ durable commit/checkpoint/outbox
→ ACK / durable publication
```

Replication MUST consume only the accepted post-commit output and MUST NOT move that boundary earlier.

Realtime presentation may use an explicitly classified non-durable authoritative-visible stream where existing netcode already does so, but such data can never become recovery authority.

Two consistency classes are therefore allowed:

- `AUTHORITATIVE_VISIBLE` — valid for presentation, not sufficient to recover canonical write authority;
- `DURABLE_COMMITTED` — anchored to existing persistence/outbox semantics and usable for recovery acceleration after revalidation.

### Activation safety fence

Neither consistency class is authority proof.

```text
AUTHORITATIVE_VISIBLE
MUST NEVER authorize recovery activation
MUST NEVER promote WARM → ACTIVE
MUST NEVER prove authority ownership
MUST NEVER advance AuthorityEpoch
MUST NEVER override Directory truth

DURABLE_COMMITTED
MUST NEVER promote WARM → ACTIVE by itself
```

Replica/cache hydration may prepare read-only or WARM state, but activation still requires canonical evidence:

```text
Directory truth
+ exact owner/lease
+ AuthorityEpoch/fence
+ canonical transfer or recovery validation
```

`cache state != proof of authority`.

## Reconstructability invariant

The strongest correctness property is:

```text
delete all Replication Plane state
→ canonical world remains correct
→ rebuild from Authority/Persistence
→ same canonical revision/checksum
```

If deleting the replica cache destroys world truth, the design is rejected.

## Ordering semantics

Reuse existing identities whenever possible:

```text
subject/aggregate identity
authority_owner_id
authority_epoch
state revision
server_tick
snapshot/delta identity
base_revision
checksum
publication sequence when needed
```

Required behavior:

- duplicate same identity + same checksum => idempotent;
- same canonical identity + different checksum => conflict / fail closed;
- stale epoch => reject;
- revision rollback => reject;
- delta base gap => do not apply; request/resynthesize snapshot;
- reordered old publication => reject;
- newer owner/epoch never rolls back to older owner/epoch.

## Fast path

The latency-critical input path remains:

```text
Client
→ Edge Gateway
→ active Authority
```

The Replication Plane MUST NOT be inserted into gameplay command ingress.

Initially player movement state MAY continue:

```text
Authority
→ Gateway
→ Client
```

while bulk/read-only state may later use:

```text
Authority
→ Replication Boundary
→ Gateway / projection consumer
```

## Interest boundary

RF does not become the owner of interest policy.

Existing MW7, EG4, RL and future NX8 mechanisms remain valid. RF0 only standardizes a shared vocabulary where useful:

- spatial scope;
- representation class;
- LOD/detail requirement;
- priority;
- consistency requirement;
- update frequency;
- bandwidth budget;
- revision.

`InterestSet` and `ActivationSet` remain distinct.

## Placement boundary

Replication Plane is not Dynamic Server Meshing.

A future Placement Observatory may read telemetry and generate proposals, but:

```text
Placement Observatory != Placement Controller
EXECUTION = FALSE
```

Dynamic placement, split/merge and interaction-aware meshing remain future work after static multi-authority correctness.

## Consequences

Positive:

- prevents future consumers from binding directly to Authority-process lifetime;
- reuses existing replication contracts;
- enables shadow proof before migration;
- gives WARM/recovery/projection consumers one semantic boundary;
- keeps physical deployment simple today;
- creates a measurable path toward later multi-authority scale.

Costs:

- one new semantic concept;
- a bounded cache implementation at RF1;
- cross-domain ownership guards and tests;
- later convergence work with NX8.

Explicitly deferred:

- dedicated replication service;
- Kafka/NATS/Redis/etcd/RAFT/Paxos requirement;
- durable replication database;
- replication sharding;
- automatic placement;
- split/merge;
- GlobalWorldEntityGraph.

## Roadmap decision

The staged train is deliberately short:

```text
SM1 ACCEPTED
    ↓
RF0 Replication Semantic Boundary      architecture guardrail / no runtime
    ↓
P7 Matter Production Convergence       product integration, not a new Matter foundation
    ↓
V0 PLAYABLE SEAMLESS PLANET            COMPOSITION ACCEPTANCE
    ↓
    ├── P8 First Mobile Construct       PRODUCT LANE
    └── RF1 Shadow Retained Cache       REPLICATION LANE
             ↓
            RF2 First Read-Only Consumer
    ↓
static N-authority scale
    ↓
NX8 convergence / Placement Observatory
    ↓
future dynamic placement / split / merge
```

RF0 changes architecture/contracts only. RF1 and RF2 require separate implementation authorization and acceptance.


## P7 ownership guard

P7 MUST integrate the accepted Matter stack rather than introduce a second terrain subsystem.

```text
tool/equipment             → P5 / existing product action owner
local Matter mutation      → MW4
Matter persistence         → MW5
Matter replication         → MW6
Matter interest            → MW7
regional authority         → MW8
durable handoff/recovery   → MW9
multi-region Matter op     → MW10
representation/meshing     → RL2/RL3
material output            → MatterMaterialBatch
inventory truth            → canonical Item Graph
```

Creating `TerrainMutationRequest`, `TerrainMutationResult`, a P7-private Matter store,
persistence owner, replication protocol, authority directory or resource inventory is a stop condition.
