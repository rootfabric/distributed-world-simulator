# FABRIC-BAKE — Roadmap Reducible World Fabric

**Статус:** dual-track research roadmap freeze после FABRIC0.15.  
**Physical-core predecessor:** FABRIC0.15 — **RESEARCH CANDIDATE CLOSED / EXACT DOUBLE PASS / DRAFT REVIEW CANDIDATE**.  
**Physical-core predecessor HEAD before roadmap freeze:** `381e2216661d07aed898f3a2bff0b9590fb5b4f5`.  
**FABRIC0.15 exact-tested executable commit:** `a8ff0d7360b4bba0f1b3e164f8c040d73622b1ee`.  
**Parallel research line:** `FABRIC-BAKE B0.x`.  
**Recommended implementation branch:** `research/fabric-bake0-reducible-world-fabric-r1`.

---

## 1. Зачем существует FABRIC-BAKE

Основная FABRIC0.x-линия отвечает на вопрос:

> Как выражать всё более сложную физику из generic physical primitives без device-specific runtime classes?

FABRIC-BAKE отвечает на другой фундаментальный вопрос:

> Может ли уже возникшая physical complexity автоматически компилироваться в значительно более дешёвое executable representation без потери причинно значимого boundary behavior, conservation и возможности безопасно вернуть детализацию?

Это две независимые research axes:

```text
FABRIC0.x / PHYSICAL CORE
=
complexity can emerge compositionally

FABRIC-BAKE / REDUCTION
=
emerged complexity can be safely reduced
```

FABRIC-BAKE не заменяет physical-core line и не тормозит её.

---

## 2. Неподвижная truth boundary

```text
Construction / canonical world state
            =
canonical semantic truth

FABRIC graph
            =
derived physical executable representation

PhysicalBakeArtifact
            =
derived optimized physical executable representation
```

Следовательно:

```text
PhysicalBakeArtifact != canonical world truth
```

Bake artifact никогда не владеет:

- item/part identity;
- canonical Construction topology;
- authoritative damage;
- inventory;
- ownership;
- canonical persistence;
- authority assignment;
- canonical mutation history.

Artifact обязан быть:

```text
invalidate-able
rebuildable
refinable
unbake-able
discardable
```

Потеря всех bake artifacts не меняет canonical checksum мира.

---

## 3. Связь с существующим Representation LOD

DWS уже имеет зрелую derived-artifact provenance architecture:

- `RepresentationSourceRevision`;
- `RepresentationDependencySet`;
- `RepresentationInvalidation`;
- source revision/hash;
- authority epoch;
- dependency hash;
- content addressing;
- build generation;
- cache lifecycle.

Эти semantics должны переиспользоваться.

Но PhysicalBakeArtifact **не является** `RepresentationArtifactManifest`.

Причина: Representation LOD описывает presentation/network/collision artifacts с полями вроде:

```text
media_type
encoding
geometric_error_m
collision_capable
interior_capable
```

Physical Bake требует другой correctness model:

```text
boundary effort/flow
power
wrench
momentum
energy
matter transfer
events
validity/error envelopes
reconstruction
```

Правильная архитектура:

```text
                    canonical world
                         │
                         ▼
              source / revision semantics
                         │
              ┌──────────┴───────────┐
              │                      │
              ▼                      ▼
     Presentation Artifact     Physical Bake Artifact
          RL0/RLx                  FABRIC-BAKE
```

Общие lifecycle concepts — да. Один artifact schema — нет.

---

## 4. Physical STALE — execution forbidden

Representation presentation может при строгих fences временно оставаться видимым как `STALE`.

Physical Bake имеет более сильное правило:

```text
presentation STALE
→ may remain visible under presentation fences

physical STALE
→ MUST NOT execute
```

Любая несовместимая source/dependency/compiler/boundary/policy revision переводит artifact в non-executable состояние.

Fallback:

```text
rebuild
refine
unbake
or FULL execution
```

