# FABRIC CONSTRUCT — Tangible Construction Roadmap

## Purpose

Turn the current abstract Construction + FABRIC + FABRIC-BAKE architecture into an executable Godot laboratory where compound objects can be seen, inspected, edited and eventually simulated through the real physical model.

This is a parallel product/research line. It must not fork canonical truth or replace FABRIC with Godot physics.

## Current boundary

```text
FABRIC0.18              ✅ CLOSED
BRIDGE-1                ✅ CLOSED
B0.3 CONTACT/WRENCH     ✅ CLOSED
POST-B0.3 SYNC          current architectural boundary
CONSTRUCT0              authorized now
```

## Roadmap

```text
                         FABRIC0.18 ✅
                              │
                         BRIDGE-1 ✅
                              │
                            B0.3 ✅
                              │
                  ┌───────────┴────────────┐
                  │                        │
             FABRIC SYNC-2            CONSTRUCT0
                  │                 TANGIBLE SANDBOX
                  │                        │
                  │                    C0.0 ✅
                  │                 architecture
                  │                        │
                  │                    C0.1 🟡
                  │                 observatory
                  │                        │
                  │                    C0.2
                  │             FABRIC-driven playback
                  │                        │
                  │                    C0.3
                  │              construction editor
                  │                        │
                  │                    C0.4
                  │              FULL / BAKED modes
                  │                        │
                  │                    C0.5
                  │          invalidation / reconstruction
                  │                        │
                  │                    C0.6
                  │           local unbake / topology split
                  │                        │
                  │                  CONSTRUCT0 CLOSED
                  │                        │
          ┌───────┴────────┐               │
          ▼                ▼               │
        B0.4             B0.5              │
     Dynamic ROM      Hybrid Bake          │
          │                │               │
          └───────┬────────┴───────────────┘
                  ▼
               BRIDGE-2
           MIXED FULL ↔ BAKED
                  │
                  ▼
             CONSTRUCT1
        dynamic/hybrid machines
                  │
                  ▼
                B0.6
      Adaptive Physical Fidelity
                  │
                  ▼
             CONSTRUCT2
       adaptive representation UI
                  │
                  ▼
              BRIDGE-3
       FULL→BAKE→UNBAKE→FULL
                  │
                  ▼
             CONSTRUCT3
        damage/refinement demo
                  │
                  ▼
                B0.7
        Unseen Machine Challenge
                  │
                  ▼
               FABRIC1
```

## CONSTRUCT0 slices

### C0.0 — architecture / branch freeze
Complete when branch, predecessor identity, invariants and acceptance boundary are documented.

### C0.1 — tangible observatory
Goal: make a compound Construction and B0.3 reduction visible.

Visible presets:
- TABLE;
- BRIDGE;
- CART.

Must show:
- canonical part/bond topology;
- current Construction checksum/revision;
- runtime projection;
- full contact-member cloud;
- baked contact extreme generators;
- reduction ratio;
- representative 6D wrench/tipping/passivity outputs;
- AUTO/FULL/BAKED contact representation view.

C0.1 explicitly does not claim time integration.

### C0.2 — FABRIC-driven playback
Goal: Godot becomes a viewer for closed FABRIC0.18 dynamics.

Reference trajectories:
- drop / impact / persistent support;
- stick→slide;
- roll/spin activation where supported;
- support loss / separation;
- deterministic replay.

Rule:
`FABRIC state → Godot transform`, never `Godot RigidBody state → FABRIC truth`.

### C0.3 — canonical construction editor
User can:
- add Block / Beam / Plate;
- select / move / rotate;
- create and break rigid bonds;
- inspect part identity and canonical revision.

Every edit goes through Construction first.

### C0.4 — physical representation forcing
Debug modes:
- AUTO;
- FORCE FULL;
- FORCE BAKED where certified.

NO_SAFE_BAKE remains visible and legal.

### C0.5 — source mutation lifecycle
Visible proof:
- canonical property edit;
- old bake immediately stale/non-executable;
- reconstruct kinematics;
- rebuild graph/artifact;
- transient contact history discarded/re-derived.

### C0.6 — topology mutation lifecycle
Visible proof:
- local bond break;
- bounded local unbake;
- canonical split;
- stale invalidation;
- deterministic component re-bake.

## CONSTRUCT0 closure gate

CONSTRUCT0 closes only when one Godot lab demonstrates:

```text
build compound object
→ inspect canonical Construction
→ run/view physical behavior
→ compare FULL / supported BAKED representation
→ mutate source
→ invalidate/rebuild
→ break topology
→ local unbake/split/re-bake
```

with no second truth, no device-specific physics shortcut and deterministic acceptance evidence.

## Later tangible stages

### CONSTRUCT1 — after B0.4/B0.5 maturity
Dynamic/hybrid compound machines:
- stateful internal subsystems;
- ROM visibility;
- hybrid modes and guards;
- lazy mode compilation.

### CONSTRUCT2 — after BRIDGE-2/B0.6
Mixed representation inside one object/world:
- FULL regions;
- structural bake;
- contact bake;
- dynamic ROM;
- hybrid bake;
- adaptive physical fidelity.

### CONSTRUCT3 — around BRIDGE-3
The decisive visible lifecycle:
- calm object mostly baked;
- local interaction triggers refinement;
- damaged region unbakes;
- canonical topology changes;
- stable remnants re-bake.

## Non-goal

The CONSTRUCT line is not a parallel game-specific physics stack. It exists to expose and falsify the existing generic model.
