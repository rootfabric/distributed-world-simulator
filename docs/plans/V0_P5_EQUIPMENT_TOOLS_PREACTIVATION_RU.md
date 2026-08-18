# V0-P5 — Equipment / Tools — pre-activation package

**Status:** `PRE-ACTIVATION / PLANNED_NOT_ELIGIBLE / NO RUNTIME MUTATION / DO NOT CREATE FEATURE BRANCH YET`  
**Prepared from canonical main:** `c58339c30e6d7e708a06c41e59208bd45f0709a4`  
**Current product checkpoint:** `V0_P4_REAL_RESOURCE_CONSTRUCTION`  
**Frozen P4 runtime/evidence target:** `2a6721cdf02fa1134c59d1ab98bb7b597c66821d`  
**Planned successor:** `V0_P5_EQUIPMENT_TOOLS`

---

## 1. Non-activation boundary

This document is preparation only. It MUST NOT be interpreted as P5 activation.

P5 is not eligible until canonical main durably proves all of the following:

```text
V0_P4_CHECKPOINT_ACCEPTED
MAIN_DECLARED_EXACT_P4_SUCCESSOR_BASE
CURRENT_MAIN_STANDARD_PC0_NON_RED
CURRENT_MAIN_DIRECTIONAL_PC0_NON_RED
FRESH_P5_PROJECT_EPOCH
FRESH_P5_WORK_ORDER
V0_PRODUCT_MUTATION_LEASE_ROTATED_TO_P5
DIRECTOR_DISPATCH
```

Until those predicates exist:

```text
DO NOT create feature/v0-p5-equipment-tools
DO NOT rotate the mutation lease
DO NOT dispatch a P5 runtime implementer
DO NOT mutate Item Graph / equipment / persistence / network runtime for P5
DO NOT treat this prep branch as product lineage
```

The actual P5 feature branch must be created only from the exact successor base declared by canonical main after P4 acceptance.

---

## 2. Activation placeholders

These values are deliberately unresolved before P4 acceptance:

```text
accepted_p4_checkpoint_event: TBD_AFTER_P4_ACCEPTANCE
accepted_p4_lineage_head: TBD_AFTER_P4_ACCEPTANCE
main_declared_successor_base_sha: TBD_AFTER_P4_ACCEPTANCE
p5_project_epoch: TBD_AFTER_P4_ACCEPTANCE
p5_work_order_id: TBD_AFTER_P4_ACCEPTANCE
p5_feature_branch: feature/v0-p5-equipment-tools
p5_mutation_lease_rotation: TBD_AFTER_P4_ACCEPTANCE
p5_director_dispatch_event: TBD_AFTER_P4_ACCEPTANCE
```

No agent may fill these fields from chat history or by guessing. They must be read from Git/main-owned control state.

---

## 3. Product goal

P5 proves that a canonical Item Graph item can become an authoritative equipped tool and that a real gameplay operation consumes that equipped state without creating a second equipment truth.

Minimal product statement:

> A player owns a canonical mining tool item, equips it through a server-authoritative operation, other clients observe the equipped state, reconnect restores it, and mining validates that exact equipped tool before producing the existing canonical P3 resource output.

P5 is intentionally bounded. It is an integration slice over existing owners, not a new equipment foundation.

---

## 4. Preferred first vertical slice

```text
canonical mining-tool item
        ↓
server-authoritative equip command
        ↓
canonical equipped-state binding
        ↓
replicated equipment presentation
        ↓
mining action validates equipped tool
        ↓
existing P3 canonical resource output
        ↓
reconnect restores same equipment state
```

Recommended first tool: one mining tool only. Do not start with a general weapon/tool framework unless the bounded implementation proves that a reusable adapter is strictly smaller than a special-case path.

---

## 5. Owner boundaries

P5 MUST reuse canonical owners.

### Item identity / possession

Source of truth remains the existing canonical Item Graph / M4 item authority.

Forbidden:

```text
P5-private item ids
P5-private inventory graph
client-owned equipped item truth
presentation node as canonical ownership record
```

### Equipment state

P5 may add the minimum canonical relation/operation needed to bind an existing item to a bounded equipment slot, but must not fork inventory ownership.

