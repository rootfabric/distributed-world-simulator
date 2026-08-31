# FABRIC0.16 — GENERAL CONVEX MULTIPOINT MCP

## Текущий статус

```text
FABRIC0.16
S1 — GENERAL CONVEX MANIFOLD + GRAPH LCP
IMPLEMENTED
EXACT LINUX DOUBLE PASS
RESEARCH SLICE ONLY
NOT CLOSED
```

**Physical branch:** `research/fabric0-compositional-world-fabric-r1`  
**Immutable predecessor frontier:** `962b9c1bbf7f04c7853f1fb0e36480cf54f3250d`  
**Predecessor:** `FABRIC0.15 — MULTIBODY CONVEX COMPLEMENTARITY GRAPH`  
**Engine used for S1:** `Godot 4.7.1.stable.double.custom_build.a13da4feb`.

Этот документ фиксирует первый executable slice FABRIC0.16. Он намеренно не объявляет весь checkpoint закрытым.

## 1. Какой барьер атакует S1

FABRIC0.15 ещё использовал специальную sphere/plane-подобную контактную геометрию и один contact row на пару. Основной новый falsification wall:

```text
explicit convex polytope
        ↓
support mapping
        ↓
GJK intersection
        ↓
EPA penetration normal/depth/witness
        ↓
face clipping
        ↓
persistent 1..4 point manifold
        ↓
graph-wide normal complementarity
        ↓
friction cones coupled back into normal solve
```

S1 должен доказать, что multipoint contact не требует device-specific collision class и что несколько manifold rows могут участвовать в одном coupled graph solve.

## 2. Реализованная geometry grammar

Новый `Fabric0GeneralConvexModelV1` хранит convex shape как:

```text
vertices[]
faces[vertex_index[]]
```

Support function работает в произвольной ориентации rigid body:

```text
support(body, world_direction)
```

На этом одном primitive проверены как минимум две разные convex families:

```text
box
regular tetrahedron
```

Это пока polytope support mapping, а не generic analytic support callback для curved primitives.

## 3. GJK / EPA

`Fabric0GjkEpaV1` реализует:

- deterministic GJK simplex evolution;
- separated/intersect classification;
- deterministic EPA face queue;
- penetration normal;
- penetration depth;
- witness points on A/B;
- fail-closed iteration/degeneracy codes.

Axis-aligned box oracle дал exact expected penetration depths для пяти разных overlap directions.

Rotated box probe:

```text
normal = (1, 0, 0)
depth  = 0.24741879096243
GJK    = 3 iterations
EPA    = 3 iterations
```

Pair reversal на nontrivial rotated case дал:

```text
depth(A,B) == depth(B,A)
normal(A,B) == -normal(B,A)
A witness <-> B witness
```

## 4. Persistent multipoint manifold

`Fabric0PersistentMultipointManifoldV1` выбирает reference/incident faces и клиппит incident polygon side planes reference face.

Rotated face-face probe дал четыре contact points:

```text
A|B|ra:A:5|ib:B:4|p0
A|B|ra:A:5|ib:B:4|p1
A|B|ra:A:5|ib:B:4|p2
A|B|ra:A:5|ib:B:4|p3
```

После малого движения B:

```text
all four IDs preserved
lifetime: 1 -> 2
```

Geometry witness `point_a/point_b` сохраняется отдельно от общего impulse point. Импульс прикладывается в общем midpoint contact point, чтобы внутренние equal/opposite impulses не создавали искусственную net torque из-за численного penetration gap.

## 5. Broadphase

S1 включает deterministic research sweep-and-prune по world AABB:

```text
sort by min_x
prune on x
AABB overlap on y/z
canonical pair order
```

Acceptance probe из четырёх тел оставляет только реальную candidate pair `[A,B]`.

Это не production broadphase: нет dynamic tree, incremental update, SIMD packing или partition ownership.

## 6. Graph-wide normal complementarity

`Fabric0GraphMcpV1` строит одну dense Delassus matrix по всем normal rows contact graph.

Ключевой probe:

```text
A
↕ 4 points
B
↕ 4 points
C
```

Итого:

```text
8 normal complementarity rows
```

Off-diagonal coupling между двумя manifolds наблюдаем:

```text
W[0,4] = -3.5
```

То есть rows `A|B` и `B|C` не решаются как независимые pair callbacks: они связаны через shared body B.

Исходные normal velocities:

```text
A = +1
B =  0
C = -1
```

После solve:

```text
pair impulse A|B = 0.99999999975
pair impulse B|C = 0.99999999975
all final z velocities ~ 0
```

Normal stage использует deterministic active-set LCP. Для rank-deficient multipoint face systems применяется явная наблюдаемая diagonal regularization:

```text
normal_regularization = 1e-9
```

Regularization не скрыта и входит в result/evidence.

## 7. Почему не оставлен первый semismooth вариант

