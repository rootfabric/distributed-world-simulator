# Distributed World Simulator — GLOBAL-P0 R3 Architecture Candidate

**Revision:** `GLOBAL-P0-2026-08-11-R3-CANDIDATE`  
**Date:** 2026-08-11  
**Branch:** `feature/global-p0-r3-architecture`  
**Base:** `main`  
**Status:** architecture candidate; no runtime ownership changes until merge and PC0 convergence  
**Parent architecture:** `GLOBAL-P0-2026-08-10-R2`

---

## 1. Purpose

R3 extends the accepted R2 program architecture from several strong domain foundations into one long-lived distributed-world architecture suitable for:

- planetary and interplanetary scale;
- mutable terrain and geology;
- very large semantic constructions;
- one or many authoritative servers;
- seamless authority handoff;
- humans and AI actors using the same world rules;
- aggressive LOD/dormancy without losing canonical truth;
- open-source self-hosting and future production clusters.

R3 does **not** replace accepted A0/A1/S0/S1, M0, M1-M6/A3, Item, Matter, Construction, G, RL, CH or existing network contracts. It defines the missing cross-domain foundations that those programs must eventually consume.

---

## 2. Canonical formula

```text
CANONICAL WORLD
    != PRESENTATION
    != TRANSPORT
    != COMPUTE
    != AUTHENTICATION
    != QUERY INDEX
    != SCHEDULER
```

R3 adds these mandatory invariants:

```text
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

The core scaling rule is:

> Everything expensive may reduce resolution; nothing important may reduce truth.

Examples:

```text
far factory:
    no animated machines
    production truth remains

far NPC population:
    no live skeletons
    population state remains

far station:
    no 100k live nodes
    Construct truth remains

far terrain:
    no centimetre mesh
    Geo + Matter truth remains
```

---

## 3. Target architecture

```text
Human Client                          AI Planner / Agent
     │                                      │
     └──────────── Actor / Intent API ──────┘
                         │
                         ▼
                 Authorization Gate
                         │
                         ▼
                    WorldOperation
                         │
                         ▼
                WorldTransactionPlan
             ┌───────────┼───────────┐
             ▼           ▼           ▼
           ITEM       CONSTRUCTION  MATTER
             │           │           │
             └───────────┼───────────┘
                         ▼
                   CANONICAL WORLD
                         │
       ┌─────────────────┼──────────────────┐
       ▼                 ▼                  ▼
 Reference Frames    Time Fabric      Material Ontology
       │                 │                  │
       └─────────────────┼──────────────────┘
                         ▼
                Spatial Domain Fabric
                         │
                         ▼
                   World Query Fabric
                         │
       ┌─────────────────┼──────────────────┐
       ▼                 ▼                  ▼
     Geo/Env           AI/Nav           Economy/Population
       │                 │                  │
       └─────────────────┼──────────────────┘
                         ▼
            Lifecycle + World Work Budget
                         │
                         ▼
              Distributed Runtime / S1
                         │
       ┌─────────────────┼──────────────────┐
       ▼                 ▼                  ▼
   Authority          Interest          Compute workers
   N3-N6 / NX7        NX8               S1
                         │
                         ▼
            disposable representations
         mesh / HLOD / physics / replica / UI
```

---

# 4. Existing foundations preserved by R3

## 4.1 A0 / A1 / S0 / S1

R3 keeps the accepted split:

```text
A1 aggregate identity/state
S0 spatial simulation substrate
S1 proposal-only distributed compute
```

S1 remains proposal-only:

```text
Authority projects immutable state
    -> Worker computes proposal
    -> Authority validates proposal
    -> M0 commits canonical mutation
