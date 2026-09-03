# FABRIC-BAKE B0.4-B — Certified Reduction

## Статус

```text
FABRIC-BAKE B0.4-B
CERTIFIED REDUCTION
RESEARCH CHECKPOINT CLOSED
EXACT-HEAD DOUBLE-GODOT PASS
PROJECT CONTROL PASS
NOT PRODUCTION ACCEPTED
```

Parent checkpoint:

```text
B0.4 DYNAMIC ROM
IN PROGRESS
NEXT = B0.4-C RUNTIME ERROR / REFINEMENT
```

## 1. Exact executable boundary

```text
branch:
research/fabric-bake0-4-dynamic-rom-r1

B0.4-A closure/evidence predecessor:
facce71d3ddb04f08493bb3c0e7612274b6005dd

exact B0.4-B executable HEAD:
01f4508c1bf58c9204e775105aa802c0f2d5d464

TREE:
b89bb59f6ba0d52e907b0e6dbbaeb3a570a1f7ce
```

B0.4-A exact FULL reference remains:

```text
512 dynamic states
4 physical effort/flow boundary ports
strict passive/stable FULL reference
```

## 2. What B0.4-B closes

B0.4-B performs the first real dynamic model-order reduction in FABRIC-BAKE.

```text
FULL dynamic model
512 states
        │
        ▼
passive rational block-Krylov projection
        │
        ▼
ROM
24 states
        │
        ▼
21.333333x state-count reduction
```

B0.4-B proves:

- deterministic reduced basis generation;
- <=24 reduced states;
- >=20x state-count reduction;
- passivity-preserving congruence projection;
- positive-definite reduced storage and dissipation operators;
- exact source / boundary / FULL-model provenance binding;
- deterministic ROM descriptor identity;
- deterministic artifact-interface binding;
- rational transfer interpolation at frozen certification points;
- strong deterministic FULL-vs-ROM observed response on the B0.4-B validation suite;
- validation-only reduced execution with explicit energy accounting.

It does **not** claim the final B0.4 runtime ErrorEnvelope.

That belongs to B0.4-C.

## 3. Reduction method

Frozen method:

```text
PASSIVE_RATIONAL_BLOCK_KRYLOV_R1
```

For the FULL system

```text
C x_dot + K x = B u
y = E x
```

B0.4-B builds the projection basis from shifted boundary response vectors:

```text
(K + s C)^-1 B
```

at the frozen non-negative Laplace shifts:

```text
s =
0
0.2
1
5
20
100
```

There are four boundary directions.

Therefore:

```text
6 shifts × 4 ports = 24 basis candidates
```

The candidates are deterministically twice re-orthogonalized in the physical
`C` inner product.

Accepted result:

```text
basis rank = 24
```

No randomized SVD, random seed or device-specific fitting is used.

## 4. Passive congruence projection

The ROM operators are:

```text
C_r = V^T C V
K_r = V^T K V
B_r = V^T B
E_r = E V
```

Because B0.4-A's accepted FULL model has positive storage and strictly dissipative
passive dynamics, and B0.4-B applies a real full-rank congruence projection, the
reduced storage/dissipation structure remains passive.

Executable certificate:

```text
certificate:
CONGRUENCE_PASSIVITY_SPD_R1

C-orthonormality error:
1.33226762955019e-15

reduced mass symmetry error:
0

reduced dissipation symmetry error:
0

reduced mass minimum Cholesky pivot:
0.999999999999999

reduced dissipation minimum Cholesky pivot:
0.2422095574285

certified:
true
```

Passivity certificate hash:

```text
c0fe9283570e1c49bee3e7d7790d2adb0d0a51fd113b77fa1eca1febf1c563a9
```

A reduced model that loses positive definiteness fails closed.

## 5. Rational interpolation certificate

The basis contains the exact FULL shifted response space used at the six frozen
Laplace shifts.

The compiler therefore verifies every shift × input-port boundary transfer probe.

