# FABRIC0.8 — COUPLED HYBRID DAE / EVENT ITERATION

**Статус:** research-only successor к FABRIC0.7.  
**Parent research head:** 7a64988e8964e4488693b4cd202e02e94ae90075.

## 1. Исследовательский барьер

FABRIC0.7 доказал FLOW / JUMP / TOPOLOGY TRANSACTION, event localization, reset maps, hysteresis и macrostep rollback.

Но temporal ODE и algebraic/nonsmooth FABRIC physics оставались рядом, а не одной системой. RK-stage не обязан был решать algebraic network; guard не мог быть настоящей функцией solved reaction; impact reset был явной формулой.

FABRIC0.8 атакует именно эту трещину.

## 2. Semi-explicit Hybrid DAE

Новая форма:

~~~text
F(x, y, p, t, topology) = 0

dx/dt = f(x, y, p, t, topology)
~~~

где x — differential state, y — algebraic unknown/reaction.

На каждой RK4 stage:

1. фиксируется trial x;
2. решается algebraic system F=0;
3. из solved y вычисляется derivative;
4. следующая stage снова решает algebraics.

Следовательно algebraic reaction участвует в trajectory, а не вычисляется после неё.

Это research semi-explicit, locally index-1-like form. Не заявляется arbitrary production DAE: нет symbolic index reduction, higher-index constraints, sparse global Jacobian или production consistent initialization.

## 3. Algebraic contract

Algebraic unknown имеет value, dimension и nominal.

Residuals dimension-checked.

Inner solve:

~~~text
bounded damped Newton
+ derivative with respect to algebraic unknowns
+ normalized residual
+ tangent-rank validation
~~~

Сохраняется урок FABRIC0.5: F=0 недостаточно, если manifold недоопределена.

Вырожденный пример:

~~~text
0 * y = 0
~~~

получает:

DAE_SINGULAR_ALGEBRAIC_MANIFOLD.

## 4. Topology становится частью equation program

Expression DSL получил bond_active(bond_id).

Пример:

~~~text
f_a - drive_force * bond_active(drive_link) = 0
~~~

Bond active:

~~~text
f_a = drive_force
~~~

После topology break:

~~~text
f_a = 0
~~~

Именно topology, а не название mode, меняет physical equation.

## 5. Guards могут зависеть от solved algebraics

Event surface может использовать state, algebraic reaction, parameters, time и topology.

Во время bisection каждая probe:

~~~text
integrate coupled segment
→ solve algebraics
→ evaluate guard
~~~

Поэтому event time теперь может зависеть от solved reaction.

## 6. Generic jump / impulse solve

FABRIC0.8 добавляет jump equation system.

Jump unknown vector может содержать:

~~~text
post-state values
+ impulse/reaction unknowns
~~~

Jump branch:

~~~text
residuals = 0
inequalities >= 0
~~~

Это temporal analogue FABRIC0.6 HybridRelation.

Impulse не вызывается procedural apply_impulse(). Он решается как неизвестная реакция, удовлетворяющая momentum, restitution и friction constraints.

## 7. Same-time event iteration

Один root event может породить другой transition в том же physical instant.

Semantics:

~~~text
root crossing
→ solve jump
→ commit state
→ re-solve algebraic network at same t
→ evaluate condition transitions
→ mode/topology transaction
→ re-solve algebraic network at same t
→ repeat until fixed point
~~~

Research cap:

MAX_EVENT_ITERATIONS = 16.

Event instant identity:

fabric0/instant/000001.

Если fixed point не достигнут:

EVENT_ITERATION_NO_FIXED_POINT.

## 8. Главный falsification experiment — два тела

Не вводятся kernel classes RigidBody, CollisionObject, ContactSolver, FrictionObject или Breaker.

State:

~~~text
x_a = 0
x_b = 2

normal:
v_a = +3
v_b = -1

tangent:
v_t_a = +2
v_t_b = -1
~~~

Masses:

~~~text
m_a = 2
m_b = 1
~~~

