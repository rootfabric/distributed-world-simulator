# Seamless World Architecture R2

Status: `RESEARCH / ARCHITECTURE CANDIDATE — SUPERSEDES R1 FOR FUTURE IMPLEMENTATION`

Branch: `research/seamless-world-architecture-r1`

Base lineage at branch creation: `main @ c58339c30e6d7e708a06c41e59208bd45f0709a4`

R1 remains preserved as research history. This R2 document is the current architectural candidate for future implementation planning on this branch.

This document does **not** activate SM1 production work, reopen frozen SM0, or bypass the sequential V0/P product train. Any future production branch must start from the exact accepted predecessor declared by then-current `main` after explicit SM1 activation.

---

## 1. Why R2 exists

R1 correctly introduced four independent concerns:

```text
Spatial Cell
Canonical Authority
InteractionIsland
Edge Gateway
```

A follow-up review of the already-proven SM0 item and player handoff evidence exposed one missing production abstraction: a player rarely migrates as a naked entity. Real gameplay state includes inventory, equipment, hotbar, carried containers, nested item relationships and operation-ledger continuity.

Migrating every carried item independently would create unnecessary ownership transitions, race windows and scaling cost proportional to inventory size.

R2 therefore adds a fifth architectural concept:

```text
AuthorityDomain
```

and separates it from `InteractionIsland`.

The central R2 distinction is:

```text
WHERE IS IT?
    Spatial Cell / Spatial Address

WHO MAY WRITE?
    Canonical Authority / OwnershipRecord

WHAT STATE MIGRATES AS ONE OWNERSHIP UNIT?
    AuthorityDomain

WHAT MUST BE SIMULATED TOGETHER?
    InteractionIsland

HOW DOES A CLIENT ENTER THE WORLD?
    Edge Gateway
```

Therefore:

```text
SpatialCellId
!= AuthorityId
!= AuthorityDomainId
!= InteractionIslandId
!= GatewayId
```

---

## 2. What is retained from R1

R2 keeps the following R1 decisions unchanged:

- stable canonical identity across processes;
- exactly one canonical writer;
- monotonic `AuthorityEpoch` and `FencingToken`;
- `DIRECTORY_COMMITTED` as the only ownership linearization point;
- Edge Gateway is non-authoritative;
- PRIMARY/OBSERVER/WARM are routing roles, not ownership grants;
- client session identity is independent of gateway process identity;
- visual seamlessness cannot create canonical truth;
- static multi-authority correctness must precede dynamic placement;
- dynamic placement must consider interaction-cut and migration cost, not CPU/player count alone;
- SM0 is an evidence donor, not a production base;
- no full-mesh requirement;
- operation identity is end-to-end across gateways and routes.

---

## 3. AuthorityDomain — new production ownership unit

### 3.1 Purpose

`AuthorityDomain` is the bounded set of canonical state whose writer ownership changes together through one directory ownership record.

A domain is not necessarily one entity and is not necessarily one physics island.

Examples:

```text
PlayerAuthorityDomain player/42
  player aggregate
  inventory root
  hotbar
  equipment bindings
  carried Item Graph subtree
  mounted/carried state that follows the player ownership unit
  domain operation sequence
```

or:

```text
WorldAuthorityDomain cell-group/earth/17
  independently owned world aggregates
  world items currently bound to this domain
```

or later:

```text
VehicleAuthorityDomain ship/17
  ship aggregate
  attached canonical subsystems
  selected owned state closure
```

### 3.2 Domain identity is stable

```text
AuthorityDomainId != AuthorityId
```

The same domain can move:

```text
Authority A -> Authority B -> Authority C
```

without changing its own identity.

### 3.3 Ownership record applies to the domain

Conceptually:

```text
OwnershipRecord {
    subject_id = AuthorityDomainId
    owner_authority_id
    authority_epoch
    fencing_token
    directory_generation
    authority_incarnation
    state_revision
    lease_state
    route_revision
}
```

Individual domain members may inherit canonical authority from the domain instead of requiring their own directory CAS.

This avoids O(number_of_inventory_items) ownership commits during normal player handoff.

---

## 4. AuthorityBinding — how subjects inherit authority

R2 introduces an explicit binding between canonical subjects and an authority domain.

Conceptual contract:

```text
AuthorityBinding {
    subject_id
    authority_domain_id
    binding_generation
    mode = INHERIT | EXPLICIT
    binding_revision
}
```

### 4.1 INHERIT

The normal carried-state mode.

