# Distributed World Simulator — Current Project Frontiers

**Operational owner:** `main`  
**Architecture baseline:** `GLOBAL-P0-2026-08-12-R3-REFRESH-R1`  
**Registry generation:** `80` activation candidate on PR #98; live `main` remains generation `79` until acceptance/merge  
**Control plane:** `PC0-2026-08-10-R1`  
**Harness:** `H0-2026-08-11-R1`

> Machine project-state truth remains `config/control/project-program-registry.v1.json`. PR #98 now contains the complete generation-80 routing candidate; it becomes canonical only after the control change is accepted into `main` and post-main Project Control is NON_RED.

## Canonical state

GLOBAL-P0 R3 V9 is canonical. C22 is MAIN_INTEGRATED. Mandatory post-R3 Project Control is NON_RED. H0.2/NX.C1 bounded source implementation exists but its exact Godot/runtime verification and source acceptance are still pending.

## Product critical path

The first product checkpoint is:

```text
V0_S1_NETWORKED_PLANETARY_OUTPOST
```

Target runtime:

```text
one procedural planet
+ one server
+ two clients
+ two playable characters
+ bidirectional remote movement
+ canonical Construction commit
+ replicated small outpost
+ reconnect to the same live world state
+ 30-minute two-client soak
```

V0-S1 uses the canonical current-main `SERVER_PREDICTED` network behavior first. It does not infer acceptance of the in-progress `OWNER_AUTHORITATIVE_VALIDATED` NX.C1 profile.

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

NX acceptance remains strict and independent.

## H0.3 boundary

H0.3 is not a gameplay prerequisite for one V0 branch. It is required before more than one concurrent autonomous runtime **mutation** worker.

Before H0.3:

```text
runtime mutation workers <= 1
```

NX verification/review-only activity may coexist with one V0 implementation worker. NX non-trivial FIX mutation and V0 mutation must be serialized.

## Fail-closed V0 -> NX rule

V0 may not implement a private protocol, authority model, ownership epoch or reconciliation contract.

If the canonical `SERVER_PREDICTED` path cannot close the V0 scenario without such a change:

```text
V0_S1_BLOCKED_REQUIRES_NX
```

The defect/requirement returns to the NX lane.

## Following slices

```text
V0-S1 NETWORKED PLANETARY OUTPOST
        ↓
V0-S2 NETWORKED LANDED SHIP-0
        ↓
V0-S3 MOVABLE SHIP
        ↓
V0-S4 PLANET <-> SPACE
```

Wave A, G9, MAT0, TS0.4, ECO production, terrain mutation and server handoff are not inserted into V0-S1 unless a concrete scenario gate proves they are required.

Historical R2 evidence remains immutable provenance and cannot authorize new post-R3 runtime work.
