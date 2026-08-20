# Seamless World SM1 Roadmap R2

Status: `RESEARCH ROADMAP CANDIDATE — NOT ACTIVATED`

Architecture: `../architecture/SEAMLESS_WORLD_ARCHITECTURE_R2_RU.md`

This roadmap supersedes `SEAMLESS_WORLD_SM1_ROADMAP_RU.md` for future implementation planning on this research branch. The older roadmap remains as history of R1.

## 1. Objective

Build a production-capable **static seamless multi-authority world** before attempting dynamic placement.

R2 adds a missing bridge between generic authority transfer and player handoff:

```text
AuthorityDomain
AuthorityBinding
Player Carrying Domain
DomainMutationBarrier
```

The project must prove that a player crosses authority boundaries together with real carried canonical state before declaring player seamlessness complete.

## 2. Control / activation rule

This roadmap is research-only.

Production SM1 work may start only after:

1. architecture candidate is independently reviewed/closed;
2. the active V0/P train reaches its required predecessor;
3. P6 is accepted on main lineage;
4. main records explicit `ACTIVATE_V0_SM1` rather than defer;
5. main declares the exact accepted successor base;
6. fresh SM1 epoch/work order exists;
7. required runtime mutation lease/ownership is rotated to SM1;
8. Director dispatches the first SM1 implementation checkpoint.

Research branch history is never the production base.

## 2.1 P5/P6 -> SM1 legacy-network transition map

The product-train transition is deliberately **not** `P5 -> throw away the old network -> SM1`.
The current network remains the production carrier through P6; after P6, main performs the explicit seamless decision and, if `ACTIVATE_V0_SM1` is selected, production SM1 starts from the then-current accepted V0 baseline.

Therefore pre-SM1 network work must preserve future foundations without spending large repair effort on synchronization/routing machinery that SM1 is expected to replace.

### Mandatory classification for every P5/P6 network RED

Before changing production code, classify the failure into exactly one primary class:

```text
FOUNDATION
LEGACY_TRANSPORT
HARNESS_TEST
```

Rules:

- `FOUNDATION` — canonical state/identity/persistence/operation/recovery correctness that remains required under SM1. Repair fully and preserve as production behavior.
- `LEGACY_TRANSPORT` — current transport/session/convergence/routing choreography that SM1 is expected to replace or substantially adapt. Apply only the smallest bounded correctness repair required to keep P5/P6 valid; do not redesign the legacy network into the future architecture.
- `HARNESS_TEST` — process lifecycle, fixed waits, port reuse, wrapper status capture, fixture orchestration, evidence collection, or another non-product defect. Repair the harness/test owner; do not mutate production semantics to satisfy a harness artifact.

A RED must never be hidden, selectively retried, removed from the continuous regression, or converted to PASS because it is considered legacy. If a required legacy test remains RED, it remains blocking unless a separate explicit main-owned control decision changes the required predicate.

### KEEP / ADAPT / REPLACE / RETIRE map

