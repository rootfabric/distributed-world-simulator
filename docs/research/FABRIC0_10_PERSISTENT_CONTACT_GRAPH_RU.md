# FABRIC0.10 — PERSISTENT CONTACT GRAPH + SPARSE HYBRID CONTACT STEP

**Статус:** research-only successor к FABRIC0.9.  
**Parent research head:** `87cf1889ad59e956dde884991af061faa423b8b9`.

## 1. Исследовательский барьер

FABRIC0.9 доказал geometry-derived multi-contact manifold, angular Jacobians, 2D Coulomb cones, global solve и order invariance.

Но contact всё ещё жил в основном как мгновенный solve.

Для persistent world нужны другие свойства:

- contact должен иметь stable identity между шагами;
- contact должен появляться, жить и исчезать;
- cached reaction должен переживать смену island topology;
- независимые body/contact components не должны влиять друг на друга;
- static environment не должен склеивать весь мир в один solver island;
- sparse graph structure должна быть observable;
- resting contacts должны долго поддерживать load;
- новый contact должен уметь появиться в локализованный event time.

FABRIC0.10 атакует эту границу.

## 2. Четыре независимых контракта

Архитектура разделена на:

```text
Contact Provider
        ↓
Persistent Contact Graph
        ↓
Island Compiler
        ↓
Island Solver
```

### Contact Provider

Выдаёт generic contact records:

```text
stable id
body_a
body_b
point
r_a
r_b
normal
tangent_1
tangent_2
gap
friction
restitution
```

Kernel graph/solver не обязан знать, была geometry sphere, box, mesh или procedural field.

Встроенный research provider пока sphere-sphere + sphere-plane.

### Persistent Contact Graph

Хранит:

```text
age_steps
first_step
last_step
warm_impulse
```

и lifecycle:

```text
appeared
persisted
disappeared
```

### Island Compiler

Dynamic-body contacts образуют graph edges.

Connected components становятся solver islands.

Static environment **не является graph node**, соединяющим разные bodies.

Следовательно два независимых тела на одном floor остаются разными islands.

### Island Solver

Каждый island:

1. получает free differential velocity от gravity/external acceleration;
2. собирает sparse contact Jacobian;
3. собирает sparse effective-mass entries;
4. решает cone-constrained algebraic impulses;
5. применяет impulses;
6. возвращает post generalized velocities;
7. cache-ит impulses по stable contact identity.

## 3. Stable contact identity

Built-in sphere provider использует:

### Static feature

```text
plane:<plane_id>|body:<body_id>
```

### Dynamic pair

```text
pair:<canonical_body_a>|<canonical_body_b>
```

Body IDs перед provider iteration канонически сортируются.

Provider output также canonical-sort по contact id.

Это позволяет warm-start state жить независимо от текущего island membership.

## 4. Dynamic body-body contact

Впервые persistent checkpoint использует dynamic↔dynamic contact как load-bearing relation.

Stack:

```text
B
↕ pair:A|B
A
↕ plane:floor|body:A
floor
```

Gravity:

`9.81 m/s²`.

dt:

`0.01 s`.

Persistent normal impulses после warm convergence:

```text
pair:A|B        ~= 0.0981 N*s
floor|A         ~= 0.1962 N*s
```

То есть upper body load проходит через body-body contact в floor.

## 5. Resting-contact time step

FABRIC0.10 использует velocity-level nonsmooth time step:

```text
free differential flow
      ↓
contact algebraic impulse solve
      ↓
post constrained velocity
      ↓
position advance
```

Normal linear term:

- free relative normal velocity;
- optional restitution only for sufficiently fast impact;
- Baumgarte correction for small penetration.

Tangential terms — free relative tangent velocity.

Каждый contact остаётся 3D Coulomb cone:

```text
j_n >= 0

sqrt(j_t1²+j_t2²)
<=
mu*j_n
```

## 6. Sparse assembly

Contact Jacobian rows хранят только nonzero generalized-DOF coefficients.

Effective mass:

```text
A = J M^-1 J^T
```

сначала собирается как sparse dictionary только для nonzero entries.

Текущий local numerical solver затем densify-ит **только island-local matrix** для Cholesky.

Это важный explicit non-claim:

> FABRIC0.10 имеет sparse graph/J/A assembly boundary, но ещё не sparse numerical factorization.

Merged D/E island:

```text
3 contacts
9 contact rows

sparse A entries = 29
dense capacity   = 81
```

## 7. Warm start

Persistent contact cache хранит предыдущий:

```text
(j_n,j_t1,j_t2)
```

