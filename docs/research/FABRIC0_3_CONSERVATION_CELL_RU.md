# FABRIC0.3 — Conservation Cell

**Статус:** research-only, exact double-Godot PASS.

## 1. Главная идея

FABRIC0.3 не вводит готовый Junction как устройство. Physical ports и active bonds сначала компилируются в connected components — Conservation Cells. Уже cells образуют equation islands и решаются.

То есть физический узел является производной от topology, а не новым authoritative object.

Каждый domain объявляет пару величин:

    common_quantity
    balance_quantity

с инвариантом:

    power = common_quantity * balance_quantity

Примеры:

    electrical-like:
      common  = voltage
      balance = current

    rotational shaft:
      common  = angular_velocity
      balance = torque

Это намеренно более абстрактно, чем жёсткие effort/flow: domain сам выбирает, какая величина в connection cell общая, а какая балансируется.

## 2. Conservation Cell

Для всех портов одного cell:

    common_1 = common_2 = ... = common_n

и:

    sum(balance_i) = 0

Следовательно:

    sum(power_i)
    = common * sum(balance_i)
    = 0

Power balance на идеальном connection cell получается прямым следствием topology constraint.

## 3. Локальные constitutive laws

### equilibrium_terminal

    balance = response_gain * (preferred_common - common)

Один и тот же элемент может в конкретном состоянии отдавать или принимать поток. Source и sink не являются жёсткими ролями.

### fixed_balance_terminal

    balance = constant

### linear_difference_coupler

Для двух cells:

    transfer = response_gain * (common_a - common_b)
    balance_a = -transfer
    balance_b = +transfer

### ideal_common_constraint

    common = prescribed_value

Неизвестный balance идеального ограничения появляется как Lagrange multiplier общей системы.

## 4. Equation island

После topology compilation cells связываются multi-port constitutive elements и образуют solve-islands.

Для линейного FABRIC0.3 получается система:

    K q + C^T lambda = r
    C q             = d

где q — common quantities cells, K — contributions локальных response laws, r — preferred-common и fixed-balance terms, C — ideal constraints, lambda — неизвестные реакции ideal constraints.

Это похоже на nodal/constraint formulations, но FABRIC0.3 использует их как domain-neutral compiler над Port/Bond/Law/State, а не как электрический simulator.

## 5. Почему это важно

### Role reversal

Элемент не имеет флага is_source. Если его preferred common ниже общего состояния cell, знак balance меняется, и он начинает поглощать поток.

### Topology is equations

Размыкание bond превращает one cell в two cells и меняет equation islands. Повторное соединение восстанавливает исходную систему и canonical state hash.

### Impossible physics fails closed

Два ideal constraints common=10 и common=12 в одном cell не усредняются. Solver возвращает CONSTRAINT_CONFLICT.

Сеть с только difference-coupler и без reference law возвращает SINGULAR_FLOATING_ISLAND.

## 6. Эксперименты

### C1 — Two sources + load

    source A: preferred=12, gain=2
    source B: preferred=6,  gain=1
    load:     preferred=0,  gain=3

Решение:

    common = 5
    A balance    = +14
    B balance    = +1
    load balance = -15
    sum balance  = 0
    power        = +70 +5 -75 = 0

### C2 — Role reversal

    strong: preferred=12 gain=3
    weak:   preferred=4  gain=1
    load:   preferred=0  gain=1

Решение:

    common = 8
    strong balance = +12
    weak balance   = -4
    load balance   = -8

weak автоматически стал consumer и поглощает power 32.

### C3 — Ideal constraint

    ideal common = 10
    load A gain  = 2
    load B gain  = 1

Решение:

    ideal balance = +30
    load A        = -20
    load B        = -10

### C4 — Topology recompilation

Исходно: 1 cell, common=5.

Bond отключён: 2 cells / 2 solve islands; source A singleton common=12; source B + load common=1.5.

Bond возвращён: 1 cell, common=5, canonical hash restored.

### C5 — Two-cell bridge

    source -- cell A -- difference coupler -- cell B -- load

Результат:

    cell A common = 9.6
    cell B common = 4.8
    coupler absorbed power = 23.04
    cell residuals = 0
    power residuals = 0

### C6 — Rotational domain

Domain:

    common  = angular_velocity
    balance = torque

Из тех же laws:

    omega = 6.666666...
    drive torque = +6.666666...
    drag torque  = -6.666666...

Solver не содержит электрических или motor-specific special cases.

## 7. Что доказано

- physical connection может быть acausal на уровне topology;
- topology автоматически компилируется в equation cells;
- source/sink role может быть emergent;
- один solver работает с разными physical domains;
- ideal reactions получаются как unknown constraints;
- conservation residual проверяется автоматически;
- topology split/merge меняет equations без device-specific rebuild logic;
- impossible и floating networks диагностируются fail-closed;
- deterministic replay сохраняется.

## 8. Что НЕ доказано

- только linear constitutive laws;
- dense Gauss-Jordan prototype вместо sparse solver;
- units пока metadata;
- нет nonlinear residual/Jacobian stamps;
- нет dynamic storage в conservation solver;
- нет vector/multi-axis ports;
- нет power-preserving cross-domain transformer;
- нет implicit integration;
- нет production Construction/authority/network integration;
- нет scale proof.

## 9. Следующая фундаментальная граница

Следующий эксперимент должен соединить два разных conservation domains одним power-preserving element:

    electrical-like network
           |
           | power-preserving map
           v
    rotational network

Требование:

    P_electrical + P_rotational + P_loss = 0

без kernel-класса Motor.

## 10. Эпистемический статус

FABRIC0.3 не заявляется как доказанно новая для человечества математика. Это собственная архитектурная синтезация нескольких сильных известных идей — connection sets, conservation junctions, local constitutive laws, Lagrange reactions, nodal stamping и power accounting — в форму для открыто-композиционного persistent distributed world.

Главный принцип проекта:

> topology не соединяет готовые устройства; topology сама становится исполняемой физической программой.