| Current capability | Transition | SM1 intent |
| --- | --- | --- |
| Canonical Item Graph structure and item/container relationships | `KEEP` | Remains canonical structure; AuthorityDomain must not become a second Item Graph. |
| Stable `PlayerEntityId`, `ItemId`, subject identity | `KEEP` | Identity must survive authority/session transitions. |
| Durable gameplay state and restart recovery | `KEEP` | Becomes more important under multi-authority recovery. |
| End-to-end `OperationId`, dedup/exactly-once semantics | `KEEP` | Required across gateway/authority retry and handoff. |
| Server/domain-authoritative durable gameplay truth | `KEEP` | Ownership mechanism changes, canonical-state discipline does not. |
| SM0 single-writer/handoff/recovery contracts | `PORT_KEEP` | Donor invariants for SM1 transfer/fencing; do not copy obsolete rollback semantics past Directory commit. |
| M3/M4 gameplay/network composition services | `ADAPT` | Preserve gameplay semantics while replacing ownership/routing boundaries underneath. |
| Current client replica machinery | `ADAPT` | Reuse useful projection/prediction pieces, but make them epoch/fence/projection aware. |
| Raw ENet packet transport where useful | `ADAPT` | Transport implementation may survive; authority semantics must not depend on the old topology. |
| Current direct client -> gameplay authority routing/session choreography | `REPLACE` | Replaced by stable gateway/session routing and canonical Directory-based authority resolution. |
| Current authority ownership/routing assumptions | `REPLACE` | Replaced by Ownership Directory + epoch/fence/incarnation + AuthorityBinding. |
| M5 final graphical checksum convergence barrier as production synchronization authority | `RETIRE_TEST_ONLY` | May remain as compatibility/acceptance machinery, but must not become the future ownership protocol. |
| Legacy client/backend finalization choreography tied to one authority session | `REPLACE` | Replaced by PRIMARY/OBSERVER/WARM projection and explicit handoff lifecycle. |
| SM1 Ownership Directory, fencing, incarnation authorization | `NEW_CANONICAL` | New production ownership authority after activation. |

### Transfer the invariant, not necessarily the legacy mechanism

The P5 M5 convergence repair exposed a durable rule that **does** carry into SM1:

```text
prepared/locked state is revocable until final consumption;
if canonical state advances, stale prepared evidence cannot authorize completion.
```

In legacy M5 this is expressed through convergence generations and authoritative checksums.
In SM1 the same correctness rule must be expressed through current ownership/binding identities such as:

```text
DirectoryGeneration
AuthorityEpoch
FencingToken
AuthorityIncarnation
binding_generation
```

A stale generation/epoch/fence/incarnation/binding must fail closed rather than complete a handoff or mutation.

### Current M7/P5 diagnostic rule

For failures in restart/recovery fixtures, including hotbar/equipment/Item Graph continuity:

- if canonical hotbar/equipment/Item Graph state is actually lost, duplicated, rolled back, or restored incorrectly after restart -> `FOUNDATION`, repair fully now;
- if canonical state is correct and the failure comes from old process cleanup, ENet session timing, port reuse, fixed sleep/wait assumptions, or legacy client-finalization choreography -> `LEGACY_TRANSPORT` or `HARNESS_TEST`, repair minimally at the correct owner;
- do not use an M7/P5 failure as justification for a broad redesign of M5/M7 legacy networking before the post-P6 SM1 activation gate.

### Regression policy before SM1

The complete P5/P6 regression remains a safety net. Legacy tests may still expose real foundation defects, so the suite remains required until an explicit main-owned control change says otherwise.

The optimization target before SM1 is therefore:

```text
fully repair future foundation defects
+ minimally stabilize required legacy network behavior
+ repair harness defects at the harness layer
- avoid deep legacy-network redesign
```

## 3. Revised milestone order

```text
PRE-ACTIVATION architecture closure

SM1-H0   Production seamless contracts
SM1-H1   Durable Ownership Directory
SM1-H2   Generic AuthorityDomain transfer
SM1-H2A  AuthorityBinding + Domain Closure
SM1-H2B  Player Carrying Domain Lab
SM1-H3   Single Edge Gateway transparency
SM1-H4   PRIMARY/OBSERVER multi-authority gateway
SM1-H5   Gateway-mediated PlayerAuthorityDomain handoff
SM1-H6   Multi-region gateway selection
SM1-H7   Gateway mobility / rehome / failure
SM1-H8   Production projection / AOI / interest aggregation
SM1-H9   Cross-authority operation foundation
SM1-H10  Physical InteractionIsland runtime
SM1-H11  Static N-authority world
SM1-H12  Integrated static seamless-world acceptance
```

Only after H12:

```text
SM-D1 Dynamic AuthorityDomain placement
SM-D2 Dynamic split/merge
SM-D3 Interaction-aware dynamic meshing
```

Dynamic balancing is not an SM1 acceptance requirement.

---

# PRE-ACTIVATION — Architecture closure

## Goal

