# GLOBAL-P0 R3 — Parallel Implementation Plan (Refresh R1)

**Candidate:** `GLOBAL-P0-2026-08-12-R3-REFRESH-R1`  
**Current finalization base:** `main @ f6d68fc7c594b371f48a9bcff056e2478e04f317`  
**Current registry:** `78`  
**Promotion:** forbidden in this plan

Historical construction provenance is preserved only as provenance:

```text
construction main     1112d1f7cfad1df18fb3621a537e191e674848c6
construction registry 75
```

The old planning assumption that treated H0.3 as a game/runtime-process scheduler is explicitly superseded by canonical Harness semantics below. Historical preparation documents may retain the old assumption as historical evidence, but this CURRENT implementation plan must not activate it.

## 1. Immediate project rule

Canonical current state:

```text
main                     f6d68fc7c594b371f48a9bcff056e2478e04f317
registry                 78
architecture             GLOBAL-P0-2026-08-10-R2
H0.1                     H0_1_PASS
C22                      MAIN_INTEGRATED
H0.1 runtime slot        RELEASED
GLOBAL-P0 R3             final repair/review sequence
NX.C1                    BLOCKED
```

Current critical path:

```text
C22 MAIN_INTEGRATED
        ↓
R3 semantic lifecycle repair
        ↓
freeze new exact mutable review target
        ↓
R2→R3 + ownership/runtime/overlap audits
        ↓
exact-head Project Control
standard + directional PC0 NON_RED
        ↓
external Evidence Map
bound to exact frozen mutable target
        ↓
Independent Reviewer
        ↓
external lifecycle synchronization
        ↓
Independent Verifier
        ↓
external lifecycle synchronization
        ↓
Director final gate
        ↓
R3_REFRESHED_CANDIDATE_READY
        ↓
HUMAN GLOBAL_ARCHITECTURE_PROMOTION
        ↓
mandatory post-R3 PC0
        ↓
fresh H0.2 / NX.C1 dispatch
```

External lifecycle synchronization only rolls durable control/evidence state between approval roles; it is not an approval role and is not candidate-internal immutable truth.

`GLOBAL_ARCHITECTURE_PROMOTION` remains a CRITICAL human gate. Nothing in this plan authorizes it automatically.

## 2. Activation classes

```text
A CONTRACT_AFTER_GATE
  DTO/value objects/interfaces/validators/fakes/tests

B ADAPTER_AFTER_GATE
  adapters around accepted domains, no truth migration

C PRODUCTION_AFTER_GATE
  runtime only after named dependencies converge

D RESERVE_ONLY
  ownership reserved, no implementation yet
```

The R3 candidate itself creates no runtime/domain implementation.

## 3. Wave A — only after canonical R3 promotion

Maximum four new foundation frontiers may start from one accepted canonical R3 base or a later explicitly audited descendant.

### IAM0 / IAM1 — Identity and Session

Class: A/B

Planned contracts:

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

Acceptance intent:

- reconnect changes SessionId without changing AccountId;
- network peer ID never becomes account identity;
- session expiration/revocation fails closed;
- gameplay stores are not imported into IAM.

### MAT0 — Material Ontology

Class: A

Planned contracts:

```text
MaterialDefinitionId
MaterialDefinition
MaterialPropertySet
MaterialRegistryPort
MaterialProjectionDescriptor
```

Acceptance intent:

- stable IDs/checksums;
- duplicate ID rejected;
- RenderMaterial cannot substitute canonical material ID;
- deterministic serialization/reload;
- no dependency on G9 runtime.

MAT0 is a hard prerequisite for G9.

### WT0 — WorldOperation contracts

Class: A

Planned contracts:

```text
WorldOperationId
WorldOperation
WorldOperationActor
DomainMutationIntent
WorldTransactionPlan
WorldOperationResult
WorldTransactionCompilerPort
```

Reference fixture:

```text
MOCK_MINE
  matter -10 kg material/iron
  item   +10 kg material/iron
```

