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


## FABRIC0.6 — NONSMOOTH WORLD

**Parent research head:** `a09ff2b7611af8fcd201de45622f3d1e6ff07c4e`  
**Design:** `docs/research/FABRIC0_6_NONSMOOTH_WORLD_RU.md`  
**Evidence:** `validation/fabric0-compositional-world-fabric-v6-validation.json`  
**Status:** `IMPLEMENTED / LOCAL_EXACT_DOUBLE_PASS / DRAFT_REVIEW_CANDIDATE`.

### Validation

- exact double-Godot: `4.7.1.stable.double.custom_build.a13da4feb`;
- focused nonsmooth acceptance: `121/121 PASS`;
- predecessor compatibility: `42/42 PASS`;
- playground: `FABRIC0_6_NONSMOOTH_PLAYGROUND_PASS`;
- editor parse/compile scan: CLEAN;
- all five executable FABRIC0.6 files are byte-identical between local exact-double tests and GitHub by Git blob SHA.

### Новый универсальный контракт

Nonsmooth physical law теперь задаётся как finite union of branch manifolds:

```text
branch:
  residuals = 0
  inequalities >= 0
```

Exact complementarity:

```text
a >= 0 ⟂ b >= 0
```

компилируется dimension-preserving способом:

```text
{a=0, b>=0}
UNION
{b=0, a>=0}
```

Поэтому разные физические dimensions не приходится искусственно складывать в один scalar NCP residual.

### Active-set semantics

Для локального island solver:

1. перечисляет branch assignments;
2. решает каждую гладкую manifold через bounded damped Newton;
3. проверяет inequality guards;
4. отбрасывает inadmissible candidates;
5. предпочитает previous active branch, если она всё ещё допустима;
6. затем использует branch priority и deterministic order.

Research cap:

`MAX_BRANCH_COMBINATIONS = 256`.

### One-way relation reused across domains

Один exact complementarity pattern без device-specific op работает как:

- electrical hard one-way element;
- pressure/flow check-valve-like element;
- rotational one-way stop/clutch-like element.

Electrical:

```text
reverse: V=-5, I=0, blocked
forward: V=0, I=-5, conducting
```

Fluid:

```text
reverse: pressure=-4, flow=0
forward: pressure=0, flow=-4
```

Rotational:

```text
free: omega=-3, torque=0
blocked direction: omega=0, torque=-3
```

### Unilateral contact

Two-port contact candidate:

```text
separation_velocity >= 0
    ⟂
normal_reaction >= 0
```

plus:

```text
force_a + force_b = 0
```

Separated:

```text
va=-1
vb=+1
reaction=0
```

Approaching:

```text
va=0
vb=0
force_a=-1
force_b=+1
absorbed power=0
```

Discrete branch transition записывается как `nonsmooth_transition`.

### Exact 1D Coulomb stick/slip

Три branch-manifolds:

```text
stick:
  v=0
  -Fmax <= F <= +Fmax

slide_pos:
  F=-Fmax
  v>=0

slide_neg:
  F=+Fmax
  v<=0
```

Observed sequence:

```text
drive=+0.5, Fmax=1 -> stick, v=0, F=-0.5
drive=+3,   Fmax=1 -> slide_pos, v=+2, F=-1, Pabs=2
drive=+3,   Fmax=4 -> stick, v=0, F=-3
drive=-3,   Fmax=1 -> slide_neg, v=-2, F=+1, Pabs=2
```

No Friction kernel class exists.

### Boundary memory + events

Если несколько branches допустимы на точной switching surface, previous active branch сохраняется.

Это предотвращает arbitrary chatter на equality boundary.

При реальном переходе записывается:

```text
nonsmooth_transition
  from
  to
  revision
```

### Fail-closed

Если ни одна branch не проходит equations + inequalities:

`NO_ADMISSIBLE_NONSMOOTH_BRANCH`.

Если active manifold вырождена:

`SINGULAR_ACTIVE_SET_MANIFOLD`.

Если branch product превышает research cap:

`ACTIVE_SET_COMBINATION_LIMIT`.

### Predecessor compatibility

FABRIC0.5 smooth law доказан как одно-branch частный случай HybridRelation:

```text
I + Is*(exp(V/Vscale)-1)=0
V=ln(4)
I=-3
```

Dimension checker сохраняется.

FABRIC0.4 dimensioned Power Map также сохраняется:

```text
V=32/3
omega=16/3
current=-8/3
torque=+16/3
P_map=0
```

