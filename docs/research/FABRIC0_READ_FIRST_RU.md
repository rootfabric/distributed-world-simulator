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

FABRIC0.14 завершён как research candidate.

Exact evidence:

```text
FABRIC0.14 Full 6DOF Frictional Feature Manifold   156/156 PASS
FABRIC0.14 playground                               PASS
editor parse/compile                                CLEAN
remote/local executable bytes                       7/7 IDENTICAL

FABRIC0.13 runtime regression                        95/95 PASS
FABRIC0.13 executable blobs                          7/7 PRESERVED
```

Exact runtime:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`.

Current design/evidence:

```text
docs/research/FABRIC0_14_FULL_6DOF_FRICTIONAL_FEATURE_MANIFOLD_RU.md

validation/fabric0-compositional-world-fabric-v14-validation.json
```

### Full rigid-body state

```text
position      3
quaternion    4
linear v      3
angular omega 3
------------------
13 components
```

Anisotropic body inertia:

`(0.19, 0.31, 0.43)`.

Torque-free 3-axis audit proves all angular components are live and checks:

```text
linear momentum drift = 0
world angular momentum drift < 1e-9
rotational energy drift < 2e-10
quaternion normalized
```

### Unilateral + Coulomb modes

One generic contact law now has executable:

```text
separated
stick
slide
```

Contact cannot provide tensile normal support.

Stick is accepted inside the Coulomb cone.

Slide lives on:

`|Ft| = mu Fn`.

### Dynamic feature topology

Geometry-derived box support hierarchy:

```text
vertex = 1 point
edge   = 2 points
face   = 4 points
```

Main sliding run:

```text
0.25850330043665
v:--- -> edge -> v:+--

0.31322331523056
v:+-- -> edge -> v:++-
```

Each event reaches fixed point in three iterations with two topology mutations.

### Critical falsification findings

#### Coordinate-frame bug

Wrong use of Godot `Vector3.UP` in a Z-up research world caused impossible geometry and energy gain.

Rule:

```text
coordinate convention
=
executable physics contract
```

#### Hidden projection impulse

Initial feature switch silently removed normal velocity by projection.

Energy discrepancy stayed approximately constant under refinement.

This proved it was missing physical semantics, not truncation error.

Now feature transition is:

```text
lineage remap
→ explicit frictional unilateral impulse
→ linear/angular momentum audit
→ kinetic-loss audit
→ constraint projection
```

### Energy ledger

Main `1e-9` sliding run:

```text
continuous friction =
1.2019943422435

discrete feature losses =
4.06330610007658

energy delta =
-5.26530042753262

closure residual =
1.4787455704379227e-8
```

Refinement:

```text
closure:
3.8287e-7
→ 1.4787e-8
→ 3.3513e-10

event-time error:
6.5110e-8
→ 1.5767e-9
→ 3.3263e-11

13D state error:
5.4644e-7
→ 1.2632e-8
→ 2.5862e-10
```

All strictly decrease.

### Main hashes

```text
sliding physical:
2b52dc944cdc4a48152265db3e456c629bfb5f66969850563e39ec188147efe7

impact:
de5584cb0f2da6b788e8873eac1ff99e2a8bedd1f71c56727fe809eaae29efe9

torque-free:
e57d66d29b7de53757f5b4ba2d0d2a26f3c2a342086a63aebc93726b40666a99

parallel:
526844a8ca0629969477f2942853b3e7b9617b391e39fc54147d30d38852773c
```

### Important scope

FABRIC0.14 still does not prove:

- several simultaneously free interacting 6DOF bodies;
- coupled face-point complementarity;
- persistent dynamic face manifold in the accepted trajectory;
- arbitrary convex/GJK/EPA/mesh geometry;
- localized dynamic separation;
- localized stick/slide mode transitions;
- coupled multi-contact friction cones;
- rolling/torsional friction;
- production broadphase/block-sparse/thread-pool;
- production Construction/authority/persistence/network integration;
- full DWS regression.

Next task:

**FABRIC0.15 — MULTIBODY CONVEX COMPLEMENTARITY GRAPH**

Target:

```text
multiple free 6DOF bodies
+
convex feature graph
+
simultaneous normal complementarity
+
coupled Coulomb cones
+
dynamic separation
+
stick/slide events
+
island merge/split
+
adaptive multi-event fixed point
+
block-sparse parallel solve
+
momentum / energy / refinement evidence
```

## 9. Правило новой сессии

Новая сессия должна уметь объяснить:

- почему Construction остаётся canonical semantic owner;
- почему physical ports acausal и topology компилируется в equations;
- почему dimensions/rank/event identity остаются executable contracts;
- почему convergence under refinement является частью physical evidence;
- почему coordinate frame must be explicit in physics;
- почему quaternion representation alone не означает full 6DOF;
- почему anisotropic inertia + gyroscopic term обязаны проверяться отдельным torque-free audit;
- почему unilateral normal contact запрещает tensile support;
- почему stick/slide являются solved modes одной Coulomb law;
- почему vertex/edge/face являются physical feature topology;
- почему lineage remap и physical transition impulse — разные операции;
- почему velocity projection не может скрывать physical impulse;
- почему hybrid energy ledger должен учитывать continuous friction + discrete jump losses;
- почему nonconvergent invariant discrepancy указывает на missing semantics/sign/frame before tighter tolerance;
- почему parallel audit не должен мутировать physical state;
- почему predecessor runtime regression сильнее простой byte preservation;
- почему следующий wall — graph-wide coupled complementarity, а не ещё один isolated local law;
- какие FABRIC0.14 non-claims остаются открытыми.

Если это нельзя восстановить только из Git, recovery contract нарушен.