WT plans only; M0 remains the atomic commit owner.

### WQ0 / WQ1 — World Query contracts

Class: A

Planned contracts:

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

`SD0` follows RF0 shape.

Wave B is capability-driven. It is not a blanket prerequisite for early V0 stages unless a concrete V0 stage consumes the capability.

## 5. Existing frontiers and R3 interaction

### H0.1 / C22

Current canonical disposition:

```text
H0.1 R8       H0_1_PASS
C22           MAIN_INTEGRATED
runtime slot  RELEASED
```

H0.1/C22 is historical/accepted for this transition and owns no current runtime slot.

### H0.2 / NX.C1

H0.2/NX.C1 remains blocked until all of the following are true:

```text
canonical R3
+
mandatory post-R3 PC0 NON_RED
+
fresh H0.2/NX.C1 dispatch from then-current main
```

Target source boundary remains:

```text
H0.2 / NX.C1
    ↓
NX SOURCE_ACCEPTED
```

Fresh CH→NX directional dependency revalidation is required before NX source acceptance.

### H0.3 — DEVELOPMENT multi-worker Work-Order scheduler/control layer

H0.3 is a development-control checkpoint after H0.2/NX source acceptance.

Invariant:

```text
H0.3
=
DEVELOPMENT multi-worker Work-Order scheduler/control layer

H0.3
!= game-runtime process scheduler
!= gameplay authority owner
!= simulation/game-time owner
!= production boot owner
```

Purpose:

> prove that multiple development Work Orders can be admitted, blocked, run, reviewed and integrated under explicit ownership/path/watch constraints without allowing conflicting work to proceed concurrently.

Minimum target semantics:

```text
WorkOrderCandidate
ownership claims
allowed_paths
forbidden_paths
watched_paths
critical_watched_paths
intersection classification
compatible → RUN
conflicting → BLOCK
bounded development-worker concurrency
checkpoint/evidence/review routing
integration ordering
```

H0.3 does not start, stop, schedule or own gameplay runtime processes.

Checkpoint target:

```text
H0_3_SCHEDULER_ACCEPTED
```

This is the development-control gate required before V0 runtime implementation is authorized.

### G

G8 is frozen accepted evidence. Do not rewrite G8 for R3.

After canonical R3 + MAT0:

```text
fresh current-main G9
→ layered geology/material composition
```

G9–G13 deepen world-generation capability, but are not blanket blockers for an early V0 stage if the stage only requires an already accepted/current-canonical terrain capability.

### NX

NX.C0 remains preparation-only.

NX.C1 starts only after canonical R3 + post-R3 PC0 + fresh H0.2 dispatch. After the required NX source acceptance/integration boundary, later capabilities can fan out as separately justified work:

```text
NX.C2
NX7 physics authority profiles
NX8 interest / replication budget
NX9 persistence / hardening
```

They are capability extensions, not an automatic waterfall that blocks all earlier composition.

### T / Construction

T1B stays frozen evidence. C22 is now MAIN_INTEGRATED.

T2.0 remains separately gated by its own canonical conditions, including TS0.4 ceiling evidence and PC0 convergence. V0-S1 may consume a bounded accepted/current-canonical Construction/C22 capability without claiming that full T2 scale work is complete.

### CH

CH9.6 is accepted/frozen. Character is a V0 consumer dependency only at the capability required by the scenario: player spawn, movement/presentation and item/equipment presentation where applicable.

CH→NX remains a future NX dependency revalidation gate, not a current R3 blocker.

### ECO / ECON

```text
ECO  = Evolutionary Ecology advisory/research
ECON = reserved future economy/markets/contracts
```

ECO is nonblocking for current R3 finalization. ECON has no runtime work in this refresh.

### ITEM

```text
ITEM = STABLE_CANONICAL_FOUNDATION
```

V0 consumes Item identity/container/transfer semantics and must not introduce private item truth.

### MATTER / S1

Remain stable foundations. R3 adds contracts/adapters at named intersections; it does not replace them.

## 6. Parallel work policy

