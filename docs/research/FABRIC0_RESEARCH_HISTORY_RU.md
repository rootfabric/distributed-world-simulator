# FABRIC0 — подробная история исследования и принятых решений

Этот документ сохраняет narrative research memory: почему каждый шаг появился, что он доказал и как изменил следующий вопрос.

## Исходная гипотеза

Нужен мир, в котором сложные устройства можно строить из общих элементов.

Изначальная интуиция:

```text
Body
Constraint
Storage
Conduit
Resistance
Transformer
Transducer
Switch
Sensor
Actuator
Controller
FieldCoupler
```

Однако было решено не фиксировать этот список как окончательную объектную модель. Эксперименты должны были показать, какие понятия действительно фундаментальны.

## FABRIC0.1 — scalar compositional playground

Первый вопрос:

> Можно ли вообще получить различимое device behavior из generic local laws?

Были сделаны generic:

- source;
- gain;
- transducer;
- threshold;
- gate;
- integrator;
- sink;
- typed bonds;
- breakable topology.

Experiments:

- switchable lamp-like behavior;
- electric→rotational conversion chain;
- breakable link;
- один feedback pattern для tank и heater;
- proximity door;
- deterministic replay.

Результат: 44 assertions PASS.

Главный урок:

- compositional approach жизнеспособен;
- но directed scalar graph всё ещё слишком похож на signal processing;
- reaction physics не доказана.

Следующий wall: inline stateful element + inertia/reaction.

## FABRIC0.2 — Switch и coupled rotational wall

Пользователь отдельно попросил настоящий выключатель, который зажигает лампу.

Это был полезный тест: Switch должен стать reusable Element, а не shortcut в experiment.

Получено:

```text
battery -> Switch -> lamp
```

OPEN/CLOSED/OPEN корректно меняет power и lit state.

Тот же Switch переиспользован в torque domain.

Добавлены generic:

- rotational inertia;
- viscous load.

Возник coupled directed feedback:

```text
torque
→ inertia
→ angular velocity
→ load
→ reaction torque
→ inertia
```

После отключения drive вращение сохраняется и затухает.

Результат: 70 assertions PASS.

Главный урок:

- state и reaction можно выразить generic laws;
- но directed feedback всё ещё не является полноценной acausal physical network;
- следующий wall должен быть общей точкой соединения с conservation.

## FABRIC0.3 — Conservation Cell

Ключевой вопрос:

> Что такое физический junction, если не device object?

Решение:

Physical ports + active bonds автоматически компилируются в connected components — **Conservation Cells**.

Для каждого domain выбирается:

```text
common_quantity
balance_quantity
```

и:

```text
common * balance = power
```

Cell:

```text
all common equal
sum balances = 0
```

Experiments:

- two-source + load;
- source role reversal;
- ideal common constraint с Lagrange reaction;
- conflicting constraints fail-closed;
- floating network fail-closed;
- topology split/rejoin;
- two-cell bridge;
- same solver semantics in rotational domain.

Результат: 119 assertions PASS.

Особенно важный результат:

weak "source" при общем состоянии стал consumer без смены класса.

Главный урок:

> source/sink — emergent role solved state.

Следующий wall: соединить разные domains power-preserving способом без Motor class.

## FABRIC0.4 — Power Map

Вопрос:

> Можно ли выразить transduction не специальным transformer device, а общей geometry constraints?

Введено:

```text
A q = 0
b = -A^T lambda
```

Отсюда:

```text
q^T b = 0
```

Experiments:

### motor-like

```text
electrical equilibrium
→ Power Map V-2omega=0
→ rotational storage
→ drag
```

Система раскручивается.

### open circuit

После разрыва electrical bond:

- остаётся back-EMF-like common;
- current=0;
- map torque=0.

### reverse generator

Та же карта автоматически передаёт power обратно.

### differential

Трёхпортовая relation:

```text
omega_left + omega_right - 2 omega_carrier = 0
```

выдала differential-like speed relation и conjugate torques.

Результат: 89 assertions + 49 compatibility PASS.