Close R2 architecture without production runtime mutation.

## Required review focus

- Directory CAS/fencing remains the only ownership linearization point;
- AuthorityDomain does not become a second Item Graph;
- AuthorityBinding inheritance has deterministic stale-generation rejection;
- InteractionIsland remains a placement/locality concept, not a generic inventory container;
- P9 rollback semantics are not copied past Directory commit;
- H2A/H2B truly precede H5;
- gateway remains non-authoritative;
- control/product-train lineage is not bypassed.

## Acceptance

Fresh independent architecture/control review PASS on exact head, or repair cycle until PASS.

---

# SM1-H0 — Production Seamless Contracts

## Goal

Freeze generic contracts on the current accepted product baseline.

## Identity contracts

```text
AuthorityId
AuthorityIncarnation
EntityId / SubjectId
AuthorityDomainId
InteractionIslandId
ClientSessionId
GatewayId
TransferId
OperationId
```

## Ownership contracts

```text
OwnershipRecord
AuthorityEpoch
FencingToken
DirectoryGeneration
RouteRevision
LeaseState
```

## Domain contracts

```text
AuthorityBinding
binding_generation
mode = INHERIT | EXPLICIT
DomainMutationBarrier
domain_revision
operation_sequence
freeze_generation
AuthorityTimelineStamp
```

## Gateway contracts

```text
ClientAuthorityRoute
PRIMARY | OBSERVER | WARM | DEGRADED | DRAINING
```

## Compatibility contracts

```text
build_id
protocol_hash
supported_contract_versions
capabilities
```

## Tests

- exact schemas;
- invalid IDs;
- stale epoch/fence/generation;
- binding-generation rollback;
- gateway role cannot grant ownership;
- projection read-only bypass rejection;
- same OperationId conflicting payload;
- AuthorityDomainId/InteractionIslandId/SpatialCellId independence.

---

# SM1-H1 — Durable Ownership Directory

## Goal

Provide one canonical ownership oracle before production handoff.

## Minimum behavior

```text
lookup owner
register authority incarnation
mark ACTIVE/DRAINING/UNAVAILABLE
CAS A/N/F -> B/N+1/F+1
persist/recover owner record
reject stale owner/fence
```

## Critical tests

- monotonic CAS;
- duplicate CAS retry;
- directory restart before CAS;
- crash after durable CAS before reply;
- stale lookup response;
- resurrected A@N after B@N+1 commit is fenced;
- draining target cannot receive new domain placement.

---

# SM1-H2 — Generic AuthorityDomain Transfer

## Goal

Port SM0 transfer correctness to a generic domain with real Directory CAS.

Use a bounded synthetic domain first.

## Flow

```text
SOURCE ACTIVE
TARGET WARM
SOURCE DOMAIN FROZEN
TARGET DURABLY PREPARED
DIRECTORY CAS COMMIT
TARGET ACTIVE
SOURCE RETIRED/READ_ONLY
```

## Non-negotiable rule

Before Directory commit, cancel/rollback may restore source.

After Directory commit, old source can never become writer again through local rollback.

## Tests

- repeated A<->B loops;
- stale source packet after commit;
- source/target crash around every phase;
- target failure after commit => forward recovery/fail closed, never old-source resurrection;
- duplicate/conflicting TransferId;
- process incarnation change;
- global writer analyzer <= 1;
- timeline/revision never roll back.

---

# SM1-H2A — AuthorityBinding + Domain Closure

## Goal

Prove that domain ownership can cover a bounded set of subjects without one ownership CAS per member.

## First fixture

```text
Domain D
  subject root
  member-1
  member-2
  nested-member-3
```

## Required behavior

- members use `INHERIT` binding;
- binding generation is versioned;
- effective owner resolves through current domain record;
- stale binding cannot mutate after rebind;
- `EXPLICIT` owner is reserved for independently owned subjects;
- Directory ownership transition count is O(domains), not O(members).

## Tests