```

No R3 program may turn a worker into an authoritative writer.

## 4.2 M0 and durability

M0 remains the atomic multi-aggregate transaction foundation. R3 `WT` is a semantic planner over M0, not a second transaction engine.

Existing R3/M0/MW durability remains canonical. Future async persistence changes I/O scheduling only, not commit/replay semantics.

## 4.3 Domain owners

```text
ITEM          permanent item identity and Item Graph
CONSTRUCTION  construct / part / bond / behavior truth
MATTER        mutable authoritative material-volume truth
G             deterministic procedural natural baseline
RL            disposable multiresolution representation contracts
CH            character/equipment presentation composition
NX            realtime replication and network policy
```

---

# 5. New R3 cross-domain P0 programs

## 5.1 IAM — Identity and Session Fabric

### Purpose

Separate human/account identity from network connections and world entities.

### Canonical concepts

```text
AccountId
PrincipalId
SessionId
ActorBinding
AuthenticationResult
SessionClaims
```

### Required relationship

```text
Account
  -> authentication
Principal
  -> session
Session
  -> controls one or more authorized Actors
Actor
  -> world entity / agent identity
```

### Must not own

```text
PlayerEntityId
ItemId
ConstructId
NetworkPeerId
AuthorityLease
organization policy
```

### Initial stages

```text
IAM0 Identity/Session contracts
IAM1 Local self-host identity provider
IAM2 provider-neutral authentication boundary
IAM3 reconnect/session rotation
IAM4 multi-server session acceptance
```

### Can start now

`IAM0` and a mock/local `IAM1` can start immediately. They can run entirely beside current gameplay by adapting the current logical player/session mapping without changing gameplay authority.

---

## 5.2 AUTHZ — Authorization, Ownership and Policy Fabric

### Purpose

Provide one decision boundary for who may perform an action on a resource.

### Canonical concepts

```text
PrincipalRef
ActorRef
ResourceRef
ActionId
PolicyContext
AuthorizationDecision
OwnershipClaim
RoleGrant
```

### Core API

```text
CAN_ACT(principal, actor, action, resource, context) -> decision
```

### Consumers

```text
Item operations
Construction commands
Matter excavation
containers
machines
vehicles
WorldQuery visibility
future organizations
admin tools
```

### Must not own

Authentication, domain state or gameplay result.

### Initial stages

```text
AUTHZ0 policy contracts + deny-by-default mock
AUTHZ1 actor/resource adapters
AUTHZ2 ownership/roles
AUTHZ3 organization-scoped policies
AUTHZ4 distributed policy acceptance
```

### Can start now

`AUTHZ0` can be contract-only now. Production adoption should be incremental after IAM0 because existing C12 permissions and Item permissions must be adapters, not discarded implementations.

---

## 5.3 RF — Reference Frame Fabric

### Purpose

Represent coordinates and motion across planets, ships, interiors and interplanetary distances without equating one global Cartesian vector with world identity.

### Canonical concepts

```text
ReferenceFrameId
ReferenceFrameDescriptor
FrameTransform
FrameMotion
WorldTransform
FrameRelation
```

### Example hierarchy

```text
Universe/System frame
  -> Celestial body inertial frame
     -> body-fixed rotating frame
        -> geodetic/local tangent frame

Ship frame
  -> interior compartment frame
     -> local physics frame