Главный урок:

> Motor, Generator и Differential могут быть patterns одной constraint grammar.

Также введён generic storage с явным numerical dissipation ledger.

Следующий wall: dimensions и nonlinear laws.

## FABRIC0.5 — Dimensions + nonlinear residual language

Две проблемы:

1. `V - 2omega=0` скрывало размерный смысл коэффициента;
2. реальная физика нелинейна.

Введена SI base-dimension exponent algebra.

Domain обязан быть power-conjugate.

Power Map coefficient теперь имеет dimension.

Hidden conversion fail-closed.

Введён generic:

```text
F(common,balance,parameters)=0
```

Expression language:

- constants/parameters;
- common/balance;
- add/sub/mul/div;
- powers;
- exp/tanh.

Forward automatic differentiation строит Jacobian.

Damped Newton решает unified island.

Experiments:

- exponential diode-like law;
- smooth saturation;
- cubic rotational drag;
- dimensioned Power Map;
- impossible nonlinear law.

Результат: 86 assertions + 78 compatibility PASS.

Критический найденный дефект:

Floating network могла иметь `F=0` в случайной точке, но infinite solution manifold.

Исправлено:

```text
small residual
AND nonsingular tangent
```

Главный урок:

> математическое удовлетворение equations не равно определённому physical state.

Следующий wall: nonsmooth set-valued physics.

## FABRIC0.6 — Nonsmooth World

Проблемы:

- hard one-way behavior;
- unilateral contact;
- exact Coulomb stick/slip;
- branch memory.

Вместо специальных классов введено:

```text
HybridRelation
=
union of branches

branch:
  residuals=0
  inequalities>=0
```

Complementarity:

```text
a>=0 ⟂ b>=0
```

компилируется в:

```text
a=0,b>=0
OR
b=0,a>=0
```

Это специально выбрано вместо dimension-mixing scalar NCP representation.

Active-set prototype перебирает branch assignments с cap=256.

Experiments:

### one-way, electrical

reverse blocked, forward conducting.

### one-way, fluid

тот же relation работает как check-valve-like behavior.

### one-way, rotational

тот же relation работает как clutch/stop-like behavior.

### two-port unilateral contact

separated → zero reaction.

approaching → equal velocities + equal/opposite reaction.

### exact 1D Coulomb

```text
stick → slide+ → stick → slide-
```

без smoothing.

Добавлено branch-state memory на ambiguous boundary.

Добавлен deterministic `nonsmooth_transition` event ledger.

Результат: 121 assertions + 42 predecessor compatibility PASS.

Главный урок:

> Nonsmooth object можно представить как множество admissible manifolds, а device mode становится физическим discrete state.

Оставшаяся проблема:

Transition пока выбирается между статическими branch states. Нет ещё полноценной временной semantics момента события, reset map и transaction.

## FABRIC0.7 — Stateful Hybrid Time

После FABRIC0.6 стало ясно: статический выбор nonsmooth branch ещё не отвечает на вопрос времени.

Нужно было доказать:

- crossing локализуется внутри timestep;
- существует explicit pre-state/post-state;
- reset order-independent;
- discrete mode имеет causal history;
- topology mutation atomic;
- плохой jump не оставляет partial state;
- event storm не зависает.

### Новая temporal ontology

Введено принципиальное разделение:

```text
FLOW
JUMP
TOPOLOGY TRANSACTION
```

FLOW:

```text
dx/dt = f(mode,x,p,t)
```

JUMP:

```text
x+ = R(x-,p,te)
mode+ = target
```

TOPOLOGY TRANSACTION:

```text
validate all operations
commit all
or none
```

Это стало новой важной парадигмой FABRIC: изменения мира нельзя сводить к одному procedural update callback.

### Macrostep transaction

`advance(dt)` теперь имеет recovery-safe форму:

```text
snapshot
→ flow
→ detect/localize event
→ pre-event snapshot
→ simultaneous reset + mode + topology commit
→ post-event snapshot
→ remaining flow
```

При невалидной event transaction весь macrostep rollback.