- 1/10/100/1000 inherited members with one domain CAS;
- rebind one member to another domain;
- stale binding-generation mutation rejected;
- domain transfer preserves stable member IDs;
- nested relationship structure unchanged by owner move.

---

# SM1-H2B — Player Carrying Domain Lab

## Goal

Connect player handoff, Item Graph and item authority semantics before introducing gateway-mediated handoff.

## Canonical fixture

```text
PlayerAuthorityDomain player/42
  PlayerEntityId
  InventoryRoot
    Tool
    Backpack
      Container
        Ore stack
        Battery
        Device
  hotbar
  equipment
```

## Core scenario

```text
World/A owns Item X
Player@A picks up X
X binds to PlayerDomain
PlayerDomain A -> B
X usable on B immediately
Player drops X
X binds to WorldDomain/B
```

## Mandatory assertions

```text
player identity changes = 0
item identity changes = 0
duplicate items = 0
lost items = 0
writer violations = 0
stale A mutations accepted = 0
duplicate operation commits = 0
```

## DomainMutationBarrier tests

Race handoff freeze with:

- pickup;
- drop;
- stack split;
- container move;
- equip/unequip;
- item use.

Each operation must be deterministically included-before-barrier or queued/retried-after-barrier.

## Scale test

Inventory size 1/10/100/1000: ownership CAS count remains one for normal inherited PlayerDomain handoff.

## Restart tests

- source crash before domain CAS;
- target crash before CAS;
- target crash after CAS;
- target restart and recovery;
- stale source recovery cannot mutate carried state.

## Acceptance result

A real player state closure, not a naked player entity, is proven portable.

---

# SM1-H3 — Single Edge Gateway Transparency

## Goal

Insert one non-authoritative gateway after carrying-domain semantics are already correct.

Topology:

```text
Client -> Gateway -> Authority A
```

## Tests

Direct vs gateway equivalence for:

- movement;
- pickup/drop;
- inventory mutation;
- one carried item use;
- duplicate OperationId;
- reconnect/resume.

Gateway must never satisfy an ownership check.

---

# SM1-H4 — PRIMARY / OBSERVER Multi-Authority Gateway

## Goal

Provide canonical route plus read-only foreign visibility.

```text
Client -> Gateway
           PRIMARY -> A
           OBSERVER/WARM -> B
```

## Tests

- target/prepared state arrives before Directory commit: no primary flip;
- observer projection epoch/revision rollback rejected;
- primary unavailable does not auto-promote observer;
- observer loss isolates presentation source;
- carried-domain projection never creates a second Item Graph or writer.

---

# SM1-H5 — Gateway-Mediated PlayerAuthorityDomain Handoff

## Goal

Prove the actual gameplay handoff unit:

```text
Client->Gateway remains stable
PlayerAuthorityDomain A -> B
```

The domain includes player + inventory/hotbar/equipment/carried state closure.

## Preconditions

H1/H2/H2A/H2B/H3/H4 accepted.

## Core assertions

- stable `PlayerEntityId`;
- stable `ClientSessionId`;
- stable carried `ItemId`s;
- Item Graph relationships unchanged;
- one domain ownership CAS;
- input sequence continuity;
- inventory operation sequence continuity;
- AuthorityTimelineStamp does not roll back;
- gateway primary route flips only after Directory commit;
- writer count <= 1;
- no duplicate spawn/despawn-recreate semantics.

## Visual metrics

Capture separately:

```text
movement_input_gap_ms
inventory_operation_gap_ms
projection_gap_ms
visual_gap_frames
max_prediction_error
hard_correction_count
```

---

# SM1-H6 — Multi-Region Gateway Selection

## Goal

Three or more gateways are first-class.

Signals:

- RTT;
- jitter;
- loss;
- health;
- load;
- hysteresis/cooldown.

Local deterministic network simulation is sufficient initially.

Tests cover best-score selection, loss/jitter penalties, unhealthy exclusion and anti-flap behavior.

---

# SM1-H7 — Gateway Mobility / Rehome / Failure

