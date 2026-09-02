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


## 10. FABRIC0.16 — active Physical Core successor

После dual-track frontier Physical Core действительно стартовал отдельным successor slice.

Current durable state:

```text
FABRIC0.15
RESEARCH CANDIDATE CLOSED
        ↓
FABRIC0.16
S1 — GENERAL CONVEX MANIFOLD + GRAPH LCP
IMPLEMENTED
EXACT LINUX DOUBLE PASS
110/110
IN PROGRESS
NOT CLOSED
```

Читать:

```text
docs/research/FABRIC0_16_GENERAL_CONVEX_MULTIPOINT_MCP_RU.md
docs/research/FABRIC0_16_PROGRESS_RU.md
validation/fabric0-compositional-world-fabric-v16-s1-validation.json
```

S1 уже переносит Physical Core через следующие стены FABRIC0.15:

```text
explicit convex polytope support mapping
→ deterministic GJK / EPA
→ clipped persistent 1..4 point face manifold
→ deterministic sweep-and-prune research broadphase
→ graph-wide 8-row regularized active-set normal LCP
→ coupled Coulomb normal/tangent fixed point
→ canonical caller-order-independent solution
```

Important numerical boundary:

```text
normal_regularization = 1e-9
```

Она явная и observable. S1 не выдаёт regularized active-set solve + converged friction outer loop за универсально сертифицированный монолитный Signorini-Coulomb MCP/NCP.

Current open walls before FABRIC0.16 can be considered for closure:

```text
adaptive contact/separation localization
root-localized stick/slide
persistent manifold evolution through events
same-world parallel island execution
refinement across those events
```

Next bounded slice:

```text
FABRIC0.16 S2
ADAPTIVE CONVEX CONTACT EVENTS
+
SAME-WORLD PARALLEL ISLANDS
```

Construction remains canonical semantic owner. FABRIC0.16 remains research physical execution substrate.


## 11. FABRIC0.16 S2 — current verified Physical Core boundary

Accepted executable HEAD:

```text
92588ac05a7fa5b3cedd64bb567436e82e3a0a0e
```

State:

```text
FABRIC0.15 CLOSED
  ↓
FABRIC0.16 S1 110/110 PASS
  ↓
FABRIC0.16 S2 102/102 PASS
  ↓
FABRIC0.16 S3 NEXT
```

S2 adds adaptive convex contact/separation localization, solver-surface stick/slide localization and actual same-world parallel islands.

Recovery evidence:

```text
docs/research/FABRIC0_16_GENERAL_CONVEX_MULTIPOINT_MCP_RU.md
docs/research/FABRIC0_16_PROGRESS_RU.md
validation/fabric0-compositional-world-fabric-v16-s2-validation.json
```

Important: exact-touch EPA degeneracy is handled only as bracketed zero-measure boundary evidence; it is not globally reclassified as penetration.

FABRIC0.16 is still **NOT CLOSED**. Next wall is a single unified event-driven trajectory with graph topology changes and refinement.


## 12. FABRIC0.16 — RESEARCH CANDIDATE CLOSED

Current Physical Core recovery boundary:

```text
branch:
research/fabric0-compositional-world-fabric-r1

exact-tested executable head:
3307d553c1c3c79cd9c15a5c565af7fef3f0400c

status:
FABRIC0.16
RESEARCH CANDIDATE CLOSED
EXACT DOUBLE PASS
REMOTE BYTE IDENTITY PASS
PROJECT CONTROL PASS
```

Closure suite:

```text
S1 110/110
S2 102/102
S3 101/101
editor CLEAN
```

Read:

```text
docs/research/FABRIC0_16_GENERAL_CONVEX_MULTIPOINT_MCP_RU.md
docs/research/FABRIC0_16_PROGRESS_RU.md
validation/fabric0-compositional-world-fabric-v16-validation.json
```

The decisive S3 result is a unified general-convex trajectory with actual contact graph topology mutation:

```text
[A,B] + [C,D]
      ↓ contact appear
[A,B,C,D]
      ↓ contact disappear
[A,B] + [C,D]
```

with `8 -> 12 -> 8` manifold rows and `2 -> 1 -> 2` actual Godot Threads.

