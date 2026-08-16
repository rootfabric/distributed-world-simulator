# H — Primary Execution Roadmap

**Status:** canonical execution route candidate  
**Architecture:** `GLOBAL-P0-2026-08-12-R3-REFRESH-R1`  
**Progress unit:** accepted checkpoint or removed gate, never commit count.

## Control rule

```text
BRANCHES REPORT FACTS
MAIN DECLARES PROJECT STATE
AUDITOR CHECKS CONSISTENCY
GLOBAL ARCHITECTURE DEFINES WHAT IS ALLOWED
HARNESS MOVES ONLY BETWEEN DECLARED CHECKPOINTS
```

`main` owns authorization and global state. It does not have to be the byte-for-byte runtime base of every product continuation branch. For V0, main may declare an exact product execution base when that preserves a proven stacked product composition more safely than restarting from bare main.

## Canonical anchors

```text
H0.1 / C22                         PASS
C22 MAIN_INTEGRATED               DONE
GLOBAL-P0 R3                      CANONICAL
post-R3 Project Control           NON_RED
```

C22 remains canonical Construction truth. R3 remains canonical architecture. V0 may compose these foundations but may not create duplicate ownership.

## Current execution topology

The project currently has three different kinds of work that must not be confused:

```text
CONTROL
  main / generation-80 activation refresh

PRODUCT
  P0 -> P1 -> P2 -> P3 -> P4 -> P5 -> P6

FOUNDATION HARDENING
  H0.2 / NX.C1
  SM0 seamless handoff lab
```

The product critical path is P4/P6. NX and SM0 remain valuable but are not prerequisites unless the V0 scenario proves a foundation change is required.

## V0 execution-base model

Generation-80 uses two anchors:

```text
Project Epoch / control anchor = exact current main
Runtime product execution base = exact main-declared V0 lineage head
```

Current declared P4 input candidate:

```text
repair/v0-p3-visual-interaction-r1
ef3ad5f0afc433802d639171d938e4720b3a46ec
```

This does not declare P2/P3 accepted. It only prevents the control layer from forcing an unnecessary reconstruction of already demonstrated P0-P3 composition.

After generation-80 integration, post-main PC0 + fresh dependency audit chooses `CONTINUE` or `REFRESH_REQUIRED` for the existing P4 branch.

## Actual V0 product train

```text
P0 PLAYABLE FRONTIER
  procedural Earth
  dedicated server
  clients A/B
  SERVER_PREDICTED movement
  inventory + Construction composition

        ↓

P1 WORLD ITEMS / CONTAINERS
  canonical WORLD presentation
  pickup / drop
  external container
  authoritative transfers

        ↓

P2 RECONNECTABLE SHARED STATE
  durable Item Graph recovery
  reconnect convergence
  state fingerprint

        ↓

P3 RESOURCE MINING
  authoritative resource node
  resource.mine
  depletion
  canonical item/ore output
  A/B + reconnect convergence

        ↓

P4 REAL-RESOURCE CONSTRUCTION   <-- CURRENT IMPLEMENTATION TARGET
  deterministic server allocation
  atomic Item Graph debit + Construction commit
  exact-once / rollback / ownership
  A/B publication + reconnect

        ↓

P5 EQUIPMENT / TOOLS
  mining/build tool presentation
  server-owned equipped state

        ↓

P6 PERSISTENT SHARED OUTPOST
  mine -> inventory/container -> build
  disconnect/reconnect
  5 clean E2E repeats
  30-minute two-client soak

        ↓

P7 bounded terrain mutation
        ↓
P8 first mobile construct / ship
```

Ship-first routing from the original PR #98 proposal is superseded by this product evidence. Ship work follows the stable shared-outpost loop rather than interrupting it.

## V0-P4 — Construction Consumes Real Resources

Machine checkpoint:

```text
V0_P4_REAL_RESOURCE_CONSTRUCTION
```

Target transaction:

```text
player mines item/ore
        ↓
canonical M4 inventory
        ↓
server resolves requesting logical player
        ↓
deterministic allocation by (slot_index, item_id)
        ↓
ONE atomic outcome
  Item Graph debit
  + Construction commit
        ↓
Item Graph delta + Construction event
        ↓
A/B converge
        ↓
reconnect reconstructs same truth
```

