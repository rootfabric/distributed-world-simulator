# V0 Critical Path Acceleration — P0→P4 Product-Lineage Refresh

**Status:** `GENERATION-80 CONTROL REFRESH CANDIDATE / NOT CANONICAL UNTIL MAIN ACCEPTANCE`  
**Repository:** `rootfabric/distributed-world-simulator`  
**PR:** `#98`  
**Control base:** `main @ 09714b6f2681e3b5cf3f2f9e28416cf9a7378304`  
**Architecture:** `GLOBAL-P0-2026-08-12-R3-REFRESH-R1`

## 1. Product direction

Generation-80 keeps the proven product train instead of rebuilding it from bare `main`:

```text
P0 playable frontier
→ P1 world items / containers
→ P2 reconnectable shared state
→ P3 resource mining
→ P3.1 visual interaction repair
→ P4 real-resource Construction
→ P5 equipment/tools
→ P6 persistent shared outpost
→ POST-P6 SEAMLESS INSERTION GATE
→ V0-SM1 seamless product integration
→ P7 bounded terrain mutation
→ P8 first mobile construct / ship
```

P6 is the first stable V0 baseline target **and the planned seamless insertion point**. Ship-first routing is superseded. `V0-SM1` is not an eligible Harness checkpoint yet; it is activated by a fresh main-owned control update after P6 acceptance using exact then-current P6/main/SM0/NX boundaries. See `docs/plans/V0_POST_P6_SEAMLESS_INTEGRATION_RU.md`.

## 2. Main owns control; exact product lineage may be continuation input

Generation-80 distinguishes:

```text
CONTROL / PROJECT EPOCH
  exact canonical main

RUNTIME PRODUCT EXECUTION BASE
  exact V0 lineage head declared by main-owned control
```

Current product execution base:

```text
repair/v0-p3-visual-interaction-r1
@ ef3ad5f0afc433802d639171d938e4720b3a46ec
```

It is not checkpoint acceptance. `declares_checkpoint_acceptance=false`; P2/P3 acceptance debt remains explicit.

PR #117 (`11819f6dd1ea3728382a04737d30a5300de622f7`) is intentionally excluded from this execution base until its independent HIGH-risk routing is complete.

## 3. Exact current P4 preparation

```text
branch:
feature/v0-p4-construction-real-resources

pre-runtime head:
47ff18cf603bbf98bb67f7f62962e050f8606542

work order:
#118
```

The P4 branch remains preparation-only: runners, focused tests, branch passport, evidence/checkpoint docs. The prepared three-file P4.1 production repair is still unapplied.

## 4. Why generation-80 does not immediately start mutation

The independent review of earlier PR #98 head exposed three authorization holes that generation-80 now closes:

1. a P4 audit could previously use `-SkipFetch` and still look authoritative;
2. initial `PLANNED -> DISPATCHED` was not machine-guarded by Director identity;
3. the `<=1` pre-H0.3 worker limit existed as policy constants but not as a central mutation lease.

Generation-80 therefore adds an explicit fail-closed chain rather than relying on prose.

## 5. Fresh P4 audit semantics

`RUN_V0_P4_POST_ACTIVATION_EPOCH_AUDIT.ps1` must use fresh branch refs for an authorizing result.

Possible outcomes:

```text
-SkipFetch
  -> BASE_READY_REFS_NOT_REFRESHED
  -> authoritative_for_dispatch = false

-SkipPostMainProjectControl
  -> BASE_READY_PC0_NOT_RUN
  -> authoritative_for_dispatch = false

fresh refs + full post-main PC0 + all exact checks
  -> CONTINUE
  -> refs_fetch_performed = true
  -> authoritative_for_dispatch = true
```

The `CONTINUE` artifact is bound to:

- exact P4 head;
- exact canonical main head;
- registry generation >= 80;
- exact declared P3.1 execution base;
- PR #117 exclusion;
- no production/runtime mutation in the P4 prep diff;
- standard/directional PC0 NON_RED.

The artifact must be committed as durable evidence before dispatch.

## 6. Director-only initial dispatch

Harness event reduction now treats initial:

```text
PLANNED -> DISPATCHED
```

as a guarded transition.

Requirements:

```text
actor == DIRECTOR
```

For generation-80 P4 it additionally requires a referenced committed audit artifact with:

```text
decision == CONTINUE
authoritative_for_dispatch == true
refs_fetch_performed == true
p4_head == dispatch event head_sha
canonical_main_head == current origin/main
registry_generation >= 80
```

An implementer-authored dispatch event cannot unlock mutation.

## 7. Global pre-H0.3 mutation lease

Generation-80 scheduler has one main-owned lease:

```text
effective registry generation: 80
capacity: 1
holder program: V0
holder checkpoint: V0_P4_REAL_RESOURCE_CONSTRUCTION
holder branch: feature/v0-p4-construction-real-resources
mutating states: DISPATCHED, IN_PROGRESS
```

Consequences:

```text
new P4 mutation dispatch after full audit + Director gate -> allowed
new H0.2/NX mutation dispatch -> rejected while lease belongs to P4
new SM0/non-P4 mutation dispatch -> rejected while lease belongs to P4
NX/SM0 review or verification-only work -> allowed
IMPLEMENTED state -> mutation worker released
```

Release/reassignment requires a main-owned control update. A branch cannot self-allocate a second worker.

## 8. P4 technical sequence after dispatch

### P4.1 — exact stack consumption

Repair only the already identified Construction surfaces:

```text
construction_build_plan.gd
construction_stage_transaction_planner.gd
construction_item_mutation.gd
```

Required behavior:

```text
requested > available  -> reject, mutation-free
requested < available  -> UPDATE positive remainder
requested == available -> DELETE exhausted stack
```

### P4.2 — deterministic server allocator

```text
logical_player_id resolved server-side
eligible definition_id == item/ore
requesting player's canonical inventory only
stable order = (slot_index, item_id)
multi-stack allocation supported
client item IDs never trusted
```

### P4.3 — live M4 Construction transaction port

Construction consumes from the same canonical M4 Item Graph written by P3 mining.

Forbidden:

```text
second Item Graph
mutable copied registry as authority
shadow resource/material balance
client-owned affordability truth
```

### P4.4 — composition and publication

The already-created canonical M4 owner is injected through bounded composition. A successful atomic transaction publishes the existing Item Graph delta/full fallback and Construction event/snapshot. Failure publishes neither success mutation.

### P4.5+ — hardening

- duplicate exact-once;
- operation-id conflict;
- shortfall mutation-free;
- foreign-player ownership isolation;
- source-changed-before-commit;
- fault-injection rollback;
- revision/tick purity;
- A/B replication;
- reconnect convergence.

## 9. Acceptance debt

Open inherited debt remains:

```text
P2 Director verdict pending
P3 aggregate Reviewer / Verifier / Director pending
PR #117 independent HIGH-risk routing pending
```

Policy:

```text
bounded P4 implementation
  MAY proceed after full generation-80 activation/audit/Director chain

P4 checkpoint acceptance / stable V0 baseline
  MUST wait for applicable inherited acceptance debt
```

No debt is hidden and no implementation progress is discarded merely because acceptance routing is still running.

## 10. Network boundary

V0 continues on:

```text
SERVER_PREDICTED
```

H0.2/NX.C1 `OWNER_AUTHORITATIVE_VALIDATED` remains a separate lane. If P4 discovers a real need for protocol ownership, authority model, reconciliation or Character-ownership changes, V0 fails closed to `V0_BLOCKED_REQUIRES_NX`.

The same ownership rule applies to the future post-P6 seamless insertion. SM0 is a capability donor, not permission for V0 to create a private network foundation. If V0-SM1 needs new protocol/global authority/reconciliation ownership, activation stops and routes the foundation change through NX/main control.

## 11. Exact post-merge sequence

```text
fresh independent PASS on exact PR #98 head
  ↓
human/main acceptance merge
  ↓
fetch exact new main + all branch refs
  ↓
post-main standard PC0 + directional PC0
  ↓
P4 epoch/base audit on exact 47ff18cf603bbf98bb67f7f62962e050f8606542
  ↓
CONTINUE + authoritative_for_dispatch=true
  ↓
commit exact audit JSON as evidence
  ↓
Director initial dispatch
  ↓
P4.1 RED -> GREEN
  ↓
P4.2 allocator
  ↓
P4.3 live M4 transaction port
  ↓
replication/reconnect hardening
```

Any stale ref, moved P4 head, moved execution base, imported PR #117, PC0 RED, non-Director dispatch or non-P4 mutation lease request stops the chain.

## 12. Product target after P4

```text
P4 real-resource Construction
→ P5 equipment/tools
→ P6 persistent shared outpost
   join
   → mine
   → inventory/container
   → build
   → disconnect/reconnect
   → 5 clean E2E repeats
   → 30-minute two-client soak
→ POST-P6 SEAMLESS INSERTION GATE
   → do not auto-dispatch P7
   → resolve exact accepted P6 / canonical main / frozen SM0 / current NX boundaries
   → register and human-authorize V0_SM1_SEAMLESS_PRODUCT_INTEGRATION
→ V0-SM1
   → real graphical V0 client crosses A <-> B without identity reset
   → canonical inventory/item continuity
   → mining/Construction/outpost continuity
   → multi-authority presentation convergence
   → reconnect + fault/soak
→ P7 bounded terrain
→ P8 first mobile construct/ship
```

P6 remains the first stable playable V0 baseline. It is now also the **mandatory decision/activation point for seamless integration before P7**, as defined by `docs/plans/V0_POST_P6_SEAMLESS_INTEGRATION_RU.md`.

`V0_SM1_SEAMLESS_PRODUCT_INTEGRATION` is intentionally not pre-registered today as an eligible Harness checkpoint. At P6 acceptance the Director must create a fresh main-owned control update using exact then-current heads. A human/main decision may explicitly defer the gate, but that decision must be durable; silence does not authorize P6 -> P7.

## 13. Final rule

```text
MAIN OWNS AUTHORIZATION
EXACT PRODUCT LINEAGE MAY OWN CONTINUATION INPUT
FRESH AUDIT EVIDENCE BINDS EXACT HEADS
DIRECTOR ALONE DISPATCHES INITIAL MUTATION
ONE MAIN-OWNED MUTATION LEASE UNTIL H0.3
IMPLEMENTED RELEASES THE MUTATION WORKER
ACCEPTANCE DEBT REMAINS VISIBLE
P4/P6 BEFORE TERRAIN OR SHIPS
P6 TRIGGERS THE POST-P6 SEAMLESS INSERTION GATE
DO NOT AUTO-ADVANCE P6 -> P7
SM0 IS A CAPABILITY DONOR, NOT THE FUTURE V0 BASE
V0-SM1 STARTS FROM THEN-CURRENT ACCEPTED V0/P6
NO DUPLICATE TRUTH
```
