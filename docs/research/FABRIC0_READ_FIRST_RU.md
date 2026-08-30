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

FABRIC0.11 завершён как research candidate.

Exact evidence:

```text
FABRIC0.11 Event Sparse Islands      120/120 PASS
FABRIC0.10 runtime regression         97/97 PASS
FABRIC0.11 playground                 PASS
editor parse/compile                  CLEAN
remote/local executable bytes         IDENTICAL
```

FABRIC0.11 доказал:

- event localization while old persistent island remains constrained;
- old contacts retain near-zero gaps through localization;
- free dynamic body joins existing island at localized event time;
- same-time graph merge `[A,B] -> [A,B,C]`;
- warm-start remap by stable relation identity;
- incoming impulse propagates through existing constrained stack;
- sparse effective-mass representation remains sparse through actual linear solve;
- Jacobi-preconditioned PCG backend;
- no dense effective-mass materialization in successor;
- remaining macrostep continues through new constrained graph;
- single causal lifecycle record at event time;
- independent-island solve schedule can reverse without changing result;
- full event history is order-invariant under tested body/contact/schedule permutations;
- FABRIC0.10 exact-double regression remains green.

Numerical honesty:

```text
bisection tolerance = 1e-11

but
constrained integrator substep = 0.01

therefore
event root accuracy relative to the discrete trajectory
!=
continuous trajectory accuracy
```

Next task:

**FABRIC0.12 — ADAPTIVE MULTI-EVENT MANIFOLD DAE**

Target:

```text
adaptive/error-controlled constrained integration
event-time convergence under refinement
multiple appear/disappear topology events
same-time manifold event iteration
persistent orientation-aware feature identity
manifold split/merge warm remap
sparse pattern/preconditioner caching
actual deterministic parallel island execution
sleep/wake derived computational state
```

## 9. Правило новой сессии

Новая сессия должна уметь объяснить:

- почему Construction остаётся canonical semantic owner;
- почему physical ports acausal;
- почему topology компилируется в equations;
- почему dimensions executable;
- почему residual=0 недостаточно без rank;
- почему FLOW/JUMP/TOPOLOGY TRANSACTION разделены;
- почему algebraic reactions участвуют в timestep;
- почему geometry генерирует constraints;
- почему Coulomb friction — cone;
- почему order invariance mandatory;
- почему deterministic reaction split может быть non-unique;
- почему contact является persistent relation;
- почему warm cache не semantic truth;
- почему static boundaries не склеивают dynamic islands;
- почему active old contacts должны оставаться constrained during event localization;
- почему event-time graph merge требует same-time re-solve;
- почему sparse assembly обязана оставаться sparse through linear solve;
- почему PCG/ADMM/scheduling остаются numerical machinery;
- почему bisection tolerance нельзя выдавать за continuous trajectory accuracy;
- какие non-claims FABRIC0.11 ещё действуют.

Если это нельзя восстановить только из Git, recovery contract нарушен.
