# GLOBAL-P0 R3 — Parallel Implementation Plan

**Architecture:** `GLOBAL-P0-2026-08-11-R3-CANDIDATE`  
**Branch:** `feature/global-p0-r3-architecture`  
**Purpose:** define what may be built now, what must be mocked, and what remains reserved until composition gates exist.

---

## 1. Current project work remains first-class

R3 does not pause current accepted development flow.

Current operational sequence remains:

```text
G8.4 focused/full acceptance
    -> G8.5

T1B.2 focused/full acceptance
    -> T1B.3

CH9.5 focused acceptance
    -> PC0 audit

C22/TS source accepted
    -> merge main
    -> PC0
    -> TS0.4 1M ceiling probe

M7/FIX network tuning
    -> declare actual NX frontier in main before next network acceptance
```

No R3 contract branch may rewrite current G8/T1B/CH9 runtime just to adopt new names.

---

# 2. Activation classes

Every R3 stage is assigned one of four activation classes.

```text
A — CONTRACT_NOW
    pure DTO/value objects/interfaces/validators/fakes/tests
    no canonical migration

B — ADAPTER_NOW
    can adapt an existing accepted domain without changing its truth

C — PRODUCTION_AFTER_GATE
    real runtime may start only after named dependencies converge

D — RESERVE_ONLY
    architecture ownership is reserved; no production implementation yet
```

The point is to allow useful parallel work while preventing premature global managers.

---

# 3. Wave A — start immediately after R3 acceptance

Recommended maximum: four active new R3 frontiers at once.

## 3.1 IAM0 / IAM1 — Identity contracts + local provider

**Class:** A/B  
**Branch proposal:** `feature/iam0-identity-session-contracts`

Implement:

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

Mock/live boundary:

- local provider may use deterministic local credentials/guest identities;
- no external OAuth dependency required;
- current player identity remains unchanged;
- adapter maps authenticated session to existing gameplay join command;
- ENet peer ID remains transport-only.

Acceptance:

```text
same AccountId -> new SessionId after reconnect
same PrincipalId may control same existing player actor after policy allows
changed peer ID does not change account identity
session expiration/revocation fails closed
no gameplay store imported by IAM
```

Do not implement yet:

```text
production OAuth UI
organization permissions
cross-server session propagation
```

---

## 3.2 MAT0 — Material ontology contracts

**Class:** A  
**Branch proposal:** `feature/mat0-material-ontology-contracts`

Implement:

```text
MaterialDefinitionId
MaterialDefinition
MaterialPropertySet
MaterialRegistryPort
MaterialProjectionDescriptor
```

Deterministic fixture ontology:

```text
material/water
material/ice
material/oxygen
material/nitrogen
material/iron
material/steel
material/basalt
material/granite
material/soil
```

The fixture set exists to test identity/projection/versioning. It is not final scientific content.

Acceptance:

- stable IDs and checksums;
- duplicate ID rejected;
- render material cannot substitute canonical material ID;
- domain projection cannot mutate definition;
- serialization/reload is deterministic;
- no dependency on G9, Matter runtime or Construction runtime.

Why now:

G9 geology should begin only after MAT0 exists, otherwise geology will be forced either to invent private rock identities or to be rewritten later.

---

## 3.3 WT0 — WorldOperation contracts

**Class:** A  
**Branch proposal:** `feature/wt0-world-operation-contracts`

Implement:

```text
WorldOperationId
WorldOperation
WorldOperationActor
DomainMutationIntent
WorldTransactionPlan
WorldOperationResult
WorldTransactionCompilerPort
```

Mock domain intents:

```text
item mutation intent
construction mutation intent
matter mutation intent
```

Acceptance:

```text
operation checksum deterministic
intent ordering canonical
same operation compiles same plan
invalid cross-domain precondition fails before M0
planner cannot commit state
M0 remains the only atomic commit engine
replay ID remains stable
```

Useful immediate fixture:

```text
MOCK_MINE
  matter -10 kg material/iron
  item   +10 kg material/iron
```

The mock proves plan shape only. It must not touch production Matter or Item stores yet.

---

## 3.4 WQ0 / WQ1 — World Query contracts

**Class:** A  
**Branch proposal:** `feature/wq0-world-query-contracts`

Implement:

```text
WorldQuery
WorldQueryScope
WorldQueryFilter
WorldQueryResult
WorldQueryCandidate
WorldQueryAdapterPort
WorldQueryPlanner
```

Fake adapters:

```text
fake Item adapter
fake Construction adapter
fake Geo adapter
```

Acceptance:

- result ordering deterministic;
- adapter order does not change result;
- query scope is explicit;
- actor context exists even before AUTHZ is wired;
- query planner cannot mutate canonical state;
- result includes provenance/domain source;
- duplicate candidates merge deterministically.

Why now:

This allows future AI/NAV/gameplay work to agree on one query envelope before distributed fan-out exists.

---

# 4. Wave B — start after Wave A contracts freeze

These programs may overlap with Wave A implementation, but should not all become active production frontiers simultaneously.

## 4.1 RF0 / RF1 — Reference frames

