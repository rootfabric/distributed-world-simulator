# FABRIC-BAKE B0.4 DYNAMIC ROM — Final Exact Closure

## Qualification

```text
B0.4 DYNAMIC STATE REDUCTION / ROM

CLOSED
EXACT DOUBLE PASS
FULL CLOSURE REGRESSION PASS
PROJECT CONTROL PASS
NOT PRODUCTION ACCEPTED
```

## Exact implementation/test boundary

```text
branch:
research/fabric-bake0-4-dynamic-rom-r1

exact implementation/test HEAD:
e33ac10ac94d8b70f1387d442a3ae9d3801bb08a

TREE:
f3d47eedd42f827a859d1763e8b46762696b99dd

predecessor:
FABRIC.SYNC2 closure
be419fb695221917df0f6026ed335e1355f72840
```

Fresh exact source was reconstructed from the D exact source carrier:

```text
run:
33696130137
SUCCESS

artifact:
9871826260

bundle SHA-256:
830b4b36911d3028fe59473ccdf50fed6d6e0dd91384cfeb43c82fa321ad0427

detached:
true

tracked status:
clean
```

## Godot identity

```text
4.7.1.stable.double.custom_build.a13da4feb

binary SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7

archive SHA-256:
d7a184b893d4e3ad4d4b6cb2e3a4fbb52997dfc87e4f00d2a7f24ac075903b92
```

The final parent regression was executed with the project-attached canonical double
Godot on the exact detached source above.

## B0.4-A — Dynamic Model / Port Contract

```text
609 / 609 PASS
```

Frozen FULL reference:

```text
dynamic states:
512

physical effort/flow ports:
4

reference form:
C x_dot + K x = B u
```

The FULL reference remains stable/passive, source-bound, deterministic and
presentation-order invariant.

## B0.4-B — Certified Reduction

```text
83 / 83 PASS

FULL:
512 states

ROM:
24 states

reduction:
21.3333333333x

method:
PASSIVE_RATIONAL_BLOCK_KRYLOV_R1

passivity:
certified
```

Rational interpolation evidence remains near machine precision.

Frozen transient validation remains far inside the parent target:

```text
worst relative FULL-vs-ROM boundary error:
~3.18e-8

parent target:
<= 1e-3
```

## B0.4-C — Runtime Error / Refinement

```text
1533 / 1533 PASS

actual maximum boundary error:
7.654765343811931e-08

conservative residual-bound maximum:
3.8656587223579337e-04

maximum residual dual C-norm:
5.312836647159003e-04
```

The conservative estimator remains above measured error and inside the frozen
accepted error class for the deterministic in-domain validation suite.

C provides:

- ValidatedDomain;
- ErrorEnvelope;
- ConservationEnvelope;
- RuntimeErrorEstimator;
- residual-based runtime certification;
- error / flow / horizon RefinementGuard;
- REFINE/FULL failover before certified-domain exit;
- FULL / NO_SAFE_BAKE outside certified domain.

## B0.4-D — Reconstruction / StateMapping / PhysicalBakeArtifact lifecycle

```text
287 / 287 PASS
```

The final D implementation is not a private ROM artifact path.

It materializes the common FABRIC-BAKE architecture:

```text
PhysicalBakeArtifact
├── exact PhysicalSourceBinding
├── PhysicalBoundaryContract
├── reduction_class = APPROXIMATE
├── B0.4-B ROM descriptor hash
├── reduced state schema hash
├── B0.4-C ValidatedDomain
├── B0.4-C ErrorEnvelope
├── B0.4-C ConservationEnvelope
├── B0.4-C RefinementGuard[]
├── ReconstructionDescriptor
├── StateMapping
└── build_generation
```

Projection/reconstruction is bound by one deterministic mapping contract:

```text
FULL x
  ↓ q = V^T C x
ROM q
  ↓ x_hat = V q
FULL reconstruction
```

The same mapping identity is referenced by StateMapping and
ReconstructionDescriptor.

Verified lifecycle:

```text
fresh artifact
→ common BakeExecutionGate
→ governed ROM execution
→ canonical source mutation
→ BakeInvalidation(SOURCE_REVISION)
→ STALE_PHYSICAL_BAKE_EXECUTION_FORBIDDEN
→ deterministic generation rebuild
→ fresh PhysicalBakeArtifact
```

Rebuild preserves the exact mapping/reconstruction contract where the physical
model/basis is unchanged while producing fresh artifact generation identity.

## Full parent regression

Canonical runner:

```text
RUN_FABRIC_BAKE_B0_4_D_CLOSURE_TESTS.sh
```

Final result on the exact implementation/test HEAD:

```text
B0.3 predecessor chain:
PASS

B0.4-A:
609/609 PASS

B0.4-B:
83/83 PASS

B0.4-C:
1533/1533 PASS

B0.4-D:
287/287 PASS

FABRIC-BAKE B0.4-D closure chain:
PASS

process exit:
0

fatal script/load markers:
0
```

The predecessor chain also re-ran and preserved B0.0/B0.1/B0.2/BRIDGE-1/B0.3
acceptance.

## Control evidence

Exact code subject:

```text
Project Control:
33696130121
SUCCESS

B0.4-C Portable Godot Smoke:
33696130128
SUCCESS

B0.4-D Portable Godot Smoke:
33696130098
SUCCESS

B0.4-A Exact Source Carrier:
33696130141
SUCCESS

B0.4-B Exact Source Carrier:
33696130149
SUCCESS

B0.4-C Exact Source Carrier:
33696130113
SUCCESS

B0.4-D Exact Source Carrier:
33696130137
SUCCESS
```

## Closure gate

All B0.4 R1 closure requirements are now satisfied:

- >=512 FULL dynamic states — PASS;
- <=24 reduced states — PASS;
- >=20x reduction — PASS;
- boundary port contract preserved — PASS;
- boundary error <=1e-3 in frozen suite — PASS;
- measured error inside certified envelope — PASS;
- passive fixture creates no unaccounted energy — PASS;
- runtime estimator and refinement guards — PASS;
- FULL / NO_SAFE_BAKE outside domain — PASS;
- deterministic projection/reconstruction — PASS;
- common PhysicalBakeArtifact lifecycle — PASS;
- stale artifact execution fail-closed — PASS;
- deterministic rebuild — PASS;
- exact double Godot acceptance — PASS;
- fresh exact source carrier — PASS;
- Project Control — PASS;
- full parent closure regression exit 0 — PASS.

## Verdict

```text
B0.4-A ✅ CLOSED
B0.4-B ✅ CLOSED
B0.4-C ✅ CLOSED
B0.4-D ✅ CLOSED

B0.4 DYNAMIC ROM
✅ CLOSED

NOT PRODUCTION ACCEPTED
```

## Next

The next architecture checkpoint is:

```text
FABRIC.SYNC3
post-B0.4 + B0.5-P0 synchronization
```

It must decide:

- executable B0.5 Hybrid Bake authorization;
- FABRIC0.19 necessity;
- BRIDGE-2 executable authorization.
