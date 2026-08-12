# GLOBAL-P0 R3 — Parallel Implementation Plan (Refresh R1)

**Candidate:** `GLOBAL-P0-2026-08-12-R3-REFRESH-R1`  
**Base:** `main @ 1112d1f7cfad1df18fb3621a537e191e674848c6`  
**Registry:** `75`  
**Promotion:** forbidden in this plan

## 1. Immediate project rule

R3 preparation may run in parallel with H0.1/C22, but R3 promotion may not invalidate the active H0.1 R2 checkpoint.

Current primary runtime/control sequence is:

```text
             CURRENT PRIMARY
                   │
                   ▼
             H0.1 / C22
                   │
                   ▼
              H0_1_PASS
                   │
                   ▼
      HUMAN: C22 runtime merge
                   │
                   ▼
            post-C22 PC0
                   │
                   ▼
         C22 MAIN_INTEGRATED
                   │
                   ▼
         GLOBAL-P0 R3 promotion
                   │
                   ▼
             post-R3 PC0
                   │
                   ▼
            H0.2 / NX.C1
                   │
                   ▼
         NX SOURCE_ACCEPTED
                   │
                   ▼
                 H0.3
      multi-runtime-worker scheduler
                   │
                   ▼
       H0_3_ORCHESTRATION_ACCEPTED
                   │
                   ▼
            capability fan-out
                   │
          NET / GEO-MAT / WT-WQ
                   │
                   ▼
              V0 composition
```

R3 architecture preparation therefore remains parallel, but **runtime progression is serialized at the named checkpoint boundaries**.

```text
H0.1 / C22 runtime train          GLOBAL-R3 architecture train
        |                                  |
        |                                  +-- refresh ownership
        |                                  +-- transition policy
        |                                  +-- evidence/review/PC0
        |                                  |
        +-- reach checkpoint boundary      +-- R3_REFRESHED_CANDIDATE
                         \                 /
                          \               /
                           +-- human promotion gate
                                      |
                                      +-- post-R3 PC0
                                      |
                                      +-- H0.2 / NX.C1
                                      |
                                      +-- H0.3
```

## 2. Activation classes

```text
A CONTRACT_NOW
  DTO/value objects/interfaces/validators/fakes/tests only

B ADAPTER_NOW
  adapters around accepted domains, no truth migration

C PRODUCTION_AFTER_GATE
  runtime only after named dependencies converge

D RESERVE_ONLY
  ownership reserved, no implementation yet
```

The fresh candidate itself creates no new runtime branch.

## 3. Wave A — only after canonical R3 promotion

Maximum four new foundation frontiers.

These frontiers may progress in parallel with the primary H0.2/H0.3 runtime train where control-plane worker limits permit, but they do not replace that train.

### IAM0 / IAM1 — Identity and Session

Class: A/B

Implement later:

```text
AccountId
PrincipalId
SessionId
ActorBinding
AuthenticationResult
SessionClaims
IdentityProviderPort
LocalIdentityProvider
```

Acceptance:

- reconnect changes SessionId without changing AccountId;
- network peer ID never becomes account identity;
- session expiration/revocation fails closed;
- gameplay stores are not imported into IAM.

### MAT0 — Material Ontology

Class: A

Implement later:

```text
MaterialDefinitionId
MaterialDefinition
MaterialPropertySet
MaterialRegistryPort
MaterialProjectionDescriptor
```

Fixture identities may include water, ice, oxygen, nitrogen, iron, steel, basalt, granite and soil. They are test fixtures, not final scientific content.

Acceptance:

- stable IDs/checksums;
- duplicate ID rejected;
- RenderMaterial cannot substitute canonical material ID;
- deterministic serialization/reload;
- no dependency on G9 runtime.

MAT0 is a hard prerequisite for G9.

### WT0 — WorldOperation contracts

Class: A

Implement later:

```text
WorldOperationId
WorldOperation
WorldOperationActor
DomainMutationIntent
WorldTransactionPlan
WorldOperationResult
WorldTransactionCompilerPort
```