Никакого stale-while-physics.

---

## 5. CanonicalSourceFrontier — bake может иметь несколько canonical sources

Bake source binding не предполагает один canonical object.

Серьёзная subsystem может одновременно зависеть от:

- Construction A;
- Construction B;
- Matter support;
- other canonical dependencies.

Поэтому B0.0 вводит sorted canonical frontier:

```text
CanonicalSourceFrontier
├── RepresentationSourceRevision
├── RepresentationSourceRevision
└── ...
```

Frontier:

- sorted canonically;
- unique;
- content-hashed;
- authority-fenced;
- включается целиком в bake provenance.

Запрещено добавлять `FABRIC` как canonical source domain.

FABRIC graph является derived compilation и связывается отдельно:

```text
fabric_graph_hash
fabric_compiler_version
```

---

## 6. AuthorityEnvelope

FABRIC математически может видеть physical graph, пересекающий несколько authority domains.

BAKE не имеет права автоматически превратить его в одного write-capable executable owner.

B0.x initial invariant:

```text
all mutable canonical sources
must belong to one compatible authoritative execution envelope
```

Иначе:

```text
NO_SAFE_BAKE
reason = AUTHORITY_ENVELOPE_CROSSED
```

Cross-authority bake требует отдельного distributed physical execution protocol и не входит в initial B0.x scope.

`AuthorityEnvelope` должен связывать как минимум:

- authority owner/domain;
- authority epoch frontier;
- permitted execution scope;
- write ownership constraint;
- optional read-only dependencies.

Bake artifact не расширяет authority.

---

## 7. Acausal PhysicalBoundaryContract

Фундаментальный boundary contract не должен насильно превращать FABRIC в обычный `input -> output` pipeline.

Physical boundary содержит ports с:

- stable identity;
- physical domain;
- effort quantity;
- flow quantity;
- executable dimensions;
- sign/orientation convention;
- coordinate frame;
- conservation membership;
- observable event surface.

Conceptual form:

```text
R_boundary(e, f, x_reduced, p, t) = 0
```

Causal execution form:

```text
x_dot = f(x,u)
y     = g(x,u)
```

может быть compiled artifact form только там, где causalization допустима.

---

## 8. Correctness определяется boundary observables

Внутреннее state equality не требуется:

```text
x_full != x_baked
```

Это нормально.

Correctness:

```text
|| y_full - y_baked || <= declared ErrorEnvelope
```

Boundary observable set может включать:

- effort;
- flow;
- power;
- force;
- wrench;
- motion;
- energy;
- momentum;
- matter flow;
- event identity/order/time.

Для exact bake:

```text
error ~ machine precision
```

Для approximate bake:

```text
error <= explicit deterministic bound
```

---

## 9. ValidatedDomain + ErrorEnvelope + RuntimeErrorEstimator

Не использовать расплывчатое `confidence` как authoritative physical contract.

Разделить:

### ValidatedDomain

Где artifact был физически/численно валидирован.

Например:

```text
rpm          [1000, 3000]
torque       [-300, 300]
temperature  [280, 350]
topology     exact source frontier
```

### ErrorEnvelope

Детерминированные допустимые bounds:

```text
effort_error
flow_error
power_error
motion_error
energy_drift
event_time_error
horizon
```

### RuntimeErrorEstimator

Текущая оценка:

```text
current_error_bound
distance_to_validity_boundary
guard_margin
```

Validity exit:

```text
BAKE_VALIDITY_EXIT
→ artifact execution forbidden
→ refine / rebuild / unbake / FULL
```

---

## 10. RefinementGuard — hidden detail must be able to call itself back

Главная проблема reduction:

> После удаления internal DOF именно скрытое internal process может стать причиной необходимости вернуть детализацию.

Поэтому каждый approximate artifact должен иметь conservative refinement guards.

Для structural bake:

