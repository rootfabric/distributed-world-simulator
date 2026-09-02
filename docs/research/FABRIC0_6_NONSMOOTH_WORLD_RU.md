# FABRIC0.6 — NONSMOOTH WORLD

**Статус:** research-only successor к FABRIC0.5.  
**Цель:** выразить жёсткие односторонние связи, контакт и stick/slip через общий математический контракт, не вводя kernel-классы `Diode`, `Valve`, `Clutch`, `Contact` или `Friction`.

## 1. Главная форма

FABRIC0.5 описывал гладкую физику как:

```text
F(x) = 0
```

FABRIC0.6 обобщает объект до конечного объединения гладких допустимых многообразий:

```text
HybridRelation
  branch A:
    residuals = 0
    inequalities >= 0

  branch B:
    residuals = 0
    inequalities >= 0

  ...
```

То есть nonsmooth law — не специальный object type, а:

```text
union of admissible smooth manifolds
```

Каждая ветвь по-прежнему использует dimension-aware residual expression language и automatic Jacobian.

## 2. Exact complementarity без смешивания размерностей

Классическая complementarity-пара:

```text
a >= 0
b >= 0
a*b = 0
```

эквивалентна:

```text
{ a = 0, b >= 0 }
UNION
{ b = 0, a >= 0 }
```

FABRIC компилирует её именно так:

`complementarity_branches(...)`.

Это особенно важно для dimension-aware мира.

В контакте `a` и `b` могут быть, например:

```text
separation velocity
normal force
```

Они имеют разные физические размерности. FABRIC не складывает их искусственно в один NCP residual. Каждая equality/inequality сохраняет собственную dimension и собственный nominal scale.

## 3. Active-set solve

Для каждого локального solve-island:

1. находятся HybridRelation elements;
2. строятся возможные branch assignments;
3. каждая assignment превращается в гладкую square equation system;
4. внутри ветви используется bounded damped Newton;
5. после решения проверяются inequalities;
6. остаются только admissible candidates;
7. выбирается кандидат с минимальным числом переключений branch-state;
8. при равенстве учитываются branch priority и deterministic lexical order.

Research prototype имеет fail-closed cap:

```text
MAX_BRANCH_COMBINATIONS = 256
```

Это сознательно не production scaling strategy. Следующий production candidate должен заменить exhaustive local enumeration на primal-dual active-set / semismooth / cone solver, сохранив тот же declarative law contract.

## 4. Состояние на границе

На nonsmooth boundary несколько ветвей могут быть одновременно допустимы.

FABRIC сохраняет предыдущую активную ветвь, если она остаётся admissible:

```text
previous valid branch
    wins over
equally valid alternative
```

Это даёт минимальную state continuity и предотвращает произвольное chatter на точной границе.

Это ещё не полноценный hysteresis band. Но пользователь law может задать overlapping inequality regions, и тогда branch memory естественно реализует hysteretic behavior без нового solver primitive.

## 5. Discrete event ledger

Если active branch меняется после уже решённого состояния, FABRIC записывает:

```text
nonsmooth_transition
  element_id
  from
  to
  revision
```

То есть discrete mode change становится частью наблюдаемого causal history.

## 6. Experiment NS1 — hard one-way electrical relation

Один и тот же complementarity pattern:

```text
-common >= 0
    ⟂
-balance >= 0
```

даёт:

### Blocked

```text
balance = 0
common <= 0
```

### Conducting

```text
common = 0
balance <= 0
```

При source preferred `-5 V`:

```text
branch = blocked
V = -5
I = 0
```

На boundary `V=0` обе ветви допустимы, но previous blocked state сохраняется.

При source preferred `+5 V`:

```text
branch = conducting
V = 0
I = -5
```

и возникает `nonsmooth_transition`.

В solver нет Diode class.

## 7. Experiment NS2 — тот же law в fluid domain

Без изменения complementarity grammar:

```text
common  = pressure
balance = volume_flow
```

Reverse:

```text
pressure = -4
flow = 0
```

Forward:

```text
pressure = 0
flow = -4
```

В solver нет CheckValve class.

## 8. Experiment NS3 — тот же law в rotational domain

Тот же one-way pattern:

```text
common  = angular_velocity
balance = torque
```

Свободное направление:

```text
omega = -3
torque = 0
```

Запрещённое направление:

```text
omega = 0
torque = -3
```

В solver нет OneWayClutch class.

## 9. Experiment NS4 — two-port unilateral contact

Contact candidate имеет два translational physical ports.

Power-conjugate domain:

```text
common  = velocity
balance = force
```

Shared law:

```text
force_a + force_b = 0
```

Complementarity:

```text
separation_velocity
=
velocity_b - velocity_a

separation_velocity >= 0
    ⟂
normal_reaction >= 0
```

### Separated

Preferred velocities:

```text
body_a = -1
body_b = +1
```

Решение:

```text
open
va = -1
vb = +1
reaction = 0
```

### Approaching

Preferred:

```text
body_a = +1
body_b = -1
```

Решение:

```text
closed
va = 0
vb = 0
force_a = -1
force_b = +1
absorbed power = 0
```

Реакция появляется из constraints, а не из `Contact.apply_force()`.

Текущий опыт является velocity-level contact candidate. Он ещё не содержит geometric gap state, impact impulse/time stepping или restitution.

## 10. Experiment NS5 — exact 1D Coulomb stick/slip

Один physical port:

```text
common  = velocity
balance = friction force
```

Параметр:

```text
Fmax
```

Три branch-manifolds:

### stick

```text
velocity = 0
-Fmax <= force <= +Fmax
```

### slide_pos

```text
force = -Fmax
velocity >= 0
```

### slide_neg

```text
force = +Fmax
velocity <= 0
```

Наблюдаемая sequence:

```text
drive = +0.5, Fmax=1
  -> stick
  v=0
  F=-0.5

drive = +3, Fmax=1
  -> slide_pos
  v=+2
  F=-1
  absorbed power=2

drive = +3, Fmax=4
  -> stick
  v=0
  F=-3

drive = -3, Fmax=1
  -> slide_neg
  v=-2
  F=+1
  absorbed power=2
```

Это set-valued Coulomb-like 1D law без smoothing/regularization.

В solver нет Friction class.

## 11. Fail-closed semantics

Если smooth manifold решается, но её inequalities нарушены, branch недопустима.

Если не остаётся ни одной допустимой branch:

```text
NO_ADMISSIBLE_NONSMOOTH_BRANCH
```

Если branch system вырождена:

```text
SINGULAR_ACTIVE_SET_MANIFOLD
```

Если local active-set space превышает research cap:

```text
ACTIVE_SET_COMBINATION_LIMIT
```

Никакая из этих ситуаций не заменяется эвристическим физическим состоянием.

## 12. Smooth predecessor compatibility

HybridRelation с одной branch и без inequalities эквивалентна гладкому FABRIC0.5 constitutive law.

Проверен exponential law:

```text
I + Is*(exp(V/Vscale)-1) = 0
```

Результат:

```text
V = ln(4)
I = -3
```

Dimension checker по-прежнему отвергает:

```text
exp(voltage)
```

Dimensioned mixed-domain Power Map также сохранён:

```text
V - k*omega = 0
dimension(k) = voltage/angular_velocity

V = 32/3
omega = 16/3
current = -8/3
torque = +16/3
P_map = 0
```

А historical zero-hybrid Conservation Cell всё ещё даёт:

```text
common=5
balances=+14,+1,-15
```

## 13. Что доказано

FABRIC0.6 показывает:

- smooth residual law является частным случаем hybrid relation;
- exact complementarity может компилироваться в dimension-preserving branch manifolds;
- одна nonsmooth grammar работает в electrical, fluid, rotational и translational domains;
- unilateral reaction возникает только в active contact state;
- 1D Coulomb stick/slip работает без device-specific solver class;
- discrete transitions становятся observable events;
- previous admissible state стабилизирует ambiguous boundary;
- impossible hybrid physics fail-closed;
- deterministic branch/event replay сохраняется;
- Power Map и dimension contracts пережили nonsmooth successor.

## 14. Что НЕ доказано

FABRIC0.6 всё ещё research prototype:

- branch enumeration экспоненциальна в худшем случае;
- cap = 256 combinations;
- только scalar physical ports;
- contact пока velocity-level, без geometric gap state;
- нет impact impulse/restitution;
- нет full 2D/3D Coulomb friction cone;
- нет second-order cone complementarity;
- нет rolling/spinning friction;
- нет arbitrary internal hybrid variables;
- нет persistent hysteresis state apart from active-branch memory;
- нет event-time localization inside a timestep;
- нет topology mutation from yield/break;
- нет sparse production active-set solver;
- нет full materialized DWS regression;
- нет production Construction / authority / replication integration.

## 15. Следующая фундаментальная граница

### FABRIC0.7 — STATEFUL HYBRID TIME

Следующий шаг должен добавить не новый device, а generic temporal semantics:

```text
continuous state
+
event surface
+
discrete state
+
guard
+
reset map
+
topology mutation transaction
```

Это позволит честно выразить:

- impact + restitution;
- relay / Schmitt hysteresis;
- yield then plastic state;
- fuse / breaker trip;
- bond break;
- latch;
- irreversible valve state;
- fatigue-triggered transition;

при сохранении тех же Port / Domain / Cell / Residual / Branch invariants.

## 16. Текущий принцип

> Nonsmooth object — это не класс с if/else. Это набор физически размерностно корректных manifold branches, guards и переходов между ними.

FABRIC0.6 впервые делает контакт, stick/slip и one-way behavior частью этой общей грамматики.
