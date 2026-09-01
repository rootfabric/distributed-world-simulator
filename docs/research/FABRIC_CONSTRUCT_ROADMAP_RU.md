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
CONSTRUCT0              ✅ CLOSED
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
                  │                CONSTRUCT0.PLAY1 ✅
                  │              PHYSICAL TOYBOX CLOSED
                  │                        │
                  │                    C0.4 ✅
                  │              FULL / BAKED modes
                  │                        │
                  │                    C0.5 ✅
                  │          invalidation / reconstruction
                  │                        │
                  │                    C0.6 ✅
                  │           local unbake / topology split
                  │                        │
                  │                CONSTRUCT0 ✅ CLOSED
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

The next active tangible checkpoint after the verified toybox is `C0.4 FULL ↔ BAKED PHYSICAL REPRESENTATION`.

### CONSTRUCT0.PLAY1 — PHYSICAL TOYBOX — CLOSED / EXACT DOUBLE PASS

Verified exact subject:

```text
HEAD:
a141e7a3ec51b2fda6ab1227c5153ab4e32a6d4d

TREE:
969ec5cac28c9ed5de29b17e366c587402e7b7eb

PLAY1:
111/111 PASS

C0.1→C0.3 + PLAY1:
232/232 PASS

Project Control:
33444067612 SUCCESS
```

All five mandatory experiments have deterministic twin-run state-hash checks and RESET-to-initial-hash checks.

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
A break must mutate canonical Construction rather than using a Godot-only fracture shortcut. PLAY1 closes the canonical failure boundary; bounded local unbake / topology split / deterministic re-bake remain the explicit C0.6 checkpoint.

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
   - canonical block on adjustable ramp;
   - real B0.3 ramp support/friction boundary;
   - demonstrate STICK → SLIDE under increased tangential FORCE.
   - rolling is exercised separately through CART/AXLE in PLAY1; arbitrary rolling ramp bodies remain outside this slice.

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
   - ADD_LOAD through the existing Construction structural compiler;
   - demonstrate bond utilization, overload, canonical BREAKABLE bond failure and source revision/checksum mutation;
   - local unbake / topology split / re-bake are deliberately deferred to C0.6.

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

#### PLAY1 closure gate — SATISFIED
PLAY1 closed only after:
- all five mandatory toybox experiments are runnable in the Godot lab;
- they use canonical Construction identity/topology;
- motion comes from FABRIC playback/runtime where the relevant capability exists;
- no Godot RigidBody state is promoted to canonical physical truth;
- breakable structures use canonical topology mutation;
- unsupported physics remains explicit rather than silently approximated;
- deterministic reset/replay exists for the reference experiments;
- focused acceptance and Project Control pass.

Exact result:

```text
PLAY1 111/111 PASS
full chained acceptance 232/232 PASS
fresh detached tracked-clean
canonical double Godot identity PASS
Project Control PASS
VERIFIED
```

### C0.4 — physical representation forcing — CLOSED / EXACT DOUBLE PASS

The lifecycle lab drives the exact 500-part BRIDGE-1 subject.

Debug modes:
- AUTO;
- FORCE FULL;
- FORCE BAKED where certified.

Verified:
```text
500 canonical parts
FULL  6500 DOF
BAKED   13 DOF
reduction 500x
boundary anchor mismatch <= 1e-9
```

AUTO chooses certified BAKED. Representation forcing does not mutate canonical source identity. NO_SAFE_BAKE remains explicit and fail-closed.

Acceptance:
`26/26 PASS`.

### C0.5 — source mutation lifecycle — CLOSED / EXACT DOUBLE PASS

Visible and verified:
- canonical property edit;
- RepresentationInvalidation;
- BakeInvalidation;
- old bake immediately STALE/non-executable;
- exact 500-part kinematic reconstruction;
- `DISCARD_AND_REDERIVE` transient contact policy;
- fresh graph/artifact rebuild;
- build generation increments exactly once;
- bounded state handoff;
- explicit FULL fallback remains legal.

Acceptance:
`23/23 PASS`.

### C0.6 — topology mutation lifecycle — CLOSED / EXACT DOUBLE PASS

The lifecycle lab executes the already closed B0.2-D and B0.2-E implementations on the exact 500-part structural subject.

B0.2-D:
```text
20 / 500 parts locally FULL
480 retained reduced
2 retained reduced components
2 cut interfaces
6500 → 286 DOF
>22.7x preserved reduction
4% unbaked
```

B0.2-E:
```text
bond break APPLIED
2 split components
3 predecessor reduced pieces invalidated
2 fresh executable PhysicalBakeArtifacts
6500 → 286 → 26 DOF
250x post-split reduction
```

Conservation and handoff remain within the frozen B0.2-D/E tolerances.

Acceptance:
`44/44 PASS`.

## CONSTRUCT0 closure gate — SATISFIED

A single integrated Godot entrypoint now demonstrates:

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

Integrated entrypoint:
`res://scenes/labs/fabric_construct0_complete_lab.tscn`

Exact final subject:
```text
HEAD:
afcd564b631a2f48283dfefef17f4d6542f558a3

TREE:
36064f8ad9f09e86cb242f4202f2e068044b6a2b

C0.1 58/58 PASS
C0.2 33/33 PASS
C0.3 30/30 PASS
PLAY1 111/111 PASS
C0.4 26/26 PASS
C0.5 23/23 PASS
C0.6 44/44 PASS

TOTAL:
325/325 PASS

Project Control:
33507347220 SUCCESS

verdict:
VERIFIED
```

`CONSTRUCT0` is therefore CLOSED as a research/tangible checkpoint. Production acceptance is not claimed.

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
