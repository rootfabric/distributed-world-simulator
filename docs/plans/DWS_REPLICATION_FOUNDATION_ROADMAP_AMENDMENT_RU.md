# DWS — Replication Foundation Roadmap Amendment

**Status:** PROPOSED / ROADMAP CHANGE  
**Date:** 2026-08-30  
**Base:** `main @ acb9379cacc413fc25a65117fb1627f5a01b9736`  
**Runtime changes in this amendment:** NONE  
**ADR:** `docs/architecture/adr/ADR-021-non-canonical-replication-plane.md`

## 1. Motivation

DWS already has transport-neutral replication contracts, client replica stores, M0/M6 durability and outbox, MW6/MW7 replication+interest, MW8/MW9 handoff/recovery, SM1 WARM/SHADOW, EG4 projections and RL representation streaming.

The remaining gap is narrow: realtime read-only replica/cache lifetime is not yet expressed as a shared topology-neutral substrate independent from one Authority/Gateway/consumer process lifecycle.

The goal is to make later scaling simpler, not to make the current product more distributed.

## 2. Current product position

```text
P4 Real Resource Construction        ACCEPTED
P5 Equipment / Tools                 ACCEPTED
P6 Persistent Shared Outpost         ACCEPTED
Edge Gateway Foundation              ACCEPTED
SM1 runtime R9                       MERGED TO MAIN
SM1 checkpoint control acceptance    PENDING
P7 Bounded Terrain Mutation          BLOCKED ON SM1 ACCEPTANCE
P8 First Mobile Construct            FUTURE
```

SM1 runtime merge: PR #327, source `b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f`, main merge `acb9379cacc413fc25a65117fb1627f5a01b9736`, tree `7af1fe08e1f92e3b77a4b12dbccbb96c48e93a68`.

SM1 closure/control remains separate: PR #326, branch `control/v0-sm1-b7-final-reconciliation-r2`, HEAD `3c7b395d351fa520c144240561b75dd9ef34170d`, OPEN/DRAFT at this refresh.

```text
SM1 runtime merged != SM1 checkpoint accepted
```

RF work must not overwrite or bypass this lifecycle.

## 3. Existing overlap

### Already exists

- `ReplicationTransportPort` and `ReplicationEnvelope`;
- entity/aggregate snapshot and delta contracts;
- owner/epoch/revision/tick/checksum fencing;
- duplicate/conflict handling and gap/resync semantics;
- M0 transaction outbox and M6 durable recovery;
- MW6 full Matter replication and MW7 regional interest replication;
- MW8/MW9 authority handoff and crash recovery;
- P6/SM1 WARM/SHADOW;
- EG4 interest/projection aggregation;
- RL representation-aware streaming;
- S1 proposal-only worker boundary.

### Needs generalization

- post-commit publication contract;
- bounded retained non-canonical replica;
- shared read-only consumer port;
- common reconstructability/stale/duplicate/gap rules.

### Must not be built

- second persistence, Directory, authority registry, Item Graph or Construction truth;
- new canonical player state;
- mandatory broker/distributed DB;
- dynamic placement controller.

## 4. Roadmap insertion

Chosen option: **semantic foundation now, runtime later**.

### Before

```text
SM1 acceptance
    ↓
P7
    ↓
P8
    ↓
future scale-out
```

### After

```text
SM1 acceptance
    │
    ├── RF0 Replication Semantic Boundary
    │      architecture/contracts only
    │      NON-BLOCKING FOR P7
    │
    ▼
P7 Bounded Terrain Mutation
    ↓
P8 First Mobile Construct
    ↓
RF1 Shadow Retained Replica Cache
    ↓
RF2 First Read-Only Consumer
    │
    ├── NX8 Interest/Budget convergence
    └── PO0 Placement Observatory / SHADOW
    ↓
static N-authority scale
    ↓
dynamic placement / split / merge — FUTURE
```

RF0 is a guardrail, not a product checkpoint and not a runtime mutation checkpoint.

## 5. RF0 — Replication Semantic Boundary

**Goal:** freeze `accepted canonical commit -> ReplicationPublication -> read-only non-canonical consumer`.

**Reuse:** `ReplicationTransportPort`, `ReplicationEnvelope`, aggregate/entity snapshot+delta contracts, M0/M6/MW outbox and durability boundaries.

**Runtime budget:** 0 gameplay behavior changes, 0 production processes, 0 network hops, 0 persistent owners, 0 canonical state.

**Non-goals:** cache service, Gateway migration, WARM migration, player movement changes, protocol rewrite, transport selection, dynamic placement.

**Acceptance:** machine guards prove Gateway/Directory/AuthorityEpoch/Persistence/OperationId/ItemGraph/Construction/Matter owners unchanged, S1 worker remains proposal-only, SM1 behavior unchanged, full regression PASS.

## 6. RF1 — Shadow Retained Replica Cache

```text
Authority
    ├── legacy replication path
    └── shadow committed publication
                 ↓
          RetainedReplicaCache
```