Mock fixture:

```text
MOCK_MINE
  matter -10 kg material/iron
  item   +10 kg material/iron
```

WT plans only; M0 remains the atomic commit owner.

### WQ0 / WQ1 — World Query contracts

Class: A

Implement later:

```text
WorldQuery
WorldQueryScope
WorldQueryFilter
WorldQueryCandidate
WorldQueryResult
WorldQueryAdapterPort
WorldQueryPlanner
```

No canonical WQ database is permitted.

## 4. Wave B — after first contract freeze

```text
RF0/RF1   reference frames + geodesy adapter
TF0       simulation-time contracts
AUTHZ0    authorization policy contracts
LIFE0     lifecycle vocabulary
WB0/WB1   work-budget contracts + fake arbiter
COMPAT0   compatibility/version taxonomy
```

SD0 may start after RF0 shape is frozen.

Wave B is not a prerequisite for the first V0 playable composition unless a concrete V0 scenario explicitly consumes one of these capabilities.

## 5. Existing frontiers and R3 interaction

### H0.1 / C22

Current observed H0.1 R6 Work Order is PLANNED on exact current-main base. It remains R2 until its checkpoint boundary.

R3 rules:

```text
no architecture mutation inside H0.1 C22 Work Order
no R3 promotion while H0.1 is open
finish H0.1 or explicitly invalidate/rebuild it
```

### H0.2 / NX.C1

After C22 is `MAIN_INTEGRATED`, R3 is promoted, and post-R3 PC0 is NON_RED, H0.2 consumes NX.C1 as the next primary runtime capability transfer.

Target boundary:

```text
H0.2 / NX.C1
    ↓
NX SOURCE_ACCEPTED
```

H0.2 must not become a private network implementation. It proves that the runtime/control mechanism can consume an accepted NX capability through the controlled source/worker path.

### H0.3 — multi-runtime-worker scheduler

H0.3 is the next tactical foundation checkpoint after H0.2.

Purpose:

> prove that more than one accepted runtime capability can be scheduled, observed, failed, recovered/stopped and coordinated without creating hidden ownership or startup-order correctness.

Minimum target semantics:

```text
worker registry / assignment
explicit lifecycle
bounded concurrent runtime workers
observable READY / FAILED / STOPPED state
owner-attributed failure
controlled startup/shutdown
no private gameplay truth in scheduler
```

Checkpoint target:

```text
H0_3_ORCHESTRATION_ACCEPTED
```

H0.3 is the **last mandatory runtime-foundation gate before V0 runtime composition begins**.

### G

G8 is frozen accepted evidence. Do not rewrite G8 for R3.

After promotion + MAT0:

```text
fresh current-main G9
-> layered geology/material composition
```

G9–G13 deepen world-generation capability, but they are not an unconditional barrier for the first V0 world scenario if an accepted/current-canonical terrain capability already satisfies that scenario.

### NX

NX.C0 remains preparation.

NX.C1 starts after H0.1 PASS and the required architecture/control boundary. In the preferred current train it follows canonical R3 promotion + post-R3 PC0.

After H0.2/NX.C1 reaches `NX SOURCE_ACCEPTED`, later NX work can fan out:

```text
NX.C2
NX7 physics authority profiles
NX8 interest / replication budget
NX9 persistence / hardening
```

These stages expand V0/network capability progressively. They must not all be treated as a blanket prerequisite for the first two-client V0 scenario when the accepted canonical NX path already provides the required semantics.

### T / Construction

T1B stays frozen evidence. C22 convergence is handled by H0.1. T2.0 remains gated by C22 MAIN_INTEGRATED + TS0.4 + PC0 convergence.

For V0, a small real Construction outpost may use accepted/current-canonical Construction/C22 paths without waiting for the 1M construction ceiling or full T2 scale program.

### CH

Character/embodiment is a V0 consumer dependency only at the capability needed for the scenario: player spawn, movement/presentation and item/equipment presentation where applicable.