```

### Intersections

```text
G1 geodesy      consumes body/reference-frame mapping
S0/SD           uses frame-aware WorldAddress
SP              owns celestial motion providers, not RF identity
NX              replicates frame-aware transforms
Construction    mobile constructs expose attachment/interior frames
GPU             receives observer-relative float projection only
```

### Must not own

Authority routing, cells, physics policy or celestial dynamics.

### Initial stages

```text
RF0 frame identity/transform contracts
RF1 body-fixed + local tangent adapter over accepted geodesy
RF2 mobile construct frame adapter
RF3 observer-relative presentation transform
RF4 cross-server frame acceptance
```

### Can start now

`RF0` can start as pure contracts/tests. `RF1` can be mocked against existing G1 geodesy. Production replacement of transforms should wait for explicit composition tests.

---

## 5.4 TF — Time Fabric

### Purpose

Allow different systems to run at different rates while preserving deterministic temporal meaning.

### Canonical concepts

```text
SimulationTime
SimulationEpoch
DomainTick
ScheduledWorldEvent
TemporalWindow
CatchUpPolicy
```

### Explicitly distinct clocks

```text
wall clock
monotonic process clock
simulation time
network tick
physics tick
domain tick
presentation time
```

### Consumers

Geo evolution, Matter processes, factories, environment, AI, population, economy and persistence scheduling.

### Must not own

Network clock synchronization, global work scheduling or domain-specific simulation rules.

### Initial stages

```text
TF0 time contracts
TF1 multi-rate local scheduler semantics
TF2 deterministic scheduled events
TF3 dormant/offline catch-up
TF4 cross-authority temporal acceptance
```

### Can start now

`TF0` can start immediately. `TF1` should initially use fake deterministic clocks; no production scheduler should be wired into G/T/NX until WB contracts exist.

---

## 5.5 SD — Spatial Domain Fabric

### Purpose

Map a stable world address into multiple domain-specific spatial identities without collapsing them into one chunk identifier.

### Canonical concepts

```text
WorldAddress
WorldBounds
SpatialDomainId
SpatialMappingRequest
SpatialMappingResult
```

### Mappings

```text
WorldAddress
  -> SurfaceCellKey
  -> MatterRegionId
  -> AuthorityRegionId
  -> InterestRegionId
  -> FeatureBounds
  -> ConstructionScope
  -> PopulationCell
```

### Mandatory inequalities

```text
SurfaceCellKey != FeatureId
MatterRegionId != AuthorityRegionId
AuthorityRegionId != InterestRegionId
InterestRegionId != canonical identity
ConstructionSectionId != WorldAddress
```

### Existing foundation reuse

S0 hierarchical cells/shards remain valid. SD is the cross-domain mapping fabric over them and over existing domain keys.

### Initial stages

```text
SD0 WorldAddress + mapping contracts
SD1 adapters for S0/G/MW/Construction
SD2 authority/interest mapping adapters
SD3 cross-frame spatial mapping
```

### Can start now

`SD0` contract work can begin after RF0 shape is stable enough to avoid encoding a single frame assumption.

---

## 5.6 MAT — Unified Material Ontology

### Purpose

Give geology, Matter, Items, Construction, fabrication, fluids and atmosphere one stable material identity.

### Canonical concepts

```text
MaterialDefinitionId
MaterialDefinition
MaterialComponent
MaterialPhaseProfile
MaterialPropertySet
```

### Domain projections

```text
G9 geology        -> material composition fields
Matter            -> mass/volume of MaterialDefinitionId
Item               -> material/content projection
Construction       -> structural/material requirements
Fabrication        -> recipe inputs/outputs
ENV                -> phase/gas/fluid properties
Presentation       -> render material family only
```

### Mandatory invariant

```text
RenderMaterial != MaterialDefinitionId
MaterialFamily != MaterialDefinitionId
```

### Initial seed definitions

The first contract fixture should include stable definitions for:

```text
water
ice
oxygen
nitrogen
iron
steel
basalt
granite
soil
```

These are test ontology fixtures, not a claim of final scientific fidelity.

### Initial stages

```text
MAT0 material identity/registry contracts
MAT1 property projection contracts
MAT2 Item/Matter adapters
MAT3 G9 geology adapter
MAT4 Construction/fabrication adapter
MAT5 ENV phase adapter
```

### Can start now

`MAT0` should start **before G9 production geology**, because G9 must not create private rock/ore identities.

---

## 5.7 WT — World Operation / Transaction Fabric

### Purpose

Represent one gameplay consequence that spans multiple canonical domains.

### Canonical concepts

```text
WorldOperationId
WorldOperation
WorldTransactionPlan
DomainMutationIntent
WorldOperationResult
CompensationPolicy
```

### Examples

```text
mining:
    Matter - mass
    Item   + resource

construction:
    Item         - materials
    Construction + parts

salvage:
    Construction - part
    Item/Matter  + recovered material
```

### Relationship to M0

```text
WorldOperation
   -> validation/authorization
WorldTransactionPlan
   -> M0 MutationBatch
