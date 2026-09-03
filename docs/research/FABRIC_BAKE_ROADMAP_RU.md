# FABRIC-BAKE — Roadmap Reducible World Fabric

**Статус:** dual-track research roadmap freeze после FABRIC0.15.  
**Physical-core predecessor:** FABRIC0.15 — **RESEARCH CANDIDATE CLOSED / EXACT DOUBLE PASS / DRAFT REVIEW CANDIDATE**.  
**Physical-core predecessor HEAD before roadmap freeze:** `381e2216661d07aed898f3a2bff0b9590fb5b4f5`.  
**FABRIC0.15 exact-tested executable commit:** `a8ff0d7360b4bba0f1b3e164f8c040d73622b1ee`.  
**Parallel research line:** `FABRIC-BAKE B0.x`.  
**Recommended implementation branch:** `research/fabric-bake0-reducible-world-fabric-r1`.

## Current executable frontier — FABRIC.SYNC4

```text
B0.4 Dynamic ROM                         ✅ CLOSED
B0.5-P0                                 ✅ CLOSED
FABRIC.SYNC3                            ✅ CLOSED
B0.5-A Executable Hybrid Bake           ✅ CLOSED
COMPLEX0 Breakable Structure            ✅ CLOSED
COMPLEX0-PERF1 B0.2-E Scaling           ✅ CLOSED
COMPLEX0 @ 2000 exact double            ✅ CLOSED
COMPLEX1A Powered Fence FULL baseline   ✅ CLOSED
FABRIC.SYNC4 POST-B0.5-A                ✅ CLOSED

FABRIC0.19                              ⛔ NOT AUTHORIZED
BRIDGE-2 executable research            ✅ AUTHORIZED
PRODUCTION                              ⛔ NOT ACCEPTED

NEXT:
BRIDGE-2 executable
  ├─ BRIDGE-2-A Mixed Representation Ownership Contract ✅ IMPLEMENTED CANDIDATE
  ├─ BRIDGE-2-B Executable Mixed Subject ✅ IMPLEMENTED CANDIDATE
  ├─ BRIDGE-2-C Cross-Representation Event Routing ← NEXT
  ├─ BRIDGE-2-D Invalidation / Refinement Ordering
  ├─ BRIDGE-2-E Deterministic Mixed Replay
  └─ BRIDGE-2-F / COMPLEX1B Powered Fence Mixed
→ CX2 Redundant Power Fence
```

Exact SYNC4 implementation subject:

```text
HEAD:
5f1d2dc997ecce5cf1f188a6f65d7b1c2ba0ecd9

TREE:
d094c969a4252eb77f697d142271b9f74c3f1589
```

The 2000-part COMPLEX0 exact closure proves canonical break → invalidation →
stale rejection → topology split → two fresh bake artifacts → runtime →
reconstruction with fragments 993 + 1007 and ~2e-14 maximum reconstructed
state error. PERF1 measures B0.2-E topology transaction compilation at 8.647 s
for 2000 parts and freezes a <60 s budget plus an <=8x growth bound for 4x part
growth.

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

**Final B0.3 acceptance is blocked on FABRIC0.18**, because the intended claim now requires the complete closed persistent-contact wrench boundary:

- arbitrary convex support and persistent multipoint manifolds;
- graph-wide normal/wrench coupling;
- generalized tangent/rolling/torsional wrench limits;
- persistent support redistribution;
- localized stick→slide / roll / spin transitions;
- support-loss/contact-separation event semantics;
- passive persistent-contact trajectory evidence.

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

# 18. B0.4 — DYNAMIC STATE REDUCTION / ROM — AUTHORIZED BY FABRIC.SYNC2

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

# 19. B0.5 — HYBRID MODE BAKE + LAZY MODE COMPILATION — P0 CONTRACT/PREFLIGHT AUTHORIZED

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

# 20. BRIDGE-2 — Mixed FULL ↔ BAKED physical graph — EXECUTABLE NOT YET AUTHORIZED

After B0.3/B0.4 maturity.

FABRIC.SYNC2 refines this entry gate:

```text
B0.3 CLOSED
+
B0.4 CLOSED
+
B0.5 P0 CLOSED
+
generic B0.5 mode candidate consumes B0.4 artifact interface
+
mixed state/authority ownership explicit
```

Until then BRIDGE-2 executable work is blocked.

