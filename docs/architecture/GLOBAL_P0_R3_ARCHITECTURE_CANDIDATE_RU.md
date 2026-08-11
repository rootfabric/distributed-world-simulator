# Distributed World Simulator — GLOBAL-P0 R3 Refresh R1

**Candidate revision:** `GLOBAL-P0-2026-08-12-R3-REFRESH-R1`  
**Parent:** `GLOBAL-P0-2026-08-10-R2`  
**Fresh base:** `main @ 1112d1f7cfad1df18fb3621a537e191e674848c6`  
**Registry:** `75`  
**Risk:** `CRITICAL`  
**Status:** `REFRESH IN PROGRESS / NO PROMOTION`

## 1. Purpose

R3 is the next global architecture revision for a long-lived distributed world. It does not replace the accepted Item, Matter, Construction, G, NX, M0, S1 or harness foundations. It defines the missing cross-domain contracts needed to connect them without creating duplicate global managers.

Target capabilities:

- planetary and interplanetary scale;
- mutable geology and material identity;
- very large semantic constructions;
- one or many authoritative servers;
- seamless authority handoff;
- moving ships/stations and nested reference frames;
- human and AI actors using the same world-operation path;
- aggressive LOD/dormancy without loss of canonical truth;
- query, lifecycle and work-budget fabrics that do not become new canonical stores or authorities.

Core rule:

> Everything expensive may reduce resolution; nothing important may reduce truth.

## 2. Current project boundary

This refresh is intentionally built from current main rather than the old R3 ancestry.

Current canonical state used by the candidate:

```text
H0.0     CANONICAL
H0.1 R6  fresh-current-main C22 pilot preparation on R2
G8       FULL ACCEPTED / FROZEN
T1B      HANDOFF COMPLETE
C22      SOURCE_ACCEPTED evidence; fresh convergence under H0.1
NX.C0    preparation; NX.C1 waits H0.1 PASS
MATTER   stable
S1       stable
ECO      Evolutionary Ecology research; PH3 accepted, PH3C Windows pending
```

**R3 promotion is forbidden while H0.1 R6 is an open R2 runtime checkpoint unless H0.1 is explicitly invalidated and rebuilt.** Preferred path: complete H0.1 to its checkpoint boundary, then promote R3 separately.

## 3. Canonical separation invariants

```text
CANONICAL WORLD != PRESENTATION
CANONICAL WORLD != TRANSPORT
CANONICAL WORLD != COMPUTE
CANONICAL WORLD != AUTHENTICATION
CANONICAL WORLD != QUERY INDEX
CANONICAL WORLD != SCHEDULER

AccountId != PlayerEntityId
PrincipalId != NetworkPeerId
SessionId != AuthorityLeaseId
Authorization != Authentication
ReferenceFrameId != AuthorityRegionId
SimulationTime != WallClock
DomainTick != NetworkTick
WorldQuery != CanonicalStore
WorldWorkBudget != Authority
Dormant != Deleted
MaterialDefinitionId != RenderMaterial
OrganizationClaim != ServerShard
AIPlanner != Authority
LLMOutput != WorldMutation
```

## 4. Existing truth owners remain canonical

R3 preserves existing ownership:

```text
MAIN/HARNESS  project/control/checkpoint authorization
ITEM          permanent item identity and Item Graph
MATTER        mutable authoritative material-volume truth
CONSTRUCTION  construct/part/bond truth
G             deterministic procedural natural baseline
NX            realtime transport/replication policy
AUTHORITY     authority leases/epochs/routing
M0            atomic multi-domain commit engine
S1            proposal-only distributed compute
R3/MW         persistence/replay/recovery semantics
```

No R3 foundation may absorb these owners by introducing a more global-sounding manager.

## 5. New P0 cross-domain foundations

### IAM — Identity and Session Fabric

Owns `AccountId`, `PrincipalId`, `SessionId`, actor bindings and provider-neutral authentication/session contracts.

It does **not** own PlayerEntityId, NetworkPeerId or AuthorityLease.

### AUTHZ — Authorization Fabric

One deny/allow decision boundary for principal/actor actions on resources. Domains still validate semantic preconditions and execute mutations.

### RF — Reference Frame Fabric

Stable frame identity and transforms for planets, ships, interiors and local physics.

```text
ReferenceFrameId != AuthorityRegionId
```

A ship may cross server boundaries without changing its frame identity.

### TF — Time Fabric

Separates simulation time, domain ticks, wall clock and network/presentation clocks.

### SD — Spatial Domain Fabric

Defines frame-aware `WorldAddress` mappings to domain-specific spatial identities without creating a universal `ChunkId`.

### MAT — Material Ontology

Defines canonical `MaterialDefinitionId` shared by geology, Matter, Item, Construction and environment projections.

```text
MaterialDefinitionId != RenderMaterial
```

G9 must wait for MAT0.

