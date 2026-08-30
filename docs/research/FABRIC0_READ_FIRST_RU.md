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

FABRIC0.13 завершён как research candidate.

Exact evidence:

```text
FABRIC0.13 Unified Adaptive 3D Contact Graph   95/95 PASS
FABRIC0.13 playground                          PASS
editor parse/compile                           CLEAN
remote/local executable bytes                  7/7 IDENTICAL

FABRIC0.12 executable blobs                     PRESERVED
FABRIC0.12 runtime regression rerun              NO
```

Exact runtime:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`.

FABRIC0.13 впервые объединяет:

```text
FABRIC0.11 persistent sparse contact graph

+

FABRIC0.12 adaptive multi-event manifold semantics
```

в одну accepted causal path.

Main run:

```text
persistent [A,B] support island
+
free rotating/falling C
        ↓
impact at 0.12770032218309
        ↓
[A,B] -> [A,B,C]
        ↓
manifold fixed point at 0.15171711003539
edge(2) -> face(4) -> opposite edge(2)
        ↓
reverse manifold fixed point at 0.58519759521384
        ↓
final t = 0.7
```

Persistent pre-impact reactions survive island merge:

```text
floor|A = 19.62
pair:A|B = 9.81
```

Contact mechanics explicitly couple translation and rotation:

```text
J = [0, -1, +1, dr/dtheta]

gamma =
d2r/dtheta2 * omega^2
```

Sparse evidence:

```text
PCG calls      = 38
PCG iterations = 95
pattern hits   = 36
pattern misses = 2
max constraint residual <= 2e-14
```

Unified refinement convergence against `1e-12` reference:

```text
max event-time error:

1e-7  -> 8.0345e-8
1e-9  -> 3.1108e-9
1e-11 -> 5.6382e-11

max final-state error:

1e-7  -> 6.4537e-7
1e-9  -> 2.6241e-8
1e-11 -> 4.7934e-10
```

Both strictly decrease.

Actual parallel audit:

```text
2 Godot Threads

[A,B,C]
+
[D,E]

forward/reverse spawn
→ exact same canonical hash
```

Parallel hash:

`6ef3fd35474a179a7bf02675d5bde9ecb457f235fdb7cc70f017a69757f92757`.

Physical state hash:

`f486303b7f133d28148d63362ad368d82e946132f2a12f9c164ae5edc2819483`.

### Exact-byte evidence rule

All seven current FABRIC0.13 executable files must continue to match the hashes in:

`validation/fabric0-compositional-world-fabric-v13-validation.json`.

During persistence two large files initially differed only by one missing trailing newline.

They were **not accepted** until GitHub blob SHA exactly matched local `git hash-object`.

Therefore:

```text
semantic source equivalence
!=
exact-byte evidence equivalence
```

when a validation artifact explicitly claims byte identity.

### Important scope

FABRIC0.13 still does **not** prove:

- arbitrary free 6DOF rigid body;
- three-axis angular velocity/inertia tensor dynamics;
- arbitrary convex/mesh manifold;
- adaptive tangential Coulomb cone integration;
- general unilateral complementarity/separation in the unified path;
- arbitrary simultaneous multi-body impacts;
- production broadphase/thread pool/CSR;
- full DWS production integration.

Quaternion is normalized, but the accepted rotational motion is one-axis.

A/B support is partially algebraically projected in this research stand.

Next task:

**FABRIC0.14 — FULL 6DOF FRICTIONAL FEATURE MANIFOLD**

Target:

```text
free translation 3DOF
+
free rotation 3DOF
+
quaternion differential update
+
body/world inertia tensor
+
unilateral normal complementarity
+
tangential Coulomb cones
+
persistent convex feature lineage
+
adaptive multi-event fixed points
+
island merge/split
+
sparse parallel execution
+
refinement + invariant evidence
```

## 9. Правило новой сессии

Новая сессия должна уметь объяснить:

- почему Construction остаётся canonical semantic owner;
- почему physical ports acausal;
- почему topology компилируется в equations;
- почему dimensions executable;
- почему residual=0 недостаточно без rank;
- почему FLOW/JUMP/TOPOLOGY TRANSACTION разделены;
- почему existing constraints remain active during event localization;
- почему root-search accuracy и trajectory integration accuracy различны;
- почему physical claims должны показывать convergence under refinement;
- почему integration of previously accepted subsystems является отдельным falsification gate;
- почему persistent reaction history должна переживать island merge по relation identity;
- почему orientation-dependent contact требует rotational sensitivity inside Jacobian;
- почему geometry curvature даёт acceleration-level term;
- почему multipoint edge/face transitions принадлежат topology transaction layer;
- почему contact feature identity требует lineage, а не только exact ID;
- почему warm force/impulse cache является numerical continuity, а не world truth;
- почему sparse pattern cache является computational hint;
- почему worker threads должны решать snapshots и не мутировать physical world как побочный эффект;
- почему quaternion representation не означает автоматически general 6DOF proof;
- почему algebraic projection должна быть явно отмечена как research reduction;
- почему exact-byte validation включает финальные newline/serialization bytes;
- почему FABRIC0.14 должен возвращать unilateral + friction laws в unified adaptive path;
- какие FABRIC0.13 non-claims остаются действующими.

Если это нельзя восстановить только из Git, recovery contract нарушен.
