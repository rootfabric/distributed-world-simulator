# FABRIC0.5 — NONLINEAR LAW + DIMENSIONS

**Статус:** research-only successor к FABRIC0.4.  
**Цель:** сделать физические размерности и гладкие нелинейные constitutive laws частью исполняемого контракта FABRIC, не добавляя device-specific классы.

## 1. Почему этот checkpoint нужен

FABRIC0.4 доказал, что линейные Conservation Cells, Power Maps и storage могут выражать mixed-domain machines без Motor / Generator / Differential kernel classes.

Но оставались две опасные дыры:

1. solver мог принять численно красивое, но размерностно бессмысленное уравнение;
2. реальный мир нелинеен, а каталог специальных nonlinear device ops быстро разрушил бы композиционность.

FABRIC0.5 закрывает обе дыры одной общей формой:

```text
dimension-aware physical domains
          +
generic residual laws F(q, b, p) = 0
          +
automatic Jacobian
          +
bounded Newton solve
```

## 2. Dimension algebra

Размерность представлена integer-vector по семи SI base dimensions:

```text
L      length
M      mass
T      time
I      electric current
Theta  thermodynamic temperature
N      amount of substance
J      luminous intensity
```

Derived dimensions строятся алгебраически:

```text
multiply -> add exponents
divide   -> subtract exponents
pow(n)   -> multiply exponents by n
```

Примеры:

```text
voltage * current            = power
torque * angular_velocity    = power
force * velocity             = power
pressure * volume_flow       = power
energy / time                = power
```

Angles используют SI dimensional status `1`; явный unit metadata `rad/s` всё равно сохраняется в domain contract.

## 3. Physical domain теперь должен быть power-conjugate

Регистрация domain требует:

```text
common_dimension
balance_dimension
```

и проверяет:

```text
common_dimension * balance_dimension = power_dimension
```

Поэтому корректны, например:

```text
electrical:
  common  = voltage
  balance = current

rotational:
  common  = angular_velocity
  balance = torque

fluid:
  common  = pressure
  balance = volume_flow
```

А попытка объявить:

```text
common  = voltage
balance = torque
```

fail-closed:

```text
DOMAIN_NOT_POWER_CONJUGATE
```

## 4. Dimension-aware Power Map

FABRIC0.4 позволял relation:

```text
V - 2*omega = 0
```

но numerical coefficient `2` скрывал conversion dimension.

FABRIC0.5 требует у каждого coefficient:

```text
coefficient
coefficient_dimension
```

Все terms одной row обязаны иметь одинаковую итоговую размерность:

```text
dimension(coefficient_i) * dimension(common_i)
=
row_dimension
```

Поэтому:

```text
1 * V
-
2 * omega
```

с dimensionless `2` отклоняется:

```text
POWER_MAP_ROW_DIMENSION_MISMATCH
```

Корректная карта явно говорит:

```text
coefficient_dimension
=
voltage / angular_velocity
```

Hidden unit conversion больше не допускается.

## 5. Generic nonlinear constitutive law

Новый primitive:

```text
nonlinear_constitutive
```

не знает названий Diode, Saturation, Spring, Drag, Pump.

Он содержит:

```text
physical ports
parameters(value + dimension)
residual equations
nominal residual scales
```

Математический контракт:

```text
F(q, balance, parameters) = 0
```

Для текущего prototype один balance unknown создаётся на каждый physical port, а residual system должна быть square.

## 6. Dimension-aware expression language

Residual expression tree поддерживает:

```text
constant
parameter
common(port)
balance(port)

add
sub
mul
div
neg
integer power
exp
tanh
```

Dimension checker выполняется до solve:

- add/sub требуют одинаковые dimensions;
- mul/div объединяют dimensions;
- integer power масштабирует exponent vector;
- exp/tanh требуют dimensionless argument.

Поэтому:

```text
exp(voltage)
```

fail-closed:

```text
TRANSCENDENTAL_REQUIRES_DIMENSIONLESS
```

а:

```text
current + voltage
```

отклоняется как:

```text
ADD_SUB_DIMENSION_MISMATCH
```

## 7. Automatic Jacobian

Пользователь constitutive law не пишет производные вручную.

Expression evaluator распространяет:

```text
value
sparse gradient
```

forward-mode automatic differentiation.

Из одного expression tree автоматически получаются:

```text
residual F
Jacobian dF/dx
```

Это уменьшает риск рассинхронизации law и её производной.

## 8. Unified nonlinear equation island

Unknown vector теперь может одновременно содержать:

```text
cell common quantities
nonlinear port balances
constraint reactions / lambdas
```

Equation rows содержат:

```text
cell balance equations
Power Map / ideal constraints
nonlinear constitutive residuals
```

То есть linear и nonlinear physics живут в одном equation island.

## 9. Newton contract

Prototype использует bounded damped Newton solve:

```text
1. assemble residual + Jacobian
2. check normalized residual
3. solve J dx = -F
4. line search
5. repeat
```

Limits:

```text
max Newton iterations = 48
max line-search steps = 16
```

Residuals нормируются собственными nominal scales. Это принципиально: numerical residuals разных физических dimensions нельзя честно сравнивать как голые числа.