Character clothing/ECO polish is not allowed to become a blocker for the primary V0 composition train.

### ECO / ECON

`ECO` is the live Evolutionary Ecology research program. It remains advisory/nonblocking and may continue research.

`ECON` is reserved for future world economy/markets/contracts. No ECON runtime work begins in this refresh.

Neither ECO nor ECON is a base V0 prerequisite.

### MATTER / S1

Remain stable foundations. New R3 programs consume them through explicit contracts; they are not replaced.

## 6. Parallel work allowed before and after promotion

### Safe before promotion

```text
GLOBAL-R3 ownership/intersection review
GLOBAL-R3 Evidence Map
GLOBAL-R3 PC0/reviewer/verifier
ECO research validation
H0.1/C22 single runtime worker
V0 composition planning only
```

Do not start before promotion:

```text
IAM0 production branch
MAT0 production branch
WT0 production branch
WQ0 production branch
G9 runtime
NX runtime because of R3 alone
ECON runtime
SP/ENV/AI/POP production
V0 runtime branch
```

### Safe after canonical R3 promotion + post-R3 PC0

Primary runtime train:

```text
H0.2 / NX.C1
    ↓
NX SOURCE_ACCEPTED
    ↓
H0.3
    ↓
H0_3_ORCHESTRATION_ACCEPTED
```

Parallel contract lanes, subject to worker/control limits:

```text
IAM0/IAM1
MAT0
WT0
WQ0/WQ1
```

After H0.3 the project may start **composition-driven fan-out**:

```text
          H0.3 ACCEPTED
                │
     ┌──────────┼──────────┐
     ▼          ▼          ▼
    NET       GEO/MAT     WT/WQ
 capability  capability  capability
  adapters    adapters    adapters
     │          │          │
     └──────────┼──────────┘
                ▼
               V0
```

## 7. V0 — staged playable composition

V0 is a **composition consumer**, not a new owner.

Its purpose is to answer:

> can accepted runtime/world/item/network capabilities execute a small reproducible playable scenario together?

The detailed design lane is:

```text
docs/v0-playable-composition-design
```

The runtime branch remains forbidden until H0.3 acceptance.

### V0.0 — Composition Contract Freeze

Define:

```text
ScenarioSpec
capability matrix
canonical owners
worker set
operator flows
focused tests
telemetry
```

No new canonical schema is allowed merely for the showcase.

### V0-S0 — Runtime Boot

Dependency:

```text
H0_3_ORCHESTRATION_ACCEPTED
```

Proof:

```text
ScenarioSpec
 -> canonical scheduler
 -> world/query worker
 -> network worker
 -> item/query worker
 -> READY
 -> controlled shutdown
```

Target checkpoint:

```text
V0_S0_RUNTIME_BOOT_ACCEPTED
```

### V0-S1 — World Scenario

Proof:

```text
procedural/current-canonical terrain
+ player
+ small real Construction outpost
= walkable integrated world
```

Operator flow:

```text
spawn -> walk surface -> approach outpost -> enter -> leave
```

G9–G13 and MAT0 are not mandatory for S1 unless S1 explicitly consumes those semantics.

Target checkpoint:

```text
V0_S1_WORLD_ACCEPTED
```

### V0-S2 — Item Scenario

Proof:

```text
open real container
 -> pickup/transfer through Item Graph
 -> inventory/equipment
 -> drop/return
 -> one coherent identity/state
```

WT/WQ adapters should be used where required by the canonical interaction path. No `V0Inventory` or private item truth is permitted.

Target checkpoint:

```text
V0_S2_ITEM_ACCEPTED
```

### V0-S3 — Network Scenario

Minimum fixture:

```text
1 authoritative runtime/server
2 clients
1 generated world fixture
1 outpost
1 shared item
```

Proof:

```text
A and B connect
 -> A moves
 -> A picks item
 -> B observes authoritative result
 -> A drops item
 -> B observes new authoritative world state
```

NX7/NX8/NX9 are capability extensions, not a blanket gate. The first S3 requires only the accepted/current-canonical NX semantics necessary for this two-client roundtrip.