Hard invariants:

```text
no client-trusted item IDs or affordability
no second Item Graph
no shadow material balance
no second persistence owner
no Construction without canonical debit
no debit without Construction commit
replay exact-once
same operation ID + different payload conflicts
fault injection rolls both domains back
foreign player inventory cannot be consumed
```

### P4 bounded implementation preconditions

```text
GLOBAL-P0 R3 canonical
post-R3 PC0 NON_RED
C22 main-integrated
main-owned generation-80 V0 activation accepted
main-declared exact V0 product execution base
explicit HIGH-risk P4 Work Order / Director dispatch
pre-H0.3 total mutation workers <= 1
```

The P2/P3 acceptance debt does not force P4 implementation to stop after those conditions are met. It remains a required gate for P4 checkpoint acceptance / stable V0 baseline.

### P4 acceptance debt

Current inherited debt includes:

```text
P2 Director checkpoint verdict
P3 aggregate Reviewer / Verifier / Director
PR #117 HIGH-risk replica repair routing before final replication/soak confidence
```

These may be closed through review/verification in parallel with one P4 mutation worker. They are not silently waived.

## Baseline network profile

V0 continues on:

```text
SERVER_PREDICTED
```

The opt-in NX.C1 profile:

```text
OWNER_AUTHORITATIVE_VALIDATED
```

is not a P4/P6 prerequisite.

If P4 requires changing:

```text
network protocol
locomotion authority semantics
ownership epoch semantics
reconciliation contract
canonical Character ownership
```

then V0 must fail closed:

```text
V0_BLOCKED_REQUIRES_NX
```

and route that requirement to NX instead of creating a private network foundation.

## H0.2 / NX.C1

H0.2 remains a HIGH-risk independent network convergence checkpoint. Its acceptance predicates are unchanged:

```text
owner-authority focused runtime
physics/presentation single-writer
item rollback
full world/core regression
two-client
impaired network
reconnect + ownership epoch
post-build critique
independent review
exact tested/reviewed heads
CH -> NX directional revalidation
PC0 NON_RED
```

`NX SOURCE_ACCEPTED != automatic runtime merge` and `NX pending != V0 blocked` unless V0 actually needs an NX foundation change.

## H0.3 worker boundary

Before H0.3 acceptance:

```text
simultaneous autonomous runtime mutation workers <= 1
```

Preferred current lane after generation-80 activation:

```text
P4 mutation
+
P2/P3/#117/NX/SM0 review or verification-only activity
```

Forbidden:

```text
P4 mutation + NX non-trivial runtime FIX mutation
P4 mutation + SM0 non-trivial runtime FIX mutation
```

The Director serializes those cases.

## V0 ownership rule

V0 is a composition consumer. It must not introduce private truth for:

```text
terrain
Character identity
Construction
Item Graph
Persistence
Network replication policy
Authority foundation
World Query
World Transaction
Spatial Domain
Material Ontology
Development Harness
```

## What is explicitly off the current V0 critical path

Until P6 is stable, do not make these prerequisites unless a concrete scenario gate proves otherwise:

```text
server handoff / multi-zone production integration
full Matter / volumetric terrain stack
large Construction / structural simulation
ECO production convergence
advanced procgen expansion
OWNER_AUTHORITATIVE_VALIDATED network profile
ships / orbital transition
advanced crafting/economy
```

## Stop rules

```text
NO P4 runtime mutation before generation-80 main activation + post-main PC0 + Director dispatch
NO P4 checkpoint acceptance while inherited acceptance debt is unresolved
NO NX.C1 source acceptance without its exact runtime/review predicates
NO V0 private network/authority foundation
NO V0 private Construction truth
NO V0 private Item Graph or persistence owner
NO >1 autonomous runtime mutation worker before H0.3
NO simultaneous P4 mutation + NX/SM0 non-trivial FIX mutation before H0.3
NO G9 before MAT0
NO T1B.5
NO T2.0 before its declared scale/convergence gates
```

After every main movement, checkpoint or promotion, recompute Project Control and resolve current execution state from Git rather than historical SHA examples.