Zero-hybrid Conservation Cell по-прежнему даёт:

```text
common=5
balances=+14,+1,-15
```

### Главный вывод FABRIC0.6

> Nonsmooth object is a set of dimensionally valid manifolds, guards and deterministic transitions — not a class full of object-specific if/else logic.

### Следующая фундаментальная граница

`FABRIC0.7 STATEFUL HYBRID TIME`

Нужны generic:

```text
continuous state
event surface
discrete state
guard
reset map
topology mutation transaction
```

чтобы выразить impact/restitution, hysteresis, yield/plasticity, breaker trip, bond break и latch без device-specific runtime classes.

Production promotion по-прежнему не заявляется. PR остаётся Draft.


## FABRIC0.7 — STATEFUL HYBRID TIME

**Parent research head:** `549abed8c6ba5deeb5c68303ea7a2ce5c5a85522`  
**Design:** `docs/research/FABRIC0_7_STATEFUL_HYBRID_TIME_RU.md`  
**Evidence:** `validation/fabric0-compositional-world-fabric-v7-validation.json`  
**Recovery entrypoint:** `docs/research/FABRIC0_READ_FIRST_RU.md`  
**Status:** `IMPLEMENTED / LOCAL_EXACT_DOUBLE_PASS / DRAFT_REVIEW_CANDIDATE`.

### Recovery memory checkpoint

Перед реализацией FABRIC0.7 в Git отдельно закреплена исследовательская память:

- `FABRIC0_READ_FIRST_RU.md` — обязательная точка восстановления новой сессии;
- `FABRIC0_IDEOLOGY_RU.md` — аксиомы, парадигмы, отвергнутые направления;
- `FABRIC0_RESEARCH_HISTORY_RU.md` — narrative 0.1→текущий frontier;
- `scripts/research/fabric0/AGENTS.md` — scoped правила для будущих агентов.

Цель: FABRIC должен восстанавливаться из Git без истории чата.

### Validation

- exact double-Godot: `4.7.1.stable.double.custom_build.a13da4feb`;
- focused hybrid-time acceptance: `88/88 PASS`;
- FABRIC0.6 nonsmooth regression: `121/121 PASS`;
- FABRIC0.6 predecessor compatibility regression: `42/42 PASS`;
- playground: `FABRIC0_7_HYBRID_TIME_PLAYGROUND_PASS`;
- editor parse/compile scan: CLEAN;
- все 4 executable FABRIC0.7 файла byte-identical между локально протестированными файлами и GitHub.

### Temporal triad

FABRIC теперь различает три фундаментально разные операции:

```text
FLOW
  dx/dt = f(...)

JUMP
  x+ = R(x-)
  mode+ = target

TOPOLOGY TRANSACTION
  validate all
  commit all
  or commit none
```

Нельзя смешивать их в один device-specific `update()`.

### Macrostep = transaction

`advance(dt)`:

```text
snapshot
→ flow до event
→ localize event
→ immutable pre-event snapshot
→ simultaneous reset + mode + topology commit
→ post-event snapshot
→ flow остатка dt
```

При invalid topology transaction или event storm весь macrostep rollback.

### T1 — impact + restitution

```text
h(0)=1
v(0)=-1
g=9.81
e=0.8
dt=0.6
```

Event локализован:

```text
te = 0.360950562279
pre v  = -4.540925016
post v = +3.632740013
```

Проверено:

```text
v+ = -e*v-
KE+/KE- = e^2 = 0.64
```

После остатка macrostep:

```text
h=0.588110029
v=1.287665029
t=0.6
```

### T2 — Schmitt-like hysteresis

```text
off -> on at x=1, t=1
deadband x=0.7 -> remains on, no event
on -> off at x=0.2, total t=2.2
```

Hysteresis возникает из mode + different event surfaces, без Schmitt kernel class.

### T3 — irreversible breaker

Continuous damage crossing:

```text
damage_dot=2/s
trip=1
te=0.5
```

Jump:

```text
armed -> tripped
damage+=1
fuse_link active -> false
topology_revision 0 -> 1
```

Bond остаётся отключён при дальнейшей эволюции.

### T4 — simultaneous reset

```text
pre:  a=1,b=2
reset: a+=pre(b), b+=pre(a)
post: a=2,b=1
```

Все RHS читают один immutable pre-event snapshot.

### T5 — topology transaction rollback

Transaction с одним valid и одним missing bond даёт:

`TOPOLOGY_TRANSACTION_UNKNOWN_BOND`.