## Goal

Treat gateway change as an edge transport/session transition independent of gameplay authority.

## Modes

```text
FAILURE_DRIVEN
QUALITY_DRIVEN
```

## Scenarios

- G1 dies before forwarding;
- G1 dies after forwarding/before result;
- same OperationId retried through G2 => one commit;
- G1 restarts with stale route cache;
- quality-driven G-EU -> G-US move while Authority B remains owner;
- gateway rehome races with authority handoff;
- temporary dual-path retry cannot duplicate mutation.

## Acceptance

```text
PlayerEntityId unchanged
ClientSessionId preserved/resumed
canonical owner unchanged unless independent authority protocol changes it
```

---

# SM1-H8 — Projection / AOI / Interest Aggregation

## Goal

Production relevance and visual-border hiding.

Tests:

- 1/10/100 clients;
- merged upstream subscriptions;
- budget downgrade;
- stale cache marked non-authoritative;
- rapid enter/leave cleanup;
- authority epoch change invalidates stale projection;
- unrelated source loss does not stall primary route.

---

# SM1-H9 — Cross-Authority Operation Foundation

## Goal

Explicit remote-owner gameplay semantics.

First bounded cases:

```text
player@A -> item@B
player@A -> simple object@B
owner changes B -> C during operation
```

Rules:

- resolve canonical owner;
- expected owner/epoch/revision in operation;
- stale owner rejects;
- explicit retry/re-resolve policy;
- end-to-end OperationId;
- no broadcast-to-all default;
- no gateway mutation authority.

---

# SM1-H10 — Physical InteractionIsland Runtime

## Goal

Keep physically coupled subjects on a suitable simulation authority when policy requires co-location.

First island:

```text
ship/vehicle
pilot physical presence
passengers
mounted component
bounded attached/physics cargo
```

This is deliberately separate from PlayerAuthorityDomain inventory ownership.

Tests:

- spatial cell crossing without forced split;
- membership generation join/leave;
- membership race with handoff;
- invalid partial placement rejected;
- nested reference-frame continuity;
- owner/target restart.

---

# SM1-H11 — Static N-Authority World

## Goal

Remove A/B fixture assumptions.

Progression:

```text
3 authorities -> 4 -> configurable N
```

Tests:

- arbitrary AuthorityIds;
- A->B->C transfers;
- simultaneous independent domain transfers;
- C outage isolates unrelated A/B;
- node registration/draining;
- gateway interest-driven connectivity;
- no N-backend-connection-per-client requirement.

---

# SM1-H12 — Integrated Static Seamless-World Acceptance

## Goal

Prove the whole static architecture as one user-visible journey, not only disconnected unit gates.

## Canonical journey

```text
Client -> Gateway G1 -> Authority A
player moves
player picks up Item X
X enters nested inventory
player uses X
B becomes WARM/OBSERVER
PlayerAuthorityDomain A -> B
client transport remains stable
player continues movement
player uses X immediately on B
foreign projections from A/C remain visible
G1 fails or quality degrades
session rehomes to G2
Authority B remains canonical owner
player drops X
X becomes WorldDomain/B item
B restarts/recoveries under fencing rules
player continues
```

Run under deterministic latency/jitter/loss/reorder presets.

## Final oracles

```text
writer_violations = 0
identity_changes = 0
duplicate_item_ids = 0
lost_item_ids = 0
stale_owner_mutations_accepted = 0
duplicate_canonical_commits = 0
unexpected_session_resets = 0
canonical_revision_rollbacks = 0
```

Report authority, state, transport and visual continuity separately.

---

# SM-D1 / D2 / D3 — Deferred dynamic program

No dynamic placement is activated by this roadmap.

After H12 acceptance only:

### SM-D1

Move existing AuthorityDomains using cost model + normal transfer/Directory CAS.

### SM-D2

Introduce controlled split/merge of domains.

### SM-D3

Use interaction-aware placement/island topology for dynamic meshing.

Allocator decisions never directly grant ownership.
