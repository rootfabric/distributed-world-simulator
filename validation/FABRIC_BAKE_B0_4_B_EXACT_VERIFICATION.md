# FABRIC-BAKE B0.4-B — Certified Reduction — Exact Verification

## Qualification

```text
B0.4-B CERTIFIED REDUCTION
RESEARCH CHECKPOINT CLOSED
EXACT DOUBLE PASS
PROJECT CONTROL PASS
NOT PRODUCTION ACCEPTED

B0.4 parent:
IN PROGRESS
```

## Exact subject

```text
branch:
research/fabric-bake0-4-dynamic-rom-r1

predecessor B0.4-A exact:
1fbfffe30f5758a1bbb3c65db23edf06ecf3dae4

exact B0.4-B implementation/test HEAD:
01f4508c1bf58c9204e775105aa802c0f2d5d464

TREE:
b89bb59f6ba0d52e907b0e6dbbaeb3a570a1f7ce
```

## Source carrier

```text
run:
33523690276
SUCCESS

artifact:
9806745446

bundle SHA-256:
08b48514924f8880c6425ad143518c02505f98ef7241691dad1e7dfb762d34ac
```

Fresh detached verifier:
- exact HEAD/TREE;
- tracked clean;
- canonical Linux double Godot.

Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb

binary SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Import:

```text
PASS / exit 0

B0.4 dynamic script/load fatal markers:
0
```

Known historical ECO scene parse diagnostics remain unrelated and non-fatal.

## Reduction

Frozen B0.4-A model:

```text
FULL dynamic states:
512

boundary ports:
4
```

B0.4-B:

```text
method:
PASSIVE_RATIONAL_BLOCK_KRYLOV_R1

Laplace shifts:
0
0.2
1
5
20
100

block vectors:
6 shifts × 4 ports = 24

reduced states:
24

reduction:
512 / 24 = 21.3333333333x
```

The basis is C-inner-product orthonormalized with deterministic repeated
Gram-Schmidt. The reduced operators are congruence projections:

```text
M_r = V^T C V
K_r = V^T K V
B_r = V^T B
C_r = boundary observation × V
```

## Passivity certificate

The accepted FULL model has positive storage and strictly positive dissipative
operator.

B0.4-B verifies:

- C-orthonormality;
- reduced mass symmetry;
- reduced dissipation symmetry;
- reduced mass SPD by Cholesky;
- reduced dissipation SPD by Cholesky;
- deterministic certificate hash.

Therefore the reduced validation dynamics preserve the passive quadratic
storage/dissipation form constructively.

## Rational interpolation certificate

All frozen shift/port combinations are checked against FULL:

```text
6 shifts × 4 input ports
= 24 probes
```

Playground exact result:

```text
interpolation max absolute error:
3.552713678800501e-15

interpolation max relative error:
6.813773388864296e-16
```

## Deterministic transient validation

Focused acceptance:

```text
83 / 83 PASS
```

Validation inputs include:

- step;
- impulse;
- multi-port constant excitation;
- chirp;
- deterministic broadband excitation;
- drive followed by zero-input passive decay;
- deterministic twin run.

Observed suite:

```text
worst relative FULL-vs-ROM boundary error:
3.179175431645086e-08

worst absolute FULL-vs-ROM boundary error:
3.57076923584998e-09

frozen B0.4 target:
<= 1e-3
```

The ROM validation runtime also verifies no positive unaccounted energy creation.

Playground:

```text
PASS

descriptor:
0157071e016bfec885692e53f5d6f126658b44e243db3b8ebc7ce55652d48354

FULL:
512

REDUCED:
24

ratio:
21.333333x

passivity:
true

400-step maximum absolute boundary error:
5.4302622176649606e-08
```

## Explicit execution boundary

B0.4-B emits a derived Dynamic ROM descriptor and artifact pre-binding, but not yet
an executable PhysicalBakeArtifact.

The binding is deliberately:

```text
execution_ready = false
```

and lists the missing closure requirements:

```text
VALIDATED_DOMAIN
ERROR_ENVELOPE
RUNTIME_ERROR_ESTIMATOR
REFINEMENT_GUARD
RECONSTRUCTION_DESCRIPTOR
STATE_MAPPING
```

Attempts to set `execution_ready=true` at B are rejected fail-closed.

This prevents B0.4-B from bypassing B0.4-C/D.

## Project Control

Exact subject:

```text
run:
33523690182

conclusion:
SUCCESS
```

## Verdict

```text
B0.4-A ✅ CLOSED
B0.4-B ✅ CLOSED

B0.4-C ★ NEXT
B0.4-D ⚪

B0.4 parent:
IN PROGRESS
```