```text
Item X
  -> InventoryRoot
  -> PlayerAuthorityDomain/42
  -> current domain owner Authority B
```

The item keeps its stable `ItemId`, while writer authority follows the domain.

### 4.2 EXPLICIT

Used only where an independently owned subject truly needs its own ownership record/policy.

It must not become the default for every inventory item.

### 4.3 Required invariant

A canonical mutation must resolve effective authority through the current binding generation and current domain ownership record.

Stale binding generation, stale domain epoch or stale fencing token rejects the mutation.

---

## 5. Pickup / drop / attach / detach semantics

Pickup is not merely a visual inventory operation. It changes both Item Graph membership and authority binding.

### 5.1 Pickup

Initial:

```text
Item X
Item Graph: WORLD container
AuthorityBinding: WorldDomain/A
```

After canonical pickup:

```text
Item X
Item Graph: PlayerInventory/42
AuthorityBinding: PlayerAuthorityDomain/42
```

The operation must atomically preserve these truths:

- stable `ItemId`;
- no duplicate Item Graph node;
- no stale world binding;
- no player binding without matching Item Graph membership;
- one canonical operation result for one `OperationId`.

### 5.2 Drop

Reverse transition:

```text
PlayerAuthorityDomain/42
  -> WorldAuthorityDomain/current-world-domain
```

The target world domain is resolved from canonical world/placement state, not from a stale gateway projection.

### 5.3 No second Item Graph

R2 retains the P9 lesson:

```text
Item Graph remains canonical for item/container structure.
Seamless runtime owns authority/routing metadata only.
```

---

## 6. PlayerAuthorityDomain

R2 defines the first mandatory domain use case.

Conceptually:

```text
PlayerAuthorityDomain {
    authority_domain_id
    player_entity_id
    domain_revision
    operation_sequence
    inventory_root_id
    carried_binding_generation
    owner_authority_id
    authority_epoch
}
```

The exact payload remains domain-owned and may evolve, but the handoff system treats it as one ownership unit.

### 6.1 Why this exists

The existing SM0 player handoff proves player identity and authority transition.

P9 separately proves item identity, freeze/shadow/replay/foreign-owner routing and authority-boundary transfer semantics.

R2 combines those proven ideas without requiring one transfer per carried item.

### 6.2 Required scaling invariant

For normal inherited carried state:

```text
1 carried item     -> 1 PlayerAuthorityDomain ownership CAS
10 carried items   -> 1 PlayerAuthorityDomain ownership CAS
100 carried items  -> 1 PlayerAuthorityDomain ownership CAS
1000 carried items -> 1 PlayerAuthorityDomain ownership CAS
```

The serialized payload cost may grow with actual state size, but ownership transitions must not become one directory transaction per item.

---

## 7. DomainMutationBarrier

A handoff requires an exact state boundary.

R2 introduces:

```text
DomainMutationBarrier {
    authority_domain_id
    domain_revision
    last_committed_operation_sequence
    freeze_generation
    timeline_stamp
}
```

### 7.1 Purpose

The barrier answers:

> Which inventory/gameplay mutations are included in the transfer snapshot, and which belong after the transfer?

Without this, operations racing with handoff can be lost, duplicated or committed on the wrong owner.

### 7.2 Required semantics

Before freeze:

```text
operations <= barrier.operation_sequence
```

are included in the prepared domain state.

After freeze, new mutations use one explicit policy:

- queue for target;
- reject/retry with deterministic code;
- or another checkpoint-specific bounded rule.

They may never silently commit only on the stale source.

### 7.3 Examples that must be fenced during handoff

- pickup;
- drop;
- stack split/merge;
- container move;
- equip/unequip;
- mount/unmount;
- item use;
- player state mutations covered by the domain closure.

---

## 8. Production authority-domain transfer

R2 explicitly distinguishes **SM0/P9 evidence** from the future production protocol.

P9 is retained as proof of useful primitives:

- source freeze;
- target shadow prepare;
- stable item identity;
- expected epoch/revision checks;
- replay conflict detection;
- retirement evidence;
- process-isolated execution;
- failure handling.

But P9's laboratory rollback path must not be copied after canonical directory ownership commit.

### 8.1 Production flow

```text
ACTIVE_SOURCE
    |
    v
TARGET_ROUTE_WARM
    |
    v
SOURCE_DOMAIN_FROZEN
    |
    v
TARGET_DURABLY_PREPARED_SHADOW
    |
    v
DIRECTORY_COMMITTED   <-- only ownership linearization point
    |
    v
TARGET_ACTIVE
    |
    v
SOURCE_RETIRED / READ_ONLY
```