Target composition:

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
FABRIC0.18
PERSISTENT CONTACT WRENCH DYNAMICS
RESEARCH CANDIDATE CLOSED
```

This supersedes the older 0.16-only final-acceptance gate.

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

## B0.0 closure boundary — 2026-08-31

```text
implementation HEAD:
072d313e1ecf8434987245a8edc4f9d959a4cf80

implementation TREE:
4b1dfece0b38f3fae7053aeba363544988016b76

Project Control:
33319536344 = SUCCESS

fresh exact-dependency verifier:
Godot 4.7.1.stable.double.custom_build.a13da4feb
FABRIC-BAKE B0.0 Acceptance = PASS (33/33)
Playground = PASS
```

Verifier был создан в новой файловой области и использовал exact GitHub blobs implementation HEAD для всех B0.0 executable files и всех пяти predecessor dependency files, реально загружаемых acceptance-сценарием. Dependency blob identity была проверена до запуска.

Закрытая квалификация:

```text
FABRIC-BAKE B0.0
RESEARCH CHECKPOINT CLOSED
EXACT-HEAD DOUBLE PASS
PROJECT CONTROL PASS
PRODUCTION ACCEPTANCE NOT CLAIMED
```

B0.0 closure remains immutable. B0.1 was implemented on its dedicated successor branch; Physical Core remains an independent line.


---

## B0.1 closure boundary — 2026-08-31

Dedicated branch:

```text
research/fabric-bake0-1-exact-boundary-reduction-r1
```

Exact executable subject:

```text
implementation HEAD:
e854185f501cfc2658d5d1c5430be4eed3b070ee

implementation TREE:
0114ed1973e7bcd1d6225381d07f1ad1ade6b9a0

direct parent / B0.0 closure:
d389b8ed72ffbed8949279b42089da3687125a90

ahead from B0.0 closure:
1 implementation commit
```

Implemented scope:

```text
4 boundary ports
128 internal variables
132 full equations
        ↓
exact deterministic Schur elimination
        ↓
4 boundary equations

internal rank = 128
reduced rank  = 3
arithmetic-work proxy reduction = 1089x
```

The implementation uses deterministic partial-pivot LU and repeated solves, not an
explicit inverse. Singular internal blocks, uncertifiable passive/reciprocal scope,
undersized accepted-domain candidates and foreign reduction descriptors fail closed.

The reduced descriptor is content-bound to the existing B0.0 `PhysicalBakeArtifact`;
runtime still passes through the B0.0 source/authority/dependency/validity/invalidation
execution gate. B0.1 therefore does not create a second canonical truth or a parallel
artifact lifecycle.

### Exact source identity

GitHub-hosted source-export run:

```text
33348975423 = SUCCESS

HEAD:
e854185f501cfc2658d5d1c5430be4eed3b070ee

TREE:
0114ed1973e7bcd1d6225381d07f1ad1ade6b9a0

exact git-archive SHA-256:
548d832c6d042227c3b0df85b991519e1ae2702a7ef71770bdaa6f226ba3c0d1
```

### Exact-head double pass

Two separate fresh filesystem extractions of that exact archive were imported and
executed with the pinned double build:

```text
Godot:
4.7.1.stable.double.custom_build.a13da4feb

binary SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7

PASS #1:
B0.0 Acceptance = PASS (33)
B0.1 Acceptance = PASS (64)
B0.1 Playground = PASS

PASS #2:
fresh extraction
fresh .godot/import state
B0.0 Acceptance = PASS (33)
B0.1 Acceptance = PASS (64)
B0.1 Playground = PASS
```

Both passes produced the same derived identities:

```text
descriptor:
92c62af79e1c75889c846084711c6752e92489db1d1aa27a5f13aa832bbc00f6

artifact:
a04a380833bf0f62ae0fc8f33da2cbc66d7520dd78fea193b34d9f21f6cd0300

max flow delta:
9e-14