```text
RefinementGuard
├── region load envelopes
├── bond-family capacity envelopes
├── local stress/wrench bounds
├── uncertainty margin
└── guard-to-source reconstruction mapping
```

Runtime:

```text
external boundary state
        ↓
cheap conservative guard
        ↓
region approaches hidden failure domain
        ↓
local unbake/refine before missed failure
```

Guard обязан быть conservative: ложний ранний unbake допустим; пропущенное authoritative failure событие — нет.

---

## 11. NO_SAFE_BAKE — reduction is optional

Не всякая subsystem обязана иметь безопасную дешёвую reduction.

Compiler legally returns:

```text
PhysicalBakeArtifact
```

или:

```text
NO_SAFE_BAKE
```

Возможные причины:

- authority envelope crossed;
- no valid boundary closure;
- rank-deficient/ambiguous reduction;
- error bound cannot be certified;
- near-critical hidden dynamics;
- guard cannot conservatively detect invalidation;
- cost reduction too small;
- unsupported topology/hybrid regime.

Никаких эвристик “всё равно приблизим”.

---

# 12. Final dual-track roadmap

```text
FABRIC0.15
RESEARCH CANDIDATE CLOSED
exact-double 103/103
HEAD before roadmap freeze:
381e2216661d07aed898f3a2bff0b9590fb5b4f5
         │
         ▼
DUAL-TRACK ROADMAP FREEZE
         │
    ┌────┴─────────────────────────────┐
    │                                  │
    ▼                                  ▼
PHYSICAL CORE                     FABRIC-BAKE
FABRIC0.x                         B0.x
    │                                  │
    ▼                                  ▼
FABRIC0.16                         B0.0
GENERAL CONVEX                     BAKE FOUNDATION
MULTIPOINT MCP                     CONTRACTS
    │                                  │
    │                                  ├ source frontier
    │                                  ├ authority envelope
    │                                  ├ acausal boundary
    │                                  ├ stale = non-executable
    │                                  ├ validity/error contracts
    │                                  ├ refinement guards contract
    │                                  ├ reconstruction binding
    │                                  └ NO_SAFE_BAKE
    │                                  │
    │                                  ▼
    │                                B0.1
    │                        EXACT BOUNDARY REDUCTION
    │                                  │
    │                                  ▼
    │                                B0.2
    │                     STRUCTURAL AGGREGATE BAKE
    │                      + REFINEMENT GUARDS
    │                      + LOCAL UNBAKE
    │                                  │
    ├──────────── BRIDGE-1 ────────────┤
    │                                  │
    ▼                                  ▼
0.16 RESEARCH                    B0.3
CHECKPOINT CLOSED          CONTACT / WRENCH BAKE
                                   │
                         ┌─────────┴─────────┐
                         ▼                   ▼
                       B0.4                B0.5
                  DYNAMIC ROM          HYBRID BAKE
                                       LAZY MODES
                         │                   │
                         └─────────┬─────────┘
                                   ▼
                                BRIDGE-2
                                   │
                                   ▼
                                B0.6
                     ADAPTIVE PHYSICAL FIDELITY
                          BAKE / UNBAKE
                                   │
                                   ▼
                                BRIDGE-3
                                   │
                                   ▼
                                B0.7
                      UNSEEN MACHINE SCALE
                                   │
              PHYSICAL CORE ───────┤
                                   ▼
                                FABRIC1
```

Existing FABRIC0.x numbering is preserved.

---

# 13. B0.0 — BAKE FOUNDATION CONTRACTS

## Goal

Prove an architecture in which a physical graph can be replaced by a derived reduced executable representation without creating a second truth or hidden authority transition.

## Contracts

Minimum set:

```text
CanonicalSourceFrontier
AuthorityEnvelope
PhysicalBoundaryContract
BakeSourceBinding
PhysicalBakeArtifact
BakeDependencySet
ValidatedDomain
ErrorEnvelope
RuntimeErrorEstimator contract
ConservationEnvelope
RefinementGuard
BakeInvalidation
ReconstructionDescriptor
BakeStateMapping
BakeCompileResult
```

