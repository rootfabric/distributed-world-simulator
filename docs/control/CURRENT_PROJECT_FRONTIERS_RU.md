# Distributed World Simulator — Current Project Frontiers

**Operational owner:** `main`  
**Architecture baseline:** `GLOBAL-P0-2026-08-12-R3-REFRESH-R1`  
**Registry generation:** `80` activation-refresh candidate on PR #98; live `main` remains generation `79` until acceptance/merge  
**Control plane:** `PC0-2026-08-10-R1`  
**Harness:** `H0-2026-08-11-R1`

> Machine project-state truth remains `config/control/project-program-registry.v1.json`. PR #98 is the main-owned generation-80 activation candidate. This refresh does not declare P1/P2/P3/P4 accepted; it synchronizes control routing with the product state that already exists in Git and removes the stale rule that forced the next V0 runtime branch to restart from bare `main`.

## Canonical global state

GLOBAL-P0 R3 V9 is canonical. C22 is MAIN_INTEGRATED. Mandatory post-R3 Project Control is NON_RED. H0.2/NX.C1 remains an independent HIGH-risk verification/source-acceptance lane.

The V0 network baseline remains:

```text
SERVER_PREDICTED
```

`OWNER_AUTHORITATIVE_VALIDATED` is not a prerequisite for the current V0 product loop. Any V0 change that actually requires protocol/authority/reconciliation/Character-ownership redesign fails closed back to NX.

## Actual V0 product lineage

The current product work did not remain at the original S1 planning point. It advanced as a bounded stacked product train:

```text
P0 playable frontier
  feature/v0-playable-product-frontier

        ↓

P1 world items / pickup-drop / external containers
  PR #103
  exact current head: f7ab0a8b91394724b66e3f4ee387de3441a676ca
  fresh P1 review: PASS

        ↓

P2 reconnectable shared state
  PR #109
  exact candidate: 92e3e197e11156d6c36a58a3b4a4f447397c99d7
  Windows exact-head GREEN
  Reviewer PASS
  Verifier PASS
  Director verdict pending

        ↓

P3 authoritative resource mining
  PR #113 base candidate: f27a60279c8ad61d47ebe3fad81b6898679c660f
  P3.1 interaction repair PR #115: ef3ad5f0afc433802d639171d938e4720b3a46ec
  operator demonstrated real mining and B-side depletion visibility

        ↓

P4 Construction consumes real resources
  branch: feature/v0-p4-construction-real-resources
  prebuild head at refresh input: c20310cf804374ab515fd7a363b6471c2b933ac0
  HIGH-risk Work Order: #118
  exact-consume RED contract + risk/repair map + prepared P4.1 patch exist
```

Separate network repair PR #117 (`11819f6dd1ea3728382a04737d30a5300de622f7`) remains excluded from the P4 execution base until its independent HIGH-risk acceptance routing is complete. It is required before final P4/P6 replication confidence, but it is not silently imported into P4.

## Main-owned product execution base rule

`main` remains the control owner, but **runtime continuation no longer means runtime branch must be byte-identical to current main**.

Generation-80 declares two different anchors:

```text
CONTROL / EPOCH ANCHOR
  current canonical main

RUNTIME PRODUCT EXECUTION BASE
  exact main-declared V0 product-lineage head
```

For the current P4 train the declared execution base is:

```text
branch: repair/v0-p3-visual-interaction-r1
sha:    ef3ad5f0afc433802d639171d938e4720b3a46ec
```

This is an execution-base declaration, **not checkpoint acceptance**. It does not turn P2/P3 into accepted/main-integrated checkpoints.

After PR #98 is accepted into `main`, mandatory post-main standard + directional PC0 and a fresh epoch/base dependency audit decide:

```text
CONTINUE existing P4 branch
or
REFRESH_REQUIRED with bounded capability transfer
```

The old rule "throw away the proven product train and restart V0 from bare main" is removed.

## Current V0 checkpoint

The active bounded product checkpoint is:

```text
V0_P4_REAL_RESOURCE_CONSTRUCTION
```

Goal:

```text
mine item/ore
→ canonical M4 inventory
→ server-only deterministic allocation
→ atomic Item Graph debit + Construction commit
→ Item Graph delta + Construction event
→ A/B converge
→ reconnect reconstructs same state
```

P4 must reuse the existing canonical M4 Item Graph and Construction transaction/state owners. It may not introduce a second Item Graph, shadow economy balance, client-owned affordability truth or a second persistence owner.

## Acceptance debt vs implementation continuation

The refresh explicitly separates two concepts.

Bounded P4 implementation may continue after generation-80 activation + post-main PC0 + Director dispatch even while these earlier acceptance items are still being closed:

```text
P2 Director verdict pending
P3 aggregate Reviewer / Verifier / Director pending
PR #117 independent HIGH-risk routing pending
```

But **P4 checkpoint acceptance / V0 stable baseline may not be declared** until the applicable inherited acceptance debt is resolved and exact-head P4 review/verification is complete.

This prevents governance debt from stopping useful bounded implementation without hiding or waiving the debt.

## Runtime-worker boundary

Before H0.3:

```text
total autonomous runtime mutation workers <= 1
```

The intended current mutation lane after generation-80 activation is P4.

Allowed in parallel:

```text
P4 mutation
+
P2/P3/#117/NX/SM0 review or verification-only work
```

Forbidden before H0.3:

```text
P4 runtime mutation
+
NX non-trivial FIX mutation

P4 runtime mutation
+
SM0 non-trivial runtime FIX mutation
```

Those mutation trains must be serialized.

## Product critical path from here

```text
P4 real-resource Construction
        ↓
P5 equipment / mining-build tool presentation
        ↓
P6 persistent shared outpost loop
  mine
  → inventory/container
  → build
  → disconnect/reconnect
  → 5 clean E2E repeats
  → 30-minute two-client soak
        ↓
P7 bounded terrain mutation
        ↓
P8 first mobile construct / ship
```

Terrain deformation, full Matter integration, server handoff, distributed zones, ecology production and advanced ships are not prerequisites for P4/P6.

## Parallel NX lane

```text
H0.2 / NX.C1 source IMPLEMENTED
        ↓
exact Godot focused validation
        ↓
full world/core
        ↓
two-client + impaired-network
        ↓
reconnect / ownership epoch
        ↓
independent review + CH -> NX revalidation
        ↓
H0_2_PASS + NX SOURCE_ACCEPTED
```

NX acceptance remains strict and independent. V0 does not infer NX acceptance.

## Fail-closed boundaries

V0/P4 must stop and replan if it would require:

```text
new protocol ownership
new network authority/reconciliation model
second Item Graph owner
second persistence/durability owner
second Construction truth
cross-server authority transfer
>1 autonomous runtime mutation worker before H0.3
```

Historical branches remain evidence/capability donors unless explicitly declared as an exact V0 product execution base by main-owned control.