**Class:** A/B  
**Branch proposal:** `feature/rf0-reference-frame-contracts`

Implement:

```text
ReferenceFrameId
ReferenceFrameDescriptor
FrameTransform
FrameMotion
WorldTransform
FrameRelationResolverPort
```

RF1 adapter:

- adapt accepted body/geodesy representation;
- prove body-fixed and local-tangent frames;
- no rewrite of G1 canonical geodesy;
- no server route embedded in frame ID.

Acceptance fixture:

```text
body frame
 -> local tangent frame
 -> observer-relative presentation transform
```

GPU float projection may be mocked with a pure conversion test.

---

## 4.2 TF0 — Time contracts

**Class:** A  
**Branch proposal:** `feature/tf0-time-fabric-contracts`

Implement:

```text
SimulationEpoch
SimulationTime
DomainTick
ScheduledWorldEvent
TemporalWindow
CatchUpPolicy
SimulationClockPort
FakeSimulationClock
```

Acceptance:

```text
wall time not required for deterministic test
same event schedule -> same ordered events
network tick cannot be accepted as domain tick implicitly
domain-specific cadence is explicit
catch-up policy is data, not hidden loop behaviour
```

Do not yet create a global runtime scheduler.

---

## 4.3 AUTHZ0 — Policy contracts

**Class:** A  
**Branch proposal:** `feature/authz0-policy-contracts`

Implement:

```text
AuthorizationRequest
AuthorizationDecision
ActionId
ResourceRef
PolicyContext
AuthorizationPort
DenyByDefaultAuthorization
```

Add adapter fixtures for existing permission concepts only after IAM0 is stable.

Acceptance:

- unknown action denied;
- unknown resource denied;
- no gameplay mutation inside policy engine;
- actor/principal distinction explicit;
- decision carries reason/audit fields;
- policy request deterministic/serializable.

---

## 4.4 LIFE0 — Lifecycle contracts

**Class:** A/B  
**Branch proposal:** `feature/life0-world-lifecycle-contracts`

Implement common levels:

```text
ABSTRACT
DORMANT
SIMULATED
ACTIVE
PRESENTED
```

plus:

```text
LifecycleRequest
LifecycleDecision
LifecycleEvidence
LifecycleAdapterPort
```

First real adapters should be C18 and RL only.

Acceptance:

- demotion preserves canonical ID/revision;
- representation deletion does not delete canonical state;
- re-promotion rebuilds derived state;
- domain-local activity states remain representable.

---

## 4.5 WB0 / WB1 — Work budget contracts + fake arbiter

**Class:** A  
**Branch proposal:** `feature/wb0-world-work-budget-contracts`

Implement:

```text
WorldWorkRequest
WorldWorkClass
WorkCostEstimate
WorkPriority
WorkBudget
WorkDecision
WorldWorkArbiterPort
DeterministicFakeWorkArbiter
```

Decisions:

```text
RUN_FULL
RUN_COARSE
DEFER
BATCH
DISPATCH_S1
REJECT_OVER_BUDGET
```

Acceptance:

- equal request set produces equal decision set regardless input order;
- budget never grants authority;
- S1 dispatch is a decision, not direct commit;
- local lab knobs cannot register as global canonical budget state.

Do not wire this as production global scheduler yet.

---

## 4.6 COMPAT0 — Compatibility taxonomy

**Class:** A  
**Branch proposal:** `feature/compat0-schema-version-governance`

Implement contracts for:

```text
SchemaVersion
ProtocolVersion
ContentVersion
MigrationVersion
CompatibilityDecision
```

Acceptance should include examples for:

- persistent Item schema;
- network DTO version;
- material-definition content version;
- migration declaration.

This work is mostly pure contracts and governance and can safely run beside gameplay.

---

# 5. SD0 starts after RF0

**Branch proposal:** `feature/sd0-spatial-domain-fabric`

Reason for gate:

`WorldAddress` must be frame-aware from the beginning. Starting SD first risks baking a single Cartesian frame into every future mapping.

Implement:

```text
WorldAddress
WorldBounds
SpatialDomainId
SpatialMappingRequest
SpatialMappingResult
SpatialDomainAdapterPort
```

Initial adapters/mocks:

```text
S0 cell mapping
G SurfaceCellKey mapping
Matter region mapping
Construction scope mapping
```

No N3 authority lookup yet.

Acceptance:

```text
one WorldAddress maps to multiple domain IDs
changing InterestRegion does not change entity identity
SurfaceCellKey is not AuthorityRegionId
frame relation is explicit
```

---

# 6. Existing network work that may proceed in parallel

## 6.1 M7 / NX tuning

Immediate control-plane task:

```text
declare the actual active M7/FIX network frontier in main
```

This should happen before its next acceptance because network runtime changes are too central to remain an unregistered tuning lineage.

## 6.2 B1 — NATS Core adapter

A3 has already been accepted historically, so B1 can be prepared when PC0 explicitly activates it.

B1 remains adapter-only:

```text
B0 request/reply port
    -> NATS Core adapter
```

B1 does not carry ordinary graphical realtime traffic and does not replace ENet.