max power delta:
1.42e-12
```

Post-run tracked-byte audit:

```text
tracked files checked = 5025
missing = 0
changed = 0
```

### Project Control

Exact implementation HEAD/TREE was independently checked by GitHub-hosted control run:

```text
33349147651 = SUCCESS
```

Both standard and directional Project Control commands completed successfully. The
global project dashboard was YELLOW because of unrelated active frontiers, including an
ECO advisory RED; B0.1 closure does not reinterpret those other programs as GREEN.

### Final B0.1 qualification

```text
FABRIC-BAKE B0.1
RESEARCH CHECKPOINT CLOSED
EXACT-HEAD DOUBLE PASS
PROJECT CONTROL NON-BLOCKING
PRODUCTION ACCEPTANCE NOT CLAIMED
```

The queued self-hosted Windows run `33348754783` is additional cross-platform evidence
and is not used as a prerequisite for this research closure.

Next checkpoint:

```text
B0.2
STRUCTURAL AGGREGATE BAKE
+ REFINEMENT GUARDS
+ LOCAL UNBAKE
```

Physical Core / FABRIC0.16 continues independently.


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

## B0.2 final closure status — 2026-08-31

```text
B0.2-A  STRUCTURAL AGGREGATE COMPILER       ✅ CLOSED
B0.2-B  EXACT RECONSTRUCTION MAPPING        ✅ CLOSED
B0.2-C  REFINEMENT GUARD FIELD              ✅ CLOSED / EXACT-HEAD DOUBLE PASS
B0.2-D  BOUNDED LOCAL UNBAKE                ✅ CLOSED / EXACT-HEAD DOUBLE PASS
B0.2-E  TOPOLOGY SPLIT / RE-BAKE            ✅ CLOSED / EXACT-HEAD DOUBLE PASS

B0.2 checkpoint                              ✅ RESEARCH CHECKPOINT CLOSED
PRODUCTION ACCEPTANCE                        NOT CLAIMED
```

Final executable slice boundaries:

```text
B0.2-A/B
HEAD  b417066a048d3c85bf766eb239d4111335c66602
TREE  da87230e3dd247d2fd662bf5f8ec3926c055f4d3

B0.2-C
HEAD  ffd53302d891b4d64b88589c434c56e76aef1eaa
TREE  754bdd8a38246afe7bbd85eba74615ef7f0bb3e7

B0.2-D
HEAD  8da6ec6b7c2983b127f4c0607edeb9be900825c3
TREE  285240dcc8a08a3a676897792659dfcad43bf410

B0.2-E / FINAL B0.2 EXECUTABLE SUBJECT
HEAD  91a2f79bf6738efefa342589c44e4a0f0a6960d6
TREE  610288ea119e9f7508f711ce5b0468b272a9b489
```

Final E exact-head evidence:

```text
fresh pass #1:
B0.0 33 / B0.1 64 / A-B 76 / C 118 / D 609 / E 2580 — PASS

fresh pass #2:
same deterministic summary — PASS

tracked-byte audit:
5064 checked
0 missing
0 changed
in both passes

post-split:
257 + 243 parts
3 stale reduced pieces invalidated
2 fresh BAKE_READY artifacts
6500 -> 286 -> 26 DOF
250x post-split reduction
```

The B0.2 mandatory lifecycle is now demonstrated end-to-end:

```text
canonical structure
→ bake
→ exact reconstruction
→ conservative guard
→ bounded local unbake
→ canonical topology break
→ split
→ stale invalidation
→ deterministic re-bake
```

Current certified scope remains the explicit R1 connected rigid-tree domain. Unsupported
cases remain fail-closed.

## Next FABRIC-BAKE roadmap gate

```text
BRIDGE-1
PHYSICAL SOURCE LIFECYCLE + BAKE RECONSTRUCTION
```

BRIDGE-1 is the roadmap gate immediately after the B0.1/B0.2 foundation. B0.3
Contact/Wrench Bake follows under its own Physical Core dependency rule.

Windows remains `PASS_BY_POLICY / NON-GATING`.


---

## Physical Core ↔ FABRIC-BAKE synchronization review — 2026-08-31

Reviewed exact boundaries:

```text
Physical Core:
FABRIC0.18 closure HEAD
b9f4a11cb7c31e47884d12eaad2985811e0b6563

FABRIC0.18 exact physics
e079565b4b9cd0dae530ff5042f057ce8fa0d0cc

FABRIC-BAKE B0.2 closure
f45801fc41ec4ddd067cc994b6de84a48cb88da1

B0.2 final executable
91a2f79bf6738efefa342589c44e4a0f0a6960d6