После rollback:

```text
time=0
mode restored
states restored
valid bond still active
events unchanged
hash restored
```

### T6 — event storm / Zeno guard

`MAX_EVENTS_PER_ADVANCE=32`.

Система, требующая ~100 jumps за `advance(1)`, получает:

`ZENO_OR_EVENT_STORM`

и macrostep полностью откатывается.

### Event identity

Каждый jump хранит:

```text
event_id
sequence
transition_id
time
pre/post mode
pre/post state
pre/post hash
topology revision before/after
```

Это локальная research identity, не canonical distributed authority identity.

### Главный вывод FABRIC0.7

> Persistent physical time следует моделировать не как последовательность device updates, а как чередование continuous flows, локализованных jumps и атомарных topology transactions.

### Следующая фундаментальная граница

`FABRIC0.8 COUPLED HYBRID DAE / EVENT ITERATION`.

Нужно связать hybrid time и physical equations в одну систему:

- algebraic FABRIC islands решаются на integration stages;
- guards могут зависеть от solved reactions;
- impact использует impulse/reaction solve;
- same-time events итерируются до fixed point;
- topology mutation перекомпилирует physical equations в том же event instant;
- energy/momentum audit проходит через jump.

Production promotion не заявляется. PR остаётся Draft.


## FABRIC0.8 — COUPLED HYBRID DAE / EVENT ITERATION

**Parent research head:** 7a64988e8964e4488693b4cd202e02e94ae90075  
**Design:** docs/research/FABRIC0_8_COUPLED_HYBRID_DAE_RU.md  
**Evidence:** validation/fabric0-compositional-world-fabric-v8-validation.json  
**Status:** IMPLEMENTED / LOCAL_EXACT_DOUBLE_PASS / DRAFT_REVIEW_CANDIDATE.

### Validation

- exact double-Godot: 4.7.1.stable.double.custom_build.a13da4feb;
- focused coupled hybrid DAE acceptance: 71/71 PASS;
- FABRIC0.7 regression: 88/88 PASS;
- FABRIC0.6 nonsmooth regression: 121/121 PASS;
- FABRIC0.6 predecessor compatibility: 42/42 PASS;
- playground: FABRIC0_8_COUPLED_HYBRID_DAE_PLAYGROUND_PASS;
- editor parse/compile/SCRIPT error scan: CLEAN;
- all 4 executable FABRIC0.8 files byte-identical between local tested bytes and GitHub blobs.

### Новая форма

FABRIC0.8 впервые связывает differential и algebraic state:

~~~text
F(x,y,p,t,topology)=0
xdot=f(x,y,p,t,topology)
~~~

Algebraic system решается на каждой RK4 stage до вычисления derivative.

### Topology участвует в equations

Expression bond_active(drive_link) может входить в algebraic residual.

Пока bond active:

~~~text
f_a=2 N
~~~

После topology transaction:

~~~text
drive_link=false
f_a=0
~~~

Mode name не содержит отдельной force logic.

### Geometric impact

Gap:

~~~text
x_b-x_a
~~~

локализован внутри macrostep:

~~~text
t_hit=0.472135955002
reference=-4+sqrt(20)=0.4721359549995796
~~~

Pre relative normal:

~~~text
-4.472135955
~~~

Generic jump solve дал:

~~~text
j_n=4.472135955
e=0.5

v_a+=1.236067978
v_b+=3.472135955
~~~

Normal momentum conserved, restitution relation PASS.

### Coulomb tangential branch

~~~text
mu=0.3
j_t=1.341640787
mu*j_n=1.341640787
branch=slide_neg
~~~

Tangential momentum conserved.

Kinetic energy after jump lower than before; jump does not create energy.

### Same-time event iteration

Один event instant:

~~~text
impact
→ algebraic re-solve: f_a=2
→ break_on_impulse
→ drive_link OFF
→ topology revision 0→1
→ algebraic re-solve: f_a=0
~~~

Оба transitions имеют один physical event time.

После этого остаток macrostep интегрируется уже на broken topology.

Final t=1:

~~~text
x_a=2.180339888
x_b=3.360679775
gap=1.180339888
f_a=0
~~~

### Algebraic guard

Отдельный test:

~~~text
reaction=k*x
k=2 N/m
x_dot=1 m/s

guard:
reaction=2 N
~~~

Event локализован в t=1.

Это доказывает, что guard действительно зависит от repeatedly solved algebraic reaction.

### Singular DAE

~~~text
0*y=0
~~~

