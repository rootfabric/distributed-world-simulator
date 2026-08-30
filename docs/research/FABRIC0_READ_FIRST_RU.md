# FABRIC0 — READ FIRST / восстановление исследовательского контекста

Этот файл — обязательная точка входа в исследовательскую линию **FABRIC — Constructible World Fabric**.

Цель документа: новая сессия или новый агент должны восстановить ход исследования **только из Git**, без истории чата.

## 1. Что такое FABRIC

FABRIC — исследование минимальной физической грамматики для Distributed World Simulator.

Идея:

> Не кодировать устройства как заранее известные классы. Дать миру небольшой набор универсальных физических понятий, из которых поведение устройства возникает из topology, local laws, state и conservation constraints.

Краткая формула:

```text
matter
+ geometry
+ physical ports
+ bonds
+ local constitutive laws
+ stored state
+ power/matter flows
+ mutable topology
+ hybrid time
=
constructible world fabric
```

FABRIC **не является** новым production owner.

Canonical semantic owner конструкций остаётся существующая архитектура Construction / ConstructAggregate. FABRIC — research substrate и будущий вычислительный слой/consumer, если исследования выдержат promotion gates.

## 2. Читать в таком порядке

1. `docs/research/FABRIC0_IDEOLOGY_RU.md`
2. `docs/research/FABRIC0_RESEARCH_HISTORY_RU.md`
3. `docs/research/FABRIC0_PROGRESS_RU.md`
4. design note текущего checkpoint:
   - FABRIC0.3: `FABRIC0_3_CONSERVATION_CELL_RU.md`
   - FABRIC0.4: `FABRIC0_4_POWER_MAP_RU.md`
   - FABRIC0.5: `FABRIC0_5_NONLINEAR_DIMENSIONS_RU.md`
   - FABRIC0.6: `FABRIC0_6_NONSMOOTH_WORLD_RU.md`
   - FABRIC0.7: `FABRIC0_7_STATEFUL_HYBRID_TIME_RU.md`
   - FABRIC0.8: `FABRIC0_8_COUPLED_HYBRID_DAE_RU.md`
   - FABRIC0.9: `FABRIC0_9_MULTICONTACT_GEOMETRIC_CONE_RU.md`
   - FABRIC0.10: `FABRIC0_10_PERSISTENT_CONTACT_GRAPH_RU.md`
   - FABRIC0.11: `FABRIC0_11_EVENT_LOCALIZED_SPARSE_ISLANDS_RU.md`
   - FABRIC0.12: `FABRIC0_12_ADAPTIVE_MULTIEVENT_MANIFOLD_RU.md`
   - FABRIC0.13: `FABRIC0_13_UNIFIED_ADAPTIVE_3D_CONTACT_GRAPH_RU.md`
   - FABRIC0.14: `FABRIC0_14_FULL_6DOF_FRICTIONAL_FEATURE_MANIFOLD_RU.md`
   - FABRIC0.15: `FABRIC0_15_MULTIBODY_CONVEX_COMPLEMENTARITY_GRAPH_RU.md`
   - dual-track BAKE roadmap: `FABRIC_BAKE_ROADMAP_RU.md`
   - BAKE architecture: `FABRIC_BAKE_ARCHITECTURE_RU.md`
5. validation evidence последней версии.
6. historical predecessor evidence, если меняется фундаментальная семантика.

После этого обязательно сверить root `AGENTS.md`, Project Control и canonical architecture ownership.

## 3. Текущая исследовательская линия

```text
FABRIC0.1
scalar compositional playground
        ↓
FABRIC0.2
inline Switch + feedback + inertia
        ↓
FABRIC0.3
topology-derived Conservation Cells
        ↓
FABRIC0.4
Power Maps + mixed domains + storage
        ↓
FABRIC0.5
dimensions + generic nonlinear residuals + AD/Newton
        ↓
FABRIC0.6
nonsmooth HybridRelation + complementarity + contact/friction
        ↓
FABRIC0.7
STATEFUL HYBRID TIME
continuous state + event localization + reset + discrete mode + topology transaction
        ↓
FABRIC0.8
COUPLED HYBRID DAE / EVENT ITERATION
unified temporal + algebraic physical solve
        ↓
FABRIC0.9
MULTI-CONTACT GEOMETRIC MANIFOLD + CONE SOLVE
geometry-derived coupled multi-contact
        ↓
FABRIC0.10
PERSISTENT CONTACT GRAPH + SPARSE HYBRID CONTACT STEP
long-lived multi-body contact islands
        ↓
FABRIC0.11
GENERAL EVENT-LOCALIZED CONTACT ISLANDS + SPARSE BACKEND
active-island event localization + sparse numerical solve
        ↓
FABRIC0.12
ADAPTIVE MULTI-EVENT MANIFOLD DAE
adaptive constrained time + manifold event iteration
        ↓
FABRIC0.13
UNIFIED ADAPTIVE 3D CONTACT GRAPH
integrated adaptive manifold semantics + persistent sparse contact graph
        ↓
FABRIC0.14
FULL 6DOF FRICTIONAL FEATURE MANIFOLD
full rigid-body rotation + unilateral normal + Coulomb tangent cones
        ↓
FABRIC0.15
MULTIBODY CONVEX COMPLEMENTARITY GRAPH
multiple free 6DOF bodies + coupled nonsmooth contact graph
        ↓
FABRIC0.16
GENERAL CONVEX MULTIPOINT MCP
arbitrary convex geometry + persistent multipoint manifold + stronger global complementarity
```