M0
   -> atomic canonical commit + outbox
```

WT never becomes a second repository/coordinator.

### Initial stages

```text
WT0 operation/plan contracts + mock domain adapters
WT1 deterministic planner interface
WT2 mining vertical slice
WT3 construction material consumption slice
WT4 salvage slice
WT5 cross-authority transaction policy
```

### Can start now

`WT0` can start immediately over fake domain intents and existing M0 contract fixtures. `WT2+` waits for MAT and GM composition.

---

## 5.8 WQ — World Query Fabric

### Purpose

Provide one query envelope that can plan across domain-specific indexes without becoming a new canonical database.

### Example queries

```text
find iron deposit within 20 km
find powered machine accepting recipe X
find safe pressurized room
find damaged construct section
find available docking port
find container with oxygen
find route to settlement
```

### Architecture

```text
WorldQuery
   -> query planner
      -> Geo adapter
      -> Matter adapter
      -> Item adapter
      -> Construction adapter
      -> Population adapter
      -> Spatial index adapter
   -> merged ordered result
```

### Security/knowledge rule

WorldQuery is actor-scoped. It must support authorization/perception filtering so a client or AI cannot query information it has no right to know.

### Must not own

Canonical world data, persistent domain identity or authority.

### Initial stages

```text
WQ0 query/result contracts + fake adapters
WQ1 deterministic merge/ranking
WQ2 Construction + Item adapters
WQ3 Geo + Matter adapters
WQ4 actor visibility/authorization integration
WQ5 distributed query planning
```

### Can start now

`WQ0` and `WQ1` can start now with mocks. Production distributed queries should wait for SD/N3 and AUTHZ.

---

## 5.9 LIFE — Promotion / Dormancy / Demotion Fabric

### Purpose

Represent the same canonical subject at different simulation/activity resolutions without duplicating or deleting truth.

### Standard lifecycle levels

```text
ABSTRACT
DORMANT
SIMULATED
ACTIVE
PRESENTED
```

Domains may map their own accepted states to these common lifecycle semantics.

### Existing evidence reused

```text
C18 construction activity/dormancy
RL representation pyramid
future Population Field
future AI materialization
```

### Initial stages

```text
LIFE0 lifecycle contracts
LIFE1 Construction/RL adapter proof
LIFE2 population/agent adapter
LIFE3 cross-server lifecycle acceptance
```

### Can start now

`LIFE0` can be contract-only now. `LIFE1` should deliberately adapt C18 and RL rather than invent a second dormant construct mechanism.

---

## 5.10 WB — World Work / Budget Fabric

### Purpose

Bound total computation and decide quality/defer/dispatch policy across simulation domains.

### Canonical concepts

```text
WorldWorkRequest
WorldWorkClass
WorkCostEstimate
WorkPriority
WorkBudget
WorkDecision
```

### Example decision

```text
RUN_FULL
RUN_COARSE
DEFER
BATCH
DISPATCH_S1
REJECT_OVER_BUDGET
```

### Inputs

```text
observer relevance
canonical urgency
time since last update
deadline
estimated CPU/memory/network cost
available server budget
domain quality levels
```

### Relationship to S1/NX/G

```text
WB chooses whether/how much work is allowed
S1 executes remote/local proposal work
NX8 owns replication/interest budget policy
G12 owns generation scheduling adapter
Domains own actual simulation semantics
```

### Must not own

Authority, canonical state or network routing.

### Initial stages

```text
WB0 request/budget/decision contracts
WB1 deterministic fake arbiter
WB2 G/RL/C18 adapter lab
WB3 S1 dispatch adapter
WB4 multi-server budget acceptance
```

### Can start now

`WB0` and fake `WB1` can start now. Production scheduling should wait until at least two real domains compete for a shared budget.

---

## 5.11 COMPAT — Schema and Upgrade Governance

### Purpose

Keep a persistent universe readable and network-compatible across releases.

### Canonical concepts

```text
SchemaVersion
ProtocolVersion
ContentVersion
MigrationVersion
CompatibilityDecision
MigrationDescriptor
```

### Initial stages

```text
COMPAT0 version taxonomy/contracts
COMPAT1 migration registry
COMPAT2 network compatibility matrix
COMPAT3 rolling server upgrade acceptance
```

### Can start now

`COMPAT0` can start as documentation/contracts immediately and should become a review gate for new persistent formats.

---

## 5.12 SEC — Security / Trust Boundaries

### Purpose

Make server authority operationally safe rather than merely authoritative in design.

### Scope

```text
command validation
rate limits
replay abuse
malformed payloads
economic duplication attempts
query information leaks
admin actions
audit trail
```

### Initial stages

```text
SEC0 trust-boundary model
SEC1 command abuse/rate-limit contracts
SEC2 WorldQuery visibility security
SEC3 economy/duplication attack tests
SEC4 admin/audit controls
```

### Can start now

`SEC0` can be documentation and negative-test requirements now. Runtime rate limiting should compose with existing network backpressure rather than replacing it.

---

# 6. Existing and future distributed network program

R3 preserves the already planned order:

```text
A3 single-server architecture accepted
       ↓