Do not upgrade this status to production acceptance. In particular, the checkpoint does not claim a monolithic certified Signorini-Coulomb MCP/NCP, simultaneous multi-impact closure, rolling/torsional friction or production broadphase/block-sparse/thread-pool infrastructure.


## 13. FABRIC0.17 — active Physical Core successor

FABRIC0.16 remains immutable as a closed research candidate.

```text
branch:
research/fabric0-17-simultaneous-impact-event-set-r1

predecessor closure:
ae781ab78f2e0688641f6a332a131b3fb759994f

0.17-A executable:
9139a213ccee64d3bf1bb95ea32170027421b3b3
```

Current status:

```text
FABRIC0.17
IN PROGRESS

0.17-A
SIMULTANEOUS IMPACT EVENT SET
77/77 PASS
remote byte identity 4/4
```

Read:

```text
docs/research/FABRIC0_17_SIMULTANEOUS_MULTI_IMPACT_GENERALIZED_WRENCH_RU.md
validation/fabric0-compositional-world-fabric-v17-a-validation.json
```

Critical new semantics:

```text
simultaneous != exact float timestamp equality

simultaneous =
impact roots indistinguishable
at declared temporal resolution
```

Refinement must split a merely near-coincident later impact from a stable simultaneous set.

Current stable set: `[C|L,C|R]` at approximately `0.5`. Near later event: `P|Q` at approximately `0.5002`.

0.17-A does not solve impulses.

Next: `FABRIC0.17-B — COUPLED SIMULTANEOUS IMPACT SOLVE`.


## 14. FABRIC0.17-B — coupled simultaneous impact boundary

Current executable boundary:

```text
6456ca4a5ce936c7b4c2b11906c696982a091e24
```

State:

```text
FABRIC0.17-A
77/77 PASS
        ↓
FABRIC0.17-B
63/63 PASS
        ↓
FABRIC0.17-C NEXT

FABRIC0.17 remains IN PROGRESS
```

Read:

```text
docs/research/FABRIC0_17_SIMULTANEOUS_MULTI_IMPACT_GENERALIZED_WRENCH_RU.md
validation/fabric0-compositional-world-fabric-v17-b-validation.json
```

Critical B semantics:

```text
simultaneous event set
!=
sequence of pair impacts

all event members
→ one immutable pre-impact state
→ one coupled multipoint restitution LCP
→ one post-impact state
```

The symmetric falsifier gives exact caller-order-independent coupled state, while pair-wise sequential processing has `max state delta = 4` between opposite orders.

0.17-B remains frictionless at impact. Tangential/rolling/torsional generalized wrench is deliberately deferred to 0.17-C.


## 15. FABRIC0.17-C — generalized contact wrench boundary

Current exact executable:

```text
edc021230dadf62e9bf5ffb4c17cc5f2d0140ba0
```

State:

```text
0.17-A 77/77 PASS
   ↓
0.17-B 63/63 PASS
   ↓
0.17-C 76/76 PASS
   ↓
0.17-D NEXT

FABRIC0.17 remains IN PROGRESS
```

C adds a 5DOF generalized friction wrench:

```text
tangent force (2)
rolling moment (2)
torsional moment (1)
```

with explicit geometry-scaled limits from an already-resolved normal support impulse.

Important: C does not apply normal support a second time and does not yet solve normal+wrench coupling in one MCP.

Read:

```text
docs/research/FABRIC0_17_SIMULTANEOUS_MULTI_IMPACT_GENERALIZED_WRENCH_RU.md
validation/fabric0-compositional-world-fabric-v17-c-validation.json
```

Next closure-decision wall:

`FABRIC0.17-D — UNIFIED MULTI-IMPACT WRENCH TRAJECTORY`.

## 16. FABRIC0.17-D — implemented, control-blocked boundary

Exact executable: `643b4bdc5d33756819869c3faacc1dccf1251a1f`.

Current chain:

`0.17-A 77/77 -> 0.17-B 63/63 -> 0.17-C 76/76 -> 0.17-D 157/157`.

D integrates two ordered simultaneous event sets, graph-wide generalized wrench coupling and a same-instant normal↔wrench fixed point. Naive one-pass normal→wrench composition is explicitly rejected because it reopens the normal impact law by about `0.34`; accepted recoupling reduces residual below `5e-10`.

Whole-state/event refinement is strict, energy ledger closes at `~1.78e-15`, linear/angular momentum errors are zero, and replay/body/member order determinism is exact.

