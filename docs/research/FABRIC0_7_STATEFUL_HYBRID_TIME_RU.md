# FABRIC0.7 — STATEFUL HYBRID TIME

**Статус:** research-only successor к FABRIC0.6.  
**Цель:** добавить универсальную временную семантику для continuous flow, локализованных событий, discrete mode, simultaneous reset и atomic topology mutation — без device-specific runtime classes.

## 1. Почему FABRIC0.6 было недостаточно

FABRIC0.6 умеет выражать nonsmooth state как набор допустимых manifold branches:

~~~text
residuals = 0
inequalities >= 0
~~~

Но этого недостаточно, чтобы ответить:

- когда именно произошло переключение;
- что было состоянием непосредственно до события;
- что стало состоянием сразу после;
- как мгновенно изменить continuous state;
- как атомарно изменить topology;
- как продолжить оставшуюся часть timestep;
- что делать при слишком большом числе событий.

FABRIC0.7 отделяет пространство допустимых состояний от семантики эволюции во времени.

## 2. Три разных вида изменения мира

Каноническая временная триада FABRIC:

### FLOW

Непрерывная эволюция:

~~~text
dx/dt = f(mode, x, p, t)
~~~

### JUMP

Мгновенное изменение continuous/discrete state:

~~~text
x+ = R(x-, p, te)
mode+ = target_mode
~~~

### TOPOLOGY TRANSACTION

Структурное изменение physical graph:

~~~text
validate all operations
then commit all
or commit none
~~~

Эти операции нельзя сливать в один procedural update(). Они имеют разные causal и persistence semantics.

## 3. Hybrid timeline

Timeline хранит:

~~~text
time
continuous states
parameters
modes
transitions
event ledger
diagnostics
step revision
topology revision
optional bound physical network
~~~

Continuous state имеет value, dimension, nominal.

Mode задаёт flow expressions. Missing flow означает zero derivative.

## 4. Dimension contract во времени

FABRIC0.5 dimension algebra продолжает действовать.

Для state x:

~~~text
dimension(dx/dt)
=
dimension(x) / time
~~~

Поэтому mode flow, имеющий dimension state вместо state/time, отвергается как FLOW_DIMENSION_MISMATCH.

Reset expression должен иметь ту же dimension, что reset state. Иначе RESET_DIMENSION_MISMATCH.

Guard может иметь собственную physical dimension; numerical crossing tolerance масштабируется nominal value, а не требует искусственно превращать guard в безразмерную величину.

## 5. Макро-шаг является транзакцией

Главная operational semantics:

~~~text
snapshot(t0)

flow t0 -> te
        |
        v
localized event
        |
        v
pre-event snapshot
        |
        v
simultaneous reset
+ mode transition
+ topology transaction
        |
        v
post-event snapshot
        |
        v
flow te -> t1
~~~

Если jump/topology transaction invalid или возникает event storm:

~~~text
rollback entire advance(dt)
~~~

То есть не остаётся частично применённого макро-шага.

## 6. Событие локализуется внутри timestep

Событие не происходит «в конце кадра, где условие стало true».

Prototype:

- continuous flow: RK4;
- event crossing: start/end guard sign;
- localization: bisection;
- event time tolerance: 1e-11;
- max localization iterations: 64.

Макро-шаг разбивается:

~~~text
t0 ---------------- te ---------------- t1
        flow            jump       flow
~~~

## 7. Directional guard

Transition guard содержит expr, nominal, direction.

Direction:

~~~text
+1  negative -> nonnegative
-1  positive -> nonpositive
 0  either crossing
~~~

Exact zero at segment start сам по себе не retrigger-ит transition. Это минимальная защита от мгновенного повторного firing после reset на event surface.

## 8. Reset map использует immutable pre-state

Все reset RHS вычисляются из одного и того же pre-event snapshot.

Только после вычисления всех RHS assignments commit одновременно.

~~~text
a+ = pre(b)
b+ = pre(a)
~~~

действительно меняет значения местами.

