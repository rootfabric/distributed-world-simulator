# FABRIC-BAKE — Architecture of Reducible Physical Execution

**Status:** research architecture freeze companion to `FABRIC_BAKE_ROADMAP_RU.md`.

## 1. Architectural thesis

FABRIC-BAKE is not a performance switch.

It is a physical compilation layer that asks:

> Can an existing FABRIC subsystem be replaced by a cheaper derived executable model while preserving explicitly declared boundary observables, conservation obligations, causal events, validity bounds and a deterministic path back to detail?

The truth hierarchy remains:

```text
canonical Construction / Matter
        ↓
derived FABRIC physical graph
        ↓
derived PhysicalBakeArtifact
```

Only the first layer owns canonical world truth.

---

## 2. Sibling of Representation LOD

Representation LOD and FABRIC-BAKE share provenance/lifecycle concepts but serve different correctness domains.

```text
canonical source revision
       │
       ├── Presentation artifact
       │     correctness:
       │     geometric/screen/capability error
       │
       └── Physical bake artifact
             correctness:
             effort/flow/power/wrench/
             energy/momentum/events/
             validity/reconstruction
```

Reuse:

- source revision;
- dependency hashes;
- authority epoch;
- invalidation semantics;
- content-addressed identity;
- build generation.

Do not reuse `RepresentationArtifactManifest` as the physical artifact schema.

---

## 3. CanonicalSourceFrontier

A bake may depend on several canonical sources.

```text
CanonicalSourceFrontier
{
    sources: sorted_unique RepresentationSourceRevision[],
    frontier_hash: sha256(canonical sources)
}
```

Rules:

1. sources sorted by canonical domain/id key;
2. duplicates forbidden;
3. each revision independently validates;
4. frontier hash deterministic;
5. FABRIC is not a canonical source domain.

Derived FABRIC binding is separate:

```text
fabric_graph_hash
fabric_compiler_version
```

---

## 4. AuthorityEnvelope

A bake is executable only inside an explicitly compatible authority domain.

Conceptual contract:

```text
AuthorityEnvelope
{
    execution_owner,
    source_authority_frontier,
    mutable_source_ids,
    readonly_source_ids,
    authority_epoch_binding,
    distributed_execution_protocol
}
```

Initial B0.x rule:

```text
cross-authority mutable physical island
→ NO_SAFE_BAKE
```

A bake artifact never grants or merges write authority.

---

## 5. PhysicalBoundaryContract

Boundary ports are acausal physical interfaces.

Each port declares:

```text
port_id
physical_domain
effort_quantity
flow_quantity
effort_dimension
flow_dimension
frame
orientation/sign convention
conservation group
event observables
```

Base mathematical contract:

```text
R_boundary(e, f, x_reduced, p, t) = 0
```

A causal evaluator is a compiled execution form, not the fundamental ontology.

---

## 6. BakeSourceBinding

Conceptual immutable binding:

```text
BakeSourceBinding
├── canonical_source_frontier
├── frontier_hash
├── authority_envelope
├── dependency_hash
├── fabric_graph_hash
├── fabric_compiler_version
├── boundary_contract_hash
├── bake_policy_hash
└── checksum
```

Any mismatch invalidates execution.

---

## 7. PhysicalBakeArtifact

Conceptual artifact:

```text
PhysicalBakeArtifact
├── artifact_id/hash
├── source_binding
├── boundary_contract
├── reduced_model_descriptor
├── reduced_state_schema
├── validated_domain
├── error_envelope
├── conservation_envelope
├── refinement_guards
├── reconstruction_descriptor
├── build_generation
└── checksum
```

Artifact data is derived/cacheable and may be discarded.

---

## 8. ValidatedDomain

ValidatedDomain states where the artifact is allowed to execute.

Examples:

- speed range;
- torque range;
- temperature range;
- exact topology/source frontier;
- specific active-set family;
- bounded external wrench;
- time horizon.

Outside the domain:

```text
BAKE_VALIDITY_EXIT
→ stop physical bake execution
```

No silent extrapolation.

---

## 9. ErrorEnvelope