### Before human R3 promotion

Allowed:

```text
GLOBAL-R3 repair/final evidence work
Independent Reviewer session
Independent Verifier session
Director final-gate session
H0.2/NX.C1 preparation only
H0.3 design/preparation only
V0 design/preparation only
GEO-min / ITEM-min / NET-min contract planning only
ECO advisory research/design
```

Forbidden:

```text
H0.2/NX.C1 runtime
H0.3 implementation
V0 runtime
G9 runtime
TS0.4 runtime
T2.0 runtime
Wave A production branches
GLOBAL_ARCHITECTURE_PROMOTION without explicit human authorization
```

### After canonical R3 promotion + mandatory post-R3 PC0

Primary train:

```text
fresh H0.2 / NX.C1
        ↓
NX SOURCE_ACCEPTED
        ↓
required NX integration boundary
        ↓
H0.3 development scheduler implementation
        ↓
H0_3_SCHEDULER_ACCEPTED
        ↓
V0-S0 runtime implementation may start
```

Wave A contract lanes may run in parallel only under control-plane worker limits and ownership/intersection checks:

```text
IAM0/IAM1
MAT0
WT0
WQ0/WQ1
```

There is no global adapter/runtime-worker waterfall.

## 7. V0 — capability-driven playable composition

V0 is a **composition consumer**, not a canonical truth owner.

Invariant:

```text
V0 = COMPOSITION_CONSUMER_NOT_CANONICAL_TRUTH_OWNER
```

V0 does not own a global runtime scheduler. It consumes existing production runtime lifecycle and accepted domain capabilities.

### V0.0 — Composition Contract Freeze

Define only the composition contract needed to prove staged scenarios:

```text
capability matrix
canonical owners
required minimal capabilities
operator flows
focused tests
telemetry/evidence
```

No private V0 world/item/network truth and no new universal scheduler schema.

### V0-S0 — Production Runtime Boot

Dependency:

```text
H0_3_SCHEDULER_ACCEPTED
```

Production boot path:

```text
project.godot
    ↓
main.tscn
    ↓
scripts/app/simulator_app.gd
    ↓
existing production runtime lifecycle
    ↓
READY
    ↓
controlled shutdown
```

H0.3 does not participate in this runtime call chain; it only governs development Work Orders that produced/validated the stage.

Target checkpoint:

```text
V0_S0_RUNTIME_BOOT_ACCEPTED
```

### V0-S1 — World Scenario

Capability gate:

```text
GEO-min
+
player
+
T/C22 accepted capability
```

Proof intent:

```text
procedural/current-canonical terrain
+ player
+ bounded real Construction outpost
= walkable integrated world
```

Operator flow:

```text
spawn → walk surface → approach outpost → enter → leave
```

Target checkpoint:

```text
V0_S1_WORLD_ACCEPTED
```

### V0-S2 — Item Scenario

Capability gate:

```text
ITEM-min
```

Proof intent:

```text
open real container
→ pickup/transfer through Item Graph
→ inventory/equipment
→ drop/return
→ one coherent identity/state
```

No `V0Inventory` or private item truth is permitted.

Target checkpoint:

```text
V0_S2_ITEM_ACCEPTED
```

### V0-S3 — Network Scenario

Capability gate:

```text
NX MAIN_INTEGRATED
+
NET-min
```

Minimum fixture:

```text
1 authoritative runtime/server
2 clients
1 generated world fixture
1 outpost
1 shared item
```

Proof intent:

```text
A and B connect
→ A moves
→ A picks item
→ B observes authoritative result
→ A drops item
→ B observes new authoritative world state
```

Target checkpoint:

```text
V0_S3_NETWORK_ACCEPTED
```

Final staged V0 checkpoint remains:

```text
V0_PLAYABLE_COMPOSITION_ACCEPTED
```

The intended dependency shape is capability-driven:

```text
H0.3 accepted
   ↓
V0-S0

GEO-min + player + T/C22
   ↓
V0-S1

ITEM-min
   ↓
V0-S2

NX MAIN_INTEGRATED + NET-min
   ↓
V0-S3
```