Порядок записей в reset dictionary не влияет на результат.

Это принципиально для deterministic replay.

## 9. Topology mutation является atomic transaction

Текущий research op:

~~~text
set_bond_active(bond_id, active)
~~~

Перед commit:

1. physical network должен существовать;
2. все operation types должны быть поддержаны;
3. все bond identities должны существовать;
4. один bond не должен встречаться дважды в transaction.

Только после полной validation применяются изменения.

Если хотя бы одна operation invalid, весь advance(dt) откатывается.

Это исключает half-broken construct topology.

## 10. Event ledger

Каждый committed jump получает:

~~~text
event_id
sequence
transition_id
time
pre_mode
post_mode
pre_states
post_states
pre_state_hash
post_state_hash
topology_revision_before
topology_revision_after
~~~

Текущий event_id локально детерминирован:

~~~text
fabric0/event/<sequence>/<transition_id>
~~~

Это ещё не global distributed identity, но намеренно подготавливает мост к будущим time identity / action identity / observed-state identity / historical query concepts. FABRIC не становится владельцем этих network/control foundations.

## 11. Deterministic simultaneous-event ordering

Если несколько transitions локализуются в практически один момент:

1. меньший event time;
2. при равенстве — меньший numeric priority;
3. затем lexical transition id.

Это делает prototype deterministic.

Но это не полноценная same-time event iteration. FABRIC0.8 должен уметь решать набор одновременно активированных events до fixed point.

## 12. Event storm / Zeno protection

MAX_EVENTS_PER_ADVANCE = 32.

При превышении:

ZENO_OR_EVENT_STORM

и весь macrostep rollback.

Это fail-closed guard, а не математическое решение Zeno behavior.

## 13. Experiment T1 — bouncing impact + restitution

States:

~~~text
h = height
v = velocity
~~~

Flow:

~~~text
dh/dt = v
dv/dt = -g
~~~

Parameters:

~~~text
g = 9.81 m/s^2
e = 0.8
~~~

Initial:

~~~text
h=1
v=-1
~~~

Transition:

~~~text
guard:
  h = 0
  downward crossing

reset:
  h+ = 0
  v+ = -e * v-
~~~

На macrostep dt=0.6:

~~~text
localized impact time = 0.360950562279
pre-impact v          = -4.540925016
post-impact v         = +3.632740013
~~~

Проверка restitution:

~~~text
v+ = -0.8 * v-
~~~

Проверка kinetic-energy ratio:

~~~text
KE+ / KE- = e^2 = 0.64
~~~

После оставшейся части macrostep:

~~~text
h = 0.588110029
v = 1.287665029
t = 0.6
~~~

Это первый FABRIC experiment, где физически значимый jump происходит не на frame boundary, а внутри timestep.

## 14. Experiment T2 — Schmitt-like hysteresis

Thresholds:

~~~text
upper = 1.0
lower = 0.2
~~~

Ramp up:

~~~text
off -> on at t=1
~~~

В deadband:

~~~text
x=0.7
mode remains on
no event
~~~

После crossing lower:

~~~text
on -> off at total t=2.2
~~~

Hysteresis появляется из discrete mode + разных event surfaces, а не из специального Schmitt device class.

## 15. Experiment T3 — irreversible breaker + topology transaction

Bound FABRIC0.6 physical network содержит bond fuse_link.

Continuous state damage:

~~~text
damage_dot = 2 / s
trip at damage = 1
~~~

Event:

~~~text
te = 0.5
mode armed -> tripped
damage+ = 1
disable fuse_link
topology_revision 0 -> 1
~~~

После trip дальнейший advance не возвращает bond.

В kernel нет Breaker class.

## 16. Experiment T4 — simultaneous reset

Pre-event:

~~~text
a=1
b=2
~~~

Reset:

~~~text
a+ = pre(b)
b+ = pre(a)
clock+ = 0
~~~

Post-event:

~~~text
a=2
b=1
~~~

Это доказывает snapshot semantics.

## 17. Experiment T5 — topology transaction rollback