Important current status: `FABRIC0.17 NOT CLOSED`. Project Control run `#1836` fails at repository architecture/ownership compatibility due unrelated live G/ECO passport/dependency drift. The D delta from the previously green C evidence boundary contains exactly six FABRIC research/test files and no G/ECO/Matter/control-registry changes.

Do not repair G/ECO/Matter control state from this FABRIC branch and do not treat the external RED as a FABRIC physics failure. Re-run Project Control after repository control recovery; only then decide research-candidate closure.

D non-claims: no finite-duration persistent-contact wrench-mode trajectory, no active torsion in the D fixture itself, no universal monolithic impact+wrench MCP, no production sparse backend or production acceptance.

Evidence: `validation/fabric0-compositional-world-fabric-v17-d-validation.json`.


## 17. FABRIC0.17 — CLOSED research candidate

Current Physical Core boundary:

```text
FABRIC0.16
RESEARCH CANDIDATE CLOSED
        ↓
FABRIC0.17
RESEARCH CANDIDATE CLOSED
```

FABRIC0.17 exact physics executable:

`643b4bdc5d33756819869c3faacc1dccf1251a1f`.

Closure evidence:

```text
A  77/77
B  63/63
C  76/76
D 157/157

Project Control #1855 SUCCESS
```

The closure control carrier is `3cc14e0ff7a1e6ef1e456c0e428e4caff1dd3555`. It carries only the two harness test repairs already merged to main by PR #377; D executable bytes remain exact.

Status:

```text
RESEARCH CANDIDATE CLOSED
NOT PRODUCTION ACCEPTED
```

Do not create an implicit 0.17-E. Any successor Physical Core checkpoint must first be explicitly formalized in the roadmap.


## 18. FABRIC0.18 — active successor

```text
FABRIC0.18
PERSISTENT CONTACT WRENCH DYNAMICS
IN PROGRESS

branch:
research/fabric0-18-persistent-contact-wrench-r1

base:
751c55e76f57b7a9ceef8f5bbda3dcf6d4fad1a0
```

Slices:

```text
0.18-A Persistent Wrench Contact State        STARTED
0.18-B Mode Transition Localization           NEXT
0.18-C Multicontact Persistent Wrench Graph   LATER
0.18-D Unified Persistent Contact Trajectory  CLOSURE DECISION
```

Critical A rule: persistent state may retain identity, age, mode hypothesis and projected warm-start proposal, but it must never carry a previous impulse forward as accepted physical truth. Every accepted state requires a fresh solve.

Read `docs/research/FABRIC0_18_PERSISTENT_CONTACT_WRENCH_DYNAMICS_RU.md`.

0.18 remains research-only and not production accepted.


## 19. FABRIC0.18-A — implemented candidate

Exact executable:

`c7f20c51794690930d059d10747d1a1c3e4e2c52`.

```text
0.18-A 60/60 PASS
playground PASS
editor CLEAN
remote bytes 3/3 exact
FABRIC0.18 NOT CLOSED
```

Critical invariant:

```text
persistent history may propose a warm start
but only the fresh current solve may own accepted impulse
```

Stable pair/member reordering preserves identity. Manifold membership mutation resets identity epoch and warm-start continuity. Mode changes are candidates only; 0.18-B must localize their event time.

Next: `0.18-B MODE TRANSITION LOCALIZATION`.


A consumes the existing 0.17 persistent manifold point IDs directly and normalizes the existing generalized-wrench result; do not create a parallel contact-identity scheme.


0.18-A control boundary: `Project Control #1867 SUCCESS`; FABRIC0.17 D predecessor bytes remain `6/6 exact`.


## 20. FABRIC0.18-B — implemented candidate

Exact executable:

`649d7a9d62384a6d3cdfe2efbd92534bc52573e7`.

```text
0.18-A  60/60 PASS
0.18-B 108/108 PASS

B remote bytes 4/4 exact
A bytes 3/3 preserved
0.17-D bytes 6/6 preserved

FABRIC0.18 NOT CLOSED
```

Critical B semantics:

```text
mode transition time
!=
first discrete sample whose label changed

mode transition time
=
root of a continuous feasibility guard
validated by 0.18-A semantics on both sides
```