`BakeCompileResult` explicitly supports:

```text
BAKE_READY
NO_SAFE_BAKE
```

## BakeSourceBinding

Conceptually:

```text
BakeSourceBinding
├── canonical_source_frontier[]
├── frontier_hash
├── authority_envelope
├── dependency_hash
├── fabric_graph_hash
├── fabric_compiler_version
├── boundary_contract_hash
├── bake_policy_hash
└── checksum
```

## Mandatory B0.0 falsification

```text
wrong source revision
→ reject

wrong dependency hash
→ reject

authority rollback/crossing
→ reject / NO_SAFE_BAKE

wrong FABRIC graph/compiler version
→ reject

wrong boundary hash
→ reject

stale physical artifact
→ execution forbidden

validity exit
→ execution forbidden

missing reconstruction binding
→ artifact invalid

uncertifiable guard
→ NO_SAFE_BAKE

canonical mutation
→ exact invalidation
→ old artifact cannot execute
```

## BAKE-BRIDGE-0

B0.0 contains an early lifecycle bridge:

```text
canonical source frontier
→ compile FABRIC graph
→ bind BakeSourceBinding
→ build artifact
→ canonical mutation
→ existing revision/invalidation semantics
→ artifact non-executable
```

This prevents a parallel bake revision universe.

## Predecessor

```text
FABRIC0.15 research candidate closed
+
RL0 provenance/invalidation semantics available
+
Construction canonical ownership rule
```

No FABRIC0.16 dependency.

---

# 14. B0.1 — EXACT BOUNDARY REDUCTION

## Goal

First computational bake on mature linear/acausal FABRIC semantics.

Use:

- Conservation Cells;
- Power Maps;
- linear algebraic relations;
- executable dimensions.

Subsystem:

```text
2–8 external ports
+
100+ internal equations/unknowns
```

Reduction:

```text
well-posed internal block
→ exact elimination / Schur complement
→ small boundary relation
```

## Important scope

B0.1 does **not** claim a generic exact reducer for every FABRIC graph.

Initial accepted domain:

```text
well-posed eliminable linear internal block
```

If singular / gauge-free / ambiguous:

```text
fail closed
→ NO_SAFE_BAKE / diagnostic
```

Future:

- rank-revealing QR;
- nullspace reduction;
- generalized Schur;
- DAE condensation.

## Acceptance

Across multiple boundary excitations:

```text
FULL effort ≈ BAKED effort
FULL flow   ≈ BAKED flow
FULL power  ≈ BAKED power
```

Also test where mathematically applicable:

- dimensions;
- rank/nullspace;
- symmetry/reciprocity;
- passivity/conservation;
- deterministic hash.

Exact case target: machine-precision scale equivalence.

Mandatory lifecycle:

```text
internal canonical topology mutation
→ source/dependency revision changes
→ old bake execution forbidden
→ deterministic rebuild
```

## Dependency

Already unblocked by FABRIC0.3–0.5. Does not wait for 0.16.

---

# 15. B0.2 — STRUCTURAL AGGREGATE BAKE + REFINEMENT GUARDS + LOCAL UNBAKE

## Goal

```text
hundreds of rigidly connected parts
→ one reduced rigid physical aggregate
```

Canonical Construction still retains every part/bond.

## Preserve

- total mass;
- center of mass;
- full inertia tensor;
- aggregate frame;
- linear momentum;
- angular momentum;
- boundary anchor transforms;
- boundary Jacobians;
- collision/support envelope;
- deterministic reconstruction mapping.

## Mandatory RefinementGuard

Artifact must retain enough conservative information to know when hidden detail must return.

Examples:

```text
region load envelope
bond-family capacity envelope
stress/wrench bound
uncertainty margin
guard → canonical region mapping
```

## Local unbake acceptance

