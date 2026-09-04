# FABRIC COMPLEX2-B — Compliant / Spring Response Envelope — Exact Evidence

**Verdict:** PASS / EXACT VERIFIED  
**Date:** 2026-09-04  
**Verification class:** `LOCAL_ATTACHED_CANONICAL_DOUBLE_GODOT + EXACT_SOURCE_CARRIER`  
**Branch:** `feature/fabric-complex2-modular-machine-r1`

## Exact subjects

Physical implementation subject:

```text
b1f4338b273f0889486553b18bea93d39127bba6
TREE 697a226e0eadc76803d5e70d10549931a5f8cfc6
```

Final verification / runner subject:

```text
57204de250cd05af76dbff4a42827a983d056ebb
TREE 475d8d66a89b677da4ec131cc9595844bab244b8
```

Git compare `b1f4338b... -> 57204de...` changes only:

```text
RUN_FABRIC_COMPLEX2B_TESTS.sh
tests/research/fabric_bake0/fabric_bake_complex2b_compliant_response_acceptance.gd
```

No physical runtime/model file changed after the physical implementation subject.

## Exact source carrier

```text
workflow run: 33872262806
artifact id: 9936379859
artifact name: fabric-bridge2-exact-source
artifact digest: sha256:3b515157e04891d1dfa552cda057ef0a5efead1ed9c52ae0f58cfdbdf8bac09c
bundle SHA-256: e0d90da58bda719b7e8fb5e474a0bb4ef19776a3ec8625e2d3a5ae5280311029
bundle ref: 57204de250cd05af76dbff4a42827a983d056ebb
```

Recovered checkout identity:

```text
HEAD=57204de250cd05af76dbff4a42827a983d056ebb
TREE=475d8d66a89b677da4ec131cc9595844bab244b8
```

## Canonical attached Godot

Archive:

```text
godot-4.7.1-linux-double-x86_64-a13da4f.tar(1).gz
```

Resolved binary:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

SHA-256:

```text
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

## Exact acceptance result

Runner:

```text
./RUN_FABRIC_COMPLEX2B_TESTS.sh
```

Result:

```text
FABRIC COMPLEX2-B Compliant Response Acceptance: PASS (65 assertions)
full=80
reduced=1
Kelvin-Voigt energy=PASS
guards=PASS
scene=PASS
extended=FULL_REFERENCE
```

Measured envelope:

```text
K = 720.000000 N/m
C = 116.000000 N*s/m
peak |q| = 0.095426442 m
final |q| = 0.004284087 m
max FULL/HYBRID delta = 4.996003610813204e-16
max energy residual = 0
```

Integrated experiment hash:

```text
af5779bddc65a504c9ec14612b3dc62341032e4ed770a885c2df679dcbcd6795
```

## Independent deterministic replay

The final exact bundle was invoked a second time from a fresh clone with separate HOME/XDG/project state.

Second result:

```text
FABRIC COMPLEX2-B Compliant Response Acceptance: PASS (65 assertions)
COMPLEX2B_EXPERIMENT_HASH=af5779bddc65a504c9ec14612b3dc62341032e4ed770a885c2df679dcbcd6795
```

Therefore:

```text
integrated replay #1 == integrated replay #2
```

The CI runner intentionally uses one Godot invocation. In this container, repeated Godot launches from one parent shell can become runtime-stuck despite isolated project/XDG directories. Deterministic replay evidence is therefore produced as independent exact invocations rather than weakening or bypassing the physics acceptance.

## Accepted physical properties

### Canonical / reduced structure

```text
module/complex2-20
80 canonical compliant part states
80 canonical spring/damper fibers
      ↓ coherent projection
1 reduced HYBRID compliance state q
```

The existing BRIDGE-2 ownership set remains exactly five regions:

```text
FULL
STRUCTURAL_BAKE
CONTACT_BAKE
DYNAMIC_ROM
HYBRID_BAKE
```

No sixth physical owner is introduced.

### Constitutive envelope

The compliant section uses a coherent Kelvin-Voigt response:

```text
F = K q + C q_dot
```

FULL reference explicitly sums all 80 canonical fibers. Reduced execution uses compiled aggregate `K/C` values.

Required equality:

```text
max |q_FULL - q_HYBRID| <= 1e-12
```

Observed:

```text
4.996003610813204e-16
```

### Projection / reconstruction

Acceptance verifies:

```text
FULL(80) -> reduced(1) -> FULL(80)
```

with:

```text
projection continuity <= 1e-12
reconstruction error <= 1e-12
handoff roundtrip error <= 1e-12
```

The HYBRID adapter owns a valid common `PhysicalBakeArtifact`; its backend identity changes by nesting the compliant backend under the existing COMPLEX2-A HYBRID backend identity rather than replacing BRIDGE-2 ownership semantics.

### Energy / damping

Acceptance verifies:

```text
max energy balance residual <= 1e-10
dissipated energy never negative after tolerance
stored energy decreases monotonically after release
positive total dissipated energy
```

Observed max energy residual:

```text
0
```

### Refinement guards

The reduced compliance fails closed instead of hiding states outside its certified coherent envelope:

```text
COMPLEX2B_REFINEMENT_REQUIRED_FORCE
COMPLEX2B_REFINEMENT_REQUIRED_DEFLECTION
COMPLEX2B_COHERENT_MODE_VIOLATION
```

### Parent-machine integration

Acceptance also verifies:

```text
extended HYBRID registry validates
extended mixed step == FULL reference
COMPLEX2-A parent mixed/FULL bound remains <= 1e-12
COMPLEX2-A representation swap handoff remains 0
parent machine remains 2000 canonical parts
```

## Visual evidence

Scene:

```text
res://scenes/labs/fabric/complex2b_compliant_response_lab.tscn
```

The exact acceptance loads and instantiates the scene in the same Godot process and verifies its exact scene identity.

Visual stages expose the compliant envelope without becoming canonical truth:

```text
BASELINE
LOAD_80
RELEASE
REFINEMENT_GUARD
```

## Project control / external runner

Project Control on final verification subject `57204de...`:

```text
SUCCESS
run 33872262556
```

Dedicated self-hosted workflow:

```text
FABRIC COMPLEX2-B Compliant Response Linux Double
run 33872262687
```

At evidence authoring time this external self-hosted run remains queued. It is not used as a substitute for the attached canonical-double exact PASS above.

## Conclusion

`COMPLEX2-B — Compliant / Spring Response Envelope` is **EXACT VERIFIED**.

This checkpoint does not close all of COMPLEX2. The next planned checkpoint is:

```text
COMPLEX2-C — Articulated + Rotating Coupled Motion
```
