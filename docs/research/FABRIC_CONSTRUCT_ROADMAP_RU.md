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
                  │                    C0.1 ✅
                  │                 SEE THE MODEL
                  │                        │
                  │                    C0.2 ✅
                  │             SEE FABRIC MOVE IT
                  │                        │
                  │                    C0.3 ✅
                  │                 BUILD IT
                  │                        │
                  │                CONSTRUCT0.PLAY1
                  │                 PHYSICAL TOYBOX
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

### C0.1 — tangible observatory — CLOSED / EXACT DOUBLE PASS
Goal: make a compound Construction and B0.3 reduction visible.

Implementation includes TABLE / BRIDGE / CART plus a PLANK playback preset, canonical runtime projection and direct B0.3 contact/wrench compilation.

Verified exact subject:
`837c46940acddbd841e7878dcfbfb68c0d5ac259`.

Acceptance:
`58/58 PASS`.
Project Control:
`SUCCESS`.

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

### C0.2 — FABRIC-driven playback — CLOSED / EXACT DOUBLE PASS
Goal: Godot becomes a viewer for closed FABRIC0.18 dynamics.

Implemented playback directly invokes `fabric0_persistent_contact_trajectory_v1.gd`. The Godot pose is a deterministic display projection of FABRIC event times and body velocities; Godot physics state is never fed back into FABRIC. Controls: PLAY / PAUSE / STEP EVENT / RESET and 0.5× / 1× / 2×.

Reference trajectories:
- drop / impact / persistent support;
- stick→slide;
- roll/spin activation where supported;
- support loss / separation;
- deterministic replay.

Rule:
`FABRIC state → Godot transform`, never `Godot RigidBody state → FABRIC truth`.

### C0.3 — canonical construction editor — CLOSED / EXACT DOUBLE PASS
The lab now has a BUILD IT tab backed by `ConstructAggregate`. A generic `update_part_pose` operation was added to the canonical aggregate with revision/replay/stale-write semantics.

User can:
- create a new canonical Construction;
- add Block / Beam / Plate;
- select / move / rotate;
- create rigid bonds to another/root part;
- break rigid bonds;
- inspect part identity and canonical revision.

Every edit goes through Construction first, advances the canonical revision/checksum, then recompiles the existing runtime projection.

Acceptance runners:
- `RUN_FABRIC_CONSTRUCT0_C0_1_TESTS.sh`;
- `RUN_FABRIC_CONSTRUCT0_C0_2_TESTS.sh`;
- `RUN_FABRIC_CONSTRUCT0_C0_3_TESTS.sh`.

Exact fresh detached verification completed on the pinned double Godot build:

```text
C0.1 58/58 PASS
C0.2 33/33 PASS
C0.3 30/30 PASS
CHAIN exit 0
Project Control SUCCESS
```

The next active tangible checkpoint is `CONSTRUCT0.PLAY1 PHYSICAL TOYBOX`.

### CONSTRUCT0.PLAY1 — PHYSICAL TOYBOX
Goal: make the constructor genuinely playable with a small generic vocabulary rather than a catalogue of device-specific objects.

Entry expectation:
- C0.2 FABRIC-driven playback is available for bounded scenarios;
- C0.3 canonical editing is usable enough to create/move/connect parts;
- PLAY1 may start earlier with prebuilt presets, but closes only on the real editor/playback path.

#### Generic parts
Initial palette:
- BLOCK — generic mass/body;
- PLATE — platforms, doors, decks;
- BEAM — frames, levers, bridge members;
- CYLINDER — roller/shaft-like geometry;
- WHEEL — wheel-shaped convex part, with no wheel-specific solver;
- AXLE — shaft/rotation carrier;
- WEIGHT — convenient calibrated load;
- ANCHOR — world attachment/reference part.

#### Generic relations
Initial relation set:
- RIGID_BOND;
- HINGE / revolute;
- AXLE / rotational relation;
- SLIDER / prismatic relation;
- SPRING_DAMPER;
- BREAKABLE_BOND.

BREAKABLE_BOND must expose generic strength limits and canonical state:
```text
INTACT → DEGRADED → BROKEN
```
A break must route through canonical topology mutation and existing unbake/split/re-bake lifecycle, not through a Godot-only fracture shortcut.

