# FABRIC0.9 — MULTI-CONTACT GEOMETRIC MANIFOLD + CONE SOLVE

**Статус:** research-only successor к FABRIC0.8.  
**Parent research head:** `8b7b28e9b3e1a9641a2d20e8f89c540f08a2a1ec`.

## 1. Исследовательский барьер

FABRIC0.8 доказал coupled differential/algebraic time, geometric scalar gap, solved normal/tangential impulse и same-time topology event iteration.

Но contact всё ещё имел специальную scalar shape:

```text
one normal channel
+
one tangent channel
```

Для реальной геометрии этого недостаточно.

Тело может одновременно:

- касаться нескольких точек одной поверхности;
- касаться нескольких разных поверхностей;
- вращаться;
- иметь разные contact velocities в разных точках;
- требовать coupled normal/tangential impulses;
- иметь избыточный contact manifold;
- получать разный неправильный результат, если solver последовательно обходит contacts.

FABRIC0.9 атакует эту границу.

## 2. Новая архитектурная цепочка

```text
geometry
    ↓
contact manifold
    ↓
stable contact identities
    ↓
normal + 2D tangent basis
    ↓
contact Jacobians
    ↓
global effective-mass matrix
    ↓
product of Coulomb friction cones
    ↓
one simultaneous impulse solve
    ↓
generalized post velocity
```

Главный принцип:

> Geometry определяет, где существуют constraints. Solver определяет reactions. Порядок обхода geometry/contact records не является физикой.

## 3. Первый geometry provider

Research provider:

`box against static planes`.

Body descriptor:

- mass;
- world-space diagonal inertia tensor;
- position;
- linear velocity;
- angular velocity;
- box half-extents;
- orientation Basis.

Plane descriptor:

- stable plane id;
- normal;
- offset;
- friction coefficient;
- restitution.

Compiler перечисляет box vertices, преобразует их через Basis в world space и вычисляет signed plane gap.

Contact создаётся только около event surface:

```text
abs(gap) <= contact_tolerance
```

Сильное penetration за пределами tolerance не скрывается; оно попадает в diagnostic:

`GEOMETRY_PENETRATION_OUTSIDE_EVENT_TOLERANCE`.

Это намеренно соответствует event-localized philosophy FABRIC0.7/0.8: manifold должен собираться около физического crossing instant, а не лечить глубокое проникновение эвристикой.

## 4. Stable geometry identity

Vertex identity не зависит от порядка перечисления:

```text
mx_my_mz
mx_my_pz
...
px_py_pz
```

Contact identity:

```text
<plane_id>::<vertex_id>
```

Примеры:

```text
floor::mx_my_mz
wall::mx_py_pz
```

Перед solve contacts всегда canonical-sort по id.

Plane enumeration тоже не влияет на canonical manifold order.

Это не просто удобство hashing. Stable identity нужна для:

- deterministic assembly;
- future warm start;
- persistent contact history;
- event evidence;
- distributed replay.

## 5. 2D tangent basis

Для каждого normal `n` строится deterministic orthonormal basis:

```text
n
t1
t2
```

Reference axis выбирается как global axis, наименее параллельная normal.

Проверяется:

```text
|n|=|t1|=|t2|=1

n·t1=0
n·t2=0
t1·t2=0
```

Таким образом friction больше не scalar `j_t`.

Каждый contact impulse:

```text
lambda_i =
(j_n, j_t1, j_t2)
```

## 6. Angular coupling через Jacobian

Generalized velocity одного rigid body:

```text
u =
[vx, vy, vz, wx, wy, wz]
```

Contact point offset от center of mass:

`r`.

Для direction `d` contact Jacobian row:

```text
J_d =
[d, r × d]
```

Следовательно:

```text
contact_velocity_d =
J_d u
```

Angular velocity напрямую меняет normal/tangential velocity каждой contact point.

Impulse в contact point создаёт одновременно:

- linear momentum;
- angular momentum через `r × impulse`.

## 7. Global effective-mass problem

Все contact rows собираются одновременно.

```text
J =
[J_n1
 J_t11
 J_t12
 ...
 J_nN
 J_tN1
 J_tN2]
```

World inverse generalized mass в текущем prototype:

```text
M^-1 =
diag(
  1/m,1/m,1/m,
  1/Ix,1/Iy,1/Iz
)
```

Global contact coupling:

```text
A =
J M^-1 J^T
```

То есть impulse одного contact способен изменить velocity всех остальных contact points через rigid body motion.

Contacts не решаются по одному.

## 8. Product of Coulomb cones

Для каждого contact admissible impulse:

```text
j_n >= 0

sqrt(j_t1^2 + j_t2^2)
<=
mu * j_n
```

Это настоящий 2D tangential Coulomb cone, а не отдельные независимые clamps по двум tangent axes.

FABRIC0.9 решает convex research impact candidate:

```text
minimize

1/2 lambda^T A lambda
+
b^T lambda

subject to

lambda_i ∈ CoulombCone(mu_i)
for every contact i
```

где:

```text
b_n = (1+e) * v_n^-

b_t1 = v_t1^-
b_t2 = v_t2^-
```

Эта форма используется как maximum-dissipation / cone-projected research candidate.

Не заявляется, что это универсальный production impact law для любых multi-contact restitution semantics.

## 9. Exact cone projection

В ADMM нужен projection:

```text
Proj_K(j_n, j_t)
```

для:

```text
K =
{
  j_n >= 0,
  ||j_t|| <= mu*j_n
}
```

Projection реализован аналитически.

Если point уже внутри cone — остаётся без изменений.

Если projected normal становится nonpositive — projection = zero.

Иначе projection попадает точно на:

```text
||j_t|| = mu*j_n
```

Это позволяет sliding contact естественно лежать на cone boundary.

## 10. Почему ADMM, а не sequential PGS

Последовательный contact solver легко превращает order of enumeration в скрытую физическую переменную.

FABRIC0.9 использует global convex system + ADMM splitting:

```text
lambda step:
  solve
  (A + rho I) lambda
  =
  rho(z-u) - b

z step:
  project every contact block
  onto its friction cone

u step:
  dual update
```

`A + rho I` factorizes один раз Cholesky.

Каждая iteration после этого использует triangular solves + cone projections.

Research parameters:

```text
rho = 0.1
tolerance = 1e-9
max iterations = 12000
```

Main experiment converges за:

`2395 iterations`.

ADMM rho — numerical splitting parameter, не physical coefficient.

## 11. Main experiment — box simultaneously touches floor + wall

Body:

```text
mass = 2

position =
(0.5, 0.5, 0)

half extents =
(0.5, 0.5, 0.75)

linear velocity =
(-2, -3, +1)

angular velocity =
(+0.4, +0.2, -0.6)

world diagonal inertia =
(0.5, 1.2, 0.8)
```

Planes:

```text
floor:
  normal=(0,1,0)

wall:
  normal=(1,0,0)

mu=0.25
e=0.2
```

Geometry compiler получает:

`8 contacts`.

Canonical IDs:

```text
floor::mx_my_mz
floor::mx_my_pz
floor::px_my_mz
floor::px_my_pz

wall::mx_my_mz
wall::mx_my_pz
wall::mx_py_mz
wall::mx_py_pz
```

## 12. Coupled result

Global solve:

```text
contact impulse unknowns = 24

rank(J M^-1 J^T) = 6
```

Это важный результат.

Rigid body имеет только 6 generalized velocity DOF, а manifold задаёт 24 impulse coordinates.

Следовательно reaction distribution сильно избыточна.

Solver нашёл:

```text
active contacts = 5
sliding contacts = 5
```

Все active friction impulses находятся на cone boundary.

Post linear velocity:

```text
(0.589721054,
 0.776797774,
 0.238711754)
```

Post angular velocity:

```text
(-0.074797351,
 -0.022468940,
  0.122242645)
```

## 13. Impulse / torque audit

Total world impulse:

```text
(5.17944211,
 7.55359555,
-1.52257649)
```

Total torque impulse:

```text
(-0.23739868,
 -0.26696273,
  0.57779412)
```

Проверено:

```text
m (v+ - v-)
-
sum(contact impulses)
=
0
```

и:

```text
I (w+ - w-)
-
sum(r × contact_impulse)
=
0
```

Exact acceptance residuals ниже `1e-9`.

## 14. Cone admissibility

Для каждого contact проверено:

```text
j_n >= 0

||j_t||
<=
mu*j_n
```

Maximum cone violation:

`~0 within double precision printout`.

Пять active contacts находятся на:

```text
||j_t||/(mu*j_n) = 1
```

то есть solver действительно использует 2D sliding cone boundary.

## 15. Energy audit

Pre-impact kinetic energy:

`14.208`.

Post:

`1.015847883`.

Delta:

`-13.192152117`.

Для этого dissipative impact candidate энергия не создаётся.

Это не доказательство общей energy law для всех restitution/contact manifolds, но конкретный coupled multi-surface test проходит noncreation gate.

## 16. Post-contact admissibility

После simultaneous solve normal contact velocities всех 8 constraints:

```text
>= 0
```

То есть ни одна compiled contact point не продолжает двигаться внутрь статической поверхности.

При этом impulses получили contacts с обеих поверхностей:

- floor;
- wall.

Это один coupled corner solve, а не несколько независимых single-plane experiments.

## 17. Order invariance — главный acceptance FABRIC0.9

Проверены три входа:

1. normal plane/contact enumeration;
2. contacts полностью reversed;
3. planes reversed + contacts reversed.

Все три дают одинаковые:

- canonical contact identities;
- post linear velocity;
- post angular velocity;
- per-contact canonical impulse map;
- final state hash.