Algebraic drive:

~~~text
drive_force = 2 N

f_a = 2 N * bond_active(drive_link)
f_b = 0
~~~

Flow:

~~~text
x_a_dot = v_a
x_b_dot = v_b

v_a_dot = f_a / m_a
v_b_dot = f_b / m_b
~~~

## 9. Geometric impact localization

Gap:

~~~text
g = x_b - x_a
~~~

Impact — downward crossing g=0.

До contact тело A имеет acceleration 1 m/s².

Аналитический root:

~~~text
t_hit = -4 + sqrt(20)
      = 0.4721359549995796
~~~

FABRIC localized:

~~~text
0.472135955002
~~~

Position:

~~~text
x_a ~= x_b ~= 1.527864045
~~~

## 10. Normal impulse solve

До impact:

~~~text
v_a- = 3.472135955
v_b- = -1

relative normal = -4.472135955
~~~

Restitution e=0.5.

Equations:

~~~text
m_a (v_a+ - v_a-) + j_n = 0
m_b (v_b+ - v_b-) - j_n = 0

(v_b+ - v_a+)
+ e (v_b- - v_a-)
= 0
~~~

Solved:

~~~text
j_n = 4.472135955

v_a+ = 1.236067978
v_b+ = 3.472135955
~~~

Проверено сохранение total normal momentum и restitution relation.

## 11. Tangential Coulomb impulse

mu = 0.3.

Pre relative tangent = -3.

Generic branches:

~~~text
stick:
  relative tangent+ = 0
  -mu*j_n <= j_t <= +mu*j_n

slide_neg:
  j_t = +mu*j_n
  relative tangent+ <= 0

slide_pos:
  j_t = -mu*j_n
  relative tangent+ >= 0
~~~

Solver выбирает slide_neg.

~~~text
j_t = 1.341640787
mu*j_n = 1.341640787

v_t_a+ = 1.329179607
v_t_b+ = 0.341640787
relative tangent+ ~= -0.987538820
~~~

Tangential momentum сохранён. Total kinetic energy после impact ниже pre-impact: restitution и sliding friction не создают энергию.

## 12. Solved impulse порождает structural event в том же instant

Threshold:

break_impulse = 4 N*s.

После impact:

~~~text
last_j_n = 4.472135955 > 4
~~~

Поэтому в том же event instant активируется break_on_impulse.

Ordered transitions:

~~~text
1. impact
2. break_on_impulse
~~~

После impact, но до break, immediate algebraic re-solve:

~~~text
f_a = 2 N
~~~

Topology transaction:

~~~text
drive_link active -> false
topology_revision 0 -> 1
~~~

Следующий DAE solve в том же physical time:

~~~text
f_a = 0
f_b = 0
~~~

Это центральное доказательство FABRIC0.8: solved jump может породить same-time topology mutation, после которой algebraic physics перекомпилируется до продолжения времени.

## 13. Remaining flow использует новую topology

После event instant оставшаяся часть dt идёт уже без drive force.

В t=1:

~~~text
x_a = 2.180339888
x_b = 3.360679775

v_a = 1.236067978
v_b = 3.472135955

gap = 1.180339888

f_a = 0
f_b = 0
~~~

Playground:

~~~text
algebraic solve calls = 203
event iterations = 3
~~~

Большое число solve calls ожидаемо: event localization многократно интегрирует coupled DAE.

## 14. Отдельный algebraic-reaction guard test

State:

~~~text
x_dot = 1 m/s
~~~

Algebraic relation:

~~~text
reaction - k*x = 0
k = 2 N/m
~~~

Guard:

~~~text
reaction - 2 N = 0
~~~

Transition локализован в t=1 с reaction=2 N.

После продолжения до t=1.5:

~~~text
x = 1.5
reaction = 3 N
~~~

Это доказывает, что event localization действительно зависит от solved algebraic reaction.

## 15. Deterministic replay

Fresh identical systems дают одинаковые event JSON и final state hash:

f564e9294b738d65783cefcbc03e18e54860c61541143be7dd2421d6223e9b19.

Event instant хранит time, ordered transitions, pre/post states, pre/post algebraics, jump branch, impulse values и topology revisions.

## 16. Exact validation

Runtime:

Godot 4.7.1.stable.double.custom_build.a13da4feb.

Focused:

71/71 PASS.

Regression:

~~~text
FABRIC0.7 Hybrid Time        88/88 PASS
FABRIC0.6 Nonsmooth        121/121 PASS
FABRIC0.6 Compatibility     42/42 PASS
~~~

Playground:

FABRIC0_8_COUPLED_HYBRID_DAE_PLAYGROUND_PASS.

Editor parse/compile:

CLEAN.

Все четыре FABRIC0.8 executable файла byte-identical между locally tested exact-double bytes и GitHub blobs.

## 17. Связь с известной математикой

FABRIC0.8 не заявляет изобретение hybrid DAE или contact complementarity.

Исследовательские ориентиры:

- Modelica hybrid DAE semantics: continuous DAE integration, event localization, algebraic event solve и event iteration;
- Stewart & Trinkle, 1996 — implicit time stepping for rigid-body dynamics with inelastic impacts and Coulomb friction;
- Anitescu & Potra, 1997 — complementarity formulation for multi-rigid-body contact with friction.

FABRIC исследует архитектурный вопрос: можно ли такие математические формы сделать общей grammar persistent constructible world, сохранив topology, dimensions, device-agnostic laws, event history и Construction ownership.

## 18. Что доказано

FABRIC0.8 показывает:

- differential и algebraic state участвуют в одном timestep;
- algebraics решаются на каждой RK stage;
- topology участвует непосредственно в algebraic equations;
- event guard может зависеть от solved reaction;
- event localization повторно решает coupled DAE;
- impact impulse является solved unknown;
- momentum/restitution и Coulomb branch живут в одном generic jump system;
- same-time event iteration может породить topology mutation из solved impulse;
- DAE re-solves после topology mutation до продвижения времени;
- remaining flow использует новую topology;
- singular algebraic physics fail-closed;
- deterministic event/reaction/topology replay сохраняется.

## 19. Что НЕ доказано

Research prototype ограничен:

- dense Newton и dense linear solve;
- RK4 + bisection, без adaptive error control;
- нет arbitrary higher-index DAE;
- нет symbolic index reduction;
- нет production consistent initialization;
- jump branch enumeration, не scalable cone solver;
- один normal и один tangential scalar contact channel;
- нет 3D orientation/inertia tensor;
- нет multi-point contact manifold;
- нет rolling/spinning friction;
- нет simultaneous multiple geometric impacts;
- same-time condition transitions пока детерминированно сериализуются;
- v8 использует v6 topology state, но ещё не компилирует автоматически весь historical Conservation Cell / Power Map graph в DAE residuals;
- нет sparse graph compiler;
- нет production Construction integration;
- нет distributed authority/persistence/replication;
- нет полного materialized DWS regression.

## 20. Следующий falsification wall

### FABRIC0.9 — MULTI-CONTACT GEOMETRIC MANIFOLD + CONE SOLVE

Нужно убрать scalar-contact special shape:

~~~text
geometry-derived contact manifold
multiple contact points
normal Jacobians
2D tangential basis
friction cone / cone complementarity
angular velocity + inertia tensor
simultaneous impacts
contact graph islands
order-invariant contact solve
warm-start / sparse solve
~~~

Критический experiment: одно тело одновременно касается нескольких поверхностей, вращается, скользит/залипает, получает несколько coupled impulses, и результат не зависит от порядка перечисления contacts.

Если для этого понадобится device-specific CollisionObject.solve(), гипотеза FABRIC должна считаться повреждённой.

## 21. Архитектурный вывод

> FABRIC начинает выглядеть не как объектный physics engine, а как компилятор изменяемой topology в hybrid differential-algebraic physical program.

Это research evidence, не production claim.