#### Environment primitives
- FLOOR;
- adjustable RAMP;
- MOVING_SURFACE / conveyor-like boundary condition.

These are boundary conditions / environment primitives, not special device classes.

#### Interaction tools
The user must be able to apply:
- FORCE;
- IMPULSE;
- TORQUE;
- ADD_LOAD / calibrated weight;
- BREAK_BOND debug action.

The inspector should show application point, magnitude, resulting force/torque contribution and affected canonical/physical IDs where available.

#### Tunable physical parameters
At minimum:
- part mass;
- dimensions;
- contact friction;
- rolling friction;
- torsional friction;
- bond strength;
- hinge axis / limits / friction where supported;
- spring rest length / stiffness / damping.

#### First PLAY1 experiments
Five mandatory toybox scenes:

1. INCLINED_PLANE
   - block/cylinder on adjustable ramp;
   - demonstrate stick→slide and, when supported, rolling behavior.

2. SEESAW
   - beam + hinge + movable calibrated weights;
   - demonstrate torque, balance, support redistribution and tipping.

3. CART
   - frame + wheel-shaped parts / axle relations;
   - movable payload;
   - demonstrate center-of-mass sensitivity, support, friction and rolling/contact behavior.

4. CATAPULT
   - beam + hinge + spring/damper + projectile/load;
   - demonstrate stored energy → rotation → release.

5. BREAKABLE_BRIDGE
   - multi-part deck/support structure;
   - movable/addable loads;
   - demonstrate bond load, failure, canonical topology split, local unbake and re-bake.

Recommended additional presets after the mandatory five:
- PENDULUM;
- TOWER / DOMINO stack;
- SUSPENSION_CART;
- DOOR;
- simple PRESS / SLIDER mechanism.

#### Minimal ideal sources and sensors
Allowed as laboratory primitives:
- IDEAL_FORCE_SOURCE;
- IDEAL_TORQUE_SOURCE;
- IDEAL_VELOCITY_SOURCE;
- IDEAL_ANGULAR_VELOCITY_SOURCE;
- FORCE_SENSOR;
- TORQUE_SENSOR;
- VELOCITY_SENSOR;
- ANGULAR_VELOCITY_SENSOR.

These are explicitly ideal boundary/source/sensor primitives. They must not be presented as physical motors, gearboxes or batteries.

#### Optional ratio relation
A generic kinematic ratio relation may be prototyped:
```text
omega_b = ratio * omega_a
```
This is a generic constraint for experimenting with transmission-like compositions. It must not introduce a Gearbox class.

#### Inspector requirements
For a selected part:
- mass;
- linear/angular velocity;
- net force;
- net torque;
- active contacts;
- current physical representation.

For a selected bond/relation:
- current force/torque load where available;
- configured capacity/limit;
- utilization percentage;
- state: INTACT / DEGRADED / BROKEN.

For the whole Construction:
- canonical part/bond count;
- FULL estimated physical complexity;
- current reduced complexity;
- FULL contact members;
- BAKED generators;
- reduction ratio;
- active refinement / validity guard state.

#### PLAY1 architecture rule
Do not add:
- MotorPhysics;
- GearboxPhysics;
- BatteryPhysics;
- ClutchPhysics;
- WheelPhysics;
- device-specific solver shortcuts.

The intended composition rule remains:
```text
generic parts
+ generic relations
+ generic sources
+ generic material/contact laws
→ emergent device behavior
```

If a desired toy cannot be expressed with generic primitives, that is evidence for a missing FABRIC/Construction primitive and should feed back into SYNC-2 / later physical research.

#### PLAY1 closure gate
PLAY1 closes only when:
- all five mandatory toybox experiments are runnable in the Godot lab;
- they use canonical Construction identity/topology;
- motion comes from FABRIC playback/runtime where the relevant capability exists;
- no Godot RigidBody state is promoted to canonical physical truth;
- breakable structures use canonical topology mutation;
- unsupported physics remains explicit rather than silently approximated;
- deterministic reset/replay exists for the reference experiments;
- focused acceptance and Project Control pass.

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
