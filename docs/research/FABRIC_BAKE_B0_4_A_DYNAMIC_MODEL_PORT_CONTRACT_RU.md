# FABRIC-BAKE B0.4-A — Dynamic Model / Port Contract

## Статус

```text
FABRIC-BAKE B0.4-A
DYNAMIC MODEL / PORT CONTRACT
RESEARCH CHECKPOINT CLOSED
EXACT-HEAD DOUBLE-GODOT PASS
PROJECT CONTROL PASS
NOT PRODUCTION ACCEPTED
```

Parent checkpoint:

```text
B0.4 DYNAMIC ROM
IN PROGRESS
NEXT = B0.4-B CERTIFIED REDUCTION
```

## 1. Exact executable boundary

```text
branch:
research/fabric-bake0-4-dynamic-rom-r1

predecessor:
FABRIC.SYNC2 closure
be419fb695221917df0f6026ed335e1355f72840

exact executable HEAD:
1fbfffe30f5758a1bbb3c65db23edf06ecf3dae4

TREE:
79bedac6b6668ffcf29629238a5c055fb55d5f3c
```

SYNC-2 authorization remains:

```text
FABRIC0.18 frozen
FABRIC0.19 NOT AUTHORIZED
B0.4 executable research authorized
```

B0.4-A did not require a new Physical Core primitive.

## 2. What B0.4-A closes

B0.4-A creates the executable FULL-side reference boundary required before any ROM
claim.

Implemented:

- canonical deterministic encoding of a derived dynamic-state schema;
- deterministic FULL state contract;
- generic passive dynamic-model descriptor;
- direct reuse of existing `PhysicalBoundaryContract`;
- direct reuse of existing `BakeSourceBinding`;
- exact source/dependency/compiler/graph binding;
- dimension/frame/orientation validation;
- explicit reference-only causalization;
- structural strict-passivity/stability certificate;
- deterministic 512-state FULL reference solver;
- discrete boundary-power / storage / physical-dissipation / numerical-dissipation accounting;
- fail-closed unsafe-domain cases.

Not implemented in A:

- reduced model;
- projection basis;
- Hankel singular values;
- balanced truncation;
- B0.4 PhysicalBakeArtifact emission;
- RuntimeErrorEstimator for a ROM;
- ROM RefinementGuard;
- ROM reconstruction.

Those begin in B0.4-B/C/D.

## 3. Dynamic state schema

New contract:

`scripts/research/fabric_bake0/dynamic_state_schema_v1.gd`

Each dynamic state binds:

```text
state_id
quantity_id
physical dimension
canonical reconstruction region_id
```

The schema is:

- sorted canonically by `state_id`;
- unique;
- content-hashed;
- checksum-protected;
- presentation-order independent.

This is derived physical execution state. It does not become canonical Construction or
Matter truth.

Runtime state is separately represented by:

`dynamic_full_state_v1.gd`

and binds:

- exact dynamic model hash;
- exact state-schema hash;
- time;
- deterministic step index;
- finite state vector;
- checksum.

A state from a different model is non-executable in the reference solver.

## 4. Physical port boundary

B0.4-A does not introduce a new I/O port model.

It directly consumes the existing acausal:

`physical_boundary_contract_v1.gd`.

The R1 fixture uses four generic electrical effort/flow ports:

```text
effort = electric potential
flow   = electric current

port 0   INTO_SUBSYSTEM
port 170 INTO_SUBSYSTEM
port 341 OUT_OF_SUBSYSTEM
port 511 OUT_OF_SUBSYSTEM
```

Every binding must match exactly:

- effort quantity;
- effort dimension;
- flow quantity;
- flow dimension;
- frame;
- orientation.

The FULL solver uses:

```text
FLOW_DRIVEN_REFERENCE_ONLY
```

as a temporary causalization for deterministic validation. It is explicitly not the
canonical physical direction of the boundary contract.