BRIDGE-1 design
56d316283ea34ccb70fc97f97a7493a60b577b94
```

The branches intentionally diverge from common fork
`962b9c1bbf7f04c7853f1fb0e36480cf54f3250d`; no implicit physics merge is required.

Synchronization decisions:

```text
Construction/Matter source frontier     unchanged
FABRIC as canonical source              FORBIDDEN
BRIDGE-1 min structural dependency      FABRIC0.16
Physical Core reviewed frontier         FABRIC0.18
persistent contact history in bake      FORBIDDEN AS TRUTH
mode transition → source revision       NO
canonical mutation → bake invalidation  YES
compiler/graph mismatch → execution     FORBIDDEN
B0.3 final predecessor                  FABRIC0.18
```

BRIDGE-1 is now design-synchronized and implementation-unblocked, but it is not yet an
executable or closed checkpoint.

Updated integration map:

```text
PHYSICAL CORE                              FABRIC-BAKE

FABRIC0.18 ✅ CLOSED                  B0.2 ✅ CLOSED
       │                                    │
       └──────────── SYNC REVIEW ✅ ─────────┤
                                            │
                                      BRIDGE-1
                                      🔵 IMPLEMENT NEXT
                                            │
                                            ▼
                                          B0.3
                               CONTACT / WRENCH BAKE
                               final gate = FABRIC0.18
```

No implicit FABRIC0.19 dependency is created by this review.


---

## BRIDGE-1 executable candidate — 2026-08-31

```text
BRIDGE-1
PHYSICAL SOURCE LIFECYCLE + BAKE RECONSTRUCTION

exact executable:
e128cf9d49f84691b8a5428c97ab7acd53b92d90

TREE:
f0deeb1848c6570d12364976f4fd07007657029d

146/146 PASS
7/7 exact remote bytes
Project Control #1917 SUCCESS
```

Executable proof covers canonical source binding, derived graph/bake emission, execution
gating, canonical invalidation, immediate stale rejection, exact 500-part kinematic
reconstruction, same-topology rebuild, deterministic FULL fallback and fresh re-derivation
of transient contact history.

B0.2-D `609/609` and B0.2-E `2580/2580` remain green in the exact predecessor
filesystem.

Current state:

```text
B0.2       ✅ CLOSED
SYNC REVIEW✅ PASS
BRIDGE-1   🟢 CLOSURE-READY
B0.3       ⚪ NEXT AFTER BRIDGE-1 CLOSURE
```

B0.3 final acceptance predecessor remains FABRIC0.18.


---

## BRIDGE-1 final closure status — 2026-08-31

```text
B0.2        ✅ RESEARCH CHECKPOINT CLOSED
SYNC REVIEW ✅ PASS
BRIDGE-1    ✅ RESEARCH INTEGRATION CHECKPOINT CLOSED
B0.3        ⚪ NEXT
```

BRIDGE-1 exact executable:

`e128cf9d49f84691b8a5428c97ab7acd53b92d90`

TREE:

`f0deeb1848c6570d12364976f4fd07007657029d`

Acceptance/control:

```text
BRIDGE-1 146/146 PASS
7/7 exact remote bytes
B0.2-D 609/609 PASS
B0.2-E 2580/2580 PASS

Project Control #1917 SUCCESS — executable
Project Control #1918 SUCCESS — evidence carrier
```

BRIDGE-1 is research integration closure only; production acceptance is not claimed.

Next:

`B0.3 CONTACT / WRENCH BAKE`.

Final B0.3 acceptance remains gated by closed FABRIC0.18.


---

## FABRIC-BAKE B0.3 closure boundary — 2026-08-31

```text
branch:
research/fabric-bake0-3-contact-wrench-r1

exact executable:
acc72c1fb216bea56bc44547bc3e1eec7a37af08

TREE:
f8247e39494c00d2d065ed4c4b121e103f32ab0a

Project Control #1928:
SUCCESS

focused:
319/319 PASS

FULL contact members:
441

BAKED generators:
4

reduction:
110.25x

