# FABRIC0.4 — POWER MAP / живая междоменная физика

**Статус:** research-only successor к FABRIC0.3.  
**Цель:** доказать, что разные physical domains можно соединять универсальной power-preserving структурой без kernel-классов `Motor`, `Gearbox` или `Differential`.

## 1. Главное изменение

FABRIC0.3 научил topology компилироваться в Conservation Cells:

```text
connected physical ports
        ↓
Conservation Cells
        ↓
common equality + balance zero-sum
```

FABRIC0.4 добавляет второй уровень:

```text
Conservation Cell A
        │
        │
     Power Map
        │
        │
Conservation Cell B / C / ...
```

Power Map не является устройством. Это однородное линейное подпространство допустимых common-величин нескольких physical ports.

## 2. Формальный инвариант

Пусть:

- `q` — vector common quantities подключённых cells;
- `A q = 0` — homogeneous constraint rows Power Map;
- `lambda` — реакции constraints;
- `b = -A^T lambda` — balance reactions ports.

Тогда мощность Power Map:

```text
P = q^T b
  = -q^T A^T lambda
  = -(A q)^T lambda
  = 0
```

То есть lossless power preservation является не runtime-проверкой конкретного device, а алгебраическим следствием формы constraints.

В numerical solve эти реакции появляются как Lagrange multipliers augmented system.

## 3. Почему это глубже "трансформатора"

Один `linear_power_map` принимает:

```text
port_domains
constraint_rows
```

и не знает семантики ports.

### Двухпортовая relation

```text
V - 2*omega = 0
```

даёт автоматически сопряжённые реакции:

```text
I_map
tau_map
```

с нулевой суммарной мощностью.

### Трёхпортовая relation

```text
omega_left + omega_right - 2*omega_carrier = 0
```

автоматически порождает reaction torques с тем же power-preserving свойством.

Поэтому Gear, Transformer, Differential и ideal electromechanical conversion становятся не kernel operations, а разными coefficient matrices одной структуры.

## 4. Mixed-domain equation islands

FABRIC0.3 v1 запрещал solve-island, содержащий разные domains.

FABRIC0.4 v2 разделяет:

- **Cell** всегда однодоменный;
- **Equation Island** может содержать много domains;
- multi-domain Power Map соединяет cells только через explicit homogeneous constraints.

Это сохраняет строгую domain-границу bonds, но разрешает физически корректное преобразование между domains.

## 5. Generic dynamic storage

Чтобы машина стала живой, добавлен `linear_storage_terminal`.

Для capacity `C`, предыдущего common-state `q_prev` и шага `dt` используется implicit/backward-Euler constitutive stamp:

```text
balance = (C / dt) * (q_prev - q)
```

Один и тот же primitive может представлять, например:

```text
rotational:
  q = angular_velocity
  balance = torque
  C = inertia J

translational:
  q = velocity
  balance = force
  C = mass

electrical-like:
  q = voltage
  balance = current
  C = capacitance
```

для тех domains, где энергия имеет квадратичную форму:

```text
H = 0.5 * C * q^2
```

### Честный numerical-energy ledger

Backward Euler диссипативен. FABRIC0.4 это не скрывает:

```text
absorbed_work
=
delta_stored_energy
+
numerical_dissipation
```

и:

```text
numerical_dissipation
=
0.5 * C * (q - q_prev)^2
>= 0
```

Таким образом numerical loss становится наблюдаемой частью evidence, а не ошибочно объявляется физическим loss.

## 6. Эксперимент P1 — motor-like machine без Motor

Состав:

```text
electrical-like terminal, preferred V=12
        │
        ▼
   Power Map
   V - 2*omega = 0
        │
        ▼
rotational storage J=2
        │
rotational drag gain=0.5
```

Kernel не содержит Motor.

При `dt=1`:

```text
omega:
4.571428571
5.442176871
5.608033690
5.639625465
5.645642946
5.646789133
```

На первом шаге:

```text
V            = 64/7
omega        = 32/7
map current  = -40/7
map torque   = +80/7
P_map        = 0
cell residuals = 0
total absorbed power = 0
```

Storage ledger:

```text
stored energy delta     = 1024/49
absorbed work           = 2048/49
numerical dissipation   = 1024/49
```

и identity выполняется точно в tolerance.

## 7. Эксперимент P2 — open circuit / back-EMF

После шести шагов электрический bond источника размыкается.

Power Map остаётся связанным с вращающимся storage, поэтому constraint продолжает давать:

```text
V = 2*omega
```

но electrical cell больше не имеет пути balance-flow:

```text
current = 0
map torque = 0
```

Наблюдение:

```text
omega before open = 5.646789133
omega after open  = 4.517431306
V open            = 9.034862612
I open            = 0
tau_map            = 0
```

То есть появляется back-EMF-like common state без тока и без электромагнитного тормозящего момента; storage продолжает замедляться только от drag.

Никакого `MotorOpenCircuitMode` нет.

## 8. Эксперимент P3 — та же карта становится генератором

Та же relation:

```text
V - 2*omega = 0
```

Теперь rotational terminal стремится к `omega=10`, а electrical terminal — к `V=0`.

Solver получает:

```text
V            = 20/3
omega        = 10/3
map current  = +20/3
map torque   = -40/3
```

Electrical load поглощает:

```text
400/9
```

Rotational drive отдаёт:

```text
400/9
```

Power Map:

```text
absorbed power = 0
```

"Motor" и "Generator" оказались не разными классами, а направлениями одного solved energy exchange.

## 9. Эксперимент P4 — differential без Differential

Три rotational cells:

```text
left
right
carrier
```

и единственная relation:

```text
omega_left + omega_right - 2*omega_carrier = 0
```

Loads намеренно разные:

```text
left gain  = 1
right gain = 2
carrier drive preferred=6 gain=2
```

Solver получает:

```text
omega_left    = 24/7
omega_right   = 12/7
omega_carrier = 18/7
```

То есть:

```text
omega_left + omega_right
=
2 * omega_carrier
```

Reaction torques:

```text
left     +24/7
right    +24/7
carrier  -48/7
```

и:

```text
P_map = 0
```

Это уже очень сильный Unknown Machine Test: один generic constraint law породил корректную идеализированную differential-like кинематику и сопряжённые torques.

## 10. Совместимость с FABRIC0.3

FABRIC0.4 использует новый research successor:

```text
fabric0_conservation_fabric_v2.gd
```

FABRIC0.3 v1 не переписан и остаётся historical evidence.

Отдельный V2 compatibility acceptance повторно проверяет:

- two-source cell;
- ideal common constraint;
- constraint conflict;
- floating island;
- two-cell difference coupler;
- topology split/rejoin + hash restoration.

## 11. Что доказано

FABRIC0.4 показывает:

1. equation island может безопасно пересекать несколько physical domains;
2. homogeneous constraint map сохраняет power по построению;
3. reaction balances могут выводиться из constraint Jacobian, а не задаваться device logic;
4. один и тот же map работает в motor и generator direction;
5. multi-port map выражает differential-like механизм;
6. generic implicit storage делает сеть динамической;
7. open topology естественно создаёт back-EMF-like common state без flow;
8. numerical dissipation интегратора явно учитывается;
9. deterministic replay сохраняется.

## 12. Что ещё НЕ доказано

- formal dimensional algebra для coefficients Power Map;
- nonlinear Power Maps;
- arbitrary nonlinear constitutive residual/Jacobian laws;
- sparse factorization;
- adaptive timestep;
- higher-order / structure-preserving integration;
- vector/spatial ports;
- thermal entropy-flow domain;
- irreversible cross-domain losses;
- contact/friction complementarity;
- production Construction / authority / replication integration;
- large-scale island partitioning.

## 13. Следующая граница

Теперь наиболее фундаментальный следующий шаг — не добавлять ещё один "device".

### FABRIC0.5 — NONLINEAR LAW + UNIT/DIMENSION CONTRACT

Нужны две вещи:

1. generic residual/Jacobian constitutive law:
   `F(q, balance, state)=0`;
2. dimension system, которая не позволит бессмысленно написать Power Map coefficients без dimensional conversion contract.

После этого можно атаковать:

- diode-like one-way nonlinear behavior;
- nonlinear spring;
- aerodynamic local law;
- saturation;
- friction/contact;
- DC motor with winding resistance + nonlinear saturation;
- pump/compressor curves;

без добавления этих device names в solver.

## 14. Текущий принцип FABRIC

> Объект — это не исполняемый класс. Объект — это устойчивый pattern topology, local constitutive laws, stored state и power-preserving constraints.

FABRIC0.4 впервые показывает это сразу на нескольких узнаваемых машинах: "motor", "generator" и "differential" появляются из одной грамматики, но самой грамматике эти слова неизвестны.