Required invariant:

```text
equipped item identity == canonical Item Graph item identity
```

### Gameplay validation

Mining/tool use must be server/domain validated. Client presentation may predict UI/animation, but canonical resource production cannot be authorized by presentation state alone.

### Persistence

Reuse existing persistence/state-store boundaries. No P5-private save format or duplicate durable owner.

### Network

Reuse current canonical command/replication path. If P5 requires a new network authority/protocol foundation, fail closed:

```text
V0_P5_BLOCKED_REQUIRES_NX_OR_FOUNDATION_DECISION
```

Do not repair network authority privately inside P5.

### Character/presentation donor

Existing CH equipment/presentation work may be used as a donor/reference only where compatible. It is not automatically the P5 product base and does not own canonical item/equipment truth unless canonical main explicitly says so.

---

## 6. Bounded implementation scope

Expected allowed scope after activation:

```text
- one canonical equipment slot or bounded tool slot;
- equip existing canonical item;
- unequip back to canonical inventory/container ownership;
- reject item that is not owned/eligible;
- exact-once authoritative equip transition;
- replication to a second client;
- reconnect restoration;
- mining operation checks equipped mining tool;
- existing P3 resource output remains canonical;
- minimal UI/presentation needed to operate and observe the slice;
- tests/evidence/harness integration for the slice.
```

Out of scope unless a finding proves necessity:

```text
full armor system
combat
weapon ballistics
complex attachment/mod system
durability economy
crafting/fabrication
new item ontology
new persistence foundation
new network protocol family
new character foundation
new general animation framework
```

---

## 7. Required acceptance scenarios

### A. Equip

1. Player owns one canonical mining tool item.
2. Client requests equip.
3. Server validates actor, ownership, item identity, slot eligibility and current revision/state.
4. Exactly one canonical equip transition is committed.
5. Item cannot simultaneously remain canonically equipped in two incompatible locations.
6. Client A sees confirmed equipped state.
7. Client B sees the same item/slot state.

### B. Invalid equip

Must reject without state divergence:

```text
unknown item
item not owned by player
wrong slot/type
stale/replayed command
already consumed/moved item
invalid actor/session
```

### C. Unequip

1. Player requests unequip.
2. Canonical item returns through existing Item Graph ownership/container rules.
3. Replicas converge.
4. No duplicated item or orphan equipment relation remains.

### D. Real tool use

1. Tool is equipped canonically.
2. Player performs existing ResourceMining action.
3. Authoritative mining path validates the exact equipped tool.
4. Existing canonical P3 output is produced exactly once.
5. Unequipped/invalid tool cannot authorize the same action if the P5 rule requires it.

### E. Reconnect

1. Equip tool.
2. Disconnect client.
3. Reconnect using canonical player/session policy.
4. Same canonical item remains equipped or is restored according to the accepted durability contract.
5. Second client converges to the same state.

### F. Recovery / restart

If the accepted existing persistence boundary covers equipment state, verify server restart restoration in P5. If it does not, P5 must record an explicit bounded blocker or next checkpoint dependency; it may not invent a private persistence owner.

---

## 8. Minimum test matrix

After activation the Work Order should require, at minimum:

```text
P5_EQUIP_OWNED_TOOL_PASS
P5_REJECT_UNOWNED_TOOL_PASS
P5_REJECT_INVALID_SLOT_PASS
P5_UNEQUIP_ITEM_GRAPH_CONVERGENCE_PASS
P5_EXACT_ONCE_EQUIP_COMMAND_PASS
P5_TWO_CLIENT_EQUIPMENT_REPLICATION_PASS
P5_RECONNECT_EQUIPMENT_RESTORATION_PASS
P5_MINING_REQUIRES_CANONICAL_EQUIPPED_TOOL_PASS
P5_CANONICAL_P3_RESOURCE_OUTPUT_EXACT_ONCE_PASS
P5_NO_PRIVATE_EQUIPMENT_TRUTH_PASS
P5_NO_DUPLICATE_ITEM_IDENTITY_PASS
FULL_WORLD_CORE_REGRESSION_PASS
POST_BUILD_CRITIQUE_COMPLETED
EVIDENCE_MAP_COMPLETE
INDEPENDENT_REVIEWER_PASS
INDEPENDENT_VERIFIER_PASS
REVIEW_HEAD_EXACT_AND_FRESH
TESTED_HEADS_EXACT_AND_FRESH
STANDARD_PC0_NON_RED
DIRECTIONAL_PC0_NON_RED_FOR_CRITICAL_HITS
CRITICAL_CROSS_BRANCH_OVERLAP_ZERO
HUMAN_ATTENTION_QUEUE_EMPTY_OR_RESOLVED
```

