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

## FABRIC0.7 — почему следующий wall именно Time

Для persistent world недостаточно знать, что существуют две modes.

Нужно ответить:

```text
когда именно произошёл переход?
какое было pre-state?
какой post-state?
какие state variables reset?
какие topology operations commit?
что делать, если event случился внутри dt?
что делать, если событий слишком много?
```

Поэтому FABRIC0.7 должен ввести hybrid-time semantics.

Базовая форма:

```text
mode
continuous state x
flow dx/dt=f(mode,x,p,t)
event surface g(x,p,t)=0
direction
guard
reset x+ = R(x-,p)
mode transition
atomic topology transaction
event identity/history
```

Главные experiments:

### bouncing impact

```text
h_dot=v
v_dot=-g

guard h=0 downward
reset:
  h=0
  v=-e * pre(v)
```

Проверить event-time localization и restitution energy ratio.

### Schmitt hysteresis

Два thresholds и discrete mode.

Проверить отсутствие chatter внутри deadband.

### breaker/fuse

Continuous accumulated damage/clock.

При crossing:

- mode -> tripped;
- bond disabled atomic transaction;
- event recorded exactly.

### simultaneous reset

Несколько reset RHS вычисляются из одного pre-event snapshot.

### failed topology transaction

Все operations validate first.

Ни одна не применяется при ошибке.

### event storm / Zeno protection

Bounded event count.

Fail-closed diagnostic.

## Research discipline

Каждый successor:

- не переписывает исторический solver;
- добавляет новый файл;
- сохраняет predecessor validation;
- явно пишет claims/non-claims;
- не self-promote в production;
- не меняет Construction ownership.

## Current durable boundary before FABRIC0.7 implementation

Branch:

`research/fabric0-compositional-world-fabric-r1`

FABRIC0.6 parent head:

`549abed8c6ba5deeb5c68303ea7a2ce5c5a85522`

Draft PR:

`#317`

FABRIC remains research-only.
