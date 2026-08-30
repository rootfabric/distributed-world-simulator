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

FABRIC0.8 завершён как research candidate.

Exact evidence:

```text
FABRIC0.8 Coupled Hybrid DAE       71/71 PASS
FABRIC0.7 Hybrid Time              88/88 PASS
FABRIC0.6 Nonsmooth              121/121 PASS
FABRIC0.6 Compatibility            42/42 PASS
FABRIC0.8 playground               PASS
editor parse/compile               CLEAN
remote/local executable bytes      IDENTICAL
```

FABRIC0.8 доказал:

- semi-explicit differential + algebraic temporal solve;
- algebraic solve на каждой RK stage;
- topology-dependent algebraic residual;
- event guard от solved algebraic reaction;
- geometric event localization через repeatedly solved DAE;
- generic branch-based impulse solve;
- restitution + Coulomb sliding branch;
- momentum audit through jump;
- same-time event iteration;
- solved impulse → topology break в том же physical instant;
- immediate DAE re-solve after topology mutation;
- remaining flow на новой topology;
- singular DAE fail-closed;
- deterministic event/impulse/topology replay.

Следующая задача:

**FABRIC0.9 — MULTI-CONTACT GEOMETRIC MANIFOLD + CONE SOLVE**

Цель — убрать scalar-contact форму FABRIC0.8:

```text
geometry-derived multiple contacts
normal/tangent Jacobians
angular velocity + inertia tensor
2D friction cone
simultaneous coupled impulses
contact islands
order-invariant solve
sparse/warm-start numerical path
```

Критический test: одно тело одновременно касается нескольких поверхностей и результат не зависит от порядка перечисления контактов.

## 9. Правило новой сессии

Новая сессия должна уметь объяснить:

- почему Construction остаётся canonical semantic owner;
- почему physical ports acausal;
- как topology превращается в equations;
- почему common*balance=power;
- зачем dimensions executable;
- почему residual=0 недостаточно без rank;
- почему nonsmooth law = admissible branch manifolds;
- почему FLOW / JUMP / TOPOLOGY TRANSACTION разделены;
- почему macrostep transactional;
- почему event time физически значим;
- почему reset читает immutable pre-state;
- почему differential и algebraic state должны решаться в одном timestep;
- почему impulse является solved reaction, а не callback;
- почему same-time topology mutation требует DAE re-solve до продолжения времени;
- какие ограничения FABRIC0.8 ещё действуют.

Если это нельзя восстановить только из Git, recovery contract нарушен.
