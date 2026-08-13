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

## Canonical anchors

```text
H0.1 / C22                         PASS
C22 MAIN_INTEGRATED               DONE
GLOBAL-P0 R3                      CANONICAL
post-R3 Project Control           NON_RED
```

C22 remains canonical Construction truth. R3 remains canonical architecture. Neither V0 nor NX may create duplicate domain ownership.

## Current execution topology

The runtime path is no longer a global waterfall `H0.2 -> H0.3 -> any V0`.

```text
                                  ┌─ H0.2 / NX.C1 runtime verification
                                  │          ↓
                                  │     H0_2_PASS + NX SOURCE_ACCEPTED
                                  │          ↓
R3 + post-R3 PC0 ─────────────────┼─> H0.3 DEVELOPMENT multi-worker scheduler
        │                         │
        │                         └─ optional OWNER_AUTHORITATIVE_VALIDATED axis
        │
        └─> V0-S1 NETWORKED PLANETARY OUTPOST
                    ↓
                 V0-S2
              LANDED SHIP-0
                    ↓
                 V0-S3+
           movable ship / space / handoff
```

## H0.2 / NX.C1

H0.2 remains a HIGH-risk network convergence checkpoint. Its acceptance predicates are unchanged.

Required proof includes:

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

Result:

```text
H0_2_PASS
NX SOURCE_ACCEPTED
```

`NX SOURCE_ACCEPTED != automatic runtime merge`.

## V0-S1 — Networked Planetary Outpost

Machine checkpoint:

```text
V0_S1_NETWORKED_PLANETARY_OUTPOST
```

Product result:

> Two clients connect to one server and one procedural planet, each has a playable character, players see each other's movement, and a small Construction outpost committed through canonical server truth is visible to both clients and survives reconnect in the live world.

### Baseline network profile

V0-S1 starts with the canonical current-main network path:

```text
SERVER_PREDICTED
```

The in-progress NX.C1 profile:

```text
OWNER_AUTHORITATIVE_VALIDATED
```

is an optional later A/B axis and is not inferred accepted by V0-S1.

### Preconditions

```text
H0_1_PASS
C22_MAIN_INTEGRATED
GLOBAL_P0_R3_CANONICAL
POST_R3_STANDARD_PC0_NON_RED
POST_R3_DIRECTIONAL_PC0_NON_RED
CANONICAL_MAIN_KNOWN
NO_GLOBAL_PROJECT_RED
CANONICAL_NETWORK_RUNTIME_PRESENT
PRE_H0_3_RUNTIME_IMPLEMENTATION_WORKERS_LE_1
```

V0-S1 does **not** require:

```text
H0_2_PASS
NX_SOURCE_ACCEPTED
H0_3_SCHEDULER_ACCEPTED
OWNER_AUTHORITATIVE_VALIDATED_ACCEPTED
```

### Required runtime behavior

```text
server boots one procedural planet
Client A + Client B join same world/session
both have playable characters
remote character visibility works both ways
movement replication works both ways
A places minimal Construction pieces
server accepts canonical Construction mutation
A and B observe same construct revision
no client-private permanent Construction truth
B disconnects/reconnects and still sees same outpost
30-minute two-client bounded soak
```

### Fail-closed NX boundary

V0 may compose existing network behavior, but it may not invent network/authority semantics.

If closing V0-S1 requires changing:

```text
network protocol
locomotion authority semantics
ownership epoch semantics
reconciliation contract
canonical Character ownership
```

then V0 emits:

```text
V0_S1_BLOCKED_REQUIRES_NX
```

and the requirement returns to H0.2/NX work.

## H0.3

H0.3 controls **development workers**, not game-runtime simulation.

Before H0.3 acceptance:

```text
simultaneous autonomous runtime IMPLEMENTATION workers <= 1
```

Allowed:

```text
1 V0 implementation worker
+
NX verification/review-only activity
```

Forbidden:

```text
V0 runtime mutation
+
NX non-trivial runtime FIX mutation
```

The Director must serialize the forbidden case.

H0.3 is required before more than one concurrent autonomous runtime mutation worker.

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

## Following product slices

```text
V0-S1 NETWORKED PLANETARY OUTPOST
        ↓
V0-S2 NETWORKED LANDED SHIP-0
        ↓
V0-S3 MOVABLE SHIP
        ↓
V0-S4 PLANET <-> SPACE
        ↓
later server handoff / multi-zone / ecology / AI / terrain mutation
```

Ship flight, orbital/reference-frame transitions and server handoff are explicitly outside V0-S1.

## Stop rules

```text
NO NX.C1 source acceptance without its exact runtime/review predicates
NO V0 private network/authority foundation
NO V0 private Construction truth
NO V0 private terrain truth
NO >1 autonomous runtime mutation worker before H0.3
NO simultaneous V0 mutation + NX non-trivial FIX mutation before H0.3
NO G9 before MAT0
NO T1B.5
NO T2.0 before its declared scale/convergence gates
NO independent Item truth fork
```

After every main movement, checkpoint or promotion, recompute Project Control and resolve CURRENT from Git rather than historical SHA examples.