```text
certificate:
RATIONAL_INTERPOLATION_R1

shifts:
[0, 0.2, 1, 5, 20, 100]

ports:
4

probe count:
24

certified tolerance:
1e-8

max absolute boundary interpolation error:
3.552713678800501e-15

max relative boundary interpolation error:
6.813773388864296e-16

certified:
true
```

Certificate hash:

```text
7c6d927355ce4d30c8dd76ea14957eafe2b2cb90946f92477dcbdc5e4ded7ede
```

This certificate is exact and deterministic **only for the frozen interpolation
conditions**.

It is not a substitute for B0.4-C's runtime ValidatedDomain / ErrorEnvelope.

## 6. Reduced descriptor identity

New executable contract:

`scripts/research/fabric_bake0/dynamic_rom_descriptor_v1.gd`

Frozen exact identities:

```text
ROM descriptor:
0157071e016bfec885692e53f5d6f126658b44e243db3b8ebc7ce55652d48354

basis:
29899b4d42f0cc7e4b89a49af4c82443aff725e37c12d404d64c6da46aca826d

reduced state schema:
442352325c2275386c28530d4a844ef98555ef57776bf195169630b4e2e0ccad
```

Descriptor binds:

- exact B0.4-A FULL model hash;
- exact source binding checksum;
- exact PhysicalBoundaryContract hash;
- exact FULL state schema;
- basis;
- reduced operators;
- port identities and orientation signs;
- reduction ratio;
- passivity certificate;
- rational interpolation certificate.

Presentation ordering cannot change descriptor identity.

## 7. PhysicalBakeArtifact interface binding

B0.4-B deliberately does not manufacture a runtime-ready PhysicalBakeArtifact.

New binding contract:

`dynamic_rom_artifact_binding_v1.gd`

Frozen identity:

```text
binding hash:
aa0e23f4567544e8cb71ca9a500fa9d9e1efadee5a9beadea370aa179eecbccc

reduction_class:
APPROXIMATE

execution_ready:
false
```

The binding freezes the fields that later enter the common artifact:

```text
source_binding_checksum
boundary_contract_hash
reduced_model_descriptor_hash
reduced_state_schema_hash
```

It also freezes mandatory missing gates:

```text
VALIDATED_DOMAIN
ERROR_ENVELOPE
RUNTIME_ERROR_ESTIMATOR
REFINEMENT_GUARD
RECONSTRUCTION_DESCRIPTOR
STATE_MAPPING
```

Attempting to flip `execution_ready=true` during B0.4-B is rejected.

This is intentional.

A good reduced trajectory is not enough to authorize physical execution.

## 8. Validation-only ROM runtime

New runtime:

`dynamic_rom_runtime_v1.gd`

Scope:

```text
VALIDATION_ONLY_B0_4_B
```

It solves:

```text
(C_r / dt + K_r) z[n+1]
=
(C_r / dt) z[n]
+
B_r u[n+1]
```

and exposes reduced boundary effort through:

```text
y_r = E_r z
```

Energy accounting mirrors B0.4-A:

```text
stored reduced energy
+
physical reduced dissipation
+
backward-Euler numerical dissipation
-
boundary energy input
≈ 0
```

The runtime is used for validation only and is not wired to the common
PhysicalBakeArtifact execution gate.

## 9. Deterministic response validation

B0.4-B additionally compares the frozen FULL model and 24-state ROM from zero state
under deterministic time-domain inputs:

- step;
- impulse;
- multi-port step;
- chirp;
- deterministic broadband input.

Frozen B0.4-B acceptance limit:

```text
observed relative boundary response <= 1e-3
observed absolute boundary response <= 1e-3
```

Actual exact-head result:

```text
worst relative L2 boundary response error:
3.179175431645086e-08

worst absolute boundary response error:
3.57076923584998e-09
```

Playground 400-step single-port step:

```text
max absolute boundary error:
5.4302622176649606e-08
```

These are strong observed validation results, but B0.4-B does not re-label them as a
general runtime error certificate.