Target checkpoint:

```text
V0_S3_NETWORK_ACCEPTED
```

Final V0 checkpoint:

```text
V0_PLAYABLE_COMPOSITION_ACCEPTED
```

## 8. Tactical dependency policy after H0.3

After H0.3, every new primary/sub-primary task should answer:

> **Which V0 scenario/capability does this unlock, harden or scale?**

Capability mapping:

| Program | Immediate V0 contribution | Not a blanket blocker for |
|---|---|---|
| H0.3 | scheduling/lifecycle/orchestration | V0-S0 after acceptance |
| G8/current G | walkable procedural world | S1 waiting for G9–G13 |
| Construction/C22 | small real outpost/presentation | S1 waiting for T2 scale ceiling |
| CH | player embodiment/presentation | S1 waiting for clothing/ECO polish |
| Item Graph | identity/container/transfer truth | S2 |
| WT/WQ | world-operation/query adapters | S2 waiting for all future Work Fabric |
| NX.C1/C2/current NX | canonical two-client path | S3 waiting for all NX7–9 |
| NX7 | physics authority policy | S0/S1/S2 |
| NX8 | interest/replication scaling | first minimal S3 |
| NX9 | hardening/async persistence/soak | first functional S3 |
| MAT0/G9 | material/geology semantics | base S1/S2 |
| G10/G11 | volumetric/heterogeneous worlds | base S1 |
| G12/G13 | cache/provenance/detail maturity | early V0 proof ladder |

Work with no clear composition payoff can still be valid research/foundation work, but it must not automatically enter the primary critical path.

## 9. Promotion sequence

```text
R3_REFRESHED_CANDIDATE
    |
    +-- verify active runtime checkpoints are at safe boundaries
    +-- final current-main freshness
    +-- CRITICAL review
    +-- ownership/intersection PASS
    +-- Evidence Map PASS
    +-- standard + directional PC0 NON_RED
    |
    +-- HUMAN: GLOBAL_ARCHITECTURE_PROMOTION
            |
            +-- control-only canonical architecture update
            +-- post-merge PC0
            +-- create Wave A from one accepted R3 base
            +-- start H0.2 / NX.C1 primary runtime train
                    |
                    +-- NX SOURCE_ACCEPTED
                    +-- H0.3
                            |
                            +-- H0_3_ORCHESTRATION_ACCEPTED
                            +-- V0 staged composition
```

## 10. Long-range convergence

The revised convergence model deliberately introduces playable composition **before** waiting for every deep subsystem program to finish:

```text
R3 promotion
    ↓
H0.2 / NX.C1
    ↓
H0.3 multi-runtime orchestration
    ↓
V0-S0 runtime composition
    ↓
V0-S1 world composition
    ↓
V0-S2 item composition
    ↓
V0-S3 two-client network composition
    ↓
V0_PLAYABLE_COMPOSITION_ACCEPTED
```

In parallel and progressively:

```text
R3 + Wave A
    -> IAM/MAT/WT/WQ foundations
    -> RF/TF/AUTHZ/LIFE/WB/COMPAT

NET
    -> NX.C2 / NX7 / NX8 / NX9

GEO/MAT
    -> MAT0 / G9 / G10 / G11 / G12 / G13 / GM

WT/WQ
    -> real cross-domain item/construction/matter operations
```

After V0 the next integrated targets can become:

```text
V1 persistent planet outpost
    -> material-aware terrain/resources
    -> persistent mutations

V2 seamless two-region world
    -> interest/authority region crossing

V3 moving ship/station reference frames
    -> RF/SD/network handoff

V4 autonomous settlement
    -> AUTHZ/WQ/WT + AI/economy

V5 distributed living world
```

The architecture train remains subordinate to checkpointed project development: architecture revision is a controlled compatibility boundary, not a reason to churn accepted runtime branches.

The composition train has the complementary rule:

> do not wait for every future subsystem to become production-complete before proving that the capabilities already accepted can actually form a playable world together.