```text
500-part baked construct
        ↓
localized load/damage/edit approaches guard
        ↓
only affected region unbakes
        ↓
bond changes/breaks
        ↓
topology splits
        ↓
new bake candidates
```

Audit:

- mass;
- linear momentum;
- angular momentum;
- pose/velocity continuity;
- no duplicate event;
- no hidden failure;
- bounded unbake region.

A design that always unbakes the entire 500-part construct for a local event does not close B0.2.

## Dependency

Full 6DOF predecessor is already available from FABRIC0.14.

B0.2 does not require FABRIC0.16 general convex contact for its rigid aggregate core.

---

# 16. BRIDGE-1 — Physical source lifecycle + bake reconstruction

Gate after B0.1/B0.2 foundation.

Must demonstrate:

```text
canonical state
→ FABRIC graph
→ bake
→ execute
→ invalidate
→ deterministic rebuild/unbake
```

with:

- exact source frontier;
- authority envelope;
- deterministic artifact identity;
- no stale execution;
- no new truth;
- reconstruction from canonical source;
- no duplicated mutation/event ownership.

BRIDGE-1 does not require contact/wrench bake.

---

# 17. B0.3 — CONTACT / WRENCH BAKE

## Dependency rule

Prototype experiments may use FABRIC0.15.

**Final B0.3 acceptance is blocked on FABRIC0.16**, because the intended claim requires:

- arbitrary convex support;
- persistent multipoint manifolds;
- stronger graph-wide complementarity semantics.

## Goal

```text
many contact manifold points
→ effective 6DOF boundary support model
```

Do not preserve arbitrary internal lambda split.

Preserve boundary admissible wrench behavior:

```text
W =
(Fx,Fy,Fz,Mx,My,Mz)
```

including:

- support limits;
- friction limits;
- tipping;
- lift-off;
- net force;
- net torque;
- slip threshold;
- energy dissipation;
- contact-loss event.

Acceptance compares FULL vs BAKED boundary observables, not pointwise redundant contact reactions.

---

# 18. B0.4 — DYNAMIC STATE REDUCTION / ROM

## Goal

Reduce complex coupled subsystem:

```text
storage
feedback
electrical/mechanical coupling
thermal state
physical controller-like feedback
```

Example:

```text
FULL 500–1000 states/equations
→
REDUCED 5–30 states
```

Priority methods:

1. exact elimination;
2. linear reduction;
3. modal reduction;
4. balanced truncation / moment matching where appropriate;
5. physics/passivity preserving ROM;
6. piecewise/local nonlinear ROM.

Do not begin with neural surrogate.

## Correctness emphasis

Prefer:

```text
small boundary error
+
passivity/conservation structure
+
no invented energy
```

over merely a low average regression error.

B0.4 requires explicit:

- ValidatedDomain;
- ErrorEnvelope;
- RuntimeErrorEstimator;
- RefinementGuard;
- NO_SAFE_BAKE path.

---

# 19. B0.5 — HYBRID MODE BAKE + LAZY MODE COMPILATION

Use existing FABRIC semantics:

```text
FLOW
JUMP
TOPOLOGY TRANSACTION
complementarity
hybrid DAE
```

Derived modes:

```text
reduced equations
validity region
transition guards
reset map
source topology binding
```

Forbidden shortcut:

```text
Motor
Gearbox
Clutch
Valve
```

as device-specific kernel classes.

Mode identity derives from physical topology/active relations.

## Lazy modes

Do not precompile exponential `2^N` active-set space.

```text
encounter stable mode
→ compile/reduce
→ validate
→ cache

new mode
→ compile when encountered
```

Unknown/uncertifiable mode:

```text
FULL / NO_SAFE_BAKE
```

---

# 20. BRIDGE-2 — Mixed FULL ↔ BAKED physical graph

After B0.3/B0.4 maturity:

```text
FULL subsystem
       ↕
BAKED subsystem
       ↕
FULL subsystem
```

Example:

```text
FULL contact
↕
BAKED transmission/ROM
↕
FULL electromechanical subsystem
```

Gate checks:

- acausal boundary compatibility;
- dimensions;
- effort/flow sign/frame;
- power conservation/error accounting;
- event ordering;
- no duplicate state ownership;
- no hidden authority crossing;
- deterministic replay.

---

# 21. B0.6 — ADAPTIVE PHYSICAL FIDELITY + BAKE/UNBAKE

FABRIC-BAKE does **not** become the global world scheduler.

It reports what is physically safe:

```text
current_fidelity
minimum_safe_fidelity
estimated_cost
error_bound
validity_margin
pending_refinement_guards
causal_dependencies
```

Possible physical fidelity levels:

```text
L0 FULL_FABRIC
L1 STRUCTURAL_BAKE
L2 DYNAMIC_ROM
L3 HYBRID_BAKE
L4 DORMANT
```

Global Simulation Scheduler decides resource allocation.

BAKE determines:

> Which fidelity levels are physically admissible now?

This separation prevents physics correctness from being dictated by a resource heuristic.

## Triggers toward more detail

- interaction;
- edit;
- damage;
- topology mutation;
- high stress/load guard;
- large energy flow;
- unexpected event;
- validity boundary;
- error-bound growth;
- causally important downstream dependency.

## Triggers toward cheaper representation

- stable mode;
- low error;
- large validity margin;
- sleeping island;
- low internal causal activity;
- long-lived stable topology.

Distance alone is insufficient.

---

# 22. Causal LOD relation

DWS architecture already contains the concept that causal detail differs from render/storage detail, but there is no mature global executable Causal LOD contract equivalent to RL0.

Therefore B0.6 should **expose safe physical fidelity**, not seize global scheduling ownership.

Later integration:

```text
FABRIC-BAKE
determines physical-safe fidelity set
        +
Global Simulation Scheduler
allocates runtime budget
        ↓
Causal LOD execution policy
```

Example:

```text
remote power plant

Presentation:
IMPOSTOR

Physical fidelity:
DYNAMIC_ROM

Reason:
causally powers local city
```

Presentation and physical fidelity are orthogonal axes.

---

# 23. BRIDGE-3 — FULL → BAKE → validity/guard event → UNBAKE → FULL

Required cycle:

```text
FULL
 ↓
BAKE
 ↓
REDUCED
 ↓
validity exit / guard / causal event
 ↓
LOCAL UNBAKE or FULL refinement
 ↓
FULL
```

Must prove absence of:

- fake energy;
- fake momentum;
- state discontinuity beyond declared reconstruction envelope;
- duplicate events;
- lost events;
- hidden damage;
- stale execution;
- nondeterministic replay.

This is the decisive runtime lifecycle gate.

---

# 24. B0.7 — UNSEEN MACHINE SCALE CHALLENGE

Before challenge, generic kernel and reduction mechanisms are frozen.

Build unseen systems only from generic FABRIC primitives, e.g.:

- electromechanical governor;
- generator-regulator;
- variable transmission;
- hydraulic automatic mechanism;
- thermal-feedback power subsystem;
- unnamed strange machine.

Forbidden:

- adding device-specific solver code to pass fixture;
- hand-written bake class per machine.

Each machine:

```text
FULL FABRIC
→
automatic/semi-automatic BAKE
→
boundary equivalence + cost comparison
```

## Physical metrics

- effort/flow;
- power;
- energy;
- momentum where applicable;
- events;
- failure point;
- mode transitions;
- validity/refinement behavior.

## Computational metrics

- states;
- equations;
- solver iterations;
- CPU;
- memory;
- event work;
- bake/rebuild/unbake cost.

B0.7 closes only if correctness and meaningful complexity reduction coexist.

---

# 25. Parallelism matrix

## Can proceed immediately in parallel with FABRIC0.16