B1 NATS Core adapter
       ↓
B2 JetStream / durable outbox delivery
       ↓
N3 World Directory + authority leases
       ↓
N4 Generic Aggregate Handoff
       ↓
N5 Seamless Player Handoff
       ↓
N6 Ghosts / overlap / interest
```

R3 adds the following interpretation:

### NX7 — Physics Authority Profiles

Policy over existing authority foundations for player, ship, projectile, valuable item and non-critical debris classes.

### NX8 — Interest and Replication Budget

Shared replication budget contract with domain adapters for players, items, Construction, Matter/RL, Geo detail and future AI/population.

### NX9 — Async Persistence / Hardening

Moves blocking I/O out of simulation hot paths while preserving R3/M0/MW durability semantics.

### Mandatory intersection

```text
N3/N4/N5/N6 consume SD/RF identities
N3/N4 consume AUTHZ/IAM session continuity where relevant
N6 consumes LIFE + NX8
NX8 coordinates with WB but neither owns the other
NX9 coordinates with TF scheduling but does not redefine simulation time
```

---

# 7. P1 domain-composition programs

## 7.1 GM — Geo / Matter Integration

```text
Procedural Geo baseline
        +
Sparse authoritative Matter mutations
        =
Current natural-world truth
```

Stages:

```text
GM0 contracts
GM1 baseline + sparse mutation composition
GM2 excavation through generated terrain
GM3 caves/overhang/volume mutation
GM4 persistence/restart
GM5 cross-region/cross-LOD mutation
GM6 presentation convergence
```

Dependencies: `G9/G10`, `MAT`, `WT`, `MW10`, `RL`, later `SD/WB`.

---

## 7.2 SP — Space / Celestial Dynamics

Purpose: travel between planetary/local frames without making one simulation mode own the universe.

Stages:

```text
SP0 celestial-body runtime contracts
SP1 deterministic ephemeris/orbit provider
SP2 ship/reference-frame integration
SP3 surface-space transition
SP4 docking/reference attachment
SP5 interplanetary travel
SP6 multi-server space handoff
```

Dependencies: `RF`, `TF`, `SD`, Construction mobile constructs, N3-N6.

SP owns celestial motion models; RF owns frame identity and transforms.

---

## 7.3 ENV — Environment / Atmosphere / Thermal / Fluid Fabric

Stages:

```text
ENV0 environment state contracts
ENV1 gas mixtures / pressure
ENV2 thermal model
ENV3 local fluids
ENV4 weather/large-scale atmosphere adapters
ENV5 Construction spaces and life-support composition
ENV6 character/environment interaction
ENV7 distributed environment budget/streaming
```

Dependencies: `MAT`, `TF`, `SD`, `WB`, Construction C7/C15, Matter where mass transfer becomes authoritative.

---

## 7.4 NAV — Hierarchical Navigation

Navigation levels:

```text
planet/system route
regional route
terrain/road route
construction/interior route
local movement/NavMesh
```

Stages:

```text
NAV0 query/route contracts
NAV1 local adapter
NAV2 Construction interior graph adapter
NAV3 regional/planetary graph
NAV4 vehicle/flight classes
NAV5 cross-frame routing
NAV6 distributed route planning
```

Dependencies: `WQ`, `SD`, `RF`, G, Construction.

---

## 7.5 AI — Actor / Agent Runtime

### Core principle

Human and AI must converge before canonical mutation:

```text
Human input      AI planner
     │               │
     └── Intent/API ─┘
            │
         AUTHZ
            │
      WorldOperation
            │
       canonical path