Failure остаётся наблюдаемым:

```text
NEWTON_SINGULAR_JACOBIAN
NEWTON_LINE_SEARCH_FAILED
NEWTON_NO_CONVERGENCE
NONLINEAR_EXP_OVERFLOW
```

## 10. Важное исправление — zero residual недостаточен

Во время compatibility test обнаружилась фундаментальная ловушка.

Floating network может иметь:

```text
F(x) = 0
```

в случайной стартовой точке, но при этом обладать бесконечным множеством решений.

Поэтому новый acceptance criterion:

```text
residual ~= 0
AND
tangent Jacobian has full rank
```

Если rank отсутствует:

```text
SINGULAR_FLOATING_ISLAND
```

или для nonlinear manifold:

```text
SINGULAR_SOLUTION_MANIFOLD
```

Solver больше не путает "уравнения удовлетворены" и "физическое состояние определено однозначно".

## 11. Experiment N1 — exponential diode-like law

Bias source:

```text
+3 A
```

Nonlinear law:

```text
I + Is * (exp(V / Vscale) - 1) = 0
```

где:

```text
Is     = 1 A
Vscale = 1 V
```

Solver получает:

```text
V = ln(4)
  = 1.3862943611198906

I = -3 A
```

Newton convergence:

```text
5 iterations
```

В kernel нет Diode class.

## 12. Experiment N2 — smooth saturation

Law:

```text
I
-
Imax * tanh((Vpreferred - V) / width)
=
0
```

Parameters:

```text
Imax       = 2 A
Vpreferred = 5 V
width      = 1 V
```

С линейной load сеть получает:

```text
V = 1.9902990904610843
I = 1.9902990904610843
```

Flow остаётся ниже limit `2 A`.

В kernel нет SaturatingSupply.

## 13. Experiment N3 — cubic rotational drag

Generic residual:

```text
torque + k * omega^3 = 0
```

Drive:

```text
+3 N.m
```

Решение:

```text
omega = cubert(3)
      = 1.4422495703074083

drag torque = -3
```

В kernel нет CubicDrag class.

## 14. Experiment N4 — dimensioned mixed-domain map

Правильный Power Map:

```text
V - k*omega = 0
```

где `k` явно имеет dimension:

```text
voltage / angular_velocity
```

Результат:

```text
V      = 32/3
omega  = 16/3
current = -8/3
torque  = +16/3
P_map   = 0
```

То есть power-preserving mixed-domain composition сохранилась после введения dimensions.

## 15. Experiment N5 — impossible nonlinear physics

Law:

```text
balance^2 + 1 A^2 = 0
```

не имеет real solution.

Solver не генерирует фиктивное состояние:

```text
NEWTON_SINGULAR_JACOBIAN
```

## 16. Regression / compatibility

FABRIC0.5 V3 повторно проверяет важные свойства predecessors:

- FABRIC0.3 two-source cell;
- topology split/rejoin + canonical hash restore;
- ideal reaction solve;
- floating island diagnostic;
- FABRIC0.4 mixed-domain dynamic machine;
- open electrical topology;
- dimension-aware three-port differential Power Map.

Historical V2 solver и FABRIC0.4 tests также остаются отдельным immutable evidence и проходят без изменений.

## 17. Что доказано

FABRIC0.5 показывает:

- dimensions могут быть executable invariants, а не comments;
- physical domains fail-closed по power-conjugacy;
- hidden cross-domain conversion запрещена;
- generic residual language выражает несколько качественно разных nonlinear laws;
- Jacobian может автоматически выводиться из law;
- linear + nonlinear + constraints решаются единым island;
- convergence использует dimension-aware nominal scaling;
- impossible и underdetermined physics fail-closed;
- deterministic nonlinear replay сохраняется;
- FABRIC0.3/0.4 semantics пережили переход к nonlinear solver.

## 18. Что ещё НЕ доказано

Текущий V3 всё ещё research prototype:

- dense Jacobian solve;
- только integer dimension exponents;
- нет unit parser/conversion database;
- affine units вроде Celsius не являются numerical transport units;
- нет nonlinear internal state residuals общего DAE вида;
- нет sparse AD/Jacobian assembly;
- нет adaptive timestep;
- нет higher-order structure-preserving integration;
- нет nonsmooth complementarity;
- нет exact contact/friction;
- нет event surfaces / hysteresis;
- нет production Construction / authority / network integration;
- нет full materialized DWS regression.

## 19. Следующая фундаментальная граница

### FABRIC0.6 — NONSMOOTH WORLD

Smooth nonlinear laws уже доказаны.

Следующая граница мира — inequalities и односторонние constraints:

```text
contact
hard diode/check valve
Coulomb friction
one-way clutch
tension-only cable
compression-only support
yield / break threshold
event surfaces
hysteresis
```

Здесь нужен generic complementarity/event contract, а не новый каталог object classes.

## 20. Текущий принцип

> Устройство — это не класс. Это область допустимых состояний и потоков, заданная topology, dimensions, constitutive residuals, storage и power-preserving constraints.

FABRIC0.5 делает этот принцип существенно строже: теперь даже сама математика устройства обязана быть физически размерностно осмысленной.