отклоняется как:

DAE_SINGULAR_ALGEBRAIC_MANIFOLD.

Zero residual без determined tangent по-прежнему не считается physical solution.

### Deterministic replay

State/event hash:

f564e9294b738d65783cefcbc03e18e54860c61541143be7dd2421d6223e9b19.

Replay сохраняет:

- event instant;
- transition ordering;
- impact branch;
- impulses;
- topology revision;
- final differential/algebraic state.

### Главный вывод FABRIC0.8

> Differential state, algebraic reaction, jump impulse и mutable topology теперь могут участвовать в одном causal physical timestep.

FABRIC начинает выглядеть как компилятор topology в hybrid differential-algebraic physical program.

### Следующий фундаментальный барьер

FABRIC0.9 — MULTI-CONTACT GEOMETRIC MANIFOLD + CONE SOLVE.

Нужно убрать scalar-contact special shape:

~~~text
multiple geometry contacts
normal Jacobians
2D tangent basis
rotational inertia
friction cone
simultaneous coupled impulses
contact-island solve
order invariance
sparse/warm-start path
~~~

Production promotion не заявляется. Draft PR сохраняется.


## FABRIC0.9 — MULTI-CONTACT GEOMETRIC MANIFOLD + CONE SOLVE

**Parent research head:** `8b7b28e9b3e1a9641a2d20e8f89c540f08a2a1ec`  
**Design:** `docs/research/FABRIC0_9_MULTICONTACT_GEOMETRIC_CONE_RU.md`  
**Evidence:** `validation/fabric0-compositional-world-fabric-v9-validation.json`  
**Status:** `IMPLEMENTED / LOCAL_EXACT_DOUBLE_PASS / DRAFT_REVIEW_CANDIDATE`.

### Validation

- exact double-Godot: `4.7.1.stable.double.custom_build.a13da4feb`;
- focused FABRIC0.9 acceptance: `136/136 PASS`;
- FABRIC0.8 regression: `71/71 PASS`;
- FABRIC0.7 regression: `88/88 PASS`;
- FABRIC0.6 nonsmooth regression: `121/121 PASS`;
- FABRIC0.6 compatibility regression: `42/42 PASS`;
- playground: `FABRIC0_9_MULTICONTACT_CONE_PLAYGROUND_PASS`;
- editor parse/compile/SCRIPT scan: CLEAN;
- all 4 executable FABRIC0.9 files byte-identical between local exact-double tests and GitHub blobs.

### Geometry -> manifold

Box одновременно касается двух static planes:

```text
floor
wall
```

Geometry compiler автоматически создаёт 8 stable contacts:

```text
floor::mx_my_mz
floor::mx_my_pz
floor::px_my_mz
floor::px_my_pz
wall::mx_my_mz
wall::mx_my_pz
wall::mx_py_mz
wall::mx_py_pz
```

Каждый contact получает:

```text
point
r from center of mass
normal
tangent_1
tangent_2
gap
friction
restitution
```

### 6D rigid-body Jacobian

Generalized velocity:

```text
[vx,vy,vz, wx,wy,wz]
```

Contact row:

```text
[d, r x d]
```

Поэтому angular velocity и torque coupling входят в тот же global solve.

### True 2D Coulomb cone

Каждый impulse:

```text
(j_n, j_t1, j_t2)
```

ограничен:

```text
j_n >= 0
sqrt(j_t1^2+j_t2^2) <= mu*j_n
```

Не используются независимые tangent clamps.

### Global solve

Все contacts собираются в:

```text
A = J M^-1 J^T
```

и решаются одним convex cone problem через ADMM.

Main experiment:

```text
contacts=8
active=5
sliding=5
rank=6/24
iterations=2395
```

Post linear:

```text
(0.589721054,
 0.776797774,
 0.238711754)
```

Post angular:

```text
(-0.074797351,
 -0.022468940,
  0.122242645)
```

### Impulse audit

Total impulse:

```text
(5.17944211,
 7.55359555,
-1.52257649)
```

Torque impulse:

```text
(-0.23739868,
 -0.26696273,
  0.57779412)
```

Linear/angular impulse residuals close at exact-double tolerance.

Energy:

```text
14.208000000
->
1.015847883
```

Main dissipative case does not create kinetic energy.

### Order invariance

Проверены:

- normal input order;
- reversed contacts;
- reversed planes + reversed contacts.

Получены exact-equal:

- post linear/angular state;
- canonical per-contact impulse map;
- state hash.

