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
