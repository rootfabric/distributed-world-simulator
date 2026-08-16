# Distributed World Simulator — Current Project Frontiers

**Operational owner:** `main`  
**Architecture baseline:** `GLOBAL-P0-2026-08-12-R3-REFRESH-R1`  
**Registry generation:** `80` activation-refresh candidate on PR #98; live `main` remains generation `79` until acceptance/merge  
**Control plane:** `PC0-2026-08-10-R1`  
**Harness:** `H0-2026-08-11-R1`

> Machine project-state truth remains `config/control/project-program-registry.v1.json`. PR #98 does not accept P1/P2/P3/P4; it updates main-owned routing and fail-closed authorization so the demonstrated product lineage can continue safely.

## Canonical global state

GLOBAL-P0 R3 V9 is canonical. C22 is MAIN_INTEGRATED. Mandatory post-R3 Project Control is NON_RED. H0.2/NX.C1 remains an independent HIGH-risk verification/source-acceptance lane.

V0 keeps `SERVER_PREDICTED` as its network baseline. `OWNER_AUTHORITATIVE_VALIDATED` is not a blanket P4/P6 prerequisite. Any concrete protocol, authority, reconciliation or Character-ownership change fails closed to NX.

## Actual V0 product lineage

```text
P0 playable frontier
  ↓
P1 world items / pickup-drop / external containers
  PR #103 @ f7ab0a8b91394724b66e3f4ee387de3441a676ca
  fresh review PASS
  ↓
P2 reconnectable shared state
  PR #109 @ 92e3e197e11156d6c36a58a3b4a4f447397c99d7
  Windows GREEN + Reviewer PASS + Verifier PASS
  Director verdict pending
  ↓
P3 authoritative mining
  PR #113 @ f27a60279c8ad61d47ebe3fad81b6898679c660f
  P3.1 PR #115 @ ef3ad5f0afc433802d639171d938e4720b3a46ec
  operator demonstrated mining + B-side depletion
  ↓
P4 real-resource Construction
  branch: feature/v0-p4-construction-real-resources
  exact pre-runtime head: 47ff18cf603bbf98bb67f7f62962e050f8606542
  Work Order #118
  prepared exact-consume repair; no production/runtime mutation yet
```

PR #117 (`11819f6dd1ea3728382a04737d30a5300de622f7`) remains excluded from the P4 execution base until its independent HIGH-risk routing is complete.

## Main-owned execution-base rule

Generation-80 distinguishes:

```text
CONTROL / PROJECT EPOCH ANCHOR
  exact canonical main

RUNTIME PRODUCT EXECUTION BASE
  exact product-lineage head explicitly declared by main-owned control
```

Current execution base:

```text
repair/v0-p3-visual-interaction-r1
@ ef3ad5f0afc433802d639171d938e4720b3a46ec
```

This is an execution input only. `declares_checkpoint_acceptance=false`; it does not turn P2/P3/P3.1 into accepted or main-integrated checkpoints.

## P4 authorization chain

Merge of PR #98 alone does **not** authorize runtime mutation.

Required sequence:

```text
generation-80 accepted into main
  ↓
fresh fetch of branch refs
  ↓
post-main standard PC0 + directional PC0
  ↓
RUN_V0_P4_POST_ACTIVATION_EPOCH_AUDIT.ps1
  ↓
only fresh/full result may be:
  decision = CONTINUE
  refs_fetch_performed = true
  authoritative_for_dispatch = true
  exact P4 head + exact canonical main head
  ↓
commit that audit artifact as durable evidence
  ↓
Director initial dispatch
  ↓
P4.1 runtime mutation
```

`-SkipFetch` is diagnostic only and yields `BASE_READY_REFS_NOT_REFRESHED`; it cannot authorize dispatch. Skipping post-main PC0 yields `BASE_READY_PC0_NOT_RUN`; it cannot authorize dispatch.

The Harness reducer machine-guards initial `PLANNED -> DISPATCHED`: actor must be `DIRECTOR`. For generation 80, P4 dispatch also requires the committed authoritative audit artifact tied to exact P4/main heads.

## Global pre-H0.3 mutation lease

Generation-80 adds one main-owned lease:

```text
capacity: 1
holder checkpoint: V0_P4_REAL_RESOURCE_CONSTRUCTION
holder branch: feature/v0-p4-construction-real-resources
mutating states: DISPATCHED, IN_PROGRESS
```

Therefore a new H0.2/NX, SM0 or other non-P4 mutation dispatch fails closed while this lease is reserved for P4. `IMPLEMENTED` releases the runtime-mutation worker and becomes verification-only, so NX/SM0 review/verification may coexist with P4 mutation.

Reassigning or releasing the lease requires a main-owned control update; branch-local state cannot self-authorize a second mutation lane.

## Current P4 target

```text
mine item/ore
→ canonical M4 inventory
→ deterministic server allocation
→ atomic Item Graph debit + Construction commit
→ Item Graph delta + Construction event
→ A/B convergence
→ reconnect convergence
```

P4 must reuse the canonical M4 Item Graph, Construction transaction/state owners and existing persistence/network authority. Forbidden: second Item Graph, second Construction truth, shadow economy/material balance, client-owned affordability or private V0 network authority.

## Acceptance debt

Bounded P4 implementation may proceed after the full authorization chain above while these remain open:

```text
P2 Director verdict pending
P3 aggregate Reviewer / Verifier / Director pending
PR #117 independent HIGH-risk routing pending
```

But P4 checkpoint acceptance / stable V0 acceptance remains blocked until applicable inherited acceptance debt and exact-head P4 review/verification gates are complete.

## Product critical path

```text
P4 real-resource Construction
→ P5 equipment/tools
→ P6 persistent shared outpost
   mine → inventory/container → build → reconnect
   → 5 clean E2E repeats
   → 30-minute two-client soak
→ P7 bounded terrain mutation
→ P8 first mobile construct / ship
```

P6 is the stable playable V0 baseline. Terrain deformation, server handoff, full Matter integration, ECO production and advanced ships are not prerequisites for P4/P6 unless a concrete machine gate proves otherwise.

## Fail-closed boundaries

Stop/replan on any requirement for:

```text
new protocol ownership
new network authority/reconciliation model
second Item Graph owner
second persistence/durability owner
second Construction truth
cross-server authority transfer
second pre-H0.3 runtime mutation worker
P4 dispatch without fresh authoritative audit evidence
non-Director initial dispatch
```

Historical branches remain evidence/capability donors unless main-owned control explicitly declares their exact head as a continuation input.