### Impact experiment

Ball:

```text
h0=1
v0=-1
g=9.81
e=0.8
```

Flow:

```text
h_dot=v
v_dot=-g
```

Impact:

```text
h=0 downward crossing
v+ = -e*v-
```

Event локализован внутри `dt=0.6`:

```text
te=0.360950562279
v-=-4.540925016
v+=+3.632740013
```

Проверено:

```text
v+ = -0.8*v-
KE+/KE- = 0.64 = e^2
```

Это первый опыт FABRIC, где physical jump существует в собственном времени, а не на frame boundary.

### Hysteresis experiment

Schmitt-like modes:

```text
off -> on at upper=1
on  -> off at lower=0.2
```

После включения состояние прошло через deadband `x=0.7` без нового event.

Значит history-dependent behavior возникло из discrete mode + separate guard surfaces, а не special device class.

### Irreversible topology experiment

Breaker-like experiment:

```text
damage_dot=2/s
trip=1
```

At `t=0.5`:

```text
armed -> tripped
damage+=1
disable fuse_link
topology_revision 0->1
```

После события bond остаётся disabled.

Это первый FABRIC experiment, где continuous state crossing порождает irreversible topology mutation.

### Reset semantics experiment

```text
pre a=1,b=2
a+=pre(b)
b+=pre(a)
post a=2,b=1
```

Это доказало: reset assignments обязаны быть simultaneous mapping одного immutable pre-event state.

### Transaction failure experiment

Event пытался отключить:

- существующий bond;
- отсутствующий bond.

Вместо half-applied topology:

`TOPOLOGY_TRANSACTION_UNKNOWN_BOND`.

Полностью восстановлены:

- time;
- state;
- mode;
- event list;
- bond state;
- state hash.

### Zeno/event-storm experiment

Periodic reset каждые `0.01s` потребовал бы ~100 jumps за macrostep.

Research cap `32`.

Solver выдаёт:

`ZENO_OR_EVENT_STORM`

и полностью rollback macrostep.

### Evidence

Exact double-Godot:

`4.7.1.stable.double.custom_build.a13da4feb`.

Results:

```text
FABRIC0.7 Hybrid Time       88/88 PASS
FABRIC0.6 Nonsmooth       121/121 PASS
FABRIC0.6 Compatibility    42/42 PASS
Playground                 PASS
Editor scan                CLEAN
```

Executable local/GitHub bytes совпали.

### Главный урок FABRIC0.7

> Время FABRIC — это не цикл обновления объектов. Это последовательность flow intervals и локализованных jump transactions над persistent state/topology.

### Что осталось несвязанным

Очень важный non-claim:

FABRIC0.7 temporal ODE solver и FABRIC0.6 algebraic/nonsmooth physical solver пока живут рядом.

Continuous RK4 stage не решает автоматически Conservation Cells/PowerMaps/contact reactions.

Bouncing impact использует reset map, а не общий impulse complementarity solve.

Поэтому следующий wall не должен добавлять ещё один тип устройства.

## FABRIC0.8 — Coupled Hybrid DAE / Event Iteration

Следующий вопрос:

> Можно ли объединить continuous storage, algebraic physical network, nonsmooth constraints и event-time jumps в одну temporal equation system?

Нужно доказать:

- physical island solve на integration stages;
- guards от solved algebraic reaction;
- geometric gap + contact;
- impulse/restitution solve;
- friction inside impact/contact;
- same-time event fixed-point iteration;
- topology recompile at same event instant;
- momentum/energy audit across jump.

Критический unknown-machine experiment:

```text
two bodies
+ gap
+ contact
+ impact
+ restitution
+ friction
+ topology event
```

без device-specific CollisionObject как canonical physical truth.

## Research discipline after 0.7

FABRIC остаётся research-only.

Historical solvers/evidence не переписываются.

Construction остаётся canonical semantic owner.

Следующий checkpoint обязан по-прежнему пытаться сломать гипотезу, а не просто расширять каталог features.