No production consumer depends on RF1 yet. The cache keeps latest accepted snapshot plus bounded recent deltas and existing authority/revision/checksum identity.

Required acceptance:

```text
legacy revision == shadow revision
legacy checksum == shadow checksum
legacy epoch == shadow epoch
duplicate same identity/checksum => idempotent
same identity/different checksum => FAIL CLOSED
stale epoch => reject
revision rollback => reject
delta gap => snapshot required
cache memory/history <= configured bounds
delete full cache => canonical world unchanged
rebuild => exact canonical revision/checksum
```

Process-kill lab additionally proves that the read-only cache can outlive an Authority process and then converge to the replacement Authority restored from canonical durability.

RF1 may remain process-local in production; a separate process is required only for lifecycle-decoupling tests unless metrics later justify deployment separation.

## 7. RF2 — First Read-Only Consumer

Preferred first consumer: `WORLD_PROJECTION / Gateway projection path`.

```text
Authority
→ Replication Boundary
→ RetainedReplicaCache
→ EG4 projection adapter
→ Gateway
→ Client
```

Excluded from RF2: Client input, player movement authority, OperationId ownership, authority transfer decision, WARM promotion and Directory decisions.

Acceptance:

```text
RF projection checksum == legacy projection checksum
projection-cache outage does not stop canonical gameplay
stale projection rejected
Gateway canonical writes == 0
client_active_world_transports == 1
movement path gains no RF hop
```

## 8. NX8 convergence

RF owns publication semantics, retained non-canonical state and the read-only distribution boundary.

NX8 remains owner of selection policy: what a consumer receives, priority, bandwidth budget, dirty scheduling, starvation protection and interest hysteresis.

Common vocabulary may include spatial scope, representation class, LOD/detail need, priority, consistency requirement, update frequency, bandwidth budget and revision.

`InterestSet != ActivationSet`.

## 9. Representation integration

RF must support multiple representation classes and must not require `everything == entity`. Consumers may receive full entities, aggregate snapshots, Matter regional projections, population/cohort summaries, regional summaries or macro/HLOD representations. Representation remains derived and disposable.

## 10. PO0 — Placement Observatory

A later independent lane may run with:

```text
mode = SHADOW
execution_enabled = false
```

It may observe CPU/tick load, players, aggregates, physics bodies, replication bandwidth, cross-authority interactions, ghost/projection traffic, handoff size/duration and churn, and produce placement proposals only.

```text
Replication Plane != Dynamic Server Meshing
Placement Observatory != Placement Controller
```

## 11. Failure matrix

RF1/RF2 must cover Authority crash, cache crash, Gateway crash, consumer crash, partition, delayed/duplicate/reordered publication, stale authority publication, handoff during delay, cache restart, total cache deletion, slow consumer and delta gaps.

## 12. Test strategy

```text
L0 contracts
unit
property/fuzz
runtime integration
multi-process
fault injection
repeated runs
full regression
```

Recovery/handoff stages require process-kill tests.

## 13. Complexity budget

| Stage | New concepts | Runtime components | Persistent state | New protocols | New production processes | Mandatory hops |
|---|---:|---:|---:|---:|---:|---:|
| RF0 | 2-4 semantic surfaces | 0 | 0 | 0 | 0 | 0 |
| RF1 | 1 bounded cache | 1 logical | 0 | preferably 0 | 0 | 0 |
| RF2 | 1 consumer adapter | 1 adapter | 0 | 0 | 0 initially | projection only |

Any proposal exceeding this budget requires a new architecture decision.

## 14. Activation rules

RF0 can be documented now but MUST NOT consume the V0 runtime mutation lease or block P7. Formal product sequencing remains `SM1 checkpoint accepted -> P7 eligible`.

RF1 requires a fresh Work Order after SM1 closure, explicit owner mapping and proof that P7/P8 product sequencing is not being delayed. RF2 starts only after RF1 shadow evidence is accepted.

## 15. Rollback

RF0: remove the semantic boundary; no runtime state exists.

RF1: disable shadow publication and delete cache; legacy path remains active.

RF2: return the read-only consumer to the legacy projection source and delete RF cache; canonical state remains unchanged.

## 16. Deferred work

Do not schedule yet: dedicated Replication Plane service, RF sharding, persistent replica DB, Kafka/NATS/Redis/etcd requirements, RAFT/Paxos, Kubernetes/Agones placement, automatic authority placement, split/merge, interaction-aware dynamic meshing or a global relation graph.

## 17. North Star

```text
BUILD THE BOUNDARY BEFORE THE DISTRIBUTED SYSTEM
PROVE STATIC CORRECTNESS BEFORE DYNAMIC PLACEMENT
REPLICATION IS NOT AUTHORITY
CACHE IS NOT PERSISTENCE
INTEREST IS NOT ACTIVATION
SERVER PROCESS IS NOT WORLD IDENTITY
```