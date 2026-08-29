# FABRIC0 — журнал исследовательского прогресса

## FABRIC0.1 — Compositional scalar playground

**Durable branch:** `research/fabric0-compositional-world-fabric-r1`  
**Historical research head:** `2306ad446f7b6f0ee13b0986e38df3ee6d274dee`  
**PR:** `#317` (Draft)  
**Evidence:** `validation/fabric0-compositional-world-fabric-v1-validation.json`  
**Result:** `PASS_RESEARCH_ONLY`, 44 assertions.

Закрыто:

- typed domains;
- generic source/gain/transducer/threshold/gate/integrator/sink;
- switchable function;
- breakable topology;
- reusable feedback pattern;
- tank + heater;
- proximity door;
- deterministic replay.

## FABRIC0.2 — Inline switch + coupled rotational wall

**Historical research head:** `6852d9f04c4403dda83f81895176be8a90eaaca1`  
**Evidence:** `validation/fabric0-compositional-world-fabric-v2-validation.json`  
**Result:** exact double-Godot `70/70 PASS`.

Закрыто:

- Switch стал самостоятельным inline Element;
- battery -> Switch -> lamp реально включает и выключает lamp element;
- тот же Switch переиспользуется в torque domain;
- generic rotational_inertia и viscous_load;
- coupled cycle speed -> reaction torque -> inertia;
- inertia сохраняет движение после отключения drive;
- local discrete work/kinetic-energy identity;
- rotational deterministic replay.

## FABRIC0.3 — Conservation Cell

**Historical research head:** `59b181b2fe215f84976cfbcc094108070f22dd46`  
**Design:** `docs/research/FABRIC0_3_CONSERVATION_CELL_RU.md`  
**Evidence:** `validation/fabric0-compositional-world-fabric-v3-validation.json`  
**Result:** `PASS_RESEARCH_ONLY`.

Validation:

- FABRIC0.3 focused acceptance: `119/119 PASS`;
- playground: `FABRIC0_3_CONSERVATION_PLAYGROUND_PASS`;
- editor parse/compile scan: CLEAN;
- previous FABRIC0.2 regression: `70/70 PASS`.

Главный результат:

- active bond topology автоматически компилируется в Conservation Cells;
- domain объявляет пару `common_quantity × balance_quantity = power`;
- common quantity одинакова внутри cell;
- balance quantities суммируются в ноль;
- source/sink role возникает из solved sign;
- topology split/merge перекомпилирует equations;
- impossible/floating physics fail closed;
- один solver работает в electrical-like и rotational domains.

## FABRIC0.4 — POWER MAP / mixed-domain living machine

**Parent research head:** `59b181b2fe215f84976cfbcc094108070f22dd46`  
**Design:** `docs/research/FABRIC0_4_POWER_MAP_RU.md`  
**Evidence:** `validation/fabric0-compositional-world-fabric-v4-validation.json`  
**Status:** `IMPLEMENTED / LOCAL_EXACT_DOUBLE_PASS / DRAFT_REVIEW_CANDIDATE`.

### Validation

- exact double-Godot: `4.7.1.stable.double.custom_build.a13da4feb`;
- Power Map focused acceptance: `89/89 PASS`;
- V2 Conservation compatibility acceptance: `49/49 PASS`;
- playground: `FABRIC0_4_POWER_MAP_PLAYGROUND_PASS`;
- editor parse/compile scan: CLEAN;
- error scan: CLEAN;
- all five tested executable files are byte-identical between local test inputs and GitHub branch by Git blob SHA.

### Новая архитектурная форма

FABRIC0.4 вводит research successor:

`scripts/research/fabric0/fabric0_conservation_fabric_v2.gd`

FABRIC0.3 v1 не переписан и остаётся historical evidence.

Power Map определяется как homogeneous constraint subspace:

```text
A q = 0
b = -A^T lambda
```

Отсюда:

```text
P = q^T b
  = -(A q)^T lambda
  = 0
```

Power preservation становится свойством формы связи, а не специальной логикой устройства.

### P1 — motor-like machine без Motor

Состав:

```text
electrical-like equilibrium terminal
        ↓
Power Map: V - 2*omega = 0
        ↓
rotational generic storage J=2
        ↓
rotational drag
```

Наблюдаемая speed history:

```text
4.571428571
5.442176871
5.608033690
5.639625465
5.645642946
5.646789133
```

На первом шаге:

- `V=64/7`;
- `omega=32/7`;
- map current `-40/7`;
- map torque `+80/7`;
- map absorbed power `0`;
- cell power residual `0`;
- total absorbed power `0`.

### P2 — open electrical topology

После разрыва supply bond:

```text
omega: 5.646789133 -> 4.517431306
V_open = 9.034862612
I_open = 0
tau_map = 0
```

То есть появляется back-EMF-like common state без current и без map reaction torque; storage замедляется только от drag.

### P3 — reverse generator mode

Та же Power Map, но энергия приходит с rotational side:

```text
V = 20/3
omega = 10/3
map current = +20/3
map torque = -40/3
```

Electrical load поглощает `400/9`, shaft drive отдаёт `400/9`, Power Map поглощает `0`.

Motor/generator direction стала solved state, а не отдельным device class.

### P4 — differential без Differential

Три rotational ports и одна relation:

```text
omega_left + omega_right - 2*omega_carrier = 0
```

Результат:

```text
omega_left    = 24/7
omega_right   = 12/7
omega_carrier = 18/7

torque_left    = +24/7
torque_right   = +24/7
torque_carrier = -48/7
```

Power Map absorbed power = `0`.

Один generic Power Map выразил motor-like transduction, reverse generator behavior и open-differential-like kinematics без kernel classes Motor / Generator / Gearbox / Differential.

### Generic dynamic storage

Добавлен `linear_storage_terminal`:

```text
balance = (capacity / dt) * (previous_common - common)
```

Для квадратичного storage:

```text
H = 0.5 * capacity * common^2
```

Backward-Euler numerical dissipation не скрывается:

```text
absorbed_work
=
delta_stored_energy
+
numerical_dissipation
```

На первом machine-step:

```text
delta energy          = 1024/49
absorbed work         = 2048/49
numerical dissipation = 1024/49
```

### Главный вывод FABRIC0.4

> Объект всё больше становится устойчивым pattern topology + constitutive laws + stored state + power constraints, а не исполняемым классом движка.

### Следующая фундаментальная граница

`FABRIC0.5 NONLINEAR LAW + UNIT/DIMENSION CONTRACT`

Цель:

1. generic nonlinear residual/Jacobian constitutive law;
2. формальная dimension algebra для physical domains и Power Map coefficients;
3. fail-closed dimensional mismatch;
4. nonlinear unknown-machine experiments: saturation, diode-like one-way law, nonlinear spring, friction/contact precursor.

Production promotion пока не заявляется. PR остаётся Draft.


## FABRIC0.5 — NONLINEAR LAW + DIMENSIONS

**Parent research head:** `d67e8c4887f176f451c3bb1206f545375af60019`  
**Design:** `docs/research/FABRIC0_5_NONLINEAR_DIMENSIONS_RU.md`  
**Evidence:** `validation/fabric0-compositional-world-fabric-v5-validation.json`  
**Status:** `IMPLEMENTED / LOCAL_EXACT_DOUBLE_PASS / DRAFT_REVIEW_CANDIDATE`.

### Validation

- exact double-Godot: `4.7.1.stable.double.custom_build.a13da4feb`;
- nonlinear + dimensions focused acceptance: `86/86 PASS`;
- V3 predecessor compatibility: `78/78 PASS`;
- historical FABRIC0.4 acceptance: `89/89 PASS`;
- historical V2 compatibility: `49/49 PASS`;
- playground: `FABRIC0_5_NONLINEAR_DIMENSIONS_PLAYGROUND_PASS`;
- editor parse/compile scan: CLEAN;
- all five V3 executable files are byte-identical between local tested files and GitHub branch by Git blob SHA.

### Dimension contract

V3 introduces seven-base SI exponent algebra:

```text
L M T I Theta N J
```

Every physical domain must satisfy:

```text
common_dimension * balance_dimension = power_dimension
```

Examples proven:

```text
voltage * current         = power
torque * angular_velocity = power
force * velocity          = power
pressure * volume_flow    = power
```

Invalid domain `voltage × torque` is rejected as `DOMAIN_NOT_POWER_CONJUGATE`.

Power Map coefficients now carry explicit dimensions. Hidden relation `V - 2*omega = 0` with dimensionless `2` is rejected; the conversion coefficient must explicitly carry `voltage/angular_velocity` dimension.

### Generic nonlinear law

New primitive:

```text
nonlinear_constitutive
```

accepts dimension-checked residual expressions:

```text
F(common, balance, parameters) = 0
```

Expression language includes add/sub/mul/div, integer powers, exp and tanh. Jacobian is produced automatically through forward-mode differentiation.

### Nonlinear evidence

**Diode-like exponential law**

```text
I + Is*(exp(V/Vscale)-1) = 0
bias = +3 A
V = ln(4) = 1.3862943611198906
I = -3
Newton iterations = 5
```

**Smooth saturation**

```text
I - Imax*tanh((Vpreferred-V)/width) = 0
common = 1.9902990904610843
balance = 1.9902990904610843
limit = 2
Newton iterations = 4
```

**Cubic rotational drag**

```text
torque + k*omega^3 = 0
drive = +3
omega = 1.4422495703074083
drag torque = -3
Newton iterations = 6
```

No Diode / Saturation / CubicDrag kernel classes exist.

### Dimensioned mixed-domain Power Map survives V3

Correct dimensioned relation:

```text
V - k*omega = 0
dimension(k) = voltage / angular_velocity
```

gives:

```text
V       = 32/3
omega   = 16/3
current = -8/3
torque  = +16/3
P_map   = 0
```

### Fail-closed nonlinear solver

Bounded damped Newton contract:

```text
max Newton iterations = 48
max line-search steps  = 16
```

Residuals use explicit nominal scaling.

A crucial compatibility finding was fixed: `F(x)=0` alone is not proof of a unique physical state. Solver now also requires a nonsingular tangent Jacobian at convergence.

Therefore floating underdetermined physics remains:

```text
SINGULAR_FLOATING_ISLAND
```

and impossible nonlinear law such as:

```text
balance^2 + 1 A^2 = 0
```

fails closed as:

```text
NEWTON_SINGULAR_JACOBIAN
```

### Главный вывод FABRIC0.5

> Physical laws are now executable, dimension-checked residuals rather than device-specific code.

FABRIC now has a coherent research chain:

```text
topology
→ Conservation Cells
→ power-conjugate domains
→ Power Maps
→ storage
→ dimension algebra
→ nonlinear residual laws
→ automatic Jacobian
→ bounded equation solve
```

### Следующая фундаментальная граница

`FABRIC0.6 NONSMOOTH WORLD`

Smooth nonlinear equations are now proven. Next research wall is inequalities, complementarity and event surfaces:

```text
hard contact
Coulomb friction
hard diode / check valve
one-way clutch
tension-only cable
compression-only support
yield / break
hysteresis
```

The goal is again to express these as generic mathematical contracts rather than object classes.

Production promotion is still not requested. PR remains Draft.