## 4. Инварианты, которые нельзя случайно потерять

### Construction ownership

```text
Construction owns semantic construct identity.
FABRIC must not become a competing canonical construct registry.
```

### Device-agnostic kernel

Нельзя добавлять kernel classes только потому, что эксперимент называется:

```text
Lamp
Motor
Generator
Differential
Diode
Valve
Contact
Friction
Fuse
Breaker
```

Название устройства может существовать в experiment/prefab/semantic layer. Kernel должен знать универсальные laws.

### Physical ports are acausal

Physical connection не является обычным `out -> in`.

Topology компилируется в equations.

### Power conjugacy

Для physical domain:

```text
common_dimension * balance_dimension = power_dimension
```

Примеры:

```text
voltage * current
angular_velocity * torque
velocity * force
pressure * volume_flow
```

### Conservation is structural

Conservation Cell:

```text
common_i = common_j
sum(balance_i) = 0
```

Power Map:

```text
A q = 0
b = -A^T lambda
=> q^T b = 0
```

### Invalid physics fails closed

Недоопределённая, невозможная, размерностно ошибочная или nonsmooth-недопустимая система не получает «разумное значение по умолчанию».

Она должна дать явную diagnostic.

### Numerical artefacts are observable

Numerical damping / approximation нельзя выдавать за физическую dissipation.

### Git is durable memory

Каждый крупный исследовательский шаг должен иметь:

- design note;
- executable focused acceptance;
- playground;
- validation JSON;
- progress entry;
- exact tested engine;
- explicit claims/non-claims;
- immutable historical predecessor evidence.

## 5. Что не следует делать

Не превращать FABRIC в:

- ECS-каталог устройств;
- электрический simulator, притворяющийся универсальным;
- набор больших procedural callbacks;
- систему, где solver знает названия предметов;
- скрытую вторую Construction truth;
- систему, которая исправляет невозможную физику эвристикой;
- систему, где единицы — комментарии;
- систему, где события/разрушения существуют только как if/else в конкретном device code.

## 6. Epistemic discipline

FABRIC использует и синтезирует сильные известные идеи:

- acausal physical modeling;
- connection sets;
- nodal/constraint assembly;
- Lagrange reactions;
- bond-graph / power-conjugate thinking;
- port-Hamiltonian power-preserving interconnection;
- dimensional analysis;
- automatic differentiation;
- Newton solving;
- complementarity;
- active sets;
- hybrid automata / reset maps.

Не заявлять, что базовая математика «впервые изобретена человечеством».

Исследовательская новизна, если она появится, должна быть в **синтезе архитектуры для открытого persistent distributed world**, где неизвестные заранее машины, поломки и режимы возникают из композиции.

## 7. Promotion philosophy

FABRIC не должен попадать в production только потому, что красив.

Минимальный promotion gate должен доказать:

1. несколько неизвестных заранее конструкций без device-specific kernel code;
2. reuse одинаковых laws в разных domains;
3. conservation / power / dimension invariants;
4. deterministic replay;
5. topology split/merge;
6. nonlinear + nonsmooth behavior;
7. stateful events and irreversible transitions;
8. масштабируемый numerical strategy;
9. ясное место под Construction canonical ownership;
10. authority/persistence/network semantics без второй истины.

## 8. Текущая граница

FABRIC0.15 завершён как research candidate.

Exact evidence:

```text
FABRIC0.15 Multibody Convex Complementarity Graph   103/103 PASS
FABRIC0.15 playground                               PASS
editor parse/compile                                CLEAN
remote/local executable bytes                       7/7 IDENTICAL

FABRIC0.14 runtime regression                        156/156 PASS
FABRIC0.14 executable blobs                          7/7 PRESERVED
```

