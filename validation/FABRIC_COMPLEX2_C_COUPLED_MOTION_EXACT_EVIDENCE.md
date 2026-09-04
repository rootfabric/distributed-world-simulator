# FABRIC COMPLEX2-C — Articulated + Rotating Coupled Motion — EXACT EVIDENCE

Status: **EXACT VERIFIED**

## Exact executable subject

```text
HEAD bfc9109a240b513dd6866da04bcad3fd8de4b275
TREE 1a676742b30179967ab7fe5ad4084a3b5cb42b75
```

The C change is additive on top of the exact-verified COMPLEX2 A+B branch state. The executable C commit adds only:

```text
scripts/research/fabric_bake0/complex2_coupled_motion_v1.gd
scripts/research/fabric_bake0/complex2c_modular_machine_extension_v1.gd
tests/research/fabric_bake0/fabric_bake_complex2c_coupled_motion_acceptance.gd
scripts/labs/fabric/complex2c_coupled_motion_lab.gd
scenes/labs/fabric/complex2c_coupled_motion_lab.tscn
RUN_FABRIC_COMPLEX2C_TESTS.sh
.github/workflows/fabric-complex2c-linux-double.yml
```

COMPLEX2-A and COMPLEX2-B implementation files were not rewritten.

## Exact source carrier

```text
workflow run 33874127393
artifact 9937128133
artifact name fabric-bridge2-exact-source
artifact digest sha256:67e6628006af8e35172fd4e95ba81ee955bd67c31e87edc8b24ab80108eff726
```

The downloaded artifact ZIP had the same SHA-256:

```text
67e6628006af8e35172fd4e95ba81ee955bd67c31e87edc8b24ab80108eff726
```

Bundle ref:

```text
bfc9109a240b513dd6866da04bcad3fd8de4b275 refs/heads/fabric-bridge2-exact
```

The checkout reconstructed from the bundle reported exactly:

```text
HEAD=bfc9109a240b513dd6866da04bcad3fd8de4b275
TREE=1a676742b30179967ab7fe5ad4084a3b5cb42b75
```

## Canonical Godot

```text
4.7.1.stable.double.custom_build.a13da4feb
SHA256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

## Physical subject

COMPLEX2-C binds the existing moving machine modules:

```text
module/complex2-08 shoulder   ARTICULATED
module/complex2-09 elbow      ARTICULATED
module/complex2-10 shaft      ROTATING
module/complex2-11 carriage   TRANSLATING
```

They form four generalized path coordinates and four velocities: 8 physical states total.

The canonical coupling graph is reciprocal and passive:

```text
shoulder <-> elbow
elbow    <-> shaft
shaft    <-> carriage
shoulder <-> carriage  (frame closure)
```

The compiled DYNAMIC_ROM evaluator uses dense M/K/C matrices compiled from those canonical links. The FULL reference rebuilds M/K/C from the canonical coupling records every step.

Time integration uses implicit midpoint. For each step the discrete energy relation is checked:

```text
E1 - E0 = boundary_work - damping_dissipation
```

## Exact acceptance result

Two independent invocations, each from a fresh checkout of the same exact bundle, produced:

```text
COMPLEX2-C metrics active_full_delta=0
energy_residual=5.273559366969494e-16
shaft_transfer=0.046778567
carriage_transfer=0.046414915
final_energy=0.005697127

COMPLEX2C_EXPERIMENT_HASH=433345db30f8b59e5da67d83cc3a737f546305563029f0f38ca583988e96a995

FABRIC COMPLEX2-C Coupled Motion Acceptance:
PASS (66 assertions)
dof=4
state=8
reciprocal=PASS
energy=PASS
swaps=2
mixed=FULL_REFERENCE
scene=PASS
```

Both independent invocations produced the exact same integrated experiment hash:

```text
433345db30f8b59e5da67d83cc3a737f546305563029f0f38ca583988e96a995
```

## Coupled-motion evidence

Observed certified peaks:

```text
shoulder  0.2304349697 rad
elbow     0.2198972800 rad
shaft     0.7201419706 rad
carriage  0.0696275307 m
```

A shoulder-only causal probe produced:

```text
coupled shaft peak     0.0467785669 m path coordinate
coupled carriage peak  0.0464149146 m
```

The same probe with all inter-DOF couplings removed produced exactly:

```text
decoupled shaft peak    0
decoupled carriage peak 0
```

Therefore downstream shaft/carriage motion is caused by the reciprocal coupling graph, not by direct hardcoded forcing.

## Mid-motion representation switching

The physical evaluator switches while non-zero energy and velocity are present:

```text
step 150: COMPILED_DYNAMIC_ROM -> FULL_CANONICAL_SUM
step 230: FULL_CANONICAL_SUM   -> COMPILED_DYNAMIC_ROM
```

The explicit q/v state packet roundtrip is exact:

```text
handoff errors [0, 0]
```

At the BRIDGE-2 layer the DYNAMIC/FULL representation pair is swapped twice as well. Results:

```text
representation events committed = 2
max state handoff error = 0
max mixed/FULL runtime delta = 0
final five-kind representation set restored
```

The COMPLEX2-B HYBRID compliant backend hash is unchanged across both C swaps.

## Energy/passivity evidence

```text
max energy balance residual <= 5.273559366969494e-16 J
minimum damping dissipation >= 0
measurable total dissipation > 1 J
release energy monotonic = true
final ringdown energy < 2% of peak energy
```

## Fail-closed boundaries

Exact acceptance requires:

```text
nonreciprocal coupling
-> COMPLEX2C_NONRECIPROCAL_COUPLING

over-force
-> COMPLEX2C_REFINEMENT_REQUIRED_FORCE

out-of-certified articulation range
-> COMPLEX2C_REFINEMENT_REQUIRED_NATIVE_RANGE

out-of-certified path speed
-> COMPLEX2C_REFINEMENT_REQUIRED_SPEED

corrupt representation state packet
-> COMPLEX2C_STATE_PACKET_CHECKSUM_MISMATCH
```

These cases require refinement/failure rather than silently executing an invalid reduced model.

## Visual evidence surface

```text
res://scenes/labs/fabric/complex2c_coupled_motion_lab.tscn
```

The scene exposes the sampled evidence states and lets the observer step through them with Space. It is read-only with respect to canonical simulation ownership.

## CI state at exact validation time

Project Control on the exact executable subject:

```text
run 33874127426
SUCCESS
```

Dedicated self-hosted workflow:

```text
FABRIC COMPLEX2-C Coupled Motion Linux Double
run 33874127456
```

was queued at the time the independent attached-Godot exact evidence was recorded. It is not substituted for or falsely reported as completed.

## Architectural result

COMPLEX2-C does not require a new generic FABRIC primitive. Coupled articulated/rotating/translating motion, reciprocal force transfer, energy accounting and mid-motion representation changes are expressible with existing representation ownership plus a nested DYNAMIC backend.

Therefore:

```text
COMPLEX2-C ✅ EXACT VERIFIED
FABRIC0.19 NOT AUTHORIZED
next: COMPLEX2-D — Independent Structural Support Failure
```