ErrorEnvelope is deterministic/falsifiable.

Possible components:

```text
effort_abs/rel
flow_abs/rel
power_abs/rel
motion_abs/rel
energy_drift
momentum_drift
event_time_error
event_order_constraints
time_horizon
```

Do not use an undefined statistical `confidence` field as an authority-quality substitute.

---

## 10. RuntimeErrorEstimator

Approximate artifacts may expose an estimator:

```text
current_error_bound
remaining_validity_margin
guard_margin
estimated_horizon
```

The estimator may trigger an earlier refinement than the static validity boundary.

It does not relax ErrorEnvelope.

---

## 11. ConservationEnvelope

The artifact explicitly states conservation/passivity obligations.

Examples:

```text
power_balance_error <= epsilon
energy_creation_forbidden
internal_linear_momentum_conserved
internal_angular_momentum_conserved
matter_balance_error <= epsilon
```

An artifact that cannot certify required conservation properties may return `NO_SAFE_BAKE`.

---

## 12. RefinementGuard

RefinementGuard protects hidden internal processes.

Conceptual form:

```text
RefinementGuard
{
    guard_id,
    observed_boundary_quantities,
    conservative_bound,
    trigger_threshold,
    mapped_source_region,
    required_refinement_level,
    uncertainty_margin
}
```

Critical property:

> A hidden authoritative failure/event must not occur before the guard requests enough detail to represent it.

False-positive early refinement is acceptable.
False-negative missed physical failure is not.

---

## 13. ReconstructionDescriptor

Unbake is a first-class contract.

Descriptor binds:

- canonical source frontier;
- reduced state;
- reconstruction mapping;
- hidden-state initialization policy;
- local region mapping;
- conservation reconciliation;
- event frontier;
- deterministic reconstruction version.

Unbake cannot invent a new canonical part topology.

It reconstructs derived physical state from canonical source plus allowed reduced-state information.

---

## 14. BakeStateMapping

For approximate dynamic artifacts:

```text
FULL → REDUCED
project_state(x_full) = x_reduced
```

and:

```text
REDUCED + canonical source → reconstructed FULL
```

Exact internal state equality is not required.

Continuity requirements are expressed through boundary/conservation envelopes.

---

## 15. BakeInvalidation

Invalidation reasons include at minimum:

```text
SOURCE_REVISION
DEPENDENCY
AUTHORITY
FABRIC_COMPILER
BOUNDARY_CONTRACT
BAKE_POLICY
VALIDITY_EXIT
REFINEMENT_GUARD
MANUAL
UNSUPPORTED_MODE
```

Physical stale rule:

```text
invalidated artifact
→ non-executable immediately
```

It may remain cached as bytes for diagnostics/rebuild reuse, but not as active physics.

---

## 16. BakeCompileResult

Compilation is allowed to fail honestly.

```text
BakeCompileResult
{
    status:
      BAKE_READY
      NO_SAFE_BAKE,

    artifact?,
    reason,
    diagnostics
}
```

Typical `NO_SAFE_BAKE` reasons:

- cross-authority mutable sources;
- rank deficiency;
- no safe elimination;
- validity/error cannot be certified;
- hidden failure cannot be guarded;
- unsupported hybrid mode;
- reduction gives insufficient cost benefit.

---

## 17. Exact vs approximate bake

### Exact

```text
boundary relation is mathematically equivalent
within floating-point tolerance
```

Example: B0.1 Schur reduction.

### Approximate

```text
boundary error <= ErrorEnvelope
within ValidatedDomain
```

Approximate artifacts additionally need:

- RuntimeErrorEstimator when meaningful;
- RefinementGuard;
- explicit horizon/domain;
- fail-closed validity exit.

---

## 18. Structural local unbake requirement

A structural bake cannot keep only:

```text
mass
COM
inertia
```

if hidden internal damage may occur.

It must retain a cheap conservative guard structure that can map an approaching internal limit to a canonical region.

```text
boundary load
→ guard evaluation
→ region R unsafe
→ local unbake R
```

After local unbake:

- canonical bonds/parts remain the source;
- physical topology may split;
- unaffected baked regions may stay reduced;
- new aggregates may be compiled.

---

## 19. Presentation LOD and Physical Fidelity are orthogonal

Example:

```text
remote power station

Presentation:
IMPOSTOR

Physical Fidelity:
DYNAMIC_ROM
```

Or:

```text
near decorative construct

Presentation:
FULL

Physical Fidelity:
DORMANT/SUMMARY
```

Distance may influence presentation but does not define causal physical fidelity.

---

## 20. Scheduler boundary

FABRIC-BAKE owns:

```text
which physical fidelities are safe
what errors they guarantee
what guards are pending
what they cost approximately
```

Global Simulation Scheduler owns:

```text
resource allocation
priorities
server scheduling
budget policy
```

The scheduler may choose only among fidelity states declared safe by the physical layer.

---

## 21. Bridge semantics

### BAKE-BRIDGE-0

Provenance + invalidation:

```text
canonical revision
→ FABRIC compile
→ bake
→ mutation
→ old bake forbidden
```

### BRIDGE-1

Lifecycle + deterministic rebuild/unbake.

### BRIDGE-2

Mixed full/reduced graph:

```text
FULL ↔ BAKED ↔ FULL
```

### BRIDGE-3

Dynamic fidelity lifecycle:

```text
FULL
→ BAKE
→ validity/guard event
→ local/full UNBAKE
→ FULL
```

No fake energy, momentum, duplicate/lost events or stale execution.

---

## 22. Physical-core dependencies

B0.0/B0.1 are already supported by mature FABRIC provenance + Conservation/Power foundations.

B0.2 relies on full 6DOF already demonstrated by FABRIC0.14.

B0.3 final acceptance must wait for FABRIC0.16 general convex multipoint contact and stronger complementarity.

Later BAKE checkpoints may acquire explicit predecessor gates when they depend on new physical-core semantics.

---

## 23. Fundamental axioms

1. Bake is derived, never canonical truth.
2. FABRIC is not added as a canonical source domain.
3. Source binding may contain multiple canonical sources.
4. Bake never crosses mutable authority silently.
5. Physical stale artifacts cannot execute.
6. Boundary contracts remain acausal at the fundamental layer.
7. Internal state equality is not the correctness criterion.
8. Every approximation declares deterministic validity/error bounds.
9. Hidden dangerous processes require conservative RefinementGuards.
10. Unbake/reconstruction is part of architecture, not an emergency hack.
11. Reduction may legally return `NO_SAFE_BAKE`.
12. Physical fidelity is distinct from presentation LOD.
13. Global scheduling cannot override minimum safe physical fidelity.
14. Device-specific classes are not a substitute for derived reduction.
15. A reduction claim is incomplete without computational-cost evidence.

---

## 24. Current status

```text
Physical Core:
FABRIC0.15 RESEARCH CANDIDATE CLOSED
FABRIC0.16 ACTIVE / INDEPENDENT

FABRIC-BAKE:
B0.0 RESEARCH CHECKPOINT CLOSED
B0.1 RESEARCH CHECKPOINT CLOSED
B0.2-A/B STRUCTURAL AGGREGATE + EXACT RECONSTRUCTION IMPLEMENTED / EXACT-HEAD DOUBLE PASS\nB0.2-C REFINEMENT GUARDS NEXT\nB0.2 CHECKPOINT REMAINS OPEN

Integration:
dual-track roadmap frozen
B0.1 exact boundary reduction is executable and closed
production acceptance is not claimed
```


---

## FABRIC-BAKE B0.0 implementation status

```text
B0.0
BAKE FOUNDATION CONTRACTS
IMPLEMENTED CANDIDATE
LOCAL DOUBLE FOCUSED PASS: 33/33
INDEPENDENT EXACT-HEAD VERIFICATION: PENDING
PRODUCTION ACCEPTANCE: NOT CLAIMED
```

Implemented on `research/fabric-bake0-reducible-world-fabric-r1` from the common dual-track fork
`962b9c1bbf7f04c7853f1fb0e36480cf54f3250d`.

Recovery entrypoints:

```text
docs/research/FABRIC_BAKE_B0_0_FOUNDATION_RU.md
validation/fabric-bake-b0-0-foundation-validation.json
tests/research/fabric_bake0/fabric_bake_b0_0_acceptance.gd
RUN_FABRIC_BAKE_B0_0_TESTS.ps1
RUN_FABRIC_BAKE_B0_0_TESTS.sh
```

B0.0 now provides executable contracts for CanonicalSourceFrontier, AuthorityEnvelope,
PhysicalBoundaryContract, source/dependency binding, ValidatedDomain, ErrorEnvelope,
RuntimeErrorEstimator, ConservationEnvelope, RefinementGuard, reconstruction/state mapping,
PhysicalBakeArtifact, BakeInvalidation, BAKE_READY/NO_SAFE_BAKE, a fail-closed execution gate,
and BAKE-BRIDGE-0 over the existing Representation revision/invalidation semantics.

This does **not** promote B0.0 to production or canonical acceptance. B0.1 remains the first
mathematical reduction checkpoint; FABRIC0.16 continues independently on Physical Core.


---

## FABRIC-BAKE B0.1 closure boundary — 2026-08-31

Exact executable subject:

```text
branch:
research/fabric-bake0-1-exact-boundary-reduction-r1

implementation HEAD:
e854185f501cfc2658d5d1c5430be4eed3b070ee

implementation TREE:
0114ed1973e7bcd1d6225381d07f1ad1ade6b9a0

parent:
d389b8ed72ffbed8949279b42089da3687125a90
(B0.0 closure)
```

B0.1 closes the first executable mathematical reduction checkpoint:

```text
4 boundary ports
+ 128 internal variables
= 132 full equations

exact Schur elimination
        ↓
4-equation boundary relation

internal rank = 128
reduced rank  = 3
runtime arithmetic-work proxy ratio = 1089x
```

Rank 3 at the reduced boundary is expected for the passive Laplacian fixture because
one common-potential gauge/nullspace mode remains at the boundary. The eliminated
internal block itself is full rank 128.

Exact-source identity was materialized by GitHub-hosted run `33348975423`:

```text
checkout HEAD = e854185f501cfc2658d5d1c5430be4eed3b070ee
checkout TREE = 0114ed1973e7bcd1d6225381d07f1ad1ade6b9a0
git-archive SHA-256 =
548d832c6d042227c3b0df85b991519e1ae2702a7ef71770bdaa6f226ba3c0d1
```

Two separate fresh-filesystem full-tree imports and canonical B0.0→B0.1 runs were
then executed with:

```text
Godot:
4.7.1.stable.double.custom_build.a13da4feb

Linux binary SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Both passes produced:

```text
B0.0 Acceptance = PASS (33 assertions)
B0.1 Acceptance = PASS (64 assertions)
B0.1 Playground = PASS

full equations       = 132
reduced equations    = 4
internal rank        = 128
reduced rank         = 3
work ratio           = 1089.0x
max boundary flow Δ  = 9e-14
max boundary power Δ = 1.42e-12

descriptor:
92c62af79e1c75889c846084711c6752e92489db1d1aa27a5f13aa832bbc00f6

artifact:
a04a380833bf0f62ae0fc8f33da2cbc66d7520dd78fea193b34d9f21f6cd0300
```

After the second import/run, all 5025 tracked archive files were compared byte-for-byte
with a pristine extraction:

```text
tracked_files_checked = 5025
missing               = 0
changed               = 0
```

Exact-head Project Control run `33349147651` completed successfully for the same
implementation HEAD/TREE. The global dashboard remained YELLOW because of unrelated
active project frontiers; this is not a claim that the whole repository is globally GREEN.

Closure qualification:

```text
FABRIC-BAKE B0.1
RESEARCH CHECKPOINT CLOSED
EXACT-HEAD DOUBLE PASS
PROJECT CONTROL NON-BLOCKING
PRODUCTION ACCEPTANCE NOT CLAIMED
```

B0.1 does not claim generic singular/nullspace reduction, DAE condensation,
nonlinear ROM, hybrid bake, contact bake or production readiness.

Next FABRIC-BAKE checkpoint:

```text
B0.2
STRUCTURAL AGGREGATE BAKE
+ REFINEMENT GUARDS
+ LOCAL UNBAKE
```


---

## FABRIC-BAKE platform verification policy — 2026-08-31

Для FABRIC-BAKE B0.x обязательная acceptance-цепь теперь платформенно нейтральна и
опирается на canonical Ubuntu/Linux double-Godot verification:

```text
exact Git HEAD/TREE
        ↓