### 8.2 Rollback rule

Before `DIRECTORY_COMMITTED`:

```text
rollback/cancel may restore source progress
```

After `DIRECTORY_COMMITTED`:

```text
NO ROLLBACK TO OLD SOURCE WRITER
```

If target fails after commit, recovery must converge from the committed ownership record by:

- restarting/recovering the committed target incarnation as allowed by policy;
- controlled forward recovery to another authority through a new fenced transfer;
- fail-closed temporary unavailability.

The old source cannot regain writer authority merely because target activation failed.

---

## 9. InteractionIsland remains separate

R2 narrows `InteractionIsland` to simulation-locality/co-location constraints.

It is **not** the default container for a player's inventory.

Typical island:

```text
InteractionIsland ship/17
  ship hull
  pilot physical presence
  passengers
  docked component
  rigid/physics constraints
  nearby objects under a bounded interaction policy
```

An `InteractionIsland` may be contained in or constrain an `AuthorityDomain`, but the two concepts must not collapse.

Rule:

```text
AuthorityDomain = ownership/migration closure
InteractionIsland = co-simulation/placement constraint
```

This prevents ordinary inventory structure from being confused with physics interaction topology.

---

## 10. Temporal continuity

R2 adds explicit simulation-time continuity across authority migration.

Conceptual stamp:

```text
AuthorityTimelineStamp {
    timeline_epoch
    simulation_tick
    state_revision
}
```

The exact clock implementation is not frozen by architecture, but the target must know that transferred state is a continuation of an existing simulation timeline rather than a new local tick-zero state.

This is required for:

- movement prediction/reconciliation;
- interpolation;
- projectiles and time-dependent actions;
- moving/nested reference frames;
- gateway projection ordering;
- measuring visible handoff rewind/correction.

Required invariant:

```text
accepted canonical/presentation timeline must not roll back because authority process changed
```

---

## 11. Edge Gateway mobility

R1 defined failure-driven rehome. R2 generalizes this to `Gateway Mobility`.

Two reasons may trigger rehome:

```text
FAILURE_DRIVEN
QUALITY_DRIVEN
```

Example:

```text
client starts near EU gateway
later network path makes US gateway materially better
```

A controlled gateway rehome may occur without changing canonical player authority.

Therefore:

```text
Gateway handoff != Authority handoff
```

Required invariants:

- `PlayerEntityId` unchanged;
- logical/resumable `ClientSessionId` continuity;
- `OperationId` dedup survives path change;
- gateway route cache has no ownership power;
- temporary dual-path retry cannot duplicate canonical commits;
- hysteresis/cooldown prevents route flapping.

---

## 12. Protocol/build compatibility gate

R2 adds a compatibility check before a target can become a valid warm/prepare candidate.

Authority/gateway processes should expose at least:

```text
build_id
protocol_hash
supported_contract_versions
capabilities
```

Before target prepare, the handoff layer validates required compatibility.

An incompatible target is not allowed to accept a domain merely because it is healthy or geographically suitable.

This supports rolling upgrades without turning handoff into a schema mismatch fault source.

---

## 13. Seamlessness dimensions

R2 makes acceptance multi-dimensional.

A transition is not called fully seamless only because writer correctness passed.

Report separately:

```text
AUTHORITY_CORRECTNESS
STATE_CONTINUITY
TRANSPORT_CONTINUITY
VISUAL_CONTINUITY
```

### Authority correctness

- one writer;
- monotonic owner/epoch/fence;
- stale writer rejection;
- replay-safe transfer.

### State continuity

- stable Player/Item identities;
- inventory graph continuity;
- operation sequence continuity;
- no state revision rollback;
- temporal continuity.

### Transport continuity

- stable or resumed client session;
- no unnecessary reconnect during authority handoff;
- gateway rehome continuity;
- no duplicate operations after route changes.

### Visual continuity

- projection continuity;
- prediction/interpolation continuity;
- no visible duplicate/despawn respawn cycle;
- bounded correction/rewind under declared network conditions.

---

## 14. Required seamless metrics

Future acceptance should record, where applicable:

```text
handoff_total_ms
canonical_write_gap_ms
movement_input_gap_ms
inventory_operation_gap_ms
projection_gap_ms
visual_gap_frames
max_prediction_error
hard_correction_count
client_disconnect_count
client_session_change_count
gateway_rehome_count
gateway_route_flip_count
duplicate_entity_count
duplicate_item_count
stale_owner_mutations_accepted
duplicate_canonical_commits
```