### WT — WorldOperation / WorldTransactionPlan

Compiles semantic cross-domain operations into the existing M0 transaction engine.

Example:

```text
MINE 10 kg iron
  -> Matter -10 kg material/iron
  -> Item   +10 kg material/iron
  -> M0 commit
```

WT never becomes a second transaction coordinator.

### WQ — World Query Fabric

Actor-scoped query planning over domain adapters. WQ owns no canonical world database.

### LIFE — Lifecycle Fabric

Shared vocabulary for abstract/dormant/simulated/active/presented states while preserving domain identity and truth.

### WB — World Work Budget

Chooses full/coarse/defer/batch/S1-dispatch policy. It does not grant authority and does not control the development harness.

### COMPAT — Compatibility Governance

Explicit schema/protocol/content/migration compatibility for a persistent universe.

### SEC — Security Boundaries

Cross-domain negative requirements, trust boundaries, query secrecy and abuse resistance.

## 6. Program-ID correction: ECO vs ECON

The old R3 candidate used `ECO` for economy. The live project now uses `ECO` for **Evolutionary Ecology**.

Fresh R3 resolves the collision:

```text
ECO   = Evolutionary Ecology
ECON  = future World Economy / Markets / Contracts
```

ECO research may later consume MAT/TF/LIFE/WB/environment adapters. ECON consumes Item/MAT/WT physical resource truth and must not create duplicate accounting.

## 7. Mandatory intersections

```text
IAM  -> AUTHZ/NX/ORG       session continuity never redefines actor identity
RF   -> SD/SP/NX/G         frame identity never implies authority routing
TF   -> ENV/AI/POP/ECO     simulation time never becomes work scheduler
MAT  -> G9/Matter/Item/... one material identity, domain projections remain owned
WT   -> Item/Matter/C22    compile to M0, never create second commit engine
WQ   -> AI/NAV/ECO/ECON    query is actor-scoped and non-authoritative
LIFE -> RL/POP/ECO         dormancy preserves canonical identity
WB   -> G/S1/NX/AI/...     budget != authority
H0   -> all runtime work   development authorization != runtime scheduling
AI   -> AUTHZ/WQ/WT        human and AI actors use the same mutation path
```

## 8. R2 -> R3 transition

The candidate does not relabel accepted history.

1. Frozen R2 evidence stays valid evidence-only.
2. Active R2 runtime work must finish at a checkpoint boundary or be explicitly invalidated/refreshed before R3 promotion.
3. All runtime branches created after promotion use canonical R3 from then-current main.
4. Research/advisory branches may remain historical R2 evidence; production promotion requires a fresh R3 frontier.
5. Stable foundations remain owners; R3 adds adapters/contracts only where named intersections require them.
6. Wave A must start from one accepted canonical R3 base.
7. Promotion is control-only, PC0 NON_RED and human-gated.

The machine-readable policy is `config/control/global-p0-r2-to-r3-transition-policy.v1.json`.

## 9. Wave A after promotion

Maximum four new foundation frontiers at once:

```text
IAM0 / IAM1
MAT0
WT0
WQ0 / WQ1
```

These are primarily contracts, validators, deterministic fixtures and adapters. They must not rewrite current gameplay/runtime merely to adopt new names.

## 10. Wave B

After first contract freeze:

```text
RF0 / RF1
TF0
AUTHZ0
LIFE0
WB0 / WB1
COMPAT0
```

`SD0` follows RF0 shape.

## 11. Reserved production work

Not authorized by this candidate:

```text
distributed SD routing
production global TF scheduler
production global WB arbiter
WT cross-authority commit
distributed WQ fan-out
GM production
SP interplanetary handoff
ENV large-scale atmosphere
AI LLM execution
POP runtime
ECON markets
OPS migrations
dynamic shard split/merge
```

## 12. Promotion checkpoint

Target is only:

```text
R3_REFRESHED_CANDIDATE
```

Required before that checkpoint can be proposed:

```text
CURRENT_MAIN_REFRESH                         DONE by construction
CRITICAL_RISK_CLASSIFIED                    DONE
DESIGN_BRIEF_READY                          DONE
FRONTIER_GUARDS_REFRESHED                   DONE
R2_TO_R3_TRANSITION_POLICY_IMPLEMENTED      DONE
OWNERSHIP_INTERSECTION_REVIEW_PASS          PENDING
EVIDENCE_MAP_COMPLETE                       PENDING
REVIEWER_VERDICT_PASS                       PENDING
PC0_NON_RED                                 PENDING
HUMAN_ATTENTION_ITEM_IF_REQUIRED            PENDING/NOT YET REQUIRED
```

After `R3_REFRESHED_CANDIDATE`, stop. Canonical promotion requires a separate explicit:

```text
GLOBAL_ARCHITECTURE_PROMOTION
```

No promotion is authorized by this branch.
