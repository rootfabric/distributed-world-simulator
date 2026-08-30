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


## FABRIC0.9 — Multi-Contact Geometric Manifold + Cone Solve

После FABRIC0.8 стало ясно, что scalar contact — следующая искусственная граница.

Один normal + один tangent channel недостаточны, когда одно rigid body одновременно касается нескольких geometric features.

### Вопрос checkpoint

Может ли geometry автоматически породить несколько coupled contacts, которые решаются одним global cone problem и дают тот же physical result независимо от порядка перечисления contacts?

Ответ research prototype: да для box против floor+wall.

### Geometry перестала быть callback owner

Первый provider:

~~~text
box vertices
against
static planes
~~~

генерирует stable contact records:

~~~text
plane id
vertex id
point
r
normal
tangent1
tangent2
gap
mu
restitution
~~~

Contact id:

~~~text
plane::vertex
~~~

После canonical sorting geometry enumeration перестаёт влиять на assembly order.

### Tangential friction стала двумерной

FABRIC0.8 имел scalar tangential impulse.

FABRIC0.9 contact имеет:

~~~text
j_n
j_t1
j_t2
~~~

с admissible cone:

~~~text
j_n >= 0
sqrt(j_t1^2+j_t2^2) <= mu*j_n
~~~

Это устраняет hidden axis-by-axis friction semantics.

### Global rigid-body coupling

Для direction d:

~~~text
J_d=[d, r x d]
~~~

Все contacts собираются в:

~~~text
A=J M^-1 J^T
~~~

Поэтому impulse в одной точке меняет velocities всех других contact points через shared rigid-body translation/rotation.

### Почему выбран ADMM

Sequential PGS мог бы сделать порядок contacts скрытой physical variable.

Вместо этого prototype решает global convex cone problem.

ADMM:

~~~text
global linear lambda solve
+
exact per-contact cone projection
+
dual update
~~~

Matrix A+rho I Cholesky-factorized один раз.

Это не production-performance решение, но хороший semantic test.

### Main corner experiment

Box одновременно касается floor и wall.

Manifold: 8 contacts.  
Impulse coordinates: 24.  
Rank effective-mass matrix: 6.  
Active: 5.  
Sliding: 5.

Post generalized state:

~~~text
linear =
(0.589721054,
 0.776797774,
 0.238711754)

angular =
(-0.074797351,
 -0.022468940,
 0.122242645)
~~~

Energy:

~~~text
14.208
->
1.015847883
~~~

Linear/angular impulse audits close.

### Order invariance стала executable

Acceptance решает тот же geometry state:

1. original;
2. reversed contacts;
3. reversed planes + reversed contacts.

Все варианты дают exact identical hash:

181d3a3cd0e4d0439c79b5ed6afd9939cc88c94276446e148ab8cdf0c453c7b5

Это первый checkpoint, где FABRIC прямо требует:

> Enumeration order is not physical semantics.

### Новый epistemic lesson — reactions can be redundant

~~~text
24 impulse coordinates
but
rank=6
~~~

Значит internal contact reaction split может иметь redundancy/gauge-like freedom.

Очень важно не перепутать deterministic numerical representative с mathematically unique physical reaction truth.

FABRIC должен в будущем решить, какие reaction details действительно canonical/persistent, а какие являются derived solve evidence.

### Evidence

~~~text
FABRIC0.9 focused            136/136 PASS
FABRIC0.8 regression          71/71 PASS
FABRIC0.7 regression          88/88 PASS
FABRIC0.6 nonsmooth          121/121 PASS
FABRIC0.6 compatibility       42/42 PASS
playground                    PASS
editor                        CLEAN
byte identity                 PASS
~~~

### Что осталось

0.9 — event-instant multi-contact solver.

Он пока не закрывает долгоживущую contact physics:

- body-body contacts;
- contact persistence;
- resting contact;
- warm start;
- sparse islands;
- automatic reintegration inside 0.8 time loop.

Поэтому следующий wall должен быть не новым impact demo, а persistent contact graph.

## FABRIC0.10 — Persistent Contact Graph + Sparse Hybrid DAE

Следующая проверка:

> Может ли несколько dynamic bodies долго жить в contact network, разбиваться на independent islands, сохранять stable contact identity/warm start и оставаться order-invariant при появлении/исчезновении contacts?

Критический experiment: stack/bridge нескольких тел с stick/slide/contact lifecycle и sparse island solve.


## FABRIC0.10 — Persistent Contact Graph + Sparse Hybrid Contact Step

После FABRIC0.9 контактная физика впервые стала multi-contact и order-invariant, но contact всё ещё был в основном мгновенным solve object.

