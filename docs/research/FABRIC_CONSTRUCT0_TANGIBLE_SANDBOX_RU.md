# FABRIC CONSTRUCT0 — Tangible Physical Construction Sandbox

## Status

```text
CONSTRUCT0
C0.1 SEE THE MODEL CLOSED
C0.2 SEE FABRIC MOVE IT CLOSED
C0.3 BUILD IT CLOSED
PLAY1 PHYSICAL TOYBOX CLOSED
C0.4 FULL ↔ BAKED CLOSED
C0.5 MUTATION / INVALIDATION / REBUILD CLOSED
C0.6 LOCAL UNBAKE / TOPOLOGY SPLIT CLOSED
CONSTRUCT0 CLOSED
EXACT DOUBLE PASS
PROJECT CONTROL PASS
NOT PRODUCTION ACCEPTED
```

Current closure branch:

`feature/fabric-construct0-c0-4-c0-6-lifecycle-r1`

Lineage:

```text
feature/fabric-construct0-tangible-sandbox-r1
        ↓
feature/fabric-construct0-play1-physical-toybox-r1
        ↓
feature/fabric-construct0-c0-4-c0-6-lifecycle-r1
```

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

### C0.1 — Tangible observatory — CLOSED
- four compound presets: TABLE, BRIDGE, CART, PLANK;
- canonical Construction parts + bonds;
- existing Construction runtime projection for geometry;
- actual B0.3 contact/wrench artifact compiled for the active support patch;
- FULL contact members and BAKED extreme generators shown in 3D;
- inspector shows part/bond counts, source revision, FULL member count, baked generator count, reduction ratio, 6D wrench capacity and passivity;
- mode toggle: AUTO / FULL CONTACT VIEW / BAKED CONTACT VIEW;
- no claim of full rigid-body time integration yet.

### C0.2 — FABRIC driven rigid-body playback — CLOSED
- bounded PLANK reference scenario driven directly by closed FABRIC0.18 research runtime;
- PLAY / PAUSE / STEP EVENT / RESET controls;
- visible event timeline and FABRIC body velocities;
- impact → persistent support → slide/roll/spin → separation;
- Godot transform follows FABRIC state, never the reverse;
- deterministic reset/replay.

### C0.3 — Construction editor — CLOSED
- create an empty canonical Construction;
- add Block / Beam / Plate;
- select/move/rotate;
- create/break rigid bonds;
- generic canonical `update_part_pose` with replay and stale-revision rejection;
- every edit mutates canonical Construction first;
- runtime projection rebuilt from canonical snapshot.

### CONSTRUCT0.PLAY1 — Physical Toybox — CLOSED
- generic parts: BLOCK, PLATE, BEAM, CYLINDER, WHEEL, AXLE, WEIGHT, ANCHOR;
- generic relations: RIGID_BOND, HINGE, AXLE/REVOLUTE, SLIDER, SPRING_DAMPER, BREAKABLE_BOND;
- environment: FLOOR, adjustable RAMP, MOVING_SURFACE;
- interaction tools: FORCE, IMPULSE, TORQUE, ADD_LOAD, BREAK_BOND;
- tunable parameters: mass, dimensions, contact/rolling/torsional friction, bond strength, spring stiffness/damping;
- mandatory experiments: INCLINED_PLANE, SEESAW, CART, CATAPULT, BREAKABLE_BRIDGE;
- optional: PENDULUM, TOWER/DOMINO, SUSPENSION_CART, DOOR, PRESS/SLIDER;
- ideal lab sources/sensors are allowed, but no Motor/Gearbox/Battery device-specific physics classes;
- breakage mutates canonical Construction; local-unbake / split / re-bake remain C0.6 and are not claimed by PLAY1.

PLAY1 is the first explicitly playable constructor milestone.

Exact closure:

```text
branch:
feature/fabric-construct0-play1-physical-toybox-r1

HEAD:
a141e7a3ec51b2fda6ab1227c5153ab4e32a6d4d

TREE:
969ec5cac28c9ed5de29b17e366c587402e7b7eb

PLAY1:
111/111 PASS

full chain:
232/232 PASS

Project Control:
33444067612 SUCCESS

verdict:
VERIFIED
```

Mandatory playable experiments now exist:
- INCLINED_PLANE — B0.3-backed stick/slide ramp;
- SEESAW — generic HINGE rotational DAE;
- CART — generic AXLE/rolling-ratio translational DAE;
- CATAPULT — HINGE + SPRING_DAMPER + BREAKABLE hybrid release;
- BREAKABLE_BRIDGE — Construction structural load/failure with canonical bond break.

All five pass deterministic twin-run and reset-to-initial-hash checks.