FULL-vs-BAKED support error:
0
```

B0.3 preserves the accepted-domain 6D boundary admissible wrench support function, not pointwise redundant contact reaction history. Internal lambda, warm start, contact age and mode history remain transient and are discarded/re-derived after reconstruction.

Out-of-domain geometry fails closed with `NO_SAFE_BAKE`. Support loss and directional wrench-capacity exits are explicit event/refinement surfaces.

Evidence carrier:

```text
c303b5c44621cae1dd073b12aef2de037fec8a74
Project Control #1930 = SUCCESS
```

Final qualification:

```text
FABRIC-BAKE B0.3
RESEARCH CHECKPOINT CLOSED
EXACT DOUBLE PASS
REMOTE BYTE AUDIT PASS
PROJECT CONTROL PASS
PRODUCTION ACCEPTANCE NOT CLAIMED
```

Runtime/test bytes remain frozen at executable HEAD `acc72c1fb216bea56bc44547bc3e1eec7a37af08`.

Next research stages are B0.4 Dynamic ROM and B0.5 Hybrid Bake; BRIDGE-2 follows their maturity.


---

# 31. FABRIC.SYNC2 — POST-B0.3 DEVELOPMENT AUTHORIZATION — 2026-09-01

Formal review branch:

```text
research/fabric-sync2-post-b0-3-development-review-r1
```

Formal base:

```text
B0.3 closure:
9575a63d6aeb4c455f8beade7588505e600c12d6

B0.3 exact executable:
acc72c1fb216bea56bc44547bc3e1eec7a37af08
```

Additional tangible evidence:

```text
CONSTRUCT0 exact:
afcd564b631a2f48283dfefef17f4d6542f558a3

CONSTRUCT0 closure:
1b1e237a4dfd3706d5375023d7832f5dc42687d1

acceptance:
325/325 PASS
```

SYNC-2 concludes that the dominant remaining reduction wall is dynamic state count,
not a currently demonstrated missing contact primitive.

Decision:

```text
PHYSICAL CORE:
FABRIC0.18 remains frozen

FABRIC0.19:
NOT AUTHORIZED

B0.4 DYNAMIC ROM:
EXECUTABLE RESEARCH AUTHORIZED
PRIMARY NEXT EXECUTABLE

authorized branch:
research/fabric-bake0-4-dynamic-rom-r1

initial reference target:
FULL >= 512 dynamic states
REDUCED <= 24 states
reduction >= 20x
relative boundary response error <= 1e-3
passivity / no invented energy required
ValidatedDomain / ErrorEnvelope / RuntimeErrorEstimator / RefinementGuard required

B0.5 HYBRID BAKE:
P0 CONTRACT / PREFLIGHT AUTHORIZED

authorized branch:
research/fabric-bake0-5-hybrid-bake-preflight-r1

B0.5 executable:
NOT AUTHORIZED until stable B0.4 mode-local ROM interface

BRIDGE-2 executable:
NOT AUTHORIZED
```

B0.5 P0 may define only generic mode/cache/transition/reset/fallback contracts over
existing FABRIC FLOW/JUMP/TOPOLOGY TRANSACTION/complementarity/hybrid-DAE semantics.

Unknown or uncertifiable dynamic/hybrid cases retain the legal path:

```text
FULL
or
NO_SAFE_BAKE
```

A later FABRIC0.19 proposal requires a concrete downstream falsifier showing that a
missing generic Physical Core primitive makes the accepted B0.4/B0.5/BRIDGE-2 goal
impossible, not merely slower in FULL mode.

Detailed contracts:

- `docs/research/FABRIC_SYNC2_POST_B0_3_DEVELOPMENT_REVIEW_RU.md`;
- `docs/research/FABRIC_BAKE_B0_4_DYNAMIC_ROM_AUTHORIZATION_RU.md`;
- `docs/research/FABRIC_BAKE_B0_5_HYBRID_BAKE_PREFLIGHT_RU.md`;
- `validation/fabric_sync2_authorization.v1.json`.

Next synchronization:

```text
B0.4 CLOSED
+
B0.5 P0 CLOSED
        ↓
FABRIC synchronization review
        ↓
B0.5 executable authorization?
FABRIC0.19 necessity?
BRIDGE-2 executable authorization?
```


---

## FABRIC-BAKE B0.4-A closure boundary — 2026-09-01

```text
B0.4-A
DYNAMIC MODEL / PORT CONTRACT
✅ RESEARCH CHECKPOINT CLOSED

branch:
research/fabric-bake0-4-dynamic-rom-r1

exact executable HEAD:
1fbfffe30f5758a1bbb3c65db23edf06ecf3dae4

TREE:
79bedac6b6668ffcf29629238a5c055fb55d5f3c
```

B0.4-A freezes the FULL reference side of Dynamic ROM:

```text
CanonicalSourceFrontier
+
AuthorityEnvelope
+
DependencySet
+
PhysicalBoundaryContract
        ↓
