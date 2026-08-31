# FABRIC CONSTRUCT0 — Tangible Physical Construction Sandbox

## Status

```text
CONSTRUCT0
C0.1 SEE THE MODEL IMPLEMENTED
C0.2 SEE FABRIC MOVE IT IMPLEMENTED
C0.3 BUILD IT IMPLEMENTED
EXACT C0.1→C0.3 VERIFICATION PENDING
NOT PRODUCTION ACCEPTED
```

Branch:

`feature/fabric-construct0-tangible-sandbox-r1`

Frozen base:

```text
FABRIC-BAKE B0.3 closure
9575a63d6aeb4c455f8beade7588505e600c12d6

B0.3 exact executable
acc72c1fb216bea56bc44547bc3e1eec7a37af08

FABRIC0.18 closure
b9f4a11cb7c31e47884d12eaad2985811e0b6563
```

## Goal

Make the current Construction + FABRIC + FABRIC-BAKE model tangible in Godot without creating a second physical truth.

Godot is presentation and interaction only. Canonical object identity/topology remains Construction. FABRIC and PhysicalBakeArtifact remain derived executable physical representations.

```text
Godot input / visualization
        ↓
canonical Construction
        ↓
derived physical projection
        ↓
FULL FABRIC or BAKED FABRIC
        ↓
physical observables
        ↓
Godot visualization / inspector
```

The demo must never claim that Godot RigidBody3D is the authoritative FABRIC solver.

## Roadmap

### C0.0 — Architecture + roadmap freeze
- branch and exact predecessor boundary;
- no-new-truth rule;
- debug-only representation forcing contract;
- executable acceptance plan.

### C0.1 — Tangible observatory — IMPLEMENTED / VERIFICATION PENDING
- four compound presets: TABLE, BRIDGE, CART, PLANK;
- canonical Construction parts + bonds;
- existing Construction runtime projection for geometry;
- actual B0.3 contact/wrench artifact compiled for the active support patch;
- FULL contact members and BAKED extreme generators shown in 3D;
- inspector shows part/bond counts, source revision, FULL member count, baked generator count, reduction ratio, 6D wrench capacity and passivity;
- mode toggle: AUTO / FULL CONTACT VIEW / BAKED CONTACT VIEW;
- no claim of full rigid-body time integration yet.

### C0.2 — FABRIC driven rigid-body playback — IMPLEMENTED / VERIFICATION PENDING
- bounded PLANK reference scenario driven directly by closed FABRIC0.18 research runtime;
- PLAY / PAUSE / STEP EVENT / RESET controls;
- visible event timeline and FABRIC body velocities;
- impact → persistent support → slide/roll/spin → separation;
- Godot transform follows FABRIC state, never the reverse;
- deterministic reset/replay.

### C0.3 — Construction editor — IMPLEMENTED / VERIFICATION PENDING
- create an empty canonical Construction;
- add Block / Beam / Plate;
- select/move/rotate;
- create/break rigid bonds;
- generic canonical `update_part_pose` with replay and stale-revision rejection;
- every edit mutates canonical Construction first;
- runtime projection rebuilt from canonical snapshot.

### CONSTRUCT0.PLAY1 — Physical Toybox
- generic parts: BLOCK, PLATE, BEAM, CYLINDER, WHEEL, AXLE, WEIGHT, ANCHOR;
- generic relations: RIGID_BOND, HINGE, AXLE/REVOLUTE, SLIDER, SPRING_DAMPER, BREAKABLE_BOND;
- environment: FLOOR, adjustable RAMP, MOVING_SURFACE;
- interaction tools: FORCE, IMPULSE, TORQUE, ADD_LOAD, BREAK_BOND;
- tunable parameters: mass, dimensions, contact/rolling/torsional friction, bond strength, spring stiffness/damping;
- mandatory experiments: INCLINED_PLANE, SEESAW, CART, CATAPULT, BREAKABLE_BRIDGE;
- optional: PENDULUM, TOWER/DOMINO, SUSPENSION_CART, DOOR, PRESS/SLIDER;
- ideal lab sources/sensors are allowed, but no Motor/Gearbox/Battery device-specific physics classes;
- breakage must mutate canonical topology and route through existing local-unbake / split / re-bake mechanisms.

PLAY1 is the first explicitly playable constructor milestone.

### C0.4 — FULL ↔ BAKED physical representation
- force FULL / force supported BAKED / AUTO;
- compare boundary observables;
- show NO_SAFE_BAKE explicitly rather than silently approximating;
- show current physical representation and reduction ratio.

### C0.5 — Mutation / invalidation / rebuild
- edit mass/material/property;
- old physical artifact becomes STALE and non-executable;
- exact reconstruction;
- fresh physical graph/bake;
- contact history DISCARD_AND_REDERIVE.

### C0.6 — Local unbake / topology split
- break one bond in a larger compound object;
- bounded local unbake through B0.2-D;
- canonical topology break through B0.2-E;
- stale invalidation and deterministic re-bake.

### C0 closure
One Godot lab must make the end-to-end model visible:
Construction → physical representation → contact behavior → bake reduction → invalidation → rebuild/unbake.

## First presets

### TABLE
Top plate + four legs. Primary purpose: support distribution, tipping and contact reduction.

### BRIDGE
Two supports + multi-part deck. Primary purpose: structural identity, load/support visualization and future local-unbake demo.

### CART
Frame + four wheel-shaped parts. Initial C0.1 is visualization/contact-observatory only; wheel-specific physics is explicitly forbidden.

## Acceptance boundary for C0.1

C0.1 may close only when:
- the scene boots in the pinned double Godot build;
- preset Construction snapshots validate;
- runtime projection materializes all parts;
- B0.3 artifact is produced from the active coplanar support patch;
- FULL contact member count > BAKED generator count;
- reverse point ordering produces the same B0.3 model hash;
- B0.3 maximum-dissipation wrench remains passive;
- FULL/BAKED contact visualization changes presentation only;
- no canonical Construction checksum changes from representation switching;
- unsupported contact geometry reports NO_SAFE_BAKE;
- focused acceptance and playground pass;
- Project Control passes.

## Non-claims

CONSTRUCT0 does not yet claim:
- production physics;
- a replacement for the Godot editor;
- arbitrary mesh authoring;
- device-specific wheel/motor/gear physics;
- arbitrary non-coplanar B0.3 reduction;
- production scheduler/fidelity policy;
- networked collaborative building;
- production acceptance.