A correctness PASS and a visual PASS are separate evidence fields.

---

## 15. Revised target topology

```text
                          Gateway Discovery
                         /       |        \
                    Gateway EU Gateway US Gateway AP
                         \       |        /
                          \      |       /
                              Client
                                |
                         stable/resumable
                           client session
                                |
                                v
                      +-------------------+
                      | Edge Gateway      |
                      | non-authoritative |
                      +-------------------+
                         /      |       \
                    PRIMARY OBSERVER    WARM
                       /        |          \
                      v         v           v
                Authority A Authority B Authority C
                       \        |          /
                        +-------+---------+
                                |
                                v
                     Ownership Directory
                       CAS + fencing
                                |
              +-----------------+----------------+
              |                 |                |
        AuthorityDomains   InteractionIslands   Spatial Model
        ownership closure  locality constraint cells/addresses
```

---

## 16. Revised static-first program

The future production sequence is now:

```text
SM1-H0  Production contracts
SM1-H1  Durable Ownership Directory
SM1-H2  Generic AuthorityDomain transfer
SM1-H2A AuthorityBinding + Domain Closure
SM1-H2B Player Carrying Domain Lab
SM1-H3  Single Edge Gateway transparency
SM1-H4  PRIMARY/OBSERVER composition
SM1-H5  Gateway-mediated PlayerAuthorityDomain handoff
SM1-H6  Multi-region gateway selection
SM1-H7  Gateway mobility/rehome/failure
SM1-H8  Projection/AOI/interest aggregation
SM1-H9  Cross-authority operation foundation
SM1-H10 Physical InteractionIsland runtime
SM1-H11 Static N-authority world
SM1-H12 Integrated static seamless-world acceptance
```

Only after H12 acceptance:

```text
SM-D1 Dynamic AuthorityDomain placement
SM-D2 Dynamic split/merge
SM-D3 Interaction-aware dynamic meshing
```

---

## 17. Why these R2 additions were made

### AuthorityDomain / AuthorityBinding

**Origin:** follow-up analysis of existing SM0 player handoff + P9 item-boundary proof and the real gameplay case of player-carried nested inventory.

**Problem addressed:** independent transfer per item creates unnecessary CAS count and race surface.

**Improvement:** one ownership transition for a bounded state closure while keeping stable Item Graph identity.

### DomainMutationBarrier

**Origin:** distributed transfer consistency requirement exposed by pickup/drop/container operations racing with player handoff.

**Problem addressed:** ambiguous snapshot membership and lost/duplicated operations.

**Improvement:** exact cut between source-committed and target-post-handoff operations.

### P9 rollback restriction after Directory commit

**Origin:** reconciliation of SM0 laboratory transfer semantics with R1's stronger canonical Directory CAS model.

**Problem addressed:** restoring old source after canonical owner commit would violate fencing and one-writer semantics.

**Improvement:** irreversible ownership decision plus forward recovery.

### Temporal continuity

**Origin:** seamless movement/prediction/reference-frame review.

**Problem addressed:** correct ownership transfer can still cause tick/revision rewind or visual hard correction.

**Improvement:** handoff is a continuation of one simulation timeline.

### Gateway mobility

**Origin:** multi-region gateway architecture plus the distinction between authority movement and transport-path movement.

**Problem addressed:** a client may need a better gateway without changing gameplay authority.

**Improvement:** independent edge-path optimization and failure recovery.

### Protocol compatibility gate

**Origin:** operational requirement for rolling server upgrades in a long-lived world.

**Problem addressed:** healthy but incompatible target accepting an unreadable transfer.

**Improvement:** fail before prepare rather than during canonical ownership transition.

---

## 18. Explicit non-goals of R2

R2 does not authorize or require yet:

- automatic arbitrary InteractionIsland formation;
- dynamic allocator;
- global consensus technology choice;
- Kubernetes/Agones deployment;
- a Star Citizen-style Replication Layer clone;
- one ownership record per carried item;
- cross-authority Construction/Matter-wide transactions;
- full-world replication;
- mandatory server full mesh;
- gateway canonical world state.

---

## 19. Production activation rule

This architecture may be reviewed and refined now.

Production implementation may begin only after project control satisfies all required lineage gates, including the post-P6 explicit SM1 decision.

At activation time:

```text
production SM1 base = exact accepted predecessor declared by then-current main
```

Never:

```text
feature/sm0-two-authority-seamless-handoff-lab
research/seamless-world-architecture-r1
```

SM0 and this research branch remain donors/evidence only.