512-state generic passive dynamic model
        ↓
deterministic FULL reference solver
        ↓
boundary effort / flow / power
+
stored energy
+
physical dissipation
+
numerical dissipation
```

Reference fixture:

```text
512 dynamic states
4 generic effort/flow ports
511 internal dissipative couplings
512 positive shunts
strict structural passivity/stability certificate
```

Exact evidence:

```text
B0.4-A:
609/609 PASS

fresh exact bundle pass #1:
PASS

fresh exact bundle pass #2:
PASS

model identity:
5a75707e8d34bccd24c86ef325ccfb24ca53f5485889cc47fa32dd209490c46f

predecessor + B0.4-A acceptance:
4554/4554 PASS

Project Control:
33517363373 SUCCESS
```

B0.4-A does **not** emit a ROM and does not satisfy the parent B0.4 reduction/error
closure gate.

Current B0.4 state:

```text
B0.4-A DYNAMIC MODEL / PORT CONTRACT     ✅ CLOSED
B0.4-B CERTIFIED REDUCTION               ★ NEXT
B0.4-C RUNTIME ERROR / REFINEMENT        ⚪
B0.4-D RECONSTRUCTION / LIFECYCLE        ⚪

B0.4 parent                              IN PROGRESS
```

Next executable wall:

```text
B0.4-B
CERTIFIED REDUCTION

512 FULL dynamic states
        ↓
structure/passivity-preserving ROM
        ↓
<= 24 reduced states
>= 20x reduction
```

B0.5 P0 may continue in parallel under the SYNC-2 authorization, but B0.5 executable
hybrid reduction remains blocked on a stable B0.4 mode-local ROM artifact interface.

---

## FABRIC-BAKE B0.4 final authoritative closure — 2026-09-03

This section supersedes older intermediate B0.4-A/B/C/D status blocks above.

```text
exact implementation/test HEAD:
e33ac10ac94d8b70f1387d442a3ae9d3801bb08a

TREE:
f3d47eedd42f827a859d1763e8b46762696b99dd

B0.4-A:
609/609 PASS

B0.4-B:
83/83 PASS

B0.4-C:
1533/1533 PASS

B0.4-D:
287/287 PASS

full parent closure regression:
PASS / exit 0

Project Control:
33696130121 SUCCESS

B0.4 DYNAMIC ROM:
✅ CLOSED
```

The final D boundary uses the common FABRIC-BAKE `PhysicalBakeArtifact` architecture
with real `ReconstructionDescriptor` and `StateMapping`; it is not a private ROM
execution artifact path.

Current roadmap:

```text
B0.3 ✅
  ↓
FABRIC.SYNC2 ✅
  ↓
B0.4 DYNAMIC ROM ✅ CLOSED
  +
B0.5-P0 ✅ CLOSED
  ↓
FABRIC.SYNC3 ★ NEXT
```

SYNC-3 must decide executable B0.5 authorization, FABRIC0.19 necessity and BRIDGE-2
executable authorization.

---

## FABRIC.SYNC3 — post-B0.4 + B0.5-P0 authorization — 2026-09-03

Integration parents:

```text
B0.4 closure:
1e8324407f60b4536bf9497e0a7c8a6874ae93ca

B0.5-P0 closure:
d280096e0b64c03ac613e586881e43c816f471f0

integration commit:
91132efab20579fa2e64dc2fb9e0dc074c66179e
```

Decision:

```text
B0.4 DYNAMIC ROM:
✅ CLOSED

B0.5-P0:
✅ CLOSED

B0.5-A EXECUTABLE HYBRID BAKE:
✅ EXECUTABLE RESEARCH AUTHORIZED

FABRIC0.19:
⛔ NOT AUTHORIZED

BRIDGE-2 EXECUTABLE:
⛔ NOT AUTHORIZED

BRIDGE-2 DESIGN/PREFLIGHT:
✅ ALLOWED
```

Current roadmap:

```text
B0.4 ✅ CLOSED
  +
B0.5-P0 ✅ CLOSED
        ↓
FABRIC.SYNC3 ✅
        ↓
B0.5-A EXECUTABLE HYBRID BAKE ★ NEXT
        ↓
B0.5-A CLOSED
        ↓
BRIDGE-2 authorization review
        ↓