Transition пытается одновременно disable existing fuse_link и missing_link.

Validation обнаруживает TOPOLOGY_TRANSACTION_UNKNOWN_BOND.

Результат macrostep:

~~~text
rolled_back = true
time = 0
mode = armed
clock = 0
fuse_link still active
event ledger unchanged
state hash restored
~~~

## 18. Experiment T6 — event storm rollback

State clock пересекает event surface каждые 0.01 s, а reset возвращает clock к zero.

advance(1.0) потребовал бы около 100 jumps.

После лимита prototype aborts:

ZENO_OR_EVENT_STORM.

Весь macrostep откатывается:

~~~text
time=0
clock=0
events=[]
state hash restored
~~~

## 19. Predecessor regression

После добавления FABRIC0.7 отдельно повторно пройдены:

- FABRIC0.6 Nonsmooth Acceptance: 121/121 PASS;
- FABRIC0.6 Predecessor Compatibility: 42/42 PASS.

FABRIC0.7 не переписывает historical nonsmooth solver.

## 20. Что доказано

FABRIC0.7 показывает:

- continuous state может иметь dimension-checked flow;
- event surface локализуется внутри macrostep;
- jump имеет explicit pre/post state;
- reset map order-independent;
- discrete mode создаёт реальный hysteresis;
- irreversible mode может атомарно менять topology;
- topology change имеет revision identity;
- event получает deterministic identity/history;
- invalid event transaction rolls back macrostep;
- event storm/Zeno-like behavior fail-closed;
- deterministic replay сохраняет event list и final state hash;
- FABRIC0.6 semantics пережили добавление time layer.

## 21. Что НЕ доказано

Текущий prototype сознательно ограничен:

- RK4 + bisection, не adaptive integrator;
- не symplectic и не structure-preserving;
- continuous flow не пере-решает FABRIC0.6 algebraic/nonsmooth physical network на каждой RK stage;
- breaker topology связывает time layer с physical network, но continuous ODE и network equations пока не являются единой DAE system;
- bouncing impact использует explicit reset map, а не multi-body impulse complementarity solve;
- нет geometric contact gap state в общей physical network;
- нет simultaneous same-time event fixed-point iteration;
- нет mode invariants/domain constraints;
- нет arbitrary algebraic state inside hybrid timeline;
- topology transaction пока поддерживает только set_bond_active;
- macrostep rollback пока знает только timeline state и bond active state;
- event identity локальна, не distributed authority identity;
- нет persistence/replication integration;
- нет full materialized DWS checkout regression.

## 22. Следующая фундаментальная граница

### FABRIC0.8 — COUPLED HYBRID DAE / EVENT ITERATION

Следующий wall:

> continuous storage, algebraic Conservation/PowerMap/nonlinear/nonsmooth network и hybrid events должны решаться как одна временная система.

Нужно:

1. на каждом integration stage решать algebraic physical island;
2. guards могут зависеть от solved algebraic reactions;
3. event-time jump может решать impulse/reaction system;
4. simultaneous same-time events должны проходить event iteration до fixed point;
5. audit mass/momentum/energy через jump;
6. topology mutation должна перекомпилировать equation islands внутри того же event instant.

Ключевой falsification experiment:

~~~text
two masses
+ geometric gap
+ unilateral contact
+ impact impulse
+ restitution
+ friction
+ topology/state event
~~~

без CollisionObject как владельца физической истины.

## 23. Epistemic status

FABRIC0.7 синтезирует известные сильные идеи hybrid systems — continuous flows, guards, zero-crossing localization, reset maps, discrete modes и Zeno awareness — с уже построенными FABRIC concepts: dimensions, physical ports, Conservation Cells, Power Maps, nonsmooth relations и mutable topology.

Не заявляется новая фундаментальная математика.

Исследовательская гипотеза остаётся архитектурной:

> persistent world может быть выражен как композиционная физическая ткань, где topology, equations, continuous flow и discrete jumps являются разными слоями одной grammar, а device names остаются семантикой, не kernel behavior.