## 5. 512-state generic passive fixture

Reference fixture:

`tests/research/fabric_bake0/fabric_bake_b0_4_a_fixture.gd`

It is a generic scalar storage/dissipation path, instantiated with an electrical
effort/flow quantity system.

```text
dynamic storage states:
512

boundary ports:
4

storage elements:
512

internal dissipative edges:
511

positive shunts:
512
```

Topology:

```text
port
 ↓
[C0]--G--[C1]--G-- ... --G--[C511]
 |        |                     |
g0       g1                   g511
 ↓        ↓                     ↓
reference / dissipation
```

This is not a Battery/Motor/Transmission solver.

The defining kernel abstraction is generic:

```text
PASSIVE_SCALAR_STORAGE_PATH_R1
```

The same contract can represent another compatible effort/flow domain if the
quantity and coefficient dimensions satisfy the declared boundary relation.

## 6. Dimensional contract

For the frozen electrical fixture:

```text
effort:
electric potential
[1, 2, -3, -1, 0, 0, 0]

flow:
electric current
[0, 0, 0, 1, 0, 0, 0]

storage coefficient:
capacitance
[-1, -2, 4, 2, 0, 0, 0]

conductance:
[-1, -2, 3, 2, 0, 0, 0]
```

B0.4-A mechanically checks:

```text
storage_dimension + effort_dimension - time_dimension
= flow_dimension

conductance_dimension + effort_dimension
= flow_dimension
```

A model with incompatible coefficient dimensions fails closed.

## 7. Source and dependency binding

The dynamic model consumes existing B0.0 contracts:

```text
CanonicalSourceFrontier
AuthorityEnvelope
DependencySet
PhysicalBoundaryContract
BakeSourceBinding
```

The fixture frontier contains canonical:

- Construction source;
- Matter source.

Both mutable sources are in one compatible execution authority envelope.

The model binds:

```text
frontier_hash
authority envelope
dependency_hash
fabric_graph_hash
fabric_compiler_version
boundary_contract_hash
bake_policy_hash
```

The dynamic graph hash is deterministic and includes:

- state schema;
- storage coefficients;
- internal coupling;
- shunts;
- port bindings.

Initial runtime state values are deliberately not graph identity.

## 8. Fail-closed safety boundary

Focused acceptance proves negative paths including:

```text
cross-authority mutable source
→ NO_SAFE_BAKE / AUTHORITY_ENVELOPE_CROSSED

reference state count < 512
→ NO_SAFE_BAKE / B0_4_A_REFERENCE_STATE_COUNT_BELOW_512

non-positive storage
→ NO_SAFE_BAKE / NO_SAFE_BAKE_NONPOSITIVE_DYNAMIC_STORAGE

negative dissipative coupling
→ NO_SAFE_BAKE / NO_SAFE_BAKE_NONPOSITIVE_DYNAMIC_COUPLING

port frame mismatch
→ fail closed

port orientation mismatch
→ fail closed

physical coefficient dimension mismatch
→ fail closed

missing boundary flow in reference solver
→ fail closed

reference dt > certified max step
→ fail closed

FULL state bound to another model
→ fail closed
```

No unsafe candidate is silently coerced into the accepted reference domain.

## 9. Structural passivity/stability certificate

The B0.4-A R1 certificate is intentionally narrow and deterministic.

For the frozen path class it requires:

```text
all storage coefficients > 0
all internal conductances > 0
all shunt conductances > 0
connected canonical path
```

Therefore the homogeneous finite-dimensional reference dynamics is strictly
dissipative/stable in the accepted R1 class.

This is a structural certificate for the FULL reference model only.

It is not yet the ROM passivity certificate required from B0.4-B.

## 10. Deterministic FULL reference solver

New solver:

`dynamic_full_reference_solver_v1.gd`

Method:

```text
BACKWARD_EULER_TRIDIAGONAL_PATH_R1
```