Новый ADMM solve стартует из этого canonical contact-local impulse.

Cold first world step:

`39 iterations`.

Следующий шаг, когда те же 4 contact identities persistent:

`3 iterations`.

Warm-start hits:

`4`.

Важно:

warm-start state привязан к contact identity, а не island id.

Поэтому при merge D и E old floor impulses не теряются.

## 8. Contact graph lifecycle experiment

Initial:

```text
Island A:
  A,B

Island D:
  D

Island E:
  E
```

Всего:

`3 islands`.

На phase 2 body E перемещается так, что появляется:

`pair:D|E`.

Lifecycle:

```text
appeared:
pair:D|E
```

D и E merge:

```text
3 islands
→
2 islands
```

Merged island:

```text
bodies:
D,E

contacts:
pair:D|E
plane:floor|body:D
plane:floor|body:E
```

При этом old floor contacts дают:

`2 warm-start hits`.

На следующем шаге pair persistent и сам становится warm-startable:

`3 warm-start hits`.

На phase 4 E отделяется.

Lifecycle:

```text
disappeared:
pair:D|E
```

Graph split:

```text
2 islands
→
3 islands
```

## 9. Static environment не склеивает islands

D и E оба касаются одного floor.

Когда между ними нет dynamic edge:

```text
D -> floor

E -> floor
```

они остаются independent islands.

Static plane выступает boundary condition, а не dynamic graph node.

Это важно для масштабирования больших worlds.

## 10. Independent-island equivalence

Acceptance отдельно запускает:

1. full world A/B + D/E topology mutations;
2. isolated A/B stack only.

После пяти steps:

```text
A position
B position
A velocity
B velocity
```

совпадают до `1e-12`.

Следовательно unrelated island topology не влияет на local physical trajectory.

## 11. Resting stack evidence

После пяти gravity steps:

```text
A position ~= (0,0.5,0)
B position ~= (0,1.5,0)
```

и velocities порядка:

`< 1e-8`.

Prototype демонстрирует persistent resting load без постепенного падения stack.

Это не production long-horizon stability proof.

## 12. Order invariance across graph history

Запускается одна и та же пятишаговая lifecycle sequence:

### Run A

- normal body insertion;
- normal contact order.

### Run B

- reversed body insertion;
- reversed provider contact order.

Одинаковы:

- contact history JSON;
- final body positions;
- final velocities;
- final contact cache;
- final world hash.

Hash:

`4103da3235e4cdd7f1c63c809d3dd71ab39d10ec7f68094d6eef33eabfe6033d`.

Order invariance FABRIC0.9 пережила persistent graph mutation.

## 13. Event-aware bridge к FABRIC0.8

Чтобы FABRIC0.10 не стал только frame-boundary contact cache, добавлен ограниченный bridge:

`advance_contact_free_to_first_plane_event`.

Precondition:

```text
world has no active contacts at macrostep start
```

Falling sphere:

```text
center y0 = 2
radius = 0.5
vy0 = -1
g = -9.81
dt = 1
```

Geometry crossing:

```text
gap(t) = 0
```

Reference:

```text
t_event
=
(-1 + sqrt(30.43)) / 9.81
=
0.46038117899287667
```

Localized:

`0.460381178993`.

At this physical time contact history records:

```text
appeared:
plane:floor|body:fall
```

Remaining macrostep then runs through persistent island solve.

At t=1:

```text
position ~= (0,0.5,0)
velocity ~= 0
```

Event world hash:

`ac7c2758e89afb9798a3b2268c99877eb0795f33699e6fbf5a6dfe9034da6eb6`.

## 14. Explicit limitation of event bridge

Bridge intentionally rejects worlds with already-active contacts:

`EVENT_BRIDGE_REQUIRES_CONTACT_FREE_START`.

Почему:

general event localization while other sparse contact islands are active требует повторно решать constrained hybrid DAE во время bisection.

Это не замаскировано эвристикой.

Следующий checkpoint должен generalize эту границу.

## 15. Exact validation

Runtime:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`.

Focused acceptance:

`97/97 PASS`.

Playground:

`FABRIC0_10_PERSISTENT_CONTACT_GRAPH_PLAYGROUND_PASS`.

Editor parse/compile/SCRIPT scan:

`CLEAN`.

Executable local/GitHub byte identity:

```text
fabric0_persistent_contact_graph_v1.gd
65566cde148ebe598da406bcf008454e2215c8f6

fabric0_persistent_contact_graph_experiments_v1.gd
e7b8fd4e43132587ebd233af947377b71276488e