```

AI receives:

```text
WorldQuery
Perception
Capabilities
ActorCommands
```

AI does **not** receive canonical stores directly.

LLM role:

```text
reasoning / planning / dialogue
```

Deterministic runtime role:

```text
validation / reservation / execution / authority / commit
```

Stages:

```text
AI0 Actor API contracts
AI1 deterministic goal agent
AI2 WQ + WT integration
AI3 Construction C19 integration
AI4 optional LLM planner adapter
AI5 distributed agent execution
```

---

## 7.6 POP — Population Field

Purpose: simulate large populations compactly without one live entity per resident.

```text
PopulationCell
  -> aggregate cohorts/needs/jobs/activity
  -> promote selected actors near relevance
  -> demote back with durable consequences
```

Dependencies: `LIFE`, `WB`, `TF`, `AI`, `WQ`, `SD`, S1.

---

## 7.7 ECO — World Economy

Extends accepted Construction logistics/economy into cross-domain world economy.

Stages:

```text
ECO0 physical resource accounting contracts
ECO1 ownership/exchange
ECO2 contracts/orders
ECO3 markets
ECO4 logistics capacity
ECO5 production chains
ECO6 agent economy
```

Dependencies: Item, MAT, WT, Construction C20, AUTHZ/ORG, TF, WQ.

---

## 7.8 ORG — Organizations / Claims / Social Structure

Canonical concepts:

```text
OrganizationId
Membership
Role
Claim
ContractParty
ReputationRecord
```

Organization territory/claim identity is semantic world state and must not equal server shard or render chunk.

Dependencies: IAM, AUTHZ, WT, ECO, SD.

---

## 7.9 OPS — World / Cluster Operations

Operator capabilities:

```text
node health
world-server map
authority map
interest map
simulation budget map
drain/migrate
backup/restore
rolling upgrade
```

OPS observes and invokes existing authority/control APIs. It never becomes canonical world truth.

Dependencies: N3-N6, WB, COMPAT, telemetry.

---

## 7.10 MOD — Open Modding / Provider Model

Safe extension types:

```text
data definitions
generator providers
material packs
recipes
planet recipes
server rules
safe scripted proposal providers
```

Mods must not directly mutate canonical stores. They produce definitions, providers, queries or operation proposals that pass the same validation/authority boundaries.

---

# 8. Program intersection matrix

| Producer / Foundation | Main consumers | Hard rule |
|---|---|---|
| IAM | AUTHZ, player sessions, N5, ORG | network peer is never account identity |
| AUTHZ | WT, WQ, Item, Construction, Matter, AI | deny/allow decision only; domain still validates semantics |
| RF | SD, SP, G, NX, Construction mobile frames | frame identity is not server ownership |
| TF | ENV, AI, POP, ECO, factories, G evolution | time semantics are not work scheduling |
| SD | G, MW, NX, Construction, POP, WQ | no universal ChunkId |
| MAT | G9, Matter, Item, Construction, ENV, ECO | one material identity, many projections |
| WT | Item, Construction, Matter, ECO, AI | planner over M0, not a second transaction engine |
| WQ | AI, NAV, gameplay, admin tools | query fabric is not canonical storage |
| LIFE | C18, RL, POP, AI, N6 | dormant means lower resolution, not deletion |
| WB | G12, RL, C18, S1, AI, POP, ENV | budget does not imply authority |
| COMPAT | persistence, network, content, OPS | versions are explicit and migratable |
| SEC | IAM/AUTHZ/WQ/NX/ECO | security gates do not redefine gameplay truth |
| N3-N6 | all distributed domains | authority route never becomes entity identity |
| S1 | G/AI/ENV/POP heavy work | worker proposes, authority commits |

---

# 9. Cross-program convergence scenarios

## 9.1 Mining

```text
Actor
 -> IAM session
 -> AUTHZ can_mine
 -> WQ locate deposit
 -> SD/RF locate target
 -> WT mining operation
 -> MAT identifies material
 -> Matter removes mass
 -> Item receives resource
 -> M0 atomic commit
 -> NX replication
 -> LIFE/WB decide detail level