## FABRIC0.8 — Coupled Hybrid DAE / Event Iteration

После FABRIC0.7 главным нерешённым противоречием стало наличие двух соседних миров:

```text
temporal ODE
и
algebraic/nonsmooth physical fabric
```

Они уже могли взаимодействовать через topology, но ещё не составляли один timestep solve.

### Вопрос checkpoint

> Может ли differential trajectory реально зависеть от algebraic reaction, которая решается на каждой integration stage, а event/jump/topology mutation — заставлять physical equations перекомпилироваться до продолжения времени?

Ответ prototype: да, на ограниченном semi-explicit стенде.

### Новый temporal equation contract

```text
F(x,y,p,t,topology)=0
xdot=f(x,y,p,t,topology)
```

На каждой RK4 stage FABRIC сначала решает y, затем вычисляет xdot.

Это принципиально отличается от post-processing reaction после обычного ODE step.

### Geometric event теперь зависит от coupled trajectory

Two-body experiment:

- тело A ускоряется algebraic force f_a;
- f_a существует только при active physical bond;
- gap x_b-x_a локализует impact;
- поэтому contact time уже зависит от repeatedly solved DAE.

Получено:

```text
t_hit=0.472135955002
```

при аналитическом reference:

```text
-4+sqrt(20)=0.4721359549995796
```

### Impulse стал solved unknown

FABRIC0.7 bouncing-ball reset был explicit relation.

FABRIC0.8 решает post velocities и impulses одновременно.

Normal equations сохраняют momentum и задают restitution.

Tangential branch выбирается из generic Coulomb manifolds.

Result:

```text
j_n=4.472135955
j_t=1.341640787
branch=slide_neg
```

No ContactSolver/FrictionSolver device class introduced.

### Event instant стал iterative physical solve

Solved j_n превышает break threshold.

Поэтому в том же physical instant:

```text
impact
→ DAE re-solve
→ break_on_impulse
→ topology mutation
→ DAE re-solve
```

До break:

```text
f_a=2
```

После break:

```text
f_a=0
```

Только после достижения local event fixed point время продолжает двигаться.

### Отдельный reaction-guard test

Чтобы не обмануть себя одним красивым impact demo, добавлен independent experiment:

```text
reaction = k*x
x_dot = 1
guard = reaction - 2N
```

Event локализован в t=1 через repeatedly solved algebraic reaction.

### Старый singularity lesson сохранился

DAE:

```text
0*y=0
```

имеет zero residual, но infinite solutions.

FABRIC0.8 возвращает:

`DAE_SINGULAR_ALGEBRAIC_MANIFOLD`.

Таким образом принцип FABRIC0.5 пережил объединение со временем.

### Evidence

```text
FABRIC0.8 focused             71/71 PASS
FABRIC0.7 regression          88/88 PASS
FABRIC0.6 nonsmooth          121/121 PASS
FABRIC0.6 compatibility       42/42 PASS
playground                    PASS
editor                        CLEAN
byte identity                 PASS
```

Deterministic hash:

`f564e9294b738d65783cefcbc03e18e54860c61541143be7dd2421d6223e9b19`.

### Главный урок FABRIC0.8

> Reaction, impulse и topology перестают быть внешними побочными эффектами simulation loop. Они становятся неизвестными/структурными состояниями одной causal hybrid equation program.

### Что ещё сломает текущую форму

FABRIC0.8 по-прежнему имеет scalar contact shape:

- один normal channel;
- один tangential channel;
- нет rotational inertia tensor;
- нет нескольких simultaneous contact points;
- нет friction cone solve;
- branch enumeration не масштабируется.

Поэтому следующий wall должен быть не ещё одним device experiment, а разрушением scalar-contact simplification.

## FABRIC0.9 — Multi-contact Geometric Manifold + Cone Solve

Следующая проверка:

> Может ли geometry породить несколько contact constraints, которые решаются одновременно и order-invariant, включая angular motion и friction cone?

Если порядок contact enumeration начинает менять физический результат или kernel требует special CollisionObject logic, это будет важной falsification finding.