Hash:

`181d3a3cd0e4d0439c79b5ed6afd9939cc88c94276446e148ab8cdf0c453c7b5`.

### Redundant reactions

```text
matrix rank = 6
impulse coordinates = 24
```

Это означает, что per-contact reaction split на избыточном manifold не обязан быть уникальной physical truth.

FABRIC теперь явно различает:

```text
generalized physical state / total impulse observables
vs
one deterministic internal reaction representative
```

Deterministic representation не объявляется mathematically unique.

### Главный вывод FABRIC0.9

> Geometry становится compiler input для global cone-constrained reaction problem; порядок contact records не является физической семантикой.

### Следующая фундаментальная граница

`FABRIC0.10 — PERSISTENT CONTACT GRAPH + SPARSE HYBRID DAE`.

Нужно связать temporal DAE 0.8 и multi-contact cone 0.9:

```text
persistent contact identities across time
dynamic body-body contacts
contact appear/persist/disappear
contact graph islands
sparse assembly
warm-start
resting contact
cone solve inside event-time DAE
order-invariant island replay
```

Production promotion не заявляется.


## FABRIC0.10 — PERSISTENT CONTACT GRAPH + SPARSE HYBRID CONTACT STEP

**Parent research head:** `87cf1889ad59e956dde884991af061faa423b8b9`  
**Design:** `docs/research/FABRIC0_10_PERSISTENT_CONTACT_GRAPH_RU.md`  
**Evidence:** `validation/fabric0-compositional-world-fabric-v10-validation.json`  
**Status:** `IMPLEMENTED / LOCAL_EXACT_DOUBLE_PASS / DRAFT_REVIEW_CANDIDATE`.

### Validation

- exact double-Godot: `4.7.1.stable.double.custom_build.a13da4feb`;
- focused FABRIC0.10 acceptance: `97/97 PASS`;
- playground: `FABRIC0_10_PERSISTENT_CONTACT_GRAPH_PLAYGROUND_PASS`;
- editor parse/compile/SCRIPT scan: CLEAN;
- all 4 executable FABRIC0.10 files byte-identical between local exact-double tests and GitHub blobs.

### Predecessor evidence policy

В isolated FABRIC0.10 lab predecessor runtime suites **не запускались заново**.

Вместо ложного regression claim проверено, что FABRIC0.9 executable blobs на ветке неизменны относительно v9 validation evidence:

```text
solver       630f9ad5048a7061010b6a5439f18f3654440d4d
experiments  e7f0e5d23437ed142c119dd9dccc239ba0d9644c
acceptance   e91a93ae643e1a414d0baa85e0ffa5d035f4f755
playground   b7de22c76bef3f09e5db5ef498635870bb70f67b
```

То есть:

```text
predecessor bytes preserved
!=
predecessor runtime regression rerun
```

### Persistent contact graph

Contact больше не только мгновенный impact record.

Stable contact cache хранит:

```text
age_steps
first_step
last_step
warm_impulse
```

Lifecycle:

```text
appeared
persisted
disappeared
```

Built-in research identities:

```text
plane:<plane_id>|body:<body_id>

pair:<canonical_body_a>|<canonical_body_b>
```

### Dynamic body-body load

Stack:

```text
B
↕ pair:A|B
A
↕ floor
```

после пяти gravity steps сохраняет практически неизменные positions и near-zero velocities.

Persistent cached normal impulses:

```text
pair:A|B                ~= 0.0981 N*s
plane:floor|body:A      ~= 0.1962 N*s
```

То есть dynamic body-body contact реально передаёт load вниз.

### Warm start

Cold first solve:

```text
39 iterations
0 warm hits
```

Следующий timestep с теми же четырьмя stable contacts:

```text
3 iterations
4 warm hits
```

Warm state привязан к contact identity, не island id.

### Island lifecycle

Initial:

```text
island:A = [A,B]
island:D = [D]
island:E = [E]

3 islands
```

Когда появляется dynamic contact:

`pair:D|E`

получаем:

```text
3 islands
→
2 islands
```

Lifecycle:

```text
appear pair:D|E
persist pair:D|E
disappear pair:D|E
```

После disappearance:

```text
2 islands
→
3 islands
```

При merge старые D/E floor contacts сохраняют warm-start state.

### Static environment не склеивает graph

D и E могут оба касаться одного floor и при отсутствии dynamic D-E edge оставаться разными solver islands.

Static geometry — boundary condition, а не dynamic graph node.

### Sparse structure