BRIDGE-2 executable?
FABRIC0.19 necessity?
```

B0.5-A must consume the common B0.4 PhysicalBakeArtifact interface and prove a
generic two-mode FLOW→JUMP transition with B0.4 StateMapping/ReconstructionDescriptor
handoff, lazy mode-B compilation/cache, exactly-once physical event ownership and
unknown mode-C FULL/NO_SAFE_BAKE fallback.

BRIDGE-2 executable work remains blocked until that falsifier is closed.

## Canonical B0.5-A branch correction

An older parallel `research/fabric-bake0-5-a-executable-hybrid-r1` branch already
existed from the superseded pre-final B0.4 SYNC-3 attempt (PR #464).

It is not the child of this final SYNC-3 closure and is therefore not canonical.

Canonical authorized branch:

```text
research/fabric-bake0-5-a-executable-hybrid-r2

base:
3cf8e6689b8b7d20593f134a8a1eb0ce79db1ca1
(final FABRIC.SYNC3 closure)
```

PR #464 is closed as superseded by PR #473.

---

## FABRIC-BAKE B0.5-A exact closure — 2026-09-03

```text
predecessor:
FABRIC.SYNC3
28fdc16d12ddf1233a82103cb290c831342a3022

exact implementation/test HEAD:
d819fffa0dc86cc09cda0000f20c310aec23c799

TREE:
c92c1ff22c683ba348ac8596d2e6b3212a381b57

B0.5-P0:
63/63 PASS

B0.5-A:
67/67 PASS

closure chain:
PASS / exit 0

Project Control:
33708036538 SUCCESS
```

Current roadmap:

```text
B0.4 Dynamic ROM             ✅ CLOSED
B0.5-P0 contracts/preflight  ✅ CLOSED
FABRIC.SYNC3                 ✅ CLOSED
B0.5-A executable hybrid     ✅ CLOSED
        ↓
POST-B0.5-A FABRIC SYNC ★ NEXT
        ↓