fabric0_persistent_contact_graph_acceptance.gd
d3a90d53cde1844470634d2ca35aafce8278e244

fabric0_persistent_contact_graph_playground.gd
cfe58ddda4feacaf26b0e1ce1916ea747874569c
```

SHA-256:

```text
solver:
e81048f4a1951825c5e88a0da7296009b957fd309805d1f2085db187f098ebee

experiments:
f754034b8fa94b0ea64098b1533e0660130c264092f4da4e9994a7f35b2d2192

acceptance:
f61de1949bf59219c42bcf2d706584339c12228c62372776c35288b1ceba0cf7

playground:
0713b2c2952ceadd61b4498244d8674c1f705b5eb5b8402717433748a2ce3feb
```

## 16. Predecessor preservation

FABRIC0.9 executable blobs проверены на branch и совпадают с ранее зафиксированным v9 evidence.

В этом isolated 0.10 lab predecessor runtime suites **не запускались заново**.

Это принципиально записано отдельно:

```text
predecessor bytes preserved
!=
predecessor runtime regression rerun
```

## 17. Связь с известной практикой

Persistent contact identity + history-based warm starting — известный и сильный numerical pattern в nonsmooth contact simulation.

Research literature по warm-starting PGS показывает, что previous-step multipliers могут существенно уменьшать solver work для slowly changing persistent contact networks.

FABRIC-specific вопрос другой:

> может ли stable identity одновременно стать основой lifecycle, island caching, deterministic replay и будущей distributed persistence, не превращая numerical cache в canonical physical truth?

FABRIC0.10 показывает первый ограниченный yes.

## 18. Что доказано

FABRIC0.10 показывает:

- dynamic body-body contacts могут быть persistent graph edges;
- stable IDs переживают timestep и island topology changes;
- contact lifecycle explicit;
- previous impulses могут warm-start next solve;
- warm start существенно сокращает demonstrated iteration count;
- static environment не соединяет unrelated dynamic islands;
- dynamic edge merges islands;
- edge disappearance splits islands;
- independent islands дают independent physical trajectories;
- sparse Jacobian/effective-mass structure observable;
- resting stack выдерживает несколько gravity steps;
- order invariance сохраняется через contact history;
- contact-free geometric crossing может локализоваться внутри macrostep и создать persistent contact at physical event time;
- invalid provider body identity fails closed.

## 19. Что НЕ доказано

FABRIC0.10 остаётся research prototype:

- sphere provider only for dynamic body-body geometry;
- planes are static boundary features;
- no arbitrary convex/mesh persistent manifold matching;
- one contact point per sphere pair;
- no full rotated inertia tensor;
- contact positions are not integrated with body orientation;
- local island factorization is still dense after sparse assembly;
- no global sparse Cholesky/iterative linear backend;
- no broadphase acceleration structure;
- no parallel island scheduling;
- no sleep/wake semantics;
- no persistent stick/slip mode state beyond warm impulse;
- no sophisticated manifold feature matching;
- warm start cache is numerical evidence, not canonical semantic truth;
- event-aware bridge supports only contact-free start and sphere-plane first event;
- general FABRIC0.8 event-time DAE + FABRIC0.10 persistent islands are not yet one arbitrary coupled event localization algorithm;
- no production Construction / authority / persistence / replication integration;
- no full materialized DWS regression.

## 20. Следующий falsification wall

### FABRIC0.11 — GENERAL EVENT-LOCALIZED CONTACT ISLANDS + SPARSE BACKEND

Следующий шаг должен убрать два крупных research shortcuts:

1. event bridge работает только из contact-free world;
2. sparse assembly заканчивается dense local factorization.

Нужно:

```text
event localization while existing islands are active
persistent manifold feature matching
dynamic body-body impact creation inside active graph
contact island recompile at event instant
true sparse matrix representation through solve
sparse factorization / Krylov path
parallel independent-island scheduling contract
warm-start state remap after manifold topology change
sleep/wake without losing canonical time semantics
order-invariant concurrent island replay
```

Critical falsification experiment:

```text
persistent stack already resting
+
new dynamic body impacts the stack during a large macrostep
+
impact time localized while resting contacts remain constrained
+
contact graph merges at event instant
+
sparse island recompiled
+
warm starts remapped
+
remaining time continues
+
reordered body/contact input gives the same accepted world state
```

## 21. Архитектурный вывод

> FABRIC contact теперь начинает быть не transient collision result, а persistent graph relation со своей identity, history и numerical continuity.

Но canonical semantic ownership конструкции по-прежнему остаётся у Construction.

FABRIC owns only research physical execution semantics.