## 10. Fail-closed boundary

B0.4-B rejects:

```text
target != 24 states
→ NO_SAFE_BAKE

unfrozen shift set
→ NO_SAFE_BAKE

FULL predecessor invalid
→ NO_SAFE_BAKE

basis rank < 24
→ NO_SAFE_BAKE

state-count reduction < 20x
→ NO_SAFE_BAKE

reduced mass/dissipation not SPD
→ NO_SAFE_BAKE

C-orthonormality outside frozen tolerance
→ NO_SAFE_BAKE

rational interpolation error > certified tolerance
→ NO_SAFE_BAKE

artifact execution_ready = true
→ reject
```

No fallback creates an uncertified approximate executable.

## 11. Exact verification

Pinned Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb

binary SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Exact source carrier:

```text
workflow run:
33523690276

conclusion:
SUCCESS

artifact:
9806745446

bundle SHA-256:
08b48514924f8880c6425ad143518c02505f98ef7241691dad1e7dfb762d34ac
```

Fresh exact filesystem pass #1:

```text
HEAD:
01f4508c1bf58c9204e775105aa802c0f2d5d464

TREE:
b89bb59f6ba0d52e907b0e6dbbaeb3a570a1f7ce

tracked:
clean

import:
PASS / exit 0

B0.4-B acceptance:
83/83 PASS

B0.4-B playground:
PASS
```

Fresh exact filesystem pass #2 from the same exact source bundle:

```text
HEAD:
01f4508c1bf58c9204e775105aa802c0f2d5d464

TREE:
b89bb59f6ba0d52e907b0e6dbbaeb3a570a1f7ce

tracked:
clean

import:
PASS / exit 0

B0.4-B acceptance:
83/83 PASS

B0.4-B playground:
PASS
```

Both passes produce the same:

```text
descriptor:
0157071e016bfec885692e53f5d6f126658b44e243db3b8ebc7ce55652d48354

basis:
29899b4d42f0cc7e4b89a49af4c82443aff725e37c12d404d64c6da46aca826d

binding:
aa0e23f4567544e8cb71ca9a500fa9d9e1efadee5a9beadea370aa179eecbccc
```

## 12. Exact-head predecessor regression

Same exact B0.4-B subject:

```text
B0.0       33/33 PASS
B0.1       64/64 PASS
B0.2-A/B   76/76 PASS
B0.2-C    118/118 PASS
B0.2-D    609/609 PASS
B0.2-E   2580/2580 PASS
BRIDGE-1  146/146 PASS
B0.3      319/319 PASS
B0.4-A    609/609 PASS
B0.4-B     83/83 PASS
```

Total:

```text
4637 / 4637 PASS
```

The convenience aggregate terminal invocation reached the execution-window limit
while B0.2-E was running. B0.2-E was immediately executed separately on the exact
same clean checkout and passed 2580/2580; all remaining gates then passed on that
same subject.

## 13. Project Control

Exact executable subject:

```text
run:
33523690182

conclusion:
SUCCESS
```

## 14. Non-claims

B0.4-B does not claim:

- a general global ROM ErrorEnvelope;
- runtime ValidatedDomain;
- runtime error estimator;
- conservative runtime refinement trigger;
- safe reduced → FULL reconstruction;
- canonical mutation/rebuild lifecycle for the ROM;
- arbitrary nonlinear ROM;
- arbitrary unstable/chaotic reduction;
- hybrid mode bake;
- production acceptance.

## 15. Next

```text
B0.4-A ✅ CLOSED
        ↓
B0.4-B ✅ CLOSED
        ↓
★ B0.4-C RUNTIME ERROR / REFINEMENT ★
        ↓
B0.4-D RECONSTRUCTION / LIFECYCLE
```

B0.4-C must turn the strong but finite B0.4-B response evidence into explicit
`ValidatedDomain + ErrorEnvelope + RuntimeErrorEstimator + RefinementGuard`
semantics and prove fail-closed behavior near/outside the certified domain.
