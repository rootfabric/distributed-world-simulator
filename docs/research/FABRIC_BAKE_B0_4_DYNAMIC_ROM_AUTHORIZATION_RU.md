# FABRIC-BAKE B0.4 — DYNAMIC ROM — Authorization Contract R1

## Qualification

```text
B0.4 DYNAMIC STATE REDUCTION / ROM
EXECUTABLE RESEARCH AUTHORIZED
NOT IMPLEMENTED BY THIS DOCUMENT
NOT PRODUCTION ACCEPTED
```

Authorized branch:

`research/fabric-bake0-4-dynamic-rom-r1`

Authorization owner:

`FABRIC.SYNC2 POST-B0.3 DEVELOPMENT REVIEW`.

## 1. Problem

B0.1/B0.2/B0.3 reduce algebraic, structural and contact representation, but a
subsystem may still own hundreds/thousands of true dynamic storage states.

B0.4 reduces time-evolving state while preserving the physical boundary contract.

It is not a compression benchmark. A smaller state vector is useful only if the
reduced execution is physically admissible and safely refinable.

## 2. Initial executable domain

R1 is restricted to a mode-local, stable, passive dynamic subsystem with generic
physical ports.

Reference target:

```text
FULL dynamic states:
N >= 512

REDUCED dynamic states:
r <= 24

state-count reduction:
N / r >= 20
```

The subject must expose at least two physical boundary ports and may expose more.

The first reference fixture should be a generic passive state network, for example a
coupled storage/dissipation graph or port-Hamiltonian/LTI physical state system.

Forbidden as the defining abstraction:

- MotorROM;
- GearboxROM;
- BatteryROM;
- SuspensionROM;
- any device-specific solver class.

## 3. Mathematical boundary

A mode-local linear reference form may be represented internally as:

```text
x_dot = A x + B u
y     = C x + D u
```

or an equivalent descriptor / port-Hamiltonian representation.

The canonical boundary remains FABRIC effort/flow ports. A temporary causal
orientation used by the reducer does not become canonical physical direction.

Every boundary quantity must preserve:

- physical dimension;
- frame;
- sign/orientation;
- conservation group;
- source binding.

## 4. Reduction method priority

R1 method order:

1. exact elimination of algebraic/static internal variables where available;
2. stable modal truncation where physically justified;
3. balanced truncation / moment matching where certificate assumptions hold;
4. positive-real / passivity-preserving balancing;
5. structure-preserving port-Hamiltonian projection.

A generic neural surrogate is explicitly out of scope for R1.

If a method cannot provide a conservative validity/error/passivity argument, the
compiler must return `NO_SAFE_BAKE`.

## 5. PhysicalBakeArtifact integration

B0.4 must emit the existing artifact architecture, not a private ROM object.

Required artifact content:

```text
PhysicalBakeArtifact
├── source_binding
├── PhysicalBoundaryContract
├── reduction_class = APPROXIMATE
├── reduced_model_descriptor_hash
├── reduced_state_schema_hash
├── ValidatedDomain
├── ErrorEnvelope
├── ConservationEnvelope
├── RefinementGuard[]
├── ReconstructionDescriptor
├── StateMapping
└── build_generation
```

The reduced model may have a B0.4-specific descriptor, but execution is still gated
through the common bake lifecycle.

## 6. Error certificate

For the initial stable LTI/passive domain, the preferred analytical certificate is a
conservative induced boundary-response bound.

Balanced-truncation-style implementations may use:

```text
error_bound <= 2 * sum(discarded Hankel singular values)
```

when its assumptions are actually satisfied.

Alternative methods must provide an equivalent conservative certificate.

The artifact must declare at least:

- absolute boundary effort/flow error bound;
- relative boundary response error bound;
- energy/power accounting tolerance;
- certified time/frequency/excitation domain;
- state/reconstruction error bound.

Reference acceptance target for the frozen R1 fixture:

```text
relative boundary response error <= 1e-3
```

over the declared deterministic validation domain.

Measured error may be smaller, but it must never exceed the artifact's declared
certificate.

## 7. Passivity / no invented energy

For passive accepted-domain fixtures, reduced execution must not create net energy.

The acceptance harness must account for:

```text
stored energy change
dissipation
boundary power integral
numerical residual
```

and enforce a scale-aware tolerance.

A reduced model with excellent trajectory fit but positive unaccounted generated
energy fails B0.4.

## 8. Runtime estimator and refinement guard

B0.4 must have a live `RuntimeErrorEstimator`.

At runtime:

```text
safe margin
→ ROM continues

error/validity margin approaches guard
→ refinement request

outside certified domain
→ FULL / NO_SAFE_BAKE
```

The guard must be conservative and source-region bound.

No scheduler heuristic may override minimum safe fidelity.

## 9. Projection and reconstruction

B0.4 must define deterministic:

```text
FULL state
→ reduced state

reduced state
→ bounded reconstructed FULL state
```

Reconstruction is not required to recover discarded dynamic state exactly.

It is required to:

- bind to the source frontier and exact reduced artifact;
- remain within a declared reconstruction/error envelope;
- preserve boundary kinematics/observables within the declared envelope;
- preserve passivity/conservation constraints;
- provide a safe state handoff for fallback/refinement;
- fail closed when reconstruction confidence is insufficient.

## 10. Determinism

For identical:

- canonical source frontier;
- dependency set;
- boundary contract;
- FULL model;
- reduction options;
- compiler version;

B0.4 must produce byte/canonical-hash identical:

- reduced descriptor;
- state mapping;
- reconstruction descriptor;
- error envelope;
- refinement guards;
- PhysicalBakeArtifact.

Input presentation order is not artifact identity.

## 11. Mandatory R1 validation inputs

At minimum:

1. zero-input decay;
2. impulse-like bounded boundary excitation;
3. step-like bounded excitation;
4. deterministic chirp / frequency sweep;
5. deterministic broadband pseudo-random excitation;
6. near-validity-bound excitation;
7. out-of-domain excitation.

For in-domain probes:

```text
FULL vs ROM boundary response
<= certified ErrorEnvelope
```

For out-of-domain:

```text
refinement / FULL / NO_SAFE_BAKE
```

not silent extrapolation.

## 12. Suggested executable slices

### B0.4-A — Dynamic model / port contract — CLOSED

Exact executable:

```text
HEAD:
1fbfffe30f5758a1bbb3c65db23edf06ecf3dae4

TREE:
79bedac6b6668ffcf29629238a5c055fb55d5f3c
```

Implemented and verified:
- canonical dynamic-state descriptor;
- dimension/frame/sign validation;
- generic 512-state stable/passive reference fixture;
- deterministic FULL boundary reference solver;
- source/dependency binding;
- structural passivity/stability certificate;
- explicit boundary/storage/dissipation/numerical energy accounting;
- fail-closed unsafe domain;
- presentation-order and twin-run determinism.

Evidence:

```text
B0.4-A 609/609 PASS
two fresh exact-bundle filesystem passes
predecessor + A acceptance total 4554/4554 PASS
Project Control 33517363373 SUCCESS
```

Detailed closure:
`docs/research/FABRIC_BAKE_B0_4_A_DYNAMIC_MODEL_PORT_CONTRACT_RU.md`.

B0.4 parent remains IN PROGRESS. No ROM reduction claim is made by A.

### B0.4-B — Certified reduction

- exact pre-elimination where available;
- structure/passivity-preserving ROM;
- reduced descriptor;
- artifact identity;
- reduction >= 20x on the R1 fixture.

### B0.4-C — Runtime error / refinement

- ValidatedDomain;
- ErrorEnvelope;
- RuntimeErrorEstimator;
- RefinementGuard;
- near-bound and out-of-domain fail-closed probes.

### B0.4-D — Reconstruction / lifecycle closure

- projection/reconstruction;
- bounded FULL fallback state;
- canonical mutation invalidation;
- deterministic rebuild;
- exact artifact replay;
- final FULL-vs-ROM evidence suite.

## 13. Closure gate

B0.4 may be marked CLOSED only when all are true:

- R1 fixture has >=512 dynamic states;
- emitted ROM has <=24 dynamic states;
- state reduction >=20x;
- boundary ports remain dimension/frame/sign compatible;
- relative boundary response error <=1e-3 on the declared validation suite;
- measured error never exceeds the declared ErrorEnvelope;
- passive fixture creates no unaccounted energy beyond scale-aware tolerance;
- runtime estimator/guard refines before leaving the certified domain;
- explicit out-of-domain path is FULL / NO_SAFE_BAKE;
- projection/reconstruction is deterministic and within declared bounds;
- stale source/dependency/artifact execution fails closed;
- reverse/input-order determinism passes;
- exact double Godot acceptance passes;
- remote byte audit passes where required;
- Project Control passes.

## 14. Non-claims

B0.4 R1 does not claim:

- arbitrary nonlinear ROM;
- arbitrary unstable/chaotic reduction;
- hybrid mode reduction;
- contact-mode reduction;
- pressure-resolved contact;
- cross-authority dynamic bake;
- neural surrogate correctness;
- production acceptance.

Hybrid semantics belong to B0.5.

Mixed FULL↔ROM graph integration belongs to BRIDGE-2.

## 15. Authorization decision

```text
B0.4
AUTHORIZED TO START IMPLEMENTATION

branch:
research/fabric-bake0-4-dynamic-rom-r1

predecessor:
closed FABRIC.SYNC2 decision boundary

Physical Core minimum:
FABRIC0.18

FABRIC0.19 dependency:
NONE
```
