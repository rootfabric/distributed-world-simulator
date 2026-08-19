# Seamless World Validation Strategy R2

Status: `RESEARCH TEST STRATEGY CANDIDATE — SUPERSEDES R1 FOR FUTURE IMPLEMENTATION`

Architecture: `../architecture/SEAMLESS_WORLD_ARCHITECTURE_R2_RU.md`

Roadmap: `../plans/SEAMLESS_WORLD_SM1_ROADMAP_R2_RU.md`

R2 preserves the SM0 lesson: correctness is proven by adversarial state-transition evidence before visual smoothness claims.

## 1. Four independent acceptance dimensions

Every milestone reports separately:

```text
AUTHORITY_CORRECTNESS
STATE_CONTINUITY
TRANSPORT_CONTINUITY
VISUAL_CONTINUITY
```

A full seamless-world PASS requires all dimensions required by that checkpoint to pass. A visual PASS cannot repair an authority FAIL.

## 2. Global invariants

### G1 one writer

```text
accepted_active_writer_count(subject_or_domain) <= 1
```

Use a global analyzer across real authority processes.

### G2 monotonic ownership

```text
authority_epoch never decreases
fencing_token never decreases
directory_generation never rolls back
```

### G3 stale source never resurrects

After Directory commits B/N+1, A/N cannot write even after restart from durable local state.

### G4 Directory commit is irreversible for old writer

Before canonical CAS, source rollback may be valid.

After canonical CAS, target failure must not restore old source writer. Recovery is forward or fail-closed.

### G5 stable identity

Authority/gateway/process change does not change PlayerId, ItemId, domain identity or required reference-frame identity.

### G6 operation identity end-to-end

Same `OperationId` across old/new gateways and old/new routes produces at most one canonical commit.

### G7 AuthorityBinding consistency

A subject may not simultaneously have two accepted effective authority bindings for the same binding generation.

### G8 Item Graph / authority binding consistency

For bounded pickup/drop tests:

```text
Item Graph membership
and
AuthorityBinding
```

must commit consistently. No state where one says WORLD while the other says PLAYER domain is accepted.

### G9 domain-transfer scaling

Inherited domain membership must not create one Directory ownership transition per member.

### G10 DomainMutationBarrier correctness

Each racing operation is exactly one of:

```text
committed before barrier and included in transfer
or
explicitly queued/retried/rejected after barrier
```

Never lost, duplicated or silently committed only on stale source.

### G11 temporal monotonicity

Accepted canonical/presentation timeline does not roll back because authority changes.

### G12 gateway is never owner

No gateway route/cache/state can satisfy a canonical ownership check.

### G13 InteractionIsland co-location

If policy requires co-location, accepted placement cannot split required island members across owners.

### G14 unrelated failure isolation

Failure/backpressure in unrelated authority/gateway/client does not stop healthy independent paths outside declared shared dependencies.

## 3. Test layers

Use all relevant layers:

```text
A contract/model
B deterministic component
C real multi-process
D per-link network-condition simulation
E crash/restart
F graphical/user continuity
G scale/soak
```

Real-process acceptance should include separate Directory, Gateway(s), Authority processes and Client processes where checkpoint scope requires them.

## 4. Ownership Directory suite

### OD-01 monotonic CAS

Accept exact expected owner/epoch/fence. Reject wrong owner, stale epoch, stale fence, generation rollback and non-monotonic desired values.

### OD-02 stale resurrected authority

```text
A owns Domain D @ 10
A partitions
Directory commits B @ 11
A restarts from @10
A mutation -> FENCED
B remains writer
```

### OD-03 restart around commit

Crash Directory:

- before CAS;
- after durable CAS before response;
- after response before publication.

Retry converges to durable record.

### OD-04 stale lookup

Gateway gets A/N, owner becomes B/N+1, operation reaches A. A rejects and caller follows explicit re-resolve policy.

### OD-05 draining

DRAINING authority receives no new placements but can finish allowed transfer/retirement work.

## 5. Generic AuthorityDomain transfer matrix

Named phases:

```text
T0 ACTIVE_SOURCE
T1 TARGET_WARM
T2 SOURCE_DOMAIN_FROZEN
T3 TARGET_DURABLY_PREPARED
T4 BEFORE_DIRECTORY_CAS
T5 AFTER_DIRECTORY_CAS
T6 BEFORE_TARGET_ACTIVATE
T7 BEFORE_SOURCE_RETIRE
T8 SOURCE_RETIRED
```

For crashes at each meaningful phase prove:

- one writer;
- deterministic recovery owner;
- exact TransferId replay behavior;
- state revision monotonicity;
- correct proof cleanup;
- source may recover before T5 if Directory still says source;
- old source can never recover writer at/after T5.