Merged D/E island:

```text
3 contacts
9 contact rows

sparse effective-mass entries = 29
dense local capacity          = 81
```

World sparse entries during merge:

`41`.

Текущий numerical backend после sparse assembly пока densify-ит island-local matrix для Cholesky. Это explicit non-claim, а не скрытая «sparse solver» претензия.

### Independent island equivalence

Полный world с A/B + изменяющейся D/E topology сравнивается с отдельным A/B-only world.

После пяти steps:

```text
A/B positions
A/B velocities
```

совпадают до `1e-12`.

Unrelated island graph mutation не меняет local physical trajectory.

### Order invariance через историю

Run A:

- normal body insertion;
- normal contact order.

Run B:

- reversed body insertion;
- reversed provider contact order.

Exact match:

- contact history JSON;
- final physical states;
- final contact cache;
- final world hash.

Hash:

`4103da3235e4cdd7f1c63c809d3dd71ab39d10ec7f68094d6eef33eabfe6033d`.

### Event bridge

Contact-free falling sphere:

```text
y0=2
radius=0.5
vy0=-1
g=-9.81
dt=1
```

First floor crossing localized:

```text
te = 0.460381178993
reference = 0.46038117899287667
```

At exactly `te` contact graph records:

```text
appeared:
plane:floor|body:fall
```

Remaining macrostep проходит уже через persistent island solve.

Final:

```text
t=1
position ~= (0,0.5,0)
velocity ~= 0
```

Event hash:

`ac7c2758e89afb9798a3b2268c99877eb0795f33699e6fbf5a6dfe9034da6eb6`.

Bridge сознательно fail-closed, если macrostep начинается с уже активных contacts:

`EVENT_BRIDGE_REQUIRES_CONTACT_FREE_START`.

### Главный вывод FABRIC0.10

> Contact становится persistent graph relation с identity, lifecycle и numerical continuity, а solver locality следует topology динамических contact edges.

### Следующая фундаментальная граница

`FABRIC0.11 — GENERAL EVENT-LOCALIZED CONTACT ISLANDS + SPARSE BACKEND`.

Нужно убрать два research shortcuts:

1. event localization пока работает только из contact-free start;
2. sparse assembly пока заканчивается dense island-local factorization.

Критический test:

```text
resting stack already constrained
+
new dynamic body impacts stack inside a large macrostep
+
impact localized while old contacts remain active
+
contact graph merges at event instant
+
warm starts remap
+
sparse island recompile
+
remaining time continues
+
input permutation leaves accepted state unchanged
```

Production promotion не заявляется.


## FABRIC0.11 — GENERAL EVENT-LOCALIZED CONTACT ISLANDS + SPARSE BACKEND

**Parent research head:** `b1730170058d31c7fb53b1e42ff8425661797f01`  
**Design:** `docs/research/FABRIC0_11_EVENT_LOCALIZED_SPARSE_ISLANDS_RU.md`  
**Evidence:** `validation/fabric0-compositional-world-fabric-v11-validation.json`  
**Status:** `IMPLEMENTED / LOCAL_EXACT_DOUBLE_PASS / DRAFT_REVIEW_CANDIDATE`.

### Validation

- exact double-Godot: `4.7.1.stable.double.custom_build.a13da4feb`;
- focused FABRIC0.11 acceptance: `120/120 PASS`;
- FABRIC0.10 runtime regression rerun: `97/97 PASS`;
- playground: `FABRIC0_11_EVENT_SPARSE_ISLANDS_PLAYGROUND_PASS`;
- editor parse/compile/SCRIPT scan: CLEAN;
- all 4 executable FABRIC0.11 files byte-identical between local exact-double tests and GitHub blobs.

### Active-island event localization

Macrostep starts with existing stack:

```text
B
↕ pair:A|B
A
↕ floor
```

Incoming C is free.

During every bisection probe FABRIC advances the candidate world while preserving only the contact IDs active at macrostep start.

Old contacts therefore remain constrained while the new event is searched.

At event:

```text
pair:A|B gap               ~= 3.44e-12
plane:floor|body:A gap     ~= 5.54e-12
pair:B|C new gap           ~= 9.997662e-8
```

with contact tolerance `1e-7`.

### Event time

Macrostep begins at:

`0.04 s`.

Relative localized event:

`0.35709945939307 s`.

Absolute event:

`0.39709945939307 s`.

Bisection probes:

`36`.

Bisection tolerance:

`1e-11 s`.

Continuous free-fall reference:

`0.3609505622728941 s`.

Discrete constrained integrator offset:

`-0.0038511028798241 s`.

Важно: это integration discretization error текущего `0.01 s` semi-implicit substep, а не bisection error.

### Same-time island merge

Before:

```text
[A,B]
contacts:
pair:A|B
floor|A
```

At `te`:

```text
[A,B,C]
contacts:
pair:A|B
pair:B|C
floor|A
```

Appeared:

`pair:B|C`.

Old contacts persist.

Warm-start remap:

```text
pair:A|B
plane:floor|body:A
```

Event solve reports:

`2 warm-start hits`.

### Sparse PCG backend

FABRIC0.10 sparse assembly no longer densifies before linear solve.

FABRIC0.11 ADMM solves:

```text
(A + rho I) lambda
=
rho(z-u)-b
```

with Jacobi-preconditioned PCG over sparse row dictionaries.

Independent unit solve:

```text
[4 1] x = [1]
[1 3]     [2]
```

returns:

```text
x = [1/11, 7/11]
```

in exactly `2` PCG iterations.

### Event sparse solve

At merged A/B/C island:

```text
sparse A entries = 21
dense capacity   = 81

ADMM iterations = 31
PCG calls       = 31
PCG iterations  = 93
max PCG/call    = 3

dense materializations = 0
```

All 3 contacts active.

Incoming impulse propagates through B→A→floor in the same event solve.

### Remaining flow

Remaining macrostep:

`0.24290054060693 s`.

Continuation:

```text
25 constrained substeps
25 island solves
80 PCG calls
234 PCG iterations
0 dense materializations
```

Final time:

`0.64 s`.

Final stack:

```text
A y ~= 0.50000000002449
B y ~= 1.50000000004311
C y ~= 2.50000010002817
```

Velocity norms:

`< 2e-8`.

Final world hash:

`86d76fc7a4b93bdd27030e1b343151d008e2c2e62ddfa72bdc11cf46d4f6133b`.

### Event history

В exact event timestamp сохраняется ровно один topology lifecycle record:

```text
appeared:
pair:B|C

persisted:
pair:A|B
plane:floor|body:A
```

Continuation не создаёт artificial same-time persist record.

### Independent-island scheduling contract

Два independent stack islands решаются:

- forward;
- reverse island schedule;
- reversed body insertion;
- reversed provider contact order.

Exact hash:

`e50cceb70dc4ecbd0100e5207ca5a58a2285c90a5085a6556b19db8ce8699078`.

Это semantic prerequisite для будущего parallel execution.

Actual worker threads в FABRIC0.11 не заявляются.

### Главный вывод FABRIC0.11

> Persistent constrained graph, event-time topology mutation и genuinely sparse linear solve теперь находятся в одной causal execution path.

### Следующая фундаментальная граница

`FABRIC0.12 — ADAPTIVE MULTI-EVENT MANIFOLD DAE`.

Нужно убрать следующие shortcuts:

```text
fixed 0.01 constrained substeps
first topology-change event only
fail-closed old-contact disappearance
sphere/plane feature identity only
Jacobi-only sparse preconditioner
no actual parallel execution
```

Critical experiment:

```text
resting multi-contact structure
+
tumbling body
+
old contact disappears
while multiple new feature contacts appear
inside one macrostep
+
adaptive event refinement converges
+
manifold event iteration reaches fixed point
+
warm starts remap
+
parallel/reordered sparse islands
produce same accepted world state
```

Production promotion не заявляется.


## FABRIC0.12 — ADAPTIVE MULTI-EVENT MANIFOLD DAE

**Parent research head:** `9e04333a27d01992be6740d7b817579980a254f0`  
**Implementation commit:** `172549487a4637be122478df7b83b2049f531962`  
**Design:** `docs/research/FABRIC0_12_ADAPTIVE_MULTIEVENT_MANIFOLD_RU.md`  
**Evidence:** `validation/fabric0-compositional-world-fabric-v12-validation.json`  
**Status:** `IMPLEMENTED / LOCAL_EXACT_DOUBLE_PASS / DRAFT_REVIEW_CANDIDATE`.

### Validation

- exact double-Godot: `4.7.1.stable.double.custom_build.a13da4feb`;
- focused FABRIC0.12 acceptance: `115/115 PASS`;
- playground: `FABRIC0_12_ADAPTIVE_MULTIEVENT_MANIFOLD_PLAYGROUND_PASS`;
- editor parse/compile/SCRIPT scan: CLEAN;
- all 4 executable FABRIC0.12 files byte-identical between local exact-double tests and GitHub branch blobs.