Первый prototype semismooth Fischer-Burmeister solve столкнулся с singular generalized Jacobian на четырёх почти копланарных face rows.

Это не было замаскировано увеличением iteration count.

Дополнительно найден implementation bug в compact pivot code:

```text
if candidate > best: best = candidate; pivot = row
```

В GDScript `pivot = row` фактически выходил из ожидаемой условной семантики. Solver переписан на явные многострочные blocks; подобные `if ...: ...; ...` конструкции удалены из нового S1 runtime scope.

Accepted normal solve:

```text
canonical active set
+
partial-pivot dense restricted solve
+
explicit regularization
+
complementarity audit
```

## 8. Friction coupling

Однопроходная схема:

```text
normal LCP
then tangential PGS
```

была отвергнута тестом: friction impulses повторно открывали normal violation до порядка `3e-1`.

S1 поэтому использует outer fixed point:

```text
current tangential impulses
        ↓
absolute graph normal LCP
        ↓
normal impulses
        ↓
projected Coulomb tangent solve
        ↓
repeat until normal/friction fixed point
```

Strong sliding probe:

```text
8/8 rows = slide
coupling iterations = 253
max complementarity violation = 3.8684533357081426e-11
max cone violation = 6.938893903907228e-18
max normal velocity violation < 1e-9
```

Для каждого sliding row:

```text
|Pt| = mu * Pn
```

Caller contact ordering не является numerical input: input list canonicalized by persistent ID. Fresh replay и reversed input order дают exact identical solution signature.

## 9. Conservation / energy evidence

Strong sliding graph uses only internal equal/opposite impulses.

Observed:

```text
linear momentum error  = 8.921809491438631e-16
angular momentum error = 3.553147333202946e-15
kinetic energy delta   = -3.48593081473464
```

То есть current frictional solve dissipative на этом probe и не создаёт скрытый linear/angular momentum source выше double roundoff.

## 10. Exact S1 validation

Acceptance:

```text
110 / 110 PASS
```

Playground marker:

```text
FABRIC0_16_GENERAL_CONVEX_MULTIPOINT_MCP_S1_PLAYGROUND_PASS
```

Editor scan:

```text
SCRIPT / Parse / Compile errors: NONE
```

Exact executable hashes находятся в:

`validation/fabric0-compositional-world-fabric-v16-s1-validation.json`.

## 11. Что S1 доказывает

S1 даёт positive evidence для цепочки:

```text
convex polytope support mapping
+
GJK/EPA
+
true clipped four-point face manifold
+
persistent point IDs
+
AABB sweep-and-prune broadphase
+
8-row graph normal LCP
+
friction-cone fixed point
+
canonical caller-order independence
+
internal momentum audit
```

## 12. Что S1 НЕ доказывает

`FABRIC0.16 CLOSED` пока не заявляется.

Открыты:

- adaptive contact-appearance localization;
- adaptive separation localization;
- root-localized stick/slide transitions;
- persistent manifold evolution through time/event fixed points, а не только rebuild probe;
- same-world island decomposition + actual parallel island execution;
- production broadphase/thread pool/block-sparse backend;
- one monolithic globally certified Signorini-Coulomb MCP/NCP solve;
- rolling/torsional friction;
- exact simultaneous multi-impact fixed point;
- curved analytic support primitives;
- arbitrary mesh/non-convex decomposition;
- Construction/authority/persistence/network integration;
- full materialized DWS regression.

Current friction result — это graph normal LCP + converged outer normal/tangent fixed point, не заявление о завершённом universal semismooth MCP kernel.

## 13. Следующий S2

Следующий bounded step FABRIC0.16:

```text
S2 — ADAPTIVE CONVEX CONTACT EVENTS + SAME-WORLD PARALLEL ISLANDS
```

Цель:

```text
broadphase candidate interval
→ GJK distance/contact crossing localization
→ persistent manifold appear/disappear
→ root-localized stick/slide mode changes
→ contact graph island merge/split
→ deterministic island decomposition
→ actual Godot Thread solve of independent same-world islands
→ canonical join
→ refinement evidence
```

После S2 нужно снова решить, достаточно ли evidence для final FABRIC0.16 closure или нужен отдельный S3 для stronger monolithic MCP / simultaneous-impact wall.


## 14. S2 — Adaptive Convex Events + Same-World Parallel Islands

S2 executable boundary:

```text
first executable commit:
451bb9d09c527e3bf715c485f8929274157b7e1d

exact-byte repair / accepted executable head:
92588ac05a7fa5b3cedd64bb567436e82e3a0a0e
```

Status:

```text
IMPLEMENTED
EXACT LINUX DOUBLE PASS
102/102
S1 REGRESSION 110/110
REMOTE BYTE IDENTITY 5/5
S1 PREDECESSOR BLOBS PRESERVED 8/8
RESEARCH SLICE ONLY
FABRIC0.16 NOT CLOSED
```

### Contact/separation localization