### DT-POST-CAS-FAIL

Inject target activation failure immediately after durable Directory CAS.

Expected:

```text
old source remains fenced
no local rollback makes A writer
system recovers target/forward-transfers/fails closed
writer_count <= 1
```

This test explicitly prevents accidental copying of the bounded P9 post-retire rollback behavior into production semantics.

## 6. AuthorityBinding / Domain Closure suite

### AB-01 inheritance

1/10/100/1000 member subjects inherit authority from one domain.

Expected Directory domain-owner CAS count for one handoff:

```text
1
```

not member count.

### AB-02 stable member identity

All ItemIds/EntityIds remain unchanged after domain owner change.

### AB-03 stale binding generation

Rebind Item X from Domain A to Domain P. Mutation using old binding generation is rejected.

### AB-04 explicit override

An explicitly independent subject does not accidentally inherit PlayerDomain authority.

### AB-05 nested structure

Nested Item Graph structure remains byte/logically equivalent except expected revisions after domain owner change.

## 7. Pickup / drop atomicity suite

### PD-01 pickup commit

Initial:

```text
Item X in WORLD graph
binding WorldDomain/A
```

After pickup:

```text
Item X in PlayerInventory
binding PlayerDomain/P
same ItemId
```

### PD-02 pickup failure

Inject failure before commit. Both graph membership and binding remain WORLD.

### PD-03 binding failure

Cannot commit Item Graph move while authority binding remains stale.

### PD-04 drop commit

PlayerDomain item becomes WorldDomain/current owner with stable identity.

### PD-05 operation replay

Same pickup/drop OperationId is idempotent; conflicting replay fails closed.

## 8. Player Carrying Domain suite

### PC-01 basic journey

```text
A: player picks X
A->B PlayerDomain handoff
B: use X
B: drop X
```

Assertions:

```text
player identity changes = 0
item identity changes = 0
duplicate items = 0
lost items = 0
writer violations = 0
stale A mutations accepted = 0
```

### PC-02 nested inventory

Fixture:

```text
Player
  Backpack
    Container
      Ore
      Battery
      Device
  Tool
  EquippedItem
```

A->B preserves all graph relationships and stable IDs.

### PC-03 size scaling

Repeat with 1/10/100/1000 inherited items. Domain CAS count remains one; record payload size and handoff duration separately.

### PC-04 use immediately after handoff

First legal target-side inventory operation succeeds after activation without requiring item-by-item ownership repair.

### PC-05 source restart

After B owns PlayerDomain, restart A from stale durable state and attempt inventory mutation: reject by fence.

## 9. DomainMutationBarrier race suite

Freeze PlayerDomain while each operation races:

```text
PICKUP
DROP
STACK_SPLIT
STACK_MERGE
CONTAINER_MOVE
EQUIP
UNEQUIP
ITEM_USE
```

For every operation record:

```text
operation_id
source observed sequence
barrier sequence
final canonical owner
final domain revision
result classification = INCLUDED | RETRIED | REJECTED
```

No operation may be absent from both pre-transfer and post-transfer ledgers after an acknowledged client success.

### DB-duplicate-retry

If client retries queued operation after route flip, same OperationId yields one canonical commit.

## 10. Temporal continuity suite

### TC-01 tick monotonicity

Source snapshot at timeline tick T. Target activated state must continue at >= T according to frozen contract; never restart to unrelated zero/local epoch.

### TC-02 state revision monotonicity

Gateway/client cannot accept lower canonical state revision after route flip.

### TC-03 prediction continuity

Measure:

```text
max_prediction_error
hard_correction_count
hard_correction_distance
visual_rewind_frames
```

under deterministic latency.

### TC-04 nested reference frame

Moving frame and passenger/player domain handoff does not create temporal/frame discontinuity.

## 11. Gateway transparency and routing

### GT-01 direct vs proxy

Run identical movement, pickup/drop, inventory use and duplicate operation direct-to-authority and via gateway. Canonical result must match.

### GR-01 no early primary flip

Prepared B state before Directory commit cannot make B canonical route.

### GR-02 commit flips route

Only committed owner/route revision may promote B.

### GR-03 stale A packet

Never re-promote A after B/N+1.

### GR-04 primary outage

Observer not promoted without canonical ownership recovery.

## 12. Gateway mobility/rehome suite

### GM-01 failure before forwarding

Retry through G2 => one commit.

### GM-02 failure after forwarding before response

Authority already committed; G2 retry returns same result without duplicate mutation.

### GM-03 quality-driven rehome

Network evolves from G1-better to G2-materially-better. Hysteresis/cooldown allow controlled rehome only after threshold policy.