A V0 stage waits only for capabilities it actually consumes, plus its declared checkpoint/control gates.

## 8. Tactical dependency policy after H0.3

Every new primary/sub-primary task should answer:

> Which V0 scenario/capability does this unlock, harden or scale?

| Program | Immediate V0 contribution | Not a blanket blocker for |
|---|---|---|
| H0.3 | development Work-Order concurrency/control | runtime scheduling semantics |
| G8/current G | walkable procedural world | S1 waiting for G9–G13 |
| Construction/C22 | bounded real outpost/presentation | S1 waiting for T2 scale ceiling |
| CH | player embodiment/presentation | S1 waiting for ECO polish |
| Item Graph | identity/container/transfer truth | S2 |
| WT/WQ | world-operation/query contracts when required | unrelated V0 stages |
| NX.C1/current NX | canonical network capability path | S0/S1/S2 |
| NX7 | physics authority policy | S0/S1/S2 unless consumed |
| NX8 | interest/replication scaling | first minimal S3 unless required |
| NX9 | hardening/async persistence/soak | first functional S3 unless required |
| MAT0/G9 | material/geology semantics | base S1/S2 unless consumed |
| G10/G11 | volumetric/heterogeneous worlds | base S1 |
| G12/G13 | cache/provenance/detail maturity | early V0 proof ladder |

Research/foundation work without direct V0 payoff can still be valid, but it does not automatically become primary critical path work.

## 9. R3 promotion sequence

```text
R3 semantic lifecycle repair
    ↓
freeze new exact mutable review target
    ↓
R2→R3 transition audit PASS
ownership/intersection audit PASS
runtime files = 0
critical overlap = 0
    ↓
exact-head Project Control
standard PC0 NON_RED
directional PC0 NON_RED
    ↓
external Evidence Map
bound to exact frozen mutable target
    ↓
Independent Reviewer PASS
    ↓
external lifecycle synchronization
    ↓
Independent Verifier PASS
    ↓
external lifecycle synchronization
    ↓
Director final gate PASS
    ↓
R3_REFRESHED_CANDIDATE_READY
    ↓
HUMAN GLOBAL_ARCHITECTURE_PROMOTION
    ↓
control-only canonical promotion
    ↓
mandatory post-R3 PC0
```

The CURRENT lifecycle never uses a historical V2/V3 review target as authorization. Exact SHA binding belongs to the frozen Git target and its external Evidence Map, not to self-referential prose in this plan.

No implementer session may self-award the Reviewer, Verifier, or Director verdict.

## 10. Long-range convergence

Current intended convergence:

```text
canonical R3 + post-R3 PC0
    ↓
fresh H0.2 / NX.C1
    ↓
NX source/integration boundary
    ↓
H0.3 DEVELOPMENT scheduler
    ↓
H0_3_SCHEDULER_ACCEPTED
    ↓
V0-S0 production boot
    ↓
V0-S1 world composition
    ↓
V0-S2 item composition
    ↓
V0-S3 two-client network composition
    ↓
V0_PLAYABLE_COMPOSITION_ACCEPTED
```

In parallel, where explicit gates allow:

```text
R3 + Wave A
    → IAM/MAT/WT/WQ foundations
    → RF/TF/AUTHZ/LIFE/WB/COMPAT

NET
    → NX.C2 / NX7 / NX8 / NX9

GEO/MAT
    → MAT0 / G9 / G10 / G11 / G12 / G13 / GM

WT/WQ
    → real cross-domain item/construction/matter operations
```

After V0, later integrated targets can remain capability-driven:

```text
V1 persistent planet outpost
V2 seamless two-region world
V3 moving ship/station reference frames
V4 autonomous settlement
V5 distributed living world
```

Architecture revision is a controlled compatibility boundary, not a reason to churn accepted runtime branches. Playable composition should prove accepted capabilities together without inventing duplicate truth owners or a second runtime scheduler.