```text
B0.0 Foundation Contracts
B0.1 Exact Boundary Reduction
B0.2 Structural Aggregate + Guards + Local Unbake
B0.4 early ROM research
B0.5 contract/design exploration
```

## Physically blocked

### B0.3 FINAL acceptance

Requires:

```text
FABRIC0.16 general convex
+
persistent multipoint manifold
+
stronger complementarity
```

### Advanced hybrid/contact bake scenarios

May require later physical-core checkpoints if they depend on physics not yet executable.

### Cross-authority bake

Explicitly blocked pending a separate distributed execution protocol.

---

# 26. Git branch discipline

Shared roadmap freeze occurs on current FABRIC research history after closed 0.15.

Then fork:

```text
dual-track-roadmap-freeze HEAD
        │
        ├── research/fabric0-compositional-world-fabric-r1
        │       ↓
        │    FABRIC0.16
        │
        └── research/fabric-bake0-reducible-world-fabric-r1
                ↓
             B0.0
```

Physical-core experimental commits do not leak into BAKE merely because they are newer.

BAKE updates from physical-core are explicit predecessor/bridge decisions.

---

# 27. FABRIC1 target

FABRIC1 definition of done becomes:

```text
FABRIC1
=
Constructible
+
Composable
+
Hybrid
+
Persistent
+
Reducible
+
Refinable
+
Deterministic
+
Causally scalable
```

Meaning:

> Complex behavior can emerge from generic composition, and the runtime can safely manage the computational cost of that complexity without losing causally significant boundary behavior or the ability to reconstruct local detail.

---

# 28. Non-claims of this roadmap freeze

This document does not claim that:

- any B0.x executable checkpoint is already implemented;
- arbitrary subsystem is reducible;
- error certification for nonlinear/hybrid systems is solved;
- cross-authority bake is supported;
- local unbake guards are already implemented;
- Representation LOD is a physical bake system;
- distance defines physical fidelity;
- ML surrogate is required or preferred;
- physical-core development stops while BAKE is developed;
- FABRIC0.15 is production accepted.

Current BAKE status after this freeze:

```text
FABRIC-BAKE
B0.0 = NEXT EXECUTABLE CHECKPOINT
```


## FABRIC0.16 prerequisite status for B0.3

Physical Core prerequisite previously written as:

```text
B0.3 FINAL:
FABRIC0.16 general convex multipoint contact
+ stronger graph complementarity
```

is now satisfied at the FABRIC0.16 exact-tested executable boundary:

`3307d553c1c3c79cd9c15a5c565af7fef3f0400c`.

Status:

```text
FABRIC0.16 prerequisite for B0.3 FINAL  ✅ SATISFIED
B0.3 itself                              ⛔ NOT AUTO-CLOSED
```

This only unlocks the physical-core dependency. B0.3 must still pass its own BAKE contracts, boundary-observable correctness, refinement/unbake and authority gates.


## Post-freeze Physical Core successor — FABRIC0.17

The historical dual-track freeze above is preserved as historical evidence. Physical Core did not stop after FABRIC0.16.

```text
FABRIC0.16
GENERAL CONVEX MULTIPOINT MCP
RESEARCH CANDIDATE CLOSED
        ↓
FABRIC0.17
SIMULTANEOUS MULTI-IMPACT
+
GENERALIZED CONTACT WRENCH
        ↓
future physical-core checkpoints
```

FABRIC0.17 slices:

```text
A — Simultaneous Impact Event Set
B — Coupled Simultaneous Impact Solve
C — Generalized Contact Wrench
D — Unified Multi-Impact Wrench Trajectory
```

0.17 is independent of B0.2 structural bake work and may proceed in parallel.

Current 0.17-A executable head: `9139a213ccee64d3bf1bb95ea32170027421b3b3`.

This does not change the already satisfied FABRIC0.16 prerequisite for B0.3 FINAL. Future B0.x features that depend on simultaneous impact or rolling/torsional contact must name FABRIC0.17 explicitly rather than silently inheriting it.