Exact runtime:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`.

Current design/evidence:

```text
docs/research/FABRIC0_15_MULTIBODY_CONVEX_COMPLEMENTARITY_GRAPH_RU.md

validation/fabric0-compositional-world-fabric-v15-validation.json
```

Exact-tested executable commit:

`a8ff0d7360b4bba0f1b3e164f8c040d73622b1ee`.

### Multibody graph

Four dynamic bodies:

```text
A
B
C
D
```

Each is full 6DOF.

Whole state:

```text
4 × 13 =
52 components
```

Initial graph:

```text
plane
  ↕
  A
  ↕
  B
  ↕
  C

D free
```

### Merge / hold / split

Main `dt=0.001`:

```text
C|D appears
t = 0.18299031095859

[A,B,C] + [D]
→
[A,B,C,D]
```

The new contact is stick and carries both normal and tangential impulse.

At exact source change:

```text
t = 0.32

drive:D
→ upward force
```

unilateral complementarity releases C|D:

```text
Pn ~ 0
+
separating velocity > 0
→
CONTACT_DISAPPEAR
```

Graph:

```text
[A,B,C,D]
→
[A,B,C] + [D]
```

### Coupled complementarity

Analytic gravity chain expected/solved:

```text
B|C:
0.0367875
→ 0.03678437280127

A|B:
0.08379375
→ 0.08378662693623

plane|A:
0.12466875
→ 0.12466162693623
```

One coupled island can simultaneously solve:

```text
plane|A = stick
A|B     = stick
B|C     = slide
```

### Configuration localization rule

During development a new contact was detected only after penetration.

Baumgarte bias then created separating velocity and made contact lifetime timestep-dependent.

Accepted boundary:

```text
negative new gap
→ configuration-only localization to gap=0
→ no velocity/momentum change
→ then physical contact impulse
```

Do not confuse this with FABRIC0.14's hidden velocity projection.

Rule:

```text
configuration correction without momentum change
=
event localization

velocity/momentum change
=
physical jump
```

### Refinement

Reference:

`dt=0.0005`.

Merge-time errors:

```text
1.5902e-3
→ 6.8118e-4
→ 2.2666e-4
```

Full 52D state errors:

```text
4.2576e-3
→ 1.8033e-3
→ 7.3279e-4
```

Energy-ledger residual:

```text
0.186304
→ 0.092953
→ 0.047009
```

All strictly decrease.

Current integration is fixed-step refinement, not adaptive error-controlled time.

### PGS semantics

Current graph solver is projected block Gauss-Seidel.

Canonical ordering is required for deterministic replay.

Forward/reverse order at 32 iterations gives:

```text
max delta v =
1.8593214664426525e-6

max delta omega =
2.1323642847629e-7
```

Same modes, close state.

This proves current order robustness, **not** exact contact-order independence.

### Main audits

```text
contact solves      = 403
PGS iterations      = 12896

max normal violation =
1.634842214e-4

max cone violation =
0

max penetration =
4.72630019e-6

internal body-body linear momentum error =
0

internal body-body angular momentum error =
0
```

Main physical hash:

`68e18b6a9a16b574aaf0b6ca30b3cf5160ea9a69ba8919df11f1b04fda92d29c`.

Parallel canonical hash:

`49e8c7b2fa0e1177f0e19d36ee85c4e22239ad95556c2c0a7c909d24fb47b34b`.

### Important scope

FABRIC0.15 still does not prove:

- arbitrary convex polytope collision;
- GJK/EPA;
- mesh collision;
- true multipoint face manifolds;
- globally converged MCP/NCP;
- exact PGS contact-order independence;
- production block-sparse/CSR backend;
- adaptive error-controlled integration;
- exact simultaneous multi-impact localization;
- root-localized stick/slide transitions;
- a fully autonomous main split without explicit source control;
- rolling/torsional friction;
- production broadphase/same-world thread pool;
- Construction/authority/persistence/network integration;
- full DWS regression.

## 8.1. Dual-track frontier after FABRIC0.15

FABRIC0.15 is **RESEARCH CANDIDATE CLOSED**, not production-accepted.

The roadmap now has two parallel research lines:

```text
PHYSICAL CORE
FABRIC0.x

FABRIC0.15
   ↓
FABRIC0.16 — GENERAL CONVEX MULTIPOINT MCP
   ↓
future physical-core checkpoints
```

and:

```text
PHYSICAL REDUCTION
FABRIC-BAKE B0.x

B0.0 — BAKE FOUNDATION CONTRACTS
   ↓
B0.1 — EXACT BOUNDARY REDUCTION
   ↓