Risk floor should be `HIGH` because this slice mutates authoritative item/equipment gameplay state and composes network + persistence behavior.

---

## 9. Fresh P5 Work Order template

Only after P4 acceptance, Director should instantiate a fresh Work Order using current canonical schemas. Conceptual values:

```text
Program: V0
Checkpoint: V0_P5_EQUIPMENT_TOOLS
Risk: HIGH
Base: <MAIN_DECLARED_EXACT_P4_SUCCESSOR_BASE>
Branch: feature/v0-p5-equipment-tools
Runtime mutation lease: exactly one, explicitly rotated from P4 to P5
Primary slice: canonical mining tool equip → authoritative mining validation → canonical P3 output
```

Required Work Order constraints:

```text
no private Item Graph
no private equipment inventory truth
no private persistence owner
no private network authority
no mutation before Director dispatch
no inherited P4 mutation lease by assumption
exact tested/reviewed heads only
```

The Work Order itself must be generated from then-current canonical Harness schemas; this document is not a substitute for the machine contract.

---

## 10. Activation procedure after P4 acceptance

Director sequence:

```text
1. Read exact accepted P4 checkpoint from canonical Git state.
2. Confirm main explicitly declares exact successor base SHA.
3. Run current standard PC0 and directional PC0; require NON_RED.
4. Create fresh P5 Project Epoch from that exact successor base.
5. Create fresh P5 Work Order, risk HIGH.
6. Rotate the single pre-H0.3 mutation lease to P5 in main-owned control state.
7. Validate generation / branch / ownership / directional-watch constraints.
8. Create feature/v0-p5-equipment-tools from exact declared successor base.
9. Obtain required prebuild review if current review policy requires it.
10. Director records explicit DISPATCHED event.
11. Only then may the P5 runtime implementer mutate production files.
```

Any missing step is fail-closed.

---

## 11. Implementation order

Recommended order for the implementer after dispatch:

```text
P5.0 inventory existing Item Graph / CH equipment / mining / persistence entry points
P5.1 freeze equipment relation + command contract
P5.2 server-authoritative equip/unequip
P5.3 second-client replication/presentation
P5.4 mining-tool authoritative validation
P5.5 reconnect/recovery durability
P5.6 full world regression + two-client scenario
P5.7 post-build critique + evidence map
P5.8 fresh independent review + verifier
P5.9 checkpoint proposal
```

Do not broaden into P6 shared-outpost work during P5.

---

## 12. Handoff gate from current P4 closure

Current required predecessor work before this package can activate:

```text
PR #134 exact-head fresh independent PASS
→ merge #134 into recovery lineage
→ guarded append-only P4 closure continuation
→ all required P4 predicates durably recorded
→ current standard/directional PC0 NON_RED
→ P4 checkpoint proposed
→ Director accepts V0_P4_REAL_RESOURCE_CONSTRUCTION
→ canonical main declares exact P4 successor base
→ only then activate this P5 package
```

The frozen P4 runtime target must remain `2a6721cdf02fa1134c59d1ab98bb7b597c66821d` unless a new independently evidenced runtime defect requires reopening implementation.

---

## 13. Definition of ready-to-start P5

P5 is ready to start only when Git can answer all of these without chat context:

```text
What exact P4 checkpoint was accepted?
What exact SHA is the P5 predecessor base?
What exact P5 epoch is active?
What exact P5 Work Order is active?
Who owns the one runtime mutation lease?
What exact branch may mutate runtime?
What exact review/risk policy applies?
Are current standard and directional PC0 NON_RED?
```

If any answer is missing or ambiguous, P5 remains `PLANNED_NOT_ELIGIBLE`.