S2 добавляет motion-aware candidate envelope и event localization поверх реального S1 GJK/EPA.

Exact contact boundary выявил важный numerical case: при zero-measure touch GJK может подтвердить boundary, но EPA не обязан построить объёмный tetrahedron. Поэтому коды:

```text
GJK_DEGENERATE_SIMPLEX
GJK_DEGENERATE_TETRAHEDRON
EPA_DEGENERATE_INITIAL_POLYTOPE
```

разрешены **только внутри bracketed event localization** как zero-measure boundary evidence при наличии normal hint. Они не превращены в общий collision success.

Accepted semantics:

```text
separated      support gap > 0
exact boundary support gap = 0
penetrating    -EPA depth < 0
```

Reference event times:

```text
CONTACT_APPEAR    0.50000000001455
CONTACT_DISAPPEAR 0.10000000004657
```

Contact appearance refinement errors:

```text
1e-4 -> 1.5258774510584772e-05
1e-6 -> 1.1922384146600962e-07
1e-8 -> 9.167706593871117e-10
```

Они строго уменьшаются.

### Persistent manifold across event

После localized appearance строится реальный S1 clipped manifold. На двух последовательных post-event samples:

```text
points = 4
IDs preserved
lifetime 1 -> 2
feature key preserved
penetration depth increases
```

То есть persistence теперь проверена не только arbitrary rebuild, но и после event boundary.

### Root-localized stick -> slide

S2 локализует transition surface по фактическому S1 graph solve, а не по заранее заданной кинематической формуле.

Reference:

```text
stick -> slide
t = 0.15798543221899
```

Refinement errors:

```text
1e-4 -> 4.0697341319173574e-06
1e-6 -> 2.2180029191076756e-07
1e-8 -> 2.0081643015146255e-09
```

Strictly decreasing.

### Same-world parallel islands

`Fabric0GeneralConvexParallelIslandsV1` выполняет:

```text
contact graph
-> deterministic connected components
-> canonical island snapshots
-> local contact index remap
-> actual Godot Thread per independent island
-> solve through S1 graph MCP
-> join only after all islands PASS
```

Acceptance world:

```text
island 1 = [A,B]
island 2 = [D,E]
contacts = 8 total manifold rows
threads started = 2
```

Parallel result equals one sequential block-diagonal solve exactly:

```text
parallel state error = 0
```

Reverse thread spawn order gives exact identical canonical signature.

### Transactional and lifecycle hardening

S2 explicitly fails closed on:

- duplicate body IDs;
- malformed/out-of-range contact body indices;
- self-contact;
- zero/bad thread budget;
- island count above allowed thread budget;
- worker solver failure.

Physical world state is committed only after every island result succeeds.

If one worker fails, original world state remains byte-equivalent at the velocity signature boundary.

If `Thread.start()` fails after earlier workers started, already started threads are joined before returning failure.

### Exact validation

Engine:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`.

S2:

```text
102 / 102 PASS
FABRIC0_16_S2_ADAPTIVE_CONVEX_EVENTS_PARALLEL_ISLANDS_PLAYGROUND_PASS
```

S1 regression:

```text
110 / 110 PASS
```

Editor parse/compile scan:

```text
CLEAN
```

Exact S2 Git blobs:

```text
event driver      287be7f45dc3fbb7abca583d6e5269f91a06cd6a
parallel islands  33c996cd2ba75403b17290c41205ae746cb18fd8
experiments       4ab61d8ded43e966dd4577e3c9a10d99aa920dab
acceptance        9a0a92063bf133aad2503acfbb3db302fdf76dea
playground        25cdec5bbb632d9b5f9990501ed34f97bdb57325
```

Remote byte identity is 5/5 PASS. All eight S1 executable blobs are preserved exactly.

One acceptance file initially landed with a different blob despite equivalent intended content. S2 was **not** accepted until a repair commit restored the exact locally tested blob and remote verification returned 5/5.

### S2 non-claims

S2 does not yet prove a full time trajectory in which these pieces all interact in one adaptive loop.

Still open before FABRIC0.16 closure:

- unified event-driven trajectory over contact appear/disappear + manifold rebuild + graph solve;
- island merge/split during that same trajectory;
- refinement of full trajectory state across event boundaries;
- energy ledger across localized contact/mode events;
- simultaneous multi-impact fixed point;
- stronger monolithic/global Signorini-Coulomb MCP/NCP claim;
- production broadphase/block-sparse/thread-pool backend.

## 15. Next slice — S3 Unified Event-Driven Convex Trajectory

```text
FABRIC0.16 S3

candidate interval
-> localize next contact/mode event
-> advance exactly to event boundary
-> rebuild/persist manifold
-> mutate contact graph
-> island merge/split
-> solve graph MCP
-> continue
-> compare refined trajectories
```

Primary closure question for S3:

> Do event times, complete rigid-body state and energy/momentum ledger converge together when the general-convex multipoint graph changes topology?
