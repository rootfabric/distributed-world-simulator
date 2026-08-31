# FABRIC CONSTRUCT0.PLAY1 — PHYSICAL TOYBOX — Exact Verification

## Qualification

```text
CONSTRUCT0.PLAY1
PHYSICAL TOYBOX
RESEARCH / TANGIBLE CHECKPOINT CLOSED
EXACT DOUBLE PASS
PROJECT CONTROL PASS
NOT PRODUCTION ACCEPTED
```

## Subject

```text
branch:
feature/fabric-construct0-play1-physical-toybox-r1

exact implementation/test HEAD:
a141e7a3ec51b2fda6ab1227c5153ab4e32a6d4d

TREE:
969ec5cac28c9ed5de29b17e366c587402e7b7eb

accepted predecessor:
306b0abf5f05c41bde7fb5937ca92be959b6873a
(CONSTRUCT0 C0.1-C0.3 closure/evidence)
```

Fresh verifier source was reconstructed from an exact Git bundle produced by the repository source-carrier workflow.

```text
bundle SHA-256:
fc9050af46f412f272b2f819c4b91d2276eb8aa0ccc7face30b6c24e35d5c164

source carrier:
run 33444067618
SUCCESS

artifact:
9777347055
```

## Godot identity

```text
4.7.1.stable.double.custom_build.a13da4feb

binary SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7

archive SHA-256:
d7a184b893d4e3ad4d4b6cb2e3a4fbb52997dfc87e4f00d2a7f24ac075903b92
```

Fresh detached verifier identity:

```text
HEAD:
a141e7a3ec51b2fda6ab1227c5153ab4e32a6d4d

TREE:
969ec5cac28c9ed5de29b17e366c587402e7b7eb

branch:
<detached-head>

tracked status:
clean
```

## Import

```text
Godot import:
PASS
exit 0

CONSTRUCT0 SCRIPT ERROR markers:
0

CONSTRUCT0 failed-script-load markers:
0
```

Known historical ECO scene parse diagnostics remain present and non-fatal. They are outside the PLAY1 claim.

## Acceptance

```text
C0.1 SEE THE MODEL:
58 / 58 PASS

C0.2 SEE FABRIC MOVE IT:
33 / 33 PASS

C0.3 BUILD IT:
30 / 30 PASS

CONSTRUCT0.PLAY1:
111 / 111 PASS

TOTAL CHAIN:
232 / 232 PASS

runner:
RUN_FABRIC_CONSTRUCT0_PLAY1_TESTS.sh

chain exit:
0
```

The PLAY1 runner is fail-closed on:
- non-zero Godot exit;
- `SCRIPT ERROR:`;
- `ERROR: Failed to load script`.

This was added after an early verifier pass exposed that Godot could return exit 0 after a script compile error. The false-positive path is therefore explicitly covered.

## Implemented generic vocabulary

Parts:

```text
BLOCK
PLATE
BEAM
CYLINDER
WHEEL
AXLE
WEIGHT
ANCHOR
```

Relations:

```text
RIGID
HINGE
AXLE
SLIDER
SPRING_DAMPER
BREAKABLE
```

Environment:

```text
FLOOR
RAMP
MOVING_SURFACE
```

Interaction tools:

```text
FORCE
IMPULSE
TORQUE
ADD_LOAD
BREAK_BOND
```

No device-specific `MotorPhysics`, `GearboxPhysics`, `CartPhysics`, `CatapultPhysics` or `WheelPhysics` classes were introduced.

## Mandatory toybox experiments

### INCLINED_PLANE

Canonical BLOCK + ANCHOR + generic SLIDER relation on an adjustable RAMP.

Runtime:
- real B0.3 contact/wrench bake compiles the ramp support patch;
- B0.3 supplies the accepted friction/support boundary;
- low tangential demand remains STICK;
- FORCE can exceed the B0.3 tangent capacity and enter SLIDE;
- motion is integrated by the generic FABRIC DAE runtime.

A verifier-found left-handed contact frame was corrected before closure; the accepted exact subject uses a right-handed `t1/t2/normal` frame.

### SEESAW

Canonical ANCHOR + BEAM + two WEIGHT parts.

Relations:
- HINGE;
- RIGID payload attachments.

Runtime:
- generic rotational FABRIC DAE;
- inertia;
- generalized torque;
- damping;
- hinge limits;
- TORQUE interaction tool.

### CART

Canonical PLATE frame + WEIGHT payload + four WHEEL parts.

Relations:
- four generic AXLE relations;
- RIGID payload attachment.

Runtime:
- translational FABRIC DAE;
- rolling-resistance term;
- kinematic wheel/axle ratio;
- FORCE;
- IMPULSE;
- ADD_LOAD.

No cart-specific solver exists.

### CATAPULT

Canonical ANCHOR + BEAM + WEIGHT payload.

Relations:
- HINGE;
- SPRING_DAMPER;
- BREAKABLE payload latch.

Runtime:
- generic hybrid FABRIC DAE;
- spring/damper generalized torque;
- localized release guard;
- latched → released mode;
- ballistic payload state;
- release mutates the canonical BREAKABLE bond to BROKEN.

No catapult-specific physics class exists.

### BREAKABLE_BRIDGE

Canonical supports + BEAM deck + WEIGHT load.

Relations:
- BREAKABLE structural bonds;
- RIGID load attachment.

Runtime:
- existing Construction structural load-case/compiler;
- ADD_LOAD;
- bond utilization;
- canonical overload break;
- Construction revision/checksum mutation;
- failure event.

Local unbake / topology split / deterministic re-bake remain C0.6 responsibilities; PLAY1 proves the canonical failure boundary, not the later bake reconstruction lifecycle.

## Determinism

All five mandatory experiments are covered by deterministic reference sequences.

For each experiment:
- two independent runtimes start from the same canonical snapshot;
- the same tools/fixed steps are applied;
- resulting state hashes must be identical;
- RESET must return the original state hash.

This gate passed for all five experiments.

## Godot lab

Scene:

```text
res://scenes/labs/fabric_construct0_play1_lab.tscn
```

Launcher:

```text
OPEN_FABRIC_CONSTRUCT0_PLAY1_LAB.ps1
```

The lab exposes:
- all five experiments;
- PLAY / PAUSE / STEP / RESET;
- FORCE / IMPULSE / TORQUE / ADD_LOAD / BREAK_BOND;
- adjustable ramp cycling;
- canonical revision/checksum;
- FABRIC state hash;
- runtime metrics;
- failure/release events.

Godot remains presentation/interaction. It is not canonical physical truth.

## Project Control

Exact subject:

```text
run:
33444067612

conclusion:
SUCCESS
```

## Verdict

```text
VERIFIED
```

PLAY1 is CLOSED as a research/tangible checkpoint.

## Next

```text
CONSTRUCT0.PLAY1 ✅ CLOSED
        ↓
C0.4 FULL ↔ BAKED PHYSICAL REPRESENTATION
```

C0.4 must make representation choice executable and observable:
- AUTO;
- FORCE FULL;
- FORCE BAKED where certified;
- explicit NO_SAFE_BAKE;
- boundary-observable comparison;
- current physical complexity/reduction ratio.