Events: `STICK_TO_SLIDE`, `STICK_TO_ROLL`, `STICK_TO_SPIN`, `SUPPORT_TO_SEPARATION`.

Near-coincident mode roots obey explicit temporal-resolution grouping exactly as impact roots do in 0.17.

Next: `0.18-C MULTICONTACT PERSISTENT WRENCH GRAPH`.


0.18-B Project Control #1888 SUCCESS. B is an implemented candidate; FABRIC0.18 remains open and 0.18-C is next.


## 21. FABRIC0.18-C — implemented candidate

Exact executable:

`5b37312bd986c5dc4951ebe13ac670df0af11073`

TREE:

`76eff3e6ab0cd206420a68ed2fc1fa3b40f663e4`

```text
0.18-A  60/60 PASS
0.18-B 108/108 PASS
0.18-C 153/153 PASS

C bytes 4/4 exact
B bytes 4/4 preserved
A bytes 3/3 preserved
0.17-D bytes 6/6 preserved

FABRIC0.18 NOT CLOSED
```

C solves multiple fixed-anchor persistent patches of one shared dynamic rigid body as one coupled 6DOF wrench graph.

Key evidence:

```text
support redistribution   exact to ~2e-11
support loss             opens contact, no tensile normal
mixed graph modes        FLOOR slide / WALL stick
active generalized modes slide + roll + spin
reverse contact order    exact identical
sequential callbacks     state delta ~0.03125
10k-step physical creep  max speed ~1.74e-13
solver refinement        strictly decreasing
```

Do not generalize C into an arbitrary multi-dynamic-body persistent graph claim.

Next: `0.18-D UNIFIED PERSISTENT CONTACT TRAJECTORY`.


0.18-C Project Control #1893 SUCCESS. C is an implemented candidate; do not close FABRIC0.18 before 0.18-D.


## 22. FABRIC0.18-D — implemented candidate

Exact executable:

`e079565b4b9cd0dae530ff5042f057ce8fa0d0cc`

TREE:

`c051cabd50343603efc509887f32fadf479f0f54`

```text
0.18-A  60/60 PASS
0.18-B 108/108 PASS
0.18-C 153/153 PASS
0.18-D 113/113 PASS

D 4/4 exact
C/B/A/0.17-D bytes preserved
Project Control #1899 SUCCESS
```

Unified bounded timeline:

```text
free
→ impact / persistent support
→ stick
→ slide
→ roll
→ spin
→ one support separation
→ remaining support slide+roll+spin
```

B localizes transition roots directly from live C KKT/feasibility guards. A persistent history is attached only after a fresh canonical C solve, so warm-start history cannot shift the physical event surface.

Both event-time and event-resolved state refinement are strict; contact/event-spec ordering is exact deterministic.

Scope remains one dynamic body against multiple fixed anchors.

Parent status:

```text
FABRIC0.18
CLOSURE-READY
NOT YET CLOSED
NOT PRODUCTION ACCEPTED
```

Do not create an implicit 0.18-E. Next action is explicit 0.18 closure decision, then the planned Physical Core ↔ BRIDGE-1 synchronization review.


## 23. FABRIC0.18 — CLOSED research candidate

Current Physical Core boundary:

```text
FABRIC0.17
RESEARCH CANDIDATE CLOSED
        ↓
FABRIC0.18
RESEARCH CANDIDATE CLOSED
```

FABRIC0.18 exact physics executable:

`e079565b4b9cd0dae530ff5042f057ce8fa0d0cc`.

Exact physics tree:

`c051cabd50343603efc509887f32fadf479f0f54`.

Closure evidence:

```text
A  60/60 PASS
B 108/108 PASS
C 153/153 PASS
D 113/113 PASS

D 4/4 exact
C/B/A/0.17-D predecessor bytes preserved

Project Control #1899 SUCCESS
Project Control #1902 SUCCESS
```

Status:

```text
RESEARCH CANDIDATE CLOSED
NOT PRODUCTION ACCEPTED
```

Closure control carrier:

`88ba8b61ec81928aedeae5777ee1380a6458f0f6`.

Do not create an implicit `0.18-E` or `FABRIC0.19`.

Next: perform the Physical Core ↔ FABRIC-BAKE / BRIDGE-1 synchronization review; only after that review may a post-0.18 Physical Core successor be formalized.