BRIDGE-2 executable authorization?
FABRIC0.19 necessity?
```

The first executable hybrid falsifier now exists:
two generic passive B0.4-backed modes, FABRIC-owned localized JUMP, exact B0.4
ReconstructionDescriptor/StateMapping handoff, lazy mode-B hybrid wrapper/cache,
exact cache replay, stale/unknown fail-closed behavior.

This does not yet authorize BRIDGE-2 executable mixed-representation integration.


---

## COMPLEX SYSTEMS EXPERIMENTAL LADDER — post-B0.5-A insertion

Detailed stand plan:

docs/research/FABRIC_BAKE_COMPLEX_SYSTEMS_EXPERIMENTAL_LADDER_RU.md

The roadmap now explicitly includes executable experimental stands. The purpose is to
validate not only individual reduction primitives but progressively more complex systems
with physical destruction, functional dependencies, mixed fidelity and local refinement.

### Updated path

~~~text
B0.4 Dynamic ROM             ✅ CLOSED
B0.5-P0 contracts/preflight  ✅ CLOSED
FABRIC.SYNC3                 ✅ CLOSED
B0.5-A executable hybrid     ✅ CLOSED
        ↓
┌────────────────────────────────────────────┐
│ ★ COMPLEX0 — BREAKABLE STRUCTURE LAB ★    │
│ ★ COMPLEX1A — POWERED FENCE FULL ★        │
└────────────────────────────────────────────┘
        ↓
══════════════════════════════════════════════
★ POST-B0.5-A FABRIC SYNC — NEXT ★
══════════════════════════════════════════════
        │
        ├── BRIDGE-2 executable authorization?
        └── FABRIC0.19 necessity?
        │
        ▼
BRIDGE-2 executable path
        ↓
┌────────────────────────────────────────────┐
│ ★ COMPLEX1B — POWERED FENCE MIXED ★       │
│ ★ CX2 — REDUNDANT POWER FENCE ★           │
└────────────────────────────────────────────┘
        ↓
BRIDGE-2 CLOSED
        ↓
┌────────────────────────────────────────────┐
│ ★ COMPLEX2 — MODULAR MACHINE LAB ★        │
│ FULL + STRUCTURAL + CONTACT + ROM + HYBRID │
└────────────────────────────────────────────┘
        ↓
B0.6 ADAPTIVE PHYSICAL FIDELITY
        +
BRIDGE-3 FULL → BAKE → GUARD → UNBAKE → FULL
        ↓
┌────────────────────────────────────────────┐
│ ★ COMPLEX3 — ADAPTIVE DAMAGE LAB ★        │
│ ★ CX5 — LARGE POWERED STRUCTURE ★         │
└────────────────────────────────────────────┘
        ↓
B0.7 UNSEEN MACHINE SCALE CHALLENGE
        ↓
┌────────────────────────────────────────────┐
│ ★ COMPLEX4 — UNSEEN FUNCTIONAL MACHINE ★  │
└────────────────────────────────────────────┘
~~~

### COMPLEX0 — first executable complexity stand

Gate:

~~~text
B0.5-A CLOSED
~~~

Subject:

~~~text
50 → 100 → 500 → 2000 part fence / wall
construct
→ bake
→ local impact
→ topology failure
→ invalidation
→ split
→ reconstruction
→ rebake
~~~

This stand deliberately avoids requiring BRIDGE-2. It proves the structural lifecycle
before mixed-domain execution is introduced.

### COMPLEX1A — powered breakable structure FULL baseline

Gate:

~~~text
B0.5-A CLOSED
~~~

Reference system:

~~~text
battery ─── wire attached to fence ─── lamp

intact wire:
lamp ON

critical fence/wire topology break:
circuit opens
→ lamp OFF
~~~

The lamp outcome must emerge from generic physical connectivity. A direct rule such as
"fence broken => lamp off" is forbidden.

Mandatory anti-hardcode variants:

~~~text
break unrelated fence segment
→ lamp remains ON

two independent power paths
→ break one path
→ lamp remains ON if alternate path is valid

two loads on separate branches
→ only causally dependent load changes
~~~

This FULL baseline becomes the causal oracle for the later mixed/baked test.

### COMPLEX1B — powered breakable structure mixed bake

Gate:

~~~text
POST-B0.5-A SYNC
→ BRIDGE-2 executable authorized
→ working mixed FULL ↔ BAKED path
~~~

Target:

~~~text
structure         → STRUCTURAL_BAKE
local impact      → FULL
stable dynamics   → DYNAMIC_ROM
functional path   → FULL or validated reduction
~~~

After a physical break, the same canonical wire connectivity mutation and lamp outcome
must occur as in COMPLEX1A.

Primary falsifier:

~~~text
FULL causal outcome
==
MIXED FULL/BAKED causal outcome
~~~

If the mechanics look correct but the lamp remains powered after the canonical wire path
is broken, the mixed architecture fails.

### COMPLEX2 — modular machine

Gate:

~~~text
BRIDGE-2 CLOSED
~~~

Initial target:

~~~text
500–2000 canonical elements
20–50 structural modules
4–8 moving subsystems
2–4 active contact zones
1–3 functional paths
~~~

The object should simultaneously exercise:

~~~text
FULL
+
STRUCTURAL_BAKE
+
CONTACT_BAKE
+
DYNAMIC_ROM
+
HYBRID_BAKE
~~~

without duplicate state ownership.

### COMPLEX3 — adaptive damage / local unbake

Gate:

~~~text
B0.6
+
BRIDGE-3
~~~

Scale target:

~~~text
5k → 20k → 100k canonical elements
~~~

Only the causally affected region should refine to FULL during damage. Functional
consequences such as a broken electrical path must propagate while unaffected regions
remain reduced. Stable fragments must be rebake-able.

### COMPLEX4 — unseen functional systems

Gate:

~~~text
B0.7
~~~

Build previously unseen machines only from frozen generic primitives. Required pattern:

~~~text
generic composition
→ emergent function
→ reduction
→ topology/failure event
→ correct downstream functional consequence
~~~

No stand-specific solver primitive or hand-written bake class may be introduced only to
pass a fixture.

### COMPLEX acceptance rule

Every COMPLEX stand must compare a FULL reference with its reduced/mixed/adaptive subject
and record at least:

- canonical topology/damage outcome;
- functional connectivity and downstream state;
- effort/flow and power/energy envelope;
- exactly-once events;
- stale-artifact rejection;
- deterministic reconstruction/rebuild/replay;
- canonical element count vs active FULL count;
- reduced state count;
- CPU/memory/event work;
- local refinement size where applicable.

The strategic target is therefore no longer merely "can we bake a complex object?" but:

~~~text
can canonical complexity grow
while runtime physical complexity stays sparse,
and can local physical changes still produce
the correct global functional consequences?
~~~
