# Distributed World Simulator — GLOBAL-P0 R3 Refresh R1

**Candidate revision:** `GLOBAL-P0-2026-08-12-R3-REFRESH-R1`  
**Parent:** `GLOBAL-P0-2026-08-10-R2`  
**Current finalization base:** `main @ f6d68fc7c594b371f48a9bcff056e2478e04f317`  
**Current registry:** `78`  
**Risk:** `CRITICAL`  
**Status:** `FROZEN MUTABLE REVIEW TARGET / NO PROMOTION`

Historical construction provenance is preserved separately and is never authorization:

```text
construction main     1112d1f7cfad1df18fb3621a537e191e674848c6
construction registry 75
```

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

This candidate is finalized against the current canonical post-C22 state, not against its historical construction snapshot.

Current canonical state used for finalization:

```text
main      f6d68fc7c594b371f48a9bcff056e2478e04f317
registry  78
arch      GLOBAL-P0-2026-08-10-R2

H0.0      CANONICAL
H0.1 R8   H0_1_PASS
C22       MAIN_INTEGRATED
H0.1 slot RELEASED
G8        FULL ACCEPTED / FROZEN
T1B       HANDOFF COMPLETE
CH9.6     ACCEPTED / FROZEN
NX.C0     preparation only
NX.C1     BLOCKED until canonical R3 + post-R3 PC0 + fresh H0.2 dispatch
MATTER    stable
S1        stable
ECO       PH research complete; CONV0-A design-only; advisory/nonblocking
```

`C22 MAIN_INTEGRATED` authorizes only this R3 finalization sequence. It does **not** authorize NX.C1, R3 promotion, H0.3, V0, G9, TS0.4 or T2.0.

### Historical construction provenance only

The candidate was originally constructed while the repository was at:

```text
main      1112d1f7cfad1df18fb3621a537e191e674848c6
registry  75
H0.1      R6 preparation
C22       not yet MAIN_INTEGRATED
ECO       earlier research frontier
```

Those facts remain useful only for provenance. They are intentionally not rewritten as if the old preparation happened on generation 78, and they must not be read as current project state or authorization.

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
2. Active R2 runtime work must finish at a checkpoint boundary or be explicitly invalidated/refreshed before R3 promotion. H0.1 has now reached that boundary and released the runtime slot.
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

## 12. Finalization and promotion boundary

This candidate describes a stable review/promotion boundary and does not encode the current repair iteration, a repair-specific checkpoint, or post-freeze evidence state as candidate-internal mutable truth.

The lifecycle is:

```text
frozen mutable R3 target
        ↓
external exact-head Project Control
        ↓
standard PC0 NON_RED
directional PC0 NON_RED
        ↓
external Evidence Map bound to exact target
        ↓
INDEPENDENT_REVIEW_READY
        ↓
Independent Reviewer PASS
        ↓
Independent Verifier PASS
        ↓
Director final gate PASS
        ↓
R3_REFRESHED_CANDIDATE_READY
        ↓
HUMAN GLOBAL_ARCHITECTURE_PROMOTION
        ↓
mandatory post-R3 PC0
```

The candidate-side requirements are stable invariants rather than repair-iteration state:

```text
CURRENT_MAIN_REFRESH                         REQUIRED
CURRENT_REGISTRY_REFRESH                     REQUIRED
C22_MAIN_INTEGRATED                         REQUIRED
H0_1_RUNTIME_SLOT_RELEASED                  REQUIRED
CRITICAL_RISK_CLASSIFIED                    REQUIRED
DESIGN_BRIEF_READY                          REQUIRED
FRONTIER_GUARDS_REFRESHED                   REQUIRED
R2_TO_R3_TRANSITION_AUDIT_PASS              REQUIRED ON EXACT MUTABLE TARGET
OWNERSHIP_INTERSECTION_REVIEW_PASS          REQUIRED ON EXACT MUTABLE TARGET
RUNTIME_SURFACE_ZERO                        REQUIRED ON EXACT MUTABLE TARGET
CRITICAL_CROSS_BRANCH_OVERLAP_ZERO          REQUIRED ON EXACT MUTABLE TARGET
EXTERNAL_EXACT_HEAD_PROJECT_CONTROL_SUCCESS REQUIRED
STANDARD_PC0_NON_RED                        REQUIRED EXTERNAL EVIDENCE
DIRECTIONAL_PC0_NON_RED                     REQUIRED EXTERNAL EVIDENCE
EVIDENCE_MAP_BOUND_TO_EXACT_HEAD            REQUIRED EXTERNAL EVIDENCE
INDEPENDENT_REVIEWER                        DISTINCT ROLE / REQUIRED BEFORE CANDIDATE READY
INDEPENDENT_VERIFIER                        DISTINCT ROLE / REQUIRED BEFORE CANDIDATE READY
DIRECTOR                                    DISTINCT ROLE / REQUIRED BEFORE CANDIDATE READY
HUMAN_GLOBAL_ARCHITECTURE_PROMOTION         SEPARATE HUMAN GATE
POST_R3_PC0                                 REQUIRED AFTER HUMAN-AUTHORIZED PROMOTION
```

`Project Control`, PC0 results, Evidence Map completion, Reviewer/Verifier/Director verdicts and exact review-target SHAs are external lifecycle evidence. They must be bound to the frozen target without being copied back into this immutable candidate as pass/pending state.

Independent Reviewer and Independent Verifier must produce separate durable PASS evidence against the exact frozen target. A separate Director final gate is then required before:

```text
R3_REFRESHED_CANDIDATE_READY
```

may be declared. Neither Reviewer nor Verifier declares the ready-state, and the Director final gate does not perform the Human promotion.

Canonical promotion still requires a separate explicit:

```text
GLOBAL_ARCHITECTURE_PROMOTION
```

No promotion is authorized by this branch, this document, Project Control, or an Evidence Map.