```

## 9.2 Building a base

```text
Actor/AI
 -> WQ finds site/resources
 -> AUTHZ checks rights
 -> Construction BuildPlan
 -> WT consumes Items + mutates Construct
 -> MAT identifies required materials
 -> M0 commit
 -> C22/C24 derived presentation
 -> LIFE/C18 activity
 -> NX8 replication budget
```

## 9.3 Autonomous settlement

```text
POP needs
 -> AI goals
 -> WQ world knowledge
 -> NAV routes
 -> ECO orders
 -> WT operations
 -> Item/Matter/Construction mutations
 -> TF schedules coarse progression
 -> WB decides simulation detail
 -> LIFE promotes nearby actors
```

## 9.4 Player inside a moving ship crossing servers

```text
Player entity in Ship Frame
 -> RF frame hierarchy
 -> SP ship motion
 -> SD maps current location
 -> N3 route lookup
 -> N4 ship/object handoff
 -> N5 player/session handoff
 -> N6 overlap ghosts
 -> NX8 interest budget
 -> same player/item/construct identities preserved
```

---

# 10. What may be implemented now as contracts/mocks

These stages are intentionally low-risk and may proceed without waiting for the current G/T/CH candidates, provided PC0 registers each implementation frontier before code acceptance.

```text
IAM0     Principal/Account/Session contracts
IAM1     local self-host provider mock
AUTHZ0   policy request/decision contracts + deny-by-default fake
RF0      reference-frame identity/transform contracts
TF0      simulation-time/domain-tick contracts + fake clock
MAT0     material identity/registry contracts + deterministic fixture ontology
WT0      WorldOperation/WorldTransactionPlan contracts over mock domain intents
WQ0      WorldQuery/result/adapter contracts + fake adapters
WQ1      deterministic merge/ranking
LIFE0    common activity lifecycle contracts
WB0      work request/budget/decision contracts
WB1      deterministic fake budget arbiter
COMPAT0  version taxonomy and compatibility decision contracts
SEC0     trust-boundary and negative-test requirements
```

All mock/fake implementations must be replaceable adapters and must not become hidden canonical state.

---

# 11. What may begin as real parallel implementation

## Safe parallel group A

Recommended maximum initial active set:

```text
IAM0/IAM1
MAT0
WT0
WQ0/WQ1
```

Reason:

- they touch different ownership domains;
- MAT0 is needed before G9;
- WT0 is needed before serious Geo/Matter/Construction composition;
- WQ is needed before AI/NAV;
- IAM can evolve independently from terrain/construction.

## Safe parallel group B

After the first contracts freeze:

```text
RF0/RF1
TF0
AUTHZ0
LIFE0
WB0/WB1
COMPAT0
```

RF should precede SD0 to avoid embedding one-frame assumptions in WorldAddress.

## Existing network continuation

Because A3 is accepted in the historical network roadmap, `B1` can be prepared as a separate server-to-server adapter frontier once PC0 explicitly declares it. `B2/N3+` should keep their existing dependency gates.

---

# 12. What must remain mocked/reserved for now

Do not begin production implementations yet for:

```text
SD distributed routing logic before RF0 + N3 contracts
TF production global scheduler before WB contracts
WB production global arbiter before multiple real consumers exist
AUTHZ global organization policy before IAM0 and existing permission adapters are mapped
WT distributed cross-authority commit before N3/N4 policy exists
WQ distributed fan-out before SD/N3/AUTHZ
GM production before G9/G10 + MAT + WT
SP production interplanetary handoff before RF + N3-N6
ENV large-scale atmosphere before MAT/TF/WB
AI LLM-controlled execution before WQ/WT/AUTHZ Actor API
POP large population runtime before LIFE/TF/WB
ECO global markets before physical ownership/WT/MAT contracts
OPS migration controls before N3/N4
production dynamic shard split/merge before N3-N6 are proven
```

---

# 13. Current active-frontier compatibility

R3 must not block currently authorized work:

```text
G8.4 -> acceptance -> G8.5
T1B.2 -> acceptance -> T1B.3
CH9.5 -> focused acceptance
C22/TS convergence -> main integration -> TS0.4
network tuning -> explicit PC0 frontier declaration before next acceptance
```

Specific future guards:

```text
G9 must consume MAT identity
G10/GM must not replace Matter truth
G12 generation scheduler must consume WB contracts
T2 must consume SD/RF only when scale composition needs them
AI must consume C19 rather than creating a parallel construction executor
NX8 must coordinate with WB rather than becoming a global simulation scheduler
```

---

# 14. Integration milestones

## V1 — Persistent Planet Outpost

```text
procedural terrain
player connects
resource discovered
Matter excavated
physical Item resource produced
real Construction built
machine consumes/produces
server restart
second client reconnects
same canonical state recovered
```

Required programs:

```text
G + Matter + Item + Construction + CH + NX + M0
MAT + WT contracts
```

## V2 — Seamless Two-Region World

```text
server A world region
player crosses boundary
server B becomes authority
no duplicate entity
no loading-screen semantic reset
inventory/construct identity preserved
```

Required: `B1/B2 + N3/N4/N5/N6 + SD/RF`.

## V3 — Moving Ship / Station

```text
player in ship interior frame
ship travels in space
ship crosses region/server
ship docks to station
interior/item/player identities remain stable
```

Required: `RF + SP + N3-N6 + Construction mobile/spatial + NX7/NX8`.

## V4 — Autonomous Settlement

```text
5-20 agents
food/material/shelter needs
world queries
resource extraction
construction
repair
production
surplus exchange
persistent restart
```

Required: `AI + WQ + WT + NAV + TF + LIFE + WB + ECO`.

## V5 — Distributed Living World

```text
3+ authorities
100+ simulated agents
human players
100k-class construct
persistent terrain mutations
server restart
server drain/migration
bounded CPU/network budgets
```

This is the first milestone that should be treated as proof of the R3 architecture as a whole.

---

# 15. R3 architecture stop rules

Architecture review is mandatory if a branch introduces any of the following without an explicit R3 owner:

```text
new global account/player identity
new universal chunk/world address
new global material registry
new cross-domain transaction coordinator
new universal query database
new global simulation clock
new global work scheduler
new authority directory
new organization/permission foundation
new persistent lifecycle model
new direct AI canonical-store access
new LLM-to-store mutation path
```

No branch may justify duplicate ownership by calling it a cache, manager, registry or adapter if it changes canonical semantics.

---

# 16. Acceptance for GLOBAL-P0 R3

R3 architecture can be promoted from candidate only when:

```text
[ ] architecture document reviewed
[ ] machine-readable R3 program config matches this document
[ ] R3 ownership candidate reviewed
[ ] current G/T/CH/TS frontiers show no critical ownership conflict
[ ] existing A0/A1/S0/S1/M0/A3 semantics remain unchanged
[ ] active network tuning frontier is explicitly declared before next NX acceptance
[ ] initial parallel contract wave is selected, not all programs activated at once
[ ] PC0 is updated on main after merge
```

After merge, active branch passports may synchronize `GLOBAL-P0-2026-08-11-R3` as they move to their next authorized frontier. Accepted/frozen historical branches are not rewritten merely to carry R3.