Hash:

`181d3a3cd0e4d0439c79b5ed6afd9939cc88c94276446e148ab8cdf0c453c7b5`.

Сравнение hash — exact equality.

Следовательно input enumeration order не входит в physical semantics этого prototype.

## 18. Очень важный урок: deterministic != unique

Main matrix:

```text
rank = 6
unknown impulses = 24
```

Это означает, что reaction distribution по избыточным contact coordinates может не быть математически уникальной.

FABRIC0.9 сознательно различает:

### Более фундаментальные observables

- generalized post velocity;
- total impulse;
- total torque impulse;
- cone admissibility;
- conservation/dissipation audit.

### Reaction representative

Per-contact impulse distribution.

Canonical identity + zero deterministic initialization + global ADMM дают reproducible representative.

Но нельзя делать ложный вывод:

```text
deterministic reaction split
=
unique physical reaction truth
```

Это особенно важно для persistence/network replication: возможно, сохранять следует не каждую внутреннюю reaction как canonical state, а достаточные observables/evidence в зависимости от use case.

## 19. Fail-closed geometry metadata

Acceptance отдельно проверяет:

- zero/nonpositive body mass;
- zero plane normal.

Они не исправляются автоматически.

Diagnostics:

```text
BODY_MASS_NONPOSITIVE

PLANE_NORMAL_ZERO
```

## 20. Exact validation

Runtime:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`.

Focused:

`136/136 PASS`.

Playground:

`FABRIC0_9_MULTICONTACT_CONE_PLAYGROUND_PASS`.

Predecessor regressions:

```text
FABRIC0.8 Coupled Hybrid DAE     71/71 PASS

FABRIC0.7 Hybrid Time            88/88 PASS

FABRIC0.6 Nonsmooth            121/121 PASS

FABRIC0.6 Compatibility          42/42 PASS
```

Editor scan:

`CLEAN`.

Все 4 executable FABRIC0.9 файла byte-identical между locally tested exact-double bytes и GitHub blobs.

## 21. Что доказано

FABRIC0.9 показывает:

- geometry может автоматически породить несколько contacts;
- одна geometry state может одновременно породить contacts с разными surfaces;
- каждый contact получает stable identity;
- tangent space двухмерный;
- angular velocity входит в contact Jacobians;
- global effective-mass matrix couples contacts;
- 2D Coulomb friction выражается настоящим cone constraint;
- все contacts решаются одновременно;
- solution не зависит от input contact/plane order;
- normal/tangential impulses дают correct linear/angular impulse audit;
- dissipative main experiment не создаёт kinetic energy;
- redundant contact manifold выявляется явно;
- deterministic reaction representative не объявляется уникальной физической истиной.

## 22. Что НЕ доказано

FABRIC0.9 остаётся research prototype:

- только один dynamic body против static planes;
- geometry provider пока box-plane, не arbitrary convex/mesh geometry;
- orientation участвует в geometry transform, но inertia tensor solver path пока world-space diagonal;
- нет dynamic body-body contacts;
- нет continuous resting-contact lifecycle;
- нет persistent manifold matching между timesteps;
- нет warm-start cache;
- нет sparse contact islands;
- ADMM dense;
- Cholesky dense;
- 2395 iterations в main test — это proof of semantics, не production performance;
- multi-contact restitution objective является research candidate, не универсально доказанным impact law;
- redundancy не устраняется manifold reduction;
- per-contact reaction uniqueness не доказана;
- FABRIC0.9 solver ещё не встроен обратно в FABRIC0.8 event-time DAE loop;
- нет production Construction / persistence / authority / replication integration;
- нет full materialized DWS regression.

## 23. Следующий falsification wall

### FABRIC0.10 — PERSISTENT CONTACT GRAPH + SPARSE HYBRID DAE

Следующий шаг должен связать FABRIC0.8 time и FABRIC0.9 multi-contact в долгоживущую систему.

Нужны:

```text
generic geometry contact-provider boundary
persistent contact identities across time
contact appear / persist / disappear lifecycle
dynamic body-body contacts
contact graph islands
sparse J / sparse effective-mass assembly
warm-start by stable contact identity
resting-contact complementarity
multi-contact cone solve inside event-time DAE
topology split/merge of contact islands
deterministic island replay
```

Критический falsification experiment:

```text
several dynamic bodies
forming a stack / bridge,
contacts appear and disappear,
some contacts stick and some slide,
solver decomposes independent islands,
warm-start survives contact persistence,
and reversing body/contact enumeration
does not change physical result.
```

Если для этого потребуется вернуть object-order callbacks как physical truth, гипотеза FABRIC должна считаться повреждённой.

## 24. Архитектурный вывод

> FABRIC0.9 делает geometry не collision callback owner, а compiler input для глобального cone-constrained reaction problem.

Это research evidence, не production promotion.