### C0.4 — FULL ↔ BAKED physical representation — CLOSED

The lifecycle lab runs the exact 500-part BRIDGE-1 structural subject.

Verified:

```text
AUTO            → certified BAKED
FORCE FULL      → exact 500-part reconstruction
FORCE BAKED     → existing PhysicalBakeArtifact

canonical parts: 500
FULL DOF:        6500
BAKED DOF:         13
reduction:        500x
boundary mismatch <= 1e-9
```

Representation forcing does not mutate the canonical source frontier. The UI exposes artifact identity, build generation, guard margin, current physical complexity and reduction ratio.

Unsupported reduction remains explicit:

```text
NO_SAFE_BOUNDED_LOCAL_UNBAKE_LIMIT
→ NO_SAFE_BAKE
→ FAIL_CLOSED_OR_FULL
```

Acceptance: `26/26 PASS`.

### C0.5 — Mutation / invalidation / rebuild — CLOSED

Verified lifecycle:

```text
canonical property mutation
→ RepresentationInvalidation
→ BakeInvalidation
→ old artifact STALE
→ stale execution forbidden
→ exact 500-part reconstruction
→ DISCARD_AND_REDERIVE transient contact state
→ fresh graph/artifact
→ build_generation + 1
→ fresh execution gate PASS
```

An explicit FULL reconstruction fallback remains legal.

Acceptance: `23/23 PASS`.

### C0.6 — Local unbake / topology split — CLOSED

The lab directly executes the already closed B0.2-D and B0.2-E implementations.

B0.2-D bounded local unbake:

```text
500 canonical parts
20 locally FULL
480 retained reduced
2 retained components
2 cut interfaces
6500 → 286 DOF
>22.7x preserved reduction
4% unbaked
```

B0.2-E topology split / re-bake:

```text
bond break event APPLIED
2 split components
3 predecessor reduced pieces invalidated
2 fresh executable PhysicalBakeArtifacts
6500 → 286 → 26 DOF
250x post-split reduction
```

Mass, linear momentum, angular momentum and state/interface handoff remain within the frozen B0.2-D/E tolerances.

Acceptance: `44/44 PASS`.

### C0 closure — SATISFIED

Single entrypoint:

`res://scenes/labs/fabric_construct0_complete_lab.tscn`

Launcher:

`OPEN_FABRIC_CONSTRUCT0_COMPLETE_LAB.ps1`

It links the three verified tangible views:

```text
C0.1-C0.3
SEE / MOVE / BUILD
        ↓
PLAY1
PHYSICAL TOYBOX
        ↓
C0.4-C0.6
FULL / BAKE / REBUILD / SPLIT
```

End-to-end visible lifecycle:

```text
Construction
→ physical execution
→ FULL / BAKED comparison
→ canonical mutation
→ stale invalidation
→ reconstruction / rebuild
→ bounded local unbake
→ topology break
→ split
→ deterministic component re-bake
```

Godot remains presentation/interaction only.

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


## C0.1–C0.3 exact closure evidence

```text
exact subject:
837c46940acddbd841e7878dcfbfb68c0d5ac259

TREE:
8a554f9d7e45660aa6a4354c62742b4432633523

Godot:
4.7.1.stable.double.custom_build.a13da4feb

C0.1:
58/58 PASS

C0.2:
33/33 PASS

C0.3:
30/30 PASS

chained runner:
PASS / exit 0

Project Control:
SUCCESS

verdict:
VERIFIED
```

Known historical ECO scene parse diagnostics remain outside the CONSTRUCT0 claim and did not prevent import exit 0.


## C0.4–C0.6 / CONSTRUCT0 final exact closure evidence

```text
exact implementation/test HEAD:
afcd564b631a2f48283dfefef17f4d6542f558a3

TREE:
36064f8ad9f09e86cb242f4202f2e068044b6a2b

Godot:
4.7.1.stable.double.custom_build.a13da4feb

C0.1:
58/58 PASS

C0.2:
33/33 PASS

C0.3:
30/30 PASS

PLAY1:
111/111 PASS

C0.4:
26/26 PASS

C0.5:
23/23 PASS

C0.6:
44/44 PASS

TOTAL:
325/325 PASS

full chained runner:
PASS / exit 0

Project Control exact subject:
33507347220 SUCCESS

source carrier:
33507346997 SUCCESS

verdict:
VERIFIED
```

The exact implementation/test subject is frozen. All later closure changes are documentation/evidence only.

Final qualification:

```text
CONSTRUCT0
RESEARCH / TANGIBLE CHECKPOINT CLOSED
EXACT DOUBLE PASS
PROJECT CONTROL PASS
NOT PRODUCTION ACCEPTED
```