B0.2 — STRUCTURAL + REFINEMENT GUARDS + LOCAL UNBAKE
   ↓
B0.3 — CONTACT/WRENCH BAKE
   ↓
B0.4 — DYNAMIC ROM
B0.5 — HYBRID BAKE / LAZY MODES
   ↓
B0.6 — ADAPTIVE PHYSICAL FIDELITY
   ↓
B0.7 — UNSEEN MACHINE SCALE
```

Read before any BAKE work:

```text
docs/research/FABRIC_BAKE_ROADMAP_RU.md
docs/research/FABRIC_BAKE_ARCHITECTURE_RU.md
```

### Frozen BAKE architecture

A new session must understand these contracts:

```text
CanonicalSourceFrontier[]
AuthorityEnvelope
PhysicalBoundaryContract
BakeSourceBinding
PhysicalBakeArtifact
ValidatedDomain
ErrorEnvelope
RuntimeErrorEstimator
ConservationEnvelope
RefinementGuard
ReconstructionDescriptor
BakeStateMapping
BakeInvalidation
NO_SAFE_BAKE
```

Critical rules:

1. Construction/Matter remain canonical truth.
2. FABRIC and Bake are derived physical representations.
3. FABRIC is not added as a canonical source domain.
4. Bake source binding may contain several sorted canonical sources.
5. A bake cannot silently cross mutable authority domains.
6. Physical STALE is immediately non-executable.
7. Fundamental boundary semantics remain acausal effort/flow relations.
8. Reduced internal state need not equal full internal state.
9. Approximation correctness is deterministic boundary error inside ValidatedDomain.
10. Hidden dangerous processes require conservative RefinementGuards.
11. Reduction may legally return NO_SAFE_BAKE.
12. Presentation LOD and physical fidelity are different axes.
13. Global scheduling cannot request a fidelity below the physical minimum-safe fidelity.

### Current parallel next checkpoints

```text
PHYSICAL CORE:
FABRIC0.16 — GENERAL CONVEX MULTIPOINT MCP

FABRIC-BAKE:
B0.0 — BAKE FOUNDATION CONTRACTS
```

They may proceed in parallel.

B0.3 final acceptance is explicitly blocked until FABRIC0.16 provides general convex multipoint contact and stronger complementarity semantics.

## 9. Правило новой сессии

Новая сессия должна уметь объяснить:

- почему Construction остаётся canonical semantic owner;
- почему local contact correctness не означает graph correctness;
- почему contact island — physical connected component, а не scheduler-owned bucket;
- почему shared body velocity делает relation-local friction graph-coupled;
- почему `Pn >= 0` active set должен владеть separation;
- почему topology narrative `merge→hold→split` обязана переживать timestep refinement;
- почему richer scenario не всегда stronger falsification;
- почему lateral D prototype был отвергнут как основной acceptance stand;
- почему configuration localization и physical impulse — разные semantic categories;
- почему penetration/Baumgarte не должны случайно определять topology;
- почему body-body impulse internal, а plane reaction external для momentum audit;
- почему whole-graph refinement должен смотреть event time + N-body state + energy ledger;
- почему PGS finite iteration требует canonical order;
- почему order robustness не равно exact order independence;
- почему exact source event допустим как controlled falsification stimulus, но не доказывает autonomous separation family;
- почему sphere/plane является valid graph falsifier, но не general convex collision;
- почему predecessor runtime regression + byte preservation оба входят в evidence;
- какие FABRIC0.15 non-claims остаются открытыми;
- почему следующий wall — general convex multipoint MCP.

- почему physical bake является sibling presentation artifact, а не видом mesh/impostor LOD;
- почему CanonicalSourceFrontier должен поддерживать несколько canonical sources;
- почему AuthorityEnvelope запрещает скрыто объединять authoritative writers;
- почему physical STALE означает execution forbidden;
- почему acausal PhysicalBoundaryContract фундаментальнее input/output API;
- почему internal reduced state equality не является критерием bake correctness;
- почему ValidatedDomain/ErrorEnvelope должны быть deterministic/falsifiable, а не statistical confidence;
- почему RefinementGuard обязан вызвать detail обратно до скрытого authoritative failure/event;
- почему NO_SAFE_BAKE является корректным compiler result;
- почему BAKE определяет minimum safe physical fidelity, но не становится global scheduler;
- почему B0.3 final заблокирован FABRIC0.16;
- где лежат `FABRIC_BAKE_ROADMAP_RU.md` и `FABRIC_BAKE_ARCHITECTURE_RU.md`.

Если это нельзя восстановить только из Git, recovery contract нарушен.