Следующий вопрос был уже не про форму cone:

> Что должно существовать между двумя solve instants, чтобы contact стал частью persistent world?

### Contact получил историю

FABRIC0.10 вводит contact cache keyed stable identity:

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

Это важный сдвиг от transient collision record к graph relation.

### Dynamic-body graph стал solver topology

Контакты dynamic↔dynamic являются graph edges.

Static plane не становится общей graph вершиной.

Поэтому:

```text
D touches floor
E touches floor
```

не означает:

```text
D and E belong to one island
```

Но появление:

`pair:D|E`

автоматически merge-ит islands.

### Warm start стал identity-local, а не island-local

Первый solve четырёх persistent contacts:

`39 iterations`.

Следующий timestep:

`3 iterations`.

Warm hits:

`4`.

Самое важное: когда D/E islands merge, старые floor contact impulses остаются применимыми, потому что cache keyed contact identity.

Это подтверждает, что numerical continuity должна следовать stable physical relation identity, а не transient solver partition.

### Graph lifecycle experiment

Sequence:

```text
3 islands
↓
pair:D|E appears
↓
2 islands
↓
pair:D|E persists
↓
pair:D|E disappears
↓
3 islands
```

Получен explicit lifecycle:

```text
appear
persist
disappear
```

без procedural contact callbacks.

### Persistent resting load

Stack A/B под gravity остаётся практически неподвижным пять steps.

Cached impulses:

```text
A-B ~ 0.0981 N*s
floor-A ~ 0.1962 N*s
```

Upper load передаётся через dynamic pair в floor.

Это первый FABRIC checkpoint с долгоживущей body-body load path.

### Sparse topology стала observable

Jacobian rows и effective-mass entries сначала собираются sparse.

Merged D/E island:

```text
sparse A entries = 29
dense local capacity = 81
```

Но текущий solver после assembly всё ещё densify-ит local island matrix.

Очень важно не называть это production sparse solver.

### Independent islands проверены физически

A/B trajectory в full world сравнивается с isolated A/B-only world.

Несвязанные D/E merge/split не меняют A/B до `1e-12`.

Это превращает island decomposition из optimization idea в executable locality invariant.

### Order invariance пережила время и graph mutations

Reverse:

- body insertion;
- contact provider output.

Final world hash exact:

`4103da3235e4cdd7f1c63c809d3dd71ab39d10ec7f68094d6eef33eabfe6033d`.

Contact history JSON также identical.

То есть order-invariance FABRIC0.9 пережила persistent lifecycle.

### Event-time мост

Чтобы contact graph не оказался purely frame-boundary abstraction, добавлен ограниченный event bridge.

Falling sphere с contact-free start локализует floor crossing:

`t=0.460381178993`.

Именно в этот timestamp history получает:

```text
appeared:
plane:floor|body:fall
```

Remaining macrostep решается уже persistent contact island.

### Почему bridge сознательно ограничен

Если world уже имеет active contacts, helper fail-closed:

`EVENT_BRIDGE_REQUIRES_CONTACT_FREE_START`.

Это не слабость, которую надо спрятать.

General event localization при существующих constrained islands требует одновременно:

- держать старые contacts constrained;
- интегрировать differential state;
- локализовать новый geometry crossing;
- merge/recompile island в event instant;
- remap warm starts;
- продолжить remaining time.

Это и есть следующий wall.

### Evidence

```text
FABRIC0.10 focused       97/97 PASS
playground               PASS
editor                   CLEAN
byte identity            PASS
```

Predecessor runtime suites в isolated 0.10 lab не rerun.

FABRIC0.9 blobs доказанно preserved.

### Главный урок FABRIC0.10

> Contact для persistent world — это не collision callback и не только constraint row. Это stable graph relation с lifecycle, numerical continuity и island-local computational consequences.

## FABRIC0.11 — General Event-Localized Contact Islands + Sparse Backend

Следующая проверка должна слить temporal/event semantics 0.8 и persistent graph semantics 0.10 без contact-free shortcut.

Critical experiment:

```text
resting constrained stack
+
incoming dynamic body
+
large macrostep
+
localized impact while old contacts remain active
+
same-time graph merge
+
warm-start remap
+
sparse re-solve
+
remaining flow
+
order invariance
```


## FABRIC0.11 — General Event-Localized Contact Islands + Sparse Backend

После FABRIC0.10 существовали уже persistent contacts и contact islands, но temporal/event integration всё ещё имела loophole.

Event bridge умел:

```text
contact-free world
→ first contact
```

но не:

```text
already constrained world
→ new contact during macrostep
```

Кроме того, sparse graph structure всё ещё заканчивалась dense Cholesky.

### Вопрос checkpoint

> Может ли новый contact event быть найден, не отпуская старые constraints, а после graph merge весь same-time solve и remaining flow пройти через genuinely sparse linear backend?

Ответ research prototype: да.

### Старые constraints остаются физически активными во время search

Main world уже имеет A/B stack.

Incoming C падает сверху.

Каждая bisection probe продвигает candidate world через contact solve старого graph.

На найденном event:

```text
A-B gap ~ 3.44e-12
floor-A gap ~ 5.54e-12
```

Это критически важно.

Если бы event search временно отключал stack constraints, event time и impact state были бы результатом искусственного другого мира.

### Graph merge стал same-time causal operation

До event:

```text
[A,B]
```

После:

```text
[A,B,C]
```

New relation:

`pair:B|C`.

Old relations продолжают существовать.

Именно в event instant:

- graph recompiles;
- old warm-start state maps by contact identity;
- new contact starts cold;
- merged island solves before time continues.

### Warm state переживает event-time topology mutation

Event solve получает:

`2 warm hits`

от:

```text
pair:A|B
floor|A
```

Это следующий уровень идеи FABRIC0.10:

> relation-local numerical continuity должна переживать не только frame-boundary island merge, но и event-time graph mutation.

### Sparse backend стал настоящим

0.10:

```text
sparse A
→ dense A
→ Cholesky
```

0.11:

```text
sparse A
→ sparse matvec
→ Jacobi-PCG
```

ADMM linear subproblem больше не materialize-ит dense effective-mass matrix.

Independent SPD unit test даёт exact solution за две PCG iterations.

### Event solve evidence

Merged A/B/C:

```text
A sparse entries = 21
dense capacity   = 81

ADMM = 31 iterations
PCG calls = 31
PCG iterations = 93
dense materializations = 0
```

### Numerical honesty стала отдельной темой

Bisection находит event root текущей discrete constrained trajectory с tolerance `1e-11`.

Но trajectory сама построена fixed semi-implicit substeps `0.01 s`.

Поэтому:

```text
discrete event_dt =
0.35709945939307

continuous reference =
0.3609505622728941
```

Разница ~3.85 ms.

Это не надо «лечить» красивой цифрой bisection tolerance.

Нужно улучшать time integrator.

Этот урок напрямую породил следующий wall.

### Independent scheduling

Два independent islands решаются forward и reverse schedule.

Exact same hash:

`e50cceb70dc4ecbd0100e5207ca5a58a2285c90a5085a6556b19db8ce8699078`.

Это пока не actual parallel threads.

Но доказано необходимое semantic property:

```text
schedule order
!=
physical truth
```

### Full event replay

Reverse body insertion + contact order + island schedule дают тот же:

- event time;
- graph mutation;
- history;
- final state.

Hash:

`86d76fc7a4b93bdd27030e1b343151d008e2c2e62ddfa72bdc11cf46d4f6133b`.

### Evidence

```text
FABRIC0.11 focused        120/120 PASS
FABRIC0.10 regression      97/97 PASS
playground                  PASS
editor                      CLEAN
byte identity               PASS
```

### Главный урок FABRIC0.11

> Event search является частью constrained physics. Нельзя искать topology event в мире, где временно отключены уже существующие constraints.

И второй:

> Sparse topology должна оставаться sparse не только в compiler representation, но и в actual numerical linear solve.

## FABRIC0.12 — Adaptive Multi-Event Manifold DAE

0.11 выявил следующую artificial boundary:

- fixed substep determines trajectory error;
- one topology-change event per event-localized call;
- old-contact disappearance fail-closed;
- no orientation-aware feature manifold persistence;
- no actual parallel execution.

Следующий test должен заставить old contacts disappear и multiple new contacts appear в одном macrostep, при adaptive refinement и manifold event iteration.


## FABRIC0.12 — Adaptive Multi-Event Manifold DAE

FABRIC0.11 доказал, что persistent constrained graph можно менять прямо в event time и решать sparse до линейного backend.

Но он же показал неприятный truth:

```text
bisection tolerance = 1e-11
```

не спасает, если constrained trajectory строится coarse fixed step.

Следующий вопрос был поэтому не «как ещё уменьшить tolerance?», а:

> Сходится ли сама физическая trajectory и event time при systematic integration refinement?

### Reduced falsification model

Чтобы измерить convergence независимо от сложностей 3D collision geometry, FABRIC0.12 использует oriented rectangle in floor+wall corner.

Differential state:

```text
theta
omega
```

Algebraic center следует active support constraints.

Harmonic oscillator chosen because exact zero-event times known analytically.

Это даёт rare luxury для FABRIC research:

```text
known continuous reference
vs
adaptive numerical event trajectory
```

### Adaptive convergence

Tolerance:

```text
1e-5
1e-7
1e-9
1e-11
```

Max event-time error:

```text
1.47e-5
5.79e-7
1.53e-8
3.83e-10
```

Strict decrease.

Energy drift также уменьшается примерно:

```text
3.4e-5
6.7e-7
7.0e-9
7.1e-11
```

Это прямой ответ на numerical finding 0.11.

### Multi-event semantics

Один 1.2-second advance содержит два exact orientation crossings:

```text
PI/16

5PI/16
```

Solver обрабатывает оба.

После первого event интеграция реально restart from event fixed point и затем находит второй.

Это не list of precomputed event times.

### Manifold changes are not one rename

При crossing support geometry имеет degenerate configuration.

Negative side:

```text
floor BR vertex
wall BL vertex
```

Exact zero:

```text
floor bottom edge
wall left edge
```

Positive side:

```text
floor BL vertex
wall TL vertex
```

Event instant therefore performs:

```text
vertices
→ edges
→ directed vertices
→ fixed point
```

Три event iterations, две topology mutations.

Второй crossing делает обратный переход.

### Feature lineage

String IDs здесь недостаточно.

```text
edge:bottom
```

физически связан и с BL, и с BR.

Поэтому contact feature получил lineage.

Warm numerical hint remaps по overlap lineage.

Это позволило сохранить continuous numerical history даже когда exact active contact ID исчез.

### Split / merge test

Main corner path выбирает один support descendant per plane.

Чтобы generic remapper не оказался красивым special case, добавлены synthetic gates.

```text
edge warm 4
→
BL 2 + BR 2
```

и:

```text
BL 2 + BR 3
→
edge 5
```

Это первая explicit feature split/merge numerical continuity semantics в FABRIC.

### Pattern cache

0.11 PCG rebuilt numerical hints each time.

0.12 caches inverse diagonal by sparse structural pattern.

Но critical check меняет matrix coefficients при той же sparsity.

Cache still hits.

PCG solves changed matrix.

Result hash changes.

Следовательно pattern cache не secretly owns physical state.

### Actual threads

0.11 only proved reverse scheduling invariance.

0.12 starts two real Godot Thread workers.

Cold:

```text
threads=2
cache misses=2
```

Warm reverse-spawn:

```text
threads=2
cache hits=2
```

Canonical hash identical:

`40635ad181b0273659ffd0dacae622b7b7249427d5073c2f9ffb5913f43f7fe0`.

Parallelism наконец стал executable, хотя scheduler всё ещё research-only.

### Sleep/wake boundary

0.12 adds sleep/wake only as derived scheduler state.

Three quiet observations sleep island.

Motion wakes it.

Crucially sleep flag is absent from physical state hash.

This continues the long-running FABRIC separation:

```text
physical truth
!=
solver optimization state
```

### Evidence

```text
FABRIC0.12 focused       115/115 PASS
playground               PASS
editor                   CLEAN
byte identity            PASS
```

FABRIC0.11 runtime suite was not rerun in this isolated lab; predecessor executable blobs are preserved.

### Главный урок FABRIC0.12

> Numerical convergence itself is part of physical evidence.

И второй:

> Persistent feature identity should follow geometry lineage through manifold topology changes, not merely exact contact-ID equality.

### Что 0.12 намеренно не делает

Самое важное limitation:

0.12 is a **reduced manifold DAE**, not a direct adaptive rewrite of the full 0.11 3D contact graph.

Это сознательно.

Мы сначала falsify semantics in a system with analytic references, затем должны carry them into real persistent contacts.

## FABRIC0.13 — Unified Adaptive 3D Contact Graph

Следующий checkpoint должен интегрировать strongest lines:

```text
0.11 persistent sparse 3D contacts
+
0.12 adaptive multi-event manifold semantics
```

Если интеграция потребует отказаться от convergence/order/lineage principles, это будет важный architecture falsification, а не повод спрятать mismatch.


## FABRIC0.13 — Unified Adaptive 3D Contact Graph

FABRIC0.13 был принципиально другим checkpoint.

До него можно было сказать:

```text
0.11 knows persistent sparse contacts

0.12 knows adaptive multi-event manifolds
```

Но это ещё не доказывало, что эти abstractions совместимы.

### Integration itself became the falsification test

Вместо новой isolated primitive был построен единый stand:

```text
already-constrained A/B stack
+
free falling and rotating C
```

В одном `0.7 s` run должны одновременно выжить:

- old persistent relations;
- impact localization;
- island merge;
- sparse reaction solve;
- adaptive integration;
- orientation-dependent geometry;
- multipoint manifold transitions;
- feature lineage;
- deterministic replay;
- actual threaded island solve;
- refinement convergence.

Если бы любой из принципов 0.11/0.12 ломался при объединении, это было бы architecture finding.

Он не сломался на accepted stand.

### Impact joins the already constrained world

First event:

`0.12770032218309 s`.

Before:

```text
[A,B]
+
free C
```

After:

```text
[A,B,C]
```

Existing support reactions:

```text
floor|A = 19.62
A|B     = 9.81
```

survive graph merge by persistent relation identity.

Это важнее, чем просто получить новый contact.

It says:

> entering topology must join the existing physical history rather than instantiate a replacement island with amnesia.

### Rotation finally enters the same equation as translation

0.12 had orientation-aware geometry, but 0.13 explicitly couples reaction to rotational coordinate.

Contact Jacobian:

```text
[0, -1, +1, dr/dtheta]
```

and acceleration curvature term:

```text
d2r/dtheta2 * omega^2
```

This turned orientation from a feature selector into part of the constraint mechanics.

### Multipoint feature topology is now in the persistent graph path

Rocking gives:

```text
2-point edge
→ 4-point face
→ 2-point opposite edge
```

at one physical instant.

Then later the reverse transition occurs.

Each event needs:

```text
two topology mutations
three event iterations
fixed point
```

The 0.12 lineage idea therefore survived integration into a persistent contact relation.

### The strongest result: convergence survived integration

A common research failure mode is:

```text
subsystem A converges
subsystem B works
A+B becomes timestep-sensitive
```

FABRIC0.13 explicitly tested this.

Against `1e-12` reference:

Event-time max error:

```text
8.03e-8
→ 3.11e-9
→ 5.64e-11
```

Final-state error:

```text
6.45e-7
→ 2.62e-8
→ 4.79e-10
```

So adaptive refinement still converges after:

- impact;
- island merge;
- contact projection;
- sparse PCG;
- manifold transitions.

This is the central success of 0.13.

### Actual threads stay outside physical mutation

Main island `[A,B,C]` and independent `[D,E]` are solved by real Godot Threads.

Forward/reverse spawn order:

`same canonical hash`.

Parallel audit also leaves physical world hash unchanged.

This makes the execution boundary clearer:

```text
snapshot
→ worker solve
→ join
→ canonical result
```

rather than workers owning world truth.

### Quaternion is evidence with a scope warning

The final quaternion is normalized to machine precision.

But the experiment rotates only about X.

So the history explicitly records:

```text
Quaternion exists
!=
general 6DOF solved
```

This prevents future sessions from accidentally inflating the claim.

### Exact bytes exposed a repository-level lesson

During durable persistence, five files matched immediately.

Two large source files differed by exactly one trailing newline.

The code was not declared remote-identical until GitHub blob SHA equaled local `git hash-object`.

That persistence failure produced a useful principle:

> Exact validation evidence names bytes, not intentions.

If a checkpoint claims byte identity, a newline matters.

### Evidence

```text
FABRIC0.13 focused       95/95 PASS
playground               PASS
editor                   CLEAN
7 remote executable blobs IDENTICAL
```

Physical hash:

`f486303b7f133d28148d63362ad368d82e946132f2a12f9c164ae5edc2819483`.

Parallel hash:

`6ef3fd35474a179a7bf02675d5bde9ecb457f235fdb7cc70f017a69757f92757`.

FABRIC0.12 runtime suite was not rerun in this lab; its executable blobs remain preserved.

### What remains deliberately unfinished

0.13 still uses a constrained research stand with partial algebraic projection for A/B support.

The demonstrated body C rotation is one-axis.

Tangential friction cones from earlier FABRIC work are not yet unified into this adaptive multipoint successor.

Therefore the next wall is physical, not merely infrastructural.

## FABRIC0.14 — Full 6DOF Frictional Feature Manifold

Next falsification should require:

```text
free 3D translation
+
free 3D rotation
+
quaternion/inertia tensor
+
unilateral normal reaction
+
Coulomb tangent cones
+
persistent convex feature lineage
+
adaptive appear/disappear events
+
island merge/split
+
parallel sparse execution
+
refinement/invariant evidence
```

FABRIC0.13 closes the integration chapter; 0.14 should remove the remaining rigid-body/friction simplifications.