### Predecessor evidence policy

FABRIC0.11 runtime suite was not materialized in isolated FABRIC0.12 lab, therefore 0.11 runtime regression is **not** claimed.

All 0.11 executable blobs are preserved exactly against v11 evidence.

### Adaptive manifold DAE

Reduced research model:

```text
2D oriented rectangle
inside
floor + wall corner
```

Differential:

```text
theta_dot = omega
omega_dot = -frequency^2 * theta
```

Algebraic center is derived from active support feature constraints.

### Orientation-aware features

Negative orientation:

```text
floor|vertex:BR
wall|vertex:BL
```

Degenerate event manifold:

```text
floor|edge:bottom
wall|edge:left
```

Positive orientation:

```text
floor|vertex:BL
wall|vertex:TL
```

Feature records carry geometric lineage.

### Multiple event instants

One `1.2 s` adaptive advance contains two zero crossings.

Analytic references:

```text
PI/16
= 0.19634954084936...

5PI/16
= 0.98174770424681...
```

At tolerance `1e-9`:

```text
0.19634954475054
0.98174771949769
```

### Same-time manifold fixed point

Each physical event performs:

```text
vertex manifold
→ degenerate edge manifold
→ directed post-event vertex manifold
→ fixed point
```

Per event:

```text
iterations = 3
topology mutations = 2
fixed point = true
```

Two event instants therefore produce:

`4 topology mutations`.

### Adaptive convergence

Tolerance refinement:

```text
1e-5
1e-7
1e-9
1e-11
```

Max event-time error:

```text
1.467192298e-5
5.7857693e-7
1.525088e-8
3.8339e-10
```

Strictly decreasing.

Accepted steps:

```text
14
33
68
167
```

Energy drift magnitude also decreases, reaching approximately `7e-11` at `1e-11` tolerance.

This closes the FABRIC0.11 finding that bisection tolerance alone did not establish physical time convergence.

### Feature-lineage warm remap

Warm numerical state follows feature ancestry, not only exact string identity.

Demonstrated:

```text
vertex → edge → different vertex
```

while floor/wall warm values `2` and `3` survive the manifold change.

Generic split gate:

```text
edge warm=4
→
BL=2
BR=2
```

Generic merge gate:

```text
BL=2
BR=3
→
edge=5
```

### Sparse pattern/preconditioner cache

Sparse pattern key:

```text
island id
+
sorted nonzero row structure
```

Cold parallel solve:

```text
cache hits=0
misses=2
```

Warm solve:

```text
hits=2
misses=0
```

Changed coefficients with same pattern still hit cache, but physical result hash changes and PCG re-solves to tolerance.

Therefore cached preconditioner remains numerical policy, not physical truth.

### Actual Thread parallelism

Unlike FABRIC0.11, FABRIC0.12 starts real Godot `Thread` workers.

Two independent sparse systems run concurrently.

```text
threads_started=2
```

Canonical parallel hash:

`40635ad181b0273659ffd0dacae622b7b7249427d5073c2f9ffb5913f43f7fe0`.

Reverse spawn order produces exact same hash.

### Derived sleep/wake

After 3 quiet updates:

```text
sleeping=true
```

Nonzero motion:

```text
woke=true
sleeping=false
```

Sleep state remains outside physical state hash.

### Main hashes

Physical adaptive state:

`a0cad2efa4bed9d598fbaac147f177e11e4d2f4e5c8bac6d9876cec7c8ae3263`.

Parallel sparse result:

`40635ad181b0273659ffd0dacae622b7b7249427d5073c2f9ffb5913f43f7fe0`.

### Главный вывод FABRIC0.12

> Correct event semantics must demonstrate convergence under trajectory refinement, and persistent geometric identity must survive feature topology changes through lineage rather than array/string equality alone.

### Next wall

`FABRIC0.13 — UNIFIED ADAPTIVE 3D CONTACT GRAPH`.

FABRIC0.12 deliberately proved adaptive/manifold semantics in a reduced model.

Next step must integrate them back into the full persistent sparse contact graph of FABRIC0.11:

```text
adaptive persistent 3D contact stepping
3D orientation/inertia
real multipoint feature manifold
multiple event fixed points
feature lineage split/merge
sparse pattern reuse
real parallel contact islands
derived sleep/wake
refinement convergence on actual contact graph
```

Production promotion не заявляется.