fresh Ubuntu/Linux tracked tree
        ↓
pinned Godot double identity
        ↓
fresh import
        ↓
predecessor regression
        ↓
focused checkpoint acceptance
        ↓
fresh repeat / exact-head evidence
        ↓
CLOSED
```

Windows verification удалена из обязательной цепи.

Policy semantics:

```text
Ubuntu/Linux exact-double:
REQUIRED
AUTHORITATIVE FOR FABRIC-BAKE CHECKPOINT CLOSURE

Windows:
PASS_BY_POLICY
NON-GATING
NO SEPARATE EXECUTION EVIDENCE REQUIRED
```

`PASS_BY_POLICY` означает принятое cross-platform compatibility assumption для
FABRIC-BAKE и не должно интерпретироваться как утверждение, что конкретный Windows
binary действительно был запущен.

Windows runner/script может использоваться вручную для диагностики или portability
investigation, но его отсутствие, offline state, queue state или отсутствие Windows
evidence не переводят checkpoint в PENDING/RED и не блокируют следующий B0.x.

Если в будущем появится Windows-specific код, platform-specific native dependency или
расхождение поведения, отдельная Windows verification может быть возвращена только как
явно объявленный exception для конкретного checkpoint.


---

## B0.2-A/B implementation boundary — 2026-08-31

```text
branch:
research/fabric-bake0-2-structural-aggregate-r1

executable implementation HEAD:
b417066a048d3c85bf766eb239d4111335c66602

TREE:
da87230e3dd247d2fd662bf5f8ec3926c055f4d3

qualification:
IMPLEMENTED CANDIDATE
EXACT-HEAD DOUBLE PASS
B0.0/B0.1 REGRESSION PASS
TRACKED TREE BYTE-CLEAN
```

B0.2-A/B compiles a connected rigid canonical structure into deterministic aggregate
mass/COM/full-inertia, boundary-anchor and finite-support descriptors, plus exact rigid
REDUCED↔FULL reconstruction mapping.

Safety boundary remains:

```text
B0.2-A/B
→ STRUCTURAL_AGGREGATE_READY_FOR_GUARDS
→ no executable PhysicalBakeArtifact yet

B0.2-C
→ RefinementGuard certification
→ NEXT
```

Therefore B0.2 itself is **not closed**.


---

## FABRIC-BAKE B0.2-D closure boundary — 2026-08-31

```text
branch:
research/fabric-bake0-2-d-bounded-local-unbake-r1

executable HEAD:
8da6ec6b7c2983b127f4c0607edeb9be900825c3

TREE:
285240dcc8a08a3a676897792659dfcad43bf410

qualification:
RESEARCH SLICE CLOSED
EXACT-HEAD DOUBLE PASS
TRACKED TREE BYTE-CLEAN
```

B0.2-D implements the first bounded mixed structural representation transition:

```text
BAKED parent
→ C guard selects canonical region
→ exact B0.2-B reconstruction
→ selected region FULL
→ unaffected connected residuals recompiled BAKED
→ explicit FULL ↔ BAKED cut interfaces
→ conservation + continuity reconciliation
```

The 500-part acceptance fixture expands only 20 parts and retains 480 parts in two
240-part residual aggregates:

```text
6500 fully-FULL DOF
→ 286 mixed DOF
= 22.727273x retained reduction
```

The transition is derived only. Construction/Matter part and bond topology remains
canonical and unchanged. D fails closed instead of silently widening an unsafe local
unbake.

B0.2-D does not yet define post-break topology ownership, persistent split lifecycle,
or re-bake after topology changes. Those are B0.2-E.