## 6.3 B2 / N3-N6

Keep existing gates:

```text
B1
 -> B2 durable delivery
 -> N3 directory/leases
 -> N4 generic handoff
 -> N5 player handoff
 -> N6 overlap/ghosts
```

R3 contracts should be consumed where ready, but this order should not be bypassed.

---

# 7. Production gates for later programs

## 7.1 MAT -> G9

```text
MAT0 accepted
  -> G9 layered geology may introduce material composition
```

G9 must never define a private global `rock/ore` registry.

## 7.2 WT + MAT + G/MW -> GM

```text
G9/G10
MAT0+
MW10
WT0/WT1
   -> GM0
```

GM0 should first prove baseline + sparse mutation composition, not full dynamic geology.

## 7.3 RF + SD + N3-N6 -> SP

Space/celestial production waits until frame identity and distributed authority routing can coexist explicitly.

Early SP research may remain math/provider-only.

## 7.4 TF + MAT + WB -> ENV

ENV0 contracts may be researched earlier, but production atmosphere/thermal/fluid updates need explicit time and work budgets.

## 7.5 WQ + SD + RF -> NAV

NAV0 route contracts can follow WQ0. Planetary/cross-frame navigation waits for SD/RF.

## 7.6 IAM + AUTHZ + WQ + WT -> AI

AI execution gate:

```text
AI can perceive/query
AI can be authorized
AI can request WorldOperation
AI cannot mutate stores directly
```

LLM integration starts only after a deterministic actor runtime already works.

## 7.7 LIFE + TF + WB + AI -> POP

Large population simulation must begin compactly. No entity-per-resident production baseline is allowed.

---

# 8. Recommended branch budget

To keep PC0 useful, do not create all R3 branches simultaneously.

Recommended active architecture/runtime fronts at one time:

```text
existing domain fronts:  G / T / CH / TS / NX
new R3 fronts:           maximum 3-4 contract branches
```

Preferred first set after R3 merge:

```text
1. feature/mat0-material-ontology-contracts
2. feature/wt0-world-operation-contracts
3. feature/wq0-world-query-contracts
4. feature/iam0-identity-session-contracts
```

Why these four:

```text
MAT0 protects imminent G9 design
WT0 protects GM/T3/T5 cross-domain mutations
WQ0 unlocks future AI/NAV without owning storage
IAM0 closes an obvious production multiplayer gap independently
```

Second set:

```text
RF0
TF0
AUTHZ0
LIFE0/WB0
```

SD0 follows RF0.

---

# 9. Tactical tasks before starting R3 runtime code

After R3 architecture is merged into main:

```text
1. increment canonical architecture revision to GLOBAL-P0-2026-08-11-R3
2. update main architecture ownership registry from R3 candidate
3. run CONTROL_PROJECT.ps1
4. check active G/T/CH/TS passports for newly forbidden ownership
5. explicitly declare actual NX/M7 tuning frontier
6. register only selected Wave A branches in PC0
7. create branch passports with owned/watched/critical paths
8. keep fake implementations under contract/lab namespaces
9. require full world regression only when a contract branch touches shared runtime
```

---

# 10. Convergence roadmap

```text
CURRENT
  G8 / T1B / CH9 / TS0 / NX tuning
        │
        ├────────────── Wave A contracts
        │               IAM0 MAT0 WT0 WQ0
        │
        └────────────── Wave B contracts
                        RF0 TF0 AUTHZ0 LIFE0 WB0
                              │
                              ▼
                         SD0 spatial mapping
                              │
              ┌───────────────┼────────────────┐
              ▼               ▼                ▼
             G9              B1/B2             AI0/NAV0 research
              │               │
             G10             N3-N6
              │               │
              └──── GM ───────┤
                              ▼
                    V1 / V2 composition
                              │
                  RF/SD + SP + N3-N6
                              ▼
                            V3
                              │
                  TF/LIFE/WB + AI/POP/ECO
                              ▼
                            V4
                              │
                       production hardening
                              ▼
                            V5
```

---

# 11. First five R3 composition milestones

## V1 — Persistent Planet Outpost

Proof that G + Matter + Item + Construction + network + durability work as one world consequence chain.

## V2 — Seamless Two-Region World

Proof that authority can move without identity reset.

## V3 — Moving Ship / Station

Proof that nested reference frames and cross-server authority coexist.

## V4 — Autonomous Settlement

Proof that AI uses the same world APIs as humans and can create durable infrastructure/economy.

## V5 — Distributed Living World

Proof that multiple authorities, agents, large constructions, mutable terrain and bounded computation coexist under restart/migration/load.

---

# 12. Stop rule

A new implementation must stop for architecture review if it needs to create any of these outside the declared owner:

```text
Account/Principal registry
universal permission manager
reference-frame registry
simulation-time owner
WorldAddress / universal ChunkId
global material registry
cross-domain transaction coordinator
universal query database
global lifecycle manager
global work scheduler
authority directory
direct AI world-store access
```

The correct response is to add an adapter or extend the declared foundation contract, not to hide a second foundation inside a domain branch.