Authority owner remains unchanged.

### GM-04 rehome during authority handoff

G1->G2 client path change races with A->B domain transfer. Both gateways converge on Directory; route caches do not grant ownership.

### GM-05 stale old gateway restart

Old route/session cache cannot change owner or duplicate player.

## 13. Protocol/build compatibility suite

### BC-01 compatible rolling upgrade

A build 100 transfers to B build 101 when protocol/contracts declare compatibility.

### BC-02 incompatible target

Healthy B with incompatible protocol hash/required contract version is rejected before prepare/ownership CAS.

### BC-03 gateway compatibility

Gateway may not silently strip/transform ownership-critical fields across incompatible schema versions.

### BC-04 mixed-version soak

Bounded rolling-upgrade window with explicitly supported versions preserves one-writer and stable identity invariants.

## 14. Projection / AOI suite

Retain R1 tests for:

- epoch rollback;
- revision reorder;
- conflicting same revision checksum;
- exact replay;
- stale cache marking;
- interest merge;
- leave cleanup;
- bandwidth/LOD downgrade.

Add:

### PA-09 carried-domain projection

Projection of player/carried item state never materializes a second canonical Item Graph or accepts local mutation.

## 15. Cross-authority operations

Retain bounded cases:

```text
player@A -> item@B
player@A -> object@B
owner B->C after lookup
same OperationId through two gateways
```

Add:

### XO-06 target becomes PlayerDomain member

Item owner/binding changes from WorldDomain B to PlayerDomain while remote operation is in flight. Stale expected binding/epoch rejects and re-resolve policy is deterministic.

## 16. Physical InteractionIsland suite

Keep this separate from inventory carrying domain.

First fixture:

```text
ship
pilot physical body
passenger
mounted component
attached/physics cargo
```

Tests:

- spatial boundary crossing without invalid split;
- join/leave membership generation;
- membership race with transfer;
- nested reference-frame continuity;
- partial placement proposal rejection;
- owner/target restart.

## 17. Static N-authority suite

- arbitrary AuthorityIds;
- A->B->C domain progression;
- simultaneous independent domain transfers;
- unrelated C outage isolation;
- authority registration/draining;
- no mandatory full mesh;
- gateway upstream connections bounded by active relationships, not clients*authorities.

## 18. Network-condition matrix

Each logical link may receive independent deterministic conditions:

```text
Client <-> Gateway
Gateway <-> Directory
Gateway <-> Authority
Authority <-> Directory
Authority <-> Authority if checkpoint uses direct peer transport
```

Presets:

```text
LOCAL
GOOD
AVERAGE
MOBILE
BAD
EXTREME
LAG_SPIKE
ASYMMETRIC
PARTITION
```

Track latency, jitter, loss, duplicate, reorder, bandwidth, queue and disconnect schedule.

## 19. Seamless metrics

Where applicable emit:

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

## 20. Integrated H12 journey

Final static acceptance must include one end-to-end journey:

```text
connect G1
move on A
pickup X
place X in nested inventory
use X
prewarm B
handoff PlayerDomain A->B
continue movement
use X on B
gateway rehome G1->G2
show foreign projections
perform one cross-authority operation
drop X to WorldDomain/B
restart B under recovery policy
continue session
```

Run under at least one controlled adverse network preset and one fault injection schedule.

Required final counters:

```text
writer_violations = 0
identity_changes = 0
duplicate_item_ids = 0
lost_item_ids = 0
stale_owner_mutations_accepted = 0
duplicate_canonical_commits = 0
canonical_revision_rollbacks = 0
unexpected_session_resets = 0
unexpected_errors = 0
```

## 21. Machine-readable report

Every checkpoint produces exact-head machine evidence including:

```json
{
  "checkpoint": "SM1-H2B",
  "code_sha": "<exact>",
  "scenario_seed": 0,
  "authority_correctness": "PASS|FAIL|N/A",
  "state_continuity": "PASS|FAIL|N/A",
  "transport_continuity": "PASS|FAIL|N/A",
  "visual_continuity": "PASS|FAIL|N/A",
  "assertions_total": 0,
  "assertions_failed": 0,
  "writer_violations": 0,
  "identity_changes": 0,
  "duplicate_item_ids": 0,
  "lost_item_ids": 0,
  "stale_owner_mutations_accepted": 0,
  "duplicate_canonical_commits": 0,
  "result": "PASS|FAIL"
}
```

## 22. Review gates

Authority, Directory, domain-closure, gateway-session and recovery milestones require exact-head implementer evidence, applicable Project Control, fresh independent critical review, repair when required, and final verification where control policy requires it.

A prior SM0 PASS is evidence provenance, not automatic acceptance of a new production implementation.