For one step:

```text
C (v[n+1] - v[n]) / dt
+
L_G v[n+1]
+
G_shunt v[n+1]
=
boundary flow injection
```

The tridiagonal linear system is solved deterministically with the Thomas algorithm.

The accepted fixture sets:

```text
max_step_s = 0.02
```

A larger step is rejected.

## 11. Energy accounting

Stored energy:

```text
E = 1/2 Σ C_i * effort_i^2
```

Physical dissipated power includes:

```text
Σ G_edge * (e_i - e_j)^2
+
Σ G_shunt * e_i^2
```

Backward Euler also has explicit non-negative numerical dissipation:

```text
E_numeric =
1/2 Σ C_i * (e_i[n+1] - e_i[n])^2
```

Discrete balance check:

```text
ΔE
+ E_physical_dissipation
+ E_numeric
- E_boundary_in
≈ 0
```

The acceptance includes:

- exact zero equilibrium;
- passive zero-input energy decay;
- boundary energy injection;
- boundary energy extraction;
- INTO/OUT orientation power-sign check;
- no unaccounted positive energy creation;
- deterministic twin-run replay.

## 12. Exact focused evidence

Pinned Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb

Linux binary SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Exact source carrier:

```text
run:
33517363429

conclusion:
SUCCESS

artifact:
9804153300

bundle SHA-256:
eb5fef15df097f5b1d54510e31add7d7562866680ad65fecf7b0b29d6c42b3b4
```

Fresh filesystem pass #1:

```text
HEAD:
1fbfffe30f5758a1bbb3c65db23edf06ecf3dae4

TREE:
79bedac6b6668ffcf29629238a5c055fb55d5f3c

import:
PASS / exit 0

B0.4-A acceptance:
609/609 PASS

B0.4-A playground:
PASS
```

Fresh filesystem pass #2 from the same exact Git bundle:

```text
HEAD:
1fbfffe30f5758a1bbb3c65db23edf06ecf3dae4

TREE:
79bedac6b6668ffcf29629238a5c055fb55d5f3c

tracked:
clean

import:
PASS / exit 0

B0.4-A acceptance:
609/609 PASS

B0.4-A playground:
PASS
```

Both runs emitted the same model identity:

```text
5a75707e8d34bccd24c86ef325ccfb24ca53f5485889cc47fa32dd209490c46f
```

and the same playground energy summary:

```text
states = 512
ports = 4
final stored energy = 0.245836389238
boundary energy in = 0.379312178771
physical dissipation = 0.132820966813
numerical dissipation = 0.000654822720
max balance residual = 1.4983674023749671e-16
```

## 13. Predecessor regression on exact B0.4-A subject

The same exact source subject passed:

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
```

Total focused acceptance assertions:

```text
4554 / 4554 PASS
```

All relevant playgrounds executed in the regression sequence are also PASS.

The single convenience chained shell command is longer than the execution window of
the local terminal tool and was therefore completed as the same exact gate scripts on
the same fresh detached subject. No test returned a functional failure.

## 14. Project Control

Exact executable subject:

```text
run:
33517363373

conclusion:
SUCCESS
```

## 15. Non-claims

B0.4-A does not claim:

- any state-count reduction;
- a ROM artifact;
- <=24 reduced states;
- >=20x ROM reduction;
- <=1e-3 FULL-vs-ROM boundary error;
- Hankel singular-value error certificate;
- runtime ROM estimator/refinement;
- reduced-state reconstruction;
- hybrid bake;
- production acceptance.

Those parent B0.4 claims remain OPEN.

## 16. Next

```text
B0.4-A ✅ CLOSED
        ↓
B0.4-B CERTIFIED REDUCTION
```

B0.4-B must consume this frozen FULL model / state / boundary contract and produce a
structure/passivity-preserving reduced descriptor integrated with the existing
PhysicalBakeArtifact architecture.
