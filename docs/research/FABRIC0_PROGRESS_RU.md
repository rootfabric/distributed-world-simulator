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


## FABRIC0.13 — UNIFIED ADAPTIVE 3D CONTACT GRAPH

**Parent research head:** `fdcd3f5dc18a5f62a6335c954ddca794d0d79f21`  
**Design:** `docs/research/FABRIC0_13_UNIFIED_ADAPTIVE_3D_CONTACT_GRAPH_RU.md`  
**Evidence:** `validation/fabric0-compositional-world-fabric-v13-validation.json`  
**Status:** `IMPLEMENTED / EXACT_DOUBLE_PASS / REMOTE_BYTE_IDENTITY_PASS / DRAFT_REVIEW_CANDIDATE`.

### Validation

- exact Godot re-extracted from the user-provided archive: `4.7.1.stable.double.custom_build.a13da4feb`;
- focused FABRIC0.13 acceptance: `95/95 PASS`;
- playground: `FABRIC0_13_UNIFIED_ADAPTIVE_3D_CONTACT_GRAPH_PLAYGROUND_PASS`;
- editor parse/compile/SCRIPT scan: CLEAN;
- all **7** executable FABRIC0.13 files byte-identical between current exact-tested local lab and GitHub branch.

### Why 0.13 matters

FABRIC0.13 is not another isolated capability.

It closes the integration wall between:

```text
FABRIC0.11
persistent sparse contact graph

+

FABRIC0.12
adaptive multi-event manifold semantics
```

The accepted causal path is now:

```text
persistent A/B support graph
→ adaptive flow of free rotating C
→ localized impact
→ same-time island merge [A,B] -> [A,B,C]
→ sparse constrained DAE
→ adaptive rocking flow
→ edge -> face -> opposite-edge manifold fixed point
→ adaptive flow
→ reverse manifold fixed point
→ deterministic final state
```

### Three physical events in one 0.7 s advance

```text
impact:
0.12770032218309

manifold #1:
0.15171711003539

manifold #2:
0.58519759521384
```

Impact:

```text
appeared:
pair:B|C|edge:back_bottom

persisted:
floor|A
pair:A|B

island:
[A,B] -> [A,B,C]
```

Pre-impact support reactions preserved:

```text
floor|A = 19.62
pair:A|B = 9.81
```

### Multipoint feature topology

Rocking event:

```text
edge:back_bottom
2 points
→
face:bottom
4 points
→
edge:front_bottom
2 points
→ fixed point
```

Reverse event returns through the same face lineage.

Each manifold event:

```text
iterations = 3
topology mutations = 2
fixed point = true
```

Warm force and impulse survive both feature-ID changes through geometric lineage.

### Translation + rotation in the same contact equation

Rocking contact Jacobian contains:

```text
J =
[0, -1, +1, dr/dtheta]
```

and curvature acceleration:

```text
gamma =
d2r/dtheta2 * omega^2
```

Thus rotation is not presentation-only state; it contributes directly to contact reaction equations.

### Sparse numerical evidence

Main `1e-9` run:

```text
PCG calls       = 38
PCG iterations  = 95

pattern hits    = 36
pattern misses  = 2

max constraint residual
<= 2e-14
```

Final support reactions:

```text
floor|A =
26.5710523718944

pair:A|B =
16.7610523718944

pair:B|C|edge:back_bottom =
6.95105237189441
```

### Unified refinement convergence

Reference:

`tol = 1e-12`.

Maximum event-time error:

```text
1e-7  -> 8.034517395838492e-8
1e-9  -> 3.1108455811335034e-9
1e-11 -> 5.63820101717738e-11
```

Maximum final-state error:

```text
1e-7  -> 6.4536567821738e-7
1e-9  -> 2.6241198575194247e-8
1e-11 -> 4.793412056169899e-10
```

Both strictly decrease.

This is the key integration result:

> convergence survives impact-time contact graph merge, sparse reaction solve and multipoint manifold topology mutation.

### Quaternion audit

Final normalized orientation quaternion:

```text
length = 1.0

x = -0.01903164707883
y = 0
z = 0
w = 0.99981888180283
```

Important scope:

```text
quaternion representation
!=
general arbitrary-axis 6DOF proof
```

The demonstrated rotational trajectory is one-axis.

### Actual parallel contact-island audit

Two actual Godot Threads solve:

```text
island:A = [A,B,C]
island:D = [D,E]
```

Canonical hash:

`6ef3fd35474a179a7bf02675d5bde9ecb457f235fdb7cc70f017a69757f92757`.

Reverse thread spawn order gives the exact same hash.

Parallel audit does not mutate physical world hash.

### Deterministic physical hash

`f486303b7f133d28148d63362ad368d82e946132f2a12f9c164ae5edc2819483`.

Fresh `1e-9` replay reproduces exact event JSON and exact physical hash.

### Exact-byte recovery boundary

All 7 remote GitHub blobs equal local `git hash-object`.

Two large files initially differed because persistence lost one trailing final newline.

The checkpoint was **not** accepted until the trailing bytes were corrected and hashes matched.

This records an important evidence rule:

> When validation names exact executable bytes, formatting bytes are part of repository evidence. “Semantically identical source” is insufficient for an exact-byte claim.

### Predecessor policy

FABRIC0.12 runtime suite was not materialized in the current 0.13 lab, so no new 0.12 runtime regression is claimed.

All four FABRIC0.12 executable blobs are preserved exactly against v12 evidence.

### Main non-claims

Still not proven:

- general free 6DOF rigid body;
- 3-axis angular velocity/inertia tensor integration;
- arbitrary convex/mesh manifold;
- adaptive tangential Coulomb cone in this successor;
- general unilateral separation/complementarity for all multipoint rows;
- arbitrary simultaneous multi-body impact fixed point;
- production broadphase/thread pool/CSR;
- full Construction/authority/persistence/replication integration;
- full materialized DWS regression.

A/B support coordinates are partially algebraically projected in the research stand and this remains an explicit scope boundary.

### Next wall

`FABRIC0.14 — FULL 6DOF FRICTIONAL FEATURE MANIFOLD`.

Target:

```text
full translation 3DOF
+
full rotation 3DOF
+
quaternion differential update
+
body/world inertia tensor
+
normal unilateral complementarity
+
tangential Coulomb cones
+
persistent convex feature lineage
+
adaptive multi-event fixed points
+
sparse parallel islands
```

Production promotion не заявляется.


## FABRIC0.14 — FULL 6DOF FRICTIONAL FEATURE MANIFOLD

**Parent research head:** `1b4be82a4b092acbddcc4445444104c079293f91`  
**Exact-tested implementation head before documentation:** `afe5e417d9787e082fecce8a635001f363417a48`  
**Design:** `docs/research/FABRIC0_14_FULL_6DOF_FRICTIONAL_FEATURE_MANIFOLD_RU.md`  
**Evidence:** `validation/fabric0-compositional-world-fabric-v14-validation.json`  
**Status:** `IMPLEMENTED / EXACT_DOUBLE_PASS / REMOTE_BYTE_IDENTITY_PASS / PREDECESSOR_RUNTIME_PASS / DRAFT_REVIEW_CANDIDATE`.

### Exact validation

- Godot `4.7.1.stable.double.custom_build.a13da4feb`, re-extracted from the original user archive;
- FABRIC0.14 acceptance: `156/156 PASS`;
- playground: `FABRIC0_14_FULL_6DOF_FRICTIONAL_FEATURE_MANIFOLD_PLAYGROUND_PASS`;
- editor parse/compile/SCRIPT scan: CLEAN;
- executable byte identity: `7/7 PASS`;
- FABRIC0.13 runtime regression on the same engine: `95/95 PASS`;
- all seven FABRIC0.13 executable blobs preserved.

### Physical state

FABRIC0.14 uses a 13-component rigid-body state:

```text
position      3
quaternion    4
linear v      3
angular omega 3
```

Body inertia:

```text
I_body =
(0.19, 0.31, 0.43)
```

Torque-free three-axis audit:

```text
final omega =
(
 0.64777572651907,
-0.36223547345886,
 1.87243783476517
)

linear momentum drift =
0

world angular momentum drift =
9.733960482902654e-10

rotational energy drift =
1.7629e-10
```

### Unilateral + Coulomb law

Executable modes now include:

```text
separated
stick
slide
```

Stick probe:

```text
normal =
12.2798501384264

cone ratio =
0.46507393858269
```

Separation probe:

```text
active = false
normal = 0

signed required normal =
-4.3165743280206
```

Slide stays on:

`|Ft| = mu Fn`.

### Oblique impact

Impact:

```text
t =
0.16920086866594

feature =
plane|C|v:---

mode =
stick

impulse =
(
-0.38652781487918,
 2.99430127860919,
 8.6621395387905
)
```

Momentum audit:

```text
linear error  = 0
angular error = 0
```

Kinetic delta:

`-25.073057544238`.

### Feature hierarchy

Geometry-derived support classification:

```text
vertex = 1 point
edge   = 2 points
face   = 4 points
```

Face lineage probe:

```text
[
  v:++-,
  v:+--,
  v:-+-,
  v:---
]
```

### Adaptive feature events

Main `0.315 s` sliding run:

```text
0.25850330043665

v:---
→ edge:0:v:+--:v:---
→ v:+--

0.31322331523056

v:+--
→ edge:1:v:++-:v:+--
→ v:++-
```

Each:

```text
iterations = 3
topology mutations = 2
fixed point = true
```

### Hidden projection impulse was removed

During development, refinement exposed an energy discrepancy of about `0.1224` that did not shrink.

Cause:

```text
feature switch
→ silent normal-velocity projection
→ physical impulse missing from causal history
```

Fix:

```text
lineage remap
→ explicit frictional unilateral transition impulse
→ momentum/energy audit
→ only then constraint projection
```

This converted hidden numerical dissipation into explicit physical jump semantics.

### Energy ledger

Main `1e-9` sliding run:

```text
continuous friction dissipation =
1.2019943422435

discrete feature-event losses =
4.06330610007658

energy delta =
-5.26530042753262

closure residual =
1.4787455704379227e-8
```

Closure refinement:

```text
1e-7  -> 3.8286514048024856e-7
1e-9  -> 1.4787455704379227e-8
1e-11 -> 3.3513192221334975e-10
```

### Unified convergence

Event-time error:

```text
1e-7  -> 6.510981837015706e-8
1e-9  -> 1.5766716265908087e-9
1e-11 -> 3.3262503862374615e-11
```

Full 13D state error:

```text
1e-7  -> 5.464352880735213e-7
1e-9  -> 1.2631674595198206e-8
1e-11 -> 2.586177383356869e-10
```

Event time, state and energy ledger all converge.

### Main hashes

Sliding physical hash:

`2b52dc944cdc4a48152265db3e456c629bfb5f66969850563e39ec188147efe7`.

Impact-run hash:

`de5584cb0f2da6b788e8873eac1ff99e2a8bedd1f71c56727fe809eaae29efe9`.

Torque-free hash:

`e57d66d29b7de53757f5b4ba2d0d2a26f3c2a342086a63aebc93726b40666a99`.

Parallel hash:

`526844a8ca0629969477f2942853b3e7b9617b391e39fc54147d30d38852773c`.

### Exact byte boundary

Seven GitHub executable blobs exactly equal current locally tested `git hash-object` values.

This is now part of the durable v14 evidence.

### Main non-claims

Still open:

- several simultaneously free interacting 6DOF bodies;
- coupled face-point normal complementarity;
- dynamic persistent face manifold;
- arbitrary convex/GJK/EPA/mesh geometry;
- dynamic separation localization;
- dynamic stick/slide transition localization;
- coupled multi-contact friction cones;
- rolling/torsional friction;
- simultaneous-impact solver;
- production broadphase/block-sparse/thread-pool;
- Construction/authority/persistence/network integration;
- full materialized DWS regression.

### Next wall

`FABRIC0.15 — MULTIBODY CONVEX COMPLEMENTARITY GRAPH`.

Target:

```text
multiple free 6DOF rigid bodies
+
convex feature graph
+
simultaneous normal complementarity
+
coupled friction cones
+
dynamic separation
+
stick/slide events
+
island merge/split
+
adaptive fixed point
+
block-sparse parallel solve
+
momentum/energy/refinement evidence
```


## FABRIC0.15 — MULTIBODY CONVEX COMPLEMENTARITY GRAPH

**Parent research head:** `e4962f067722008ac90993ba648a6f9d2a84f9ec`  
**Exact executable commit:** `a8ff0d7360b4bba0f1b3e164f8c040d73622b1ee`  
**Design:** `docs/research/FABRIC0_15_MULTIBODY_CONVEX_COMPLEMENTARITY_GRAPH_RU.md`  
**Evidence:** `validation/fabric0-compositional-world-fabric-v15-validation.json`  
**Status:** `IMPLEMENTED / EXACT_DOUBLE_PASS / REMOTE_BYTE_IDENTITY_PASS / PREDECESSOR_RUNTIME_PASS / DRAFT_REVIEW_CANDIDATE`.

### Exact validation

- Godot `4.7.1.stable.double.custom_build.a13da4feb`;
- FABRIC0.15 acceptance: `103/103 PASS`;
- playground: `FABRIC0_15_MULTIBODY_CONVEX_COMPLEMENTARITY_GRAPH_PLAYGROUND_PASS`;
- editor parse/compile/SCRIPT scan: CLEAN;
- executable byte identity: `7/7 PASS`;
- FABRIC0.14 runtime regression on the same engine: `156/156 PASS`;
- all seven FABRIC0.14 executable blobs preserved.

### Coupled multibody graph

Main stand:

```text
plane
  ↕
  A
  ↕
  B
  ↕
  C

D = free
```

All four bodies remain full 6DOF.

Whole-system physical state:

```text
4 × 13 = 52 components
```

A projected block Gauss-Seidel contact solver updates shared body velocities, so solving one contact changes residuals at adjacent contacts.

### Graph merge

Main `dt=0.001` run:

```text
C|D appears
t = 0.18299031095859

mode = stick

normal impulse =
0.59227588215158

tangent impulse =
(
 -0.00467806420921,
 -0.03987303859427
)
```

Topology:

```text
[A,B,C] + [D]
        ↓
[A,B,C,D]
```

### Complementarity split

Exact source transition:

```text
t = 0.32

drive:D
(0,0,0)
→
(0,0,12)
```

After it:

```text
C|D
Pn ~ 0
+
separating velocity > 0
→
CONTACT_DISAPPEAR
reason = COMPLEMENTARITY_SEPARATION
```

Topology:

```text
[A,B,C,D]
        ↓
[A,B,C] + [D]
```

### Coupled normal chain

Analytic `dt=1/240` gravity-load expectations:

```text
B|C      0.0367875
A|B      0.08379375
plane|A  0.12466875
```

Solved:

```text
B|C      0.03678437280127
A|B      0.08378662693623
plane|A  0.12466162693623
```

This proves load propagation through shared contact state.

### Mixed friction in one island

Simultaneous modes:

```text
plane|A  stick
A|B      stick
B|C      slide
```

For `B|C`:

```text
Pn =
0.03678437280127

|Pt| =
0.01250668675243

|Pt| = mu Pn
```

### Configuration localization

A new-contact penetration/ Baumgarte artifact made contact lifetime timestep-dependent during development.

Accepted semantics:

```text
detect negative gap
→ configuration-only correction to gap=0
→ no velocity change
→ no momentum change
→ physical contact impulse solve
```

Main `dt=0.001`:

```text
projection distance =
1.911595595e-5

projection energy delta =
0
```

This is explicitly different from FABRIC0.14 hidden velocity projection, which was a real physical impulse.

### Refinement

Reference:

`dt=0.0005`.

Merge-time error:

```text
0.004 -> 1.5902247457270924e-3
0.002 -> 6.811752040176144e-4
0.001 -> 2.2666409624433337e-4
```

52D state error:

```text
0.004 -> 4.257633804026106e-3
0.002 -> 1.8033092993312572e-3
0.001 -> 7.327864068812362e-4
```

Energy-ledger residual:

```text
0.004 -> 0.1863040594936023
0.002 -> 0.09295272462256121
0.001 -> 0.047009019436045296
```

All three strictly decrease.

### Main numerical evidence

```text
contact solves =
403

PGS iterations =
12896

max normal violation =
1.634842214e-4

max cone violation =
0

max penetration =
4.72630019e-6

internal pair linear momentum error =
0

internal pair angular momentum error =
0
```

Energy:

```text
contact dissipation =
0.65570895032957

contact gain =
0

external work =
1.13448578288811

projection energy delta =
0

energy delta =
0.52578585199459

ledger residual =
0.04700901943605
```

### PGS order evidence

Finite-iteration forward/reverse contact order is not exact-equal.

Observed:

```text
max delta v =
1.8593214664426525e-6

max delta omega =
2.1323642847629e-7
```

Same friction modes are recovered.

Therefore current claim is **order robustness**, not exact order independence.

### Parallel audit

Two actual Godot Threads produce canonical joined hash:

`49e8c7b2fa0e1177f0e19d36ee85c4e22239ad95556c2c0a7c909d24fb47b34b`.

Reverse spawn order yields exactly the same hash and does not mutate physical world state.

### Main state hash

`68e18b6a9a16b574aaf0b6ca30b3cf5160ea9a69ba8919df11f1b04fda92d29c`.

### Exact byte boundary

Seven exact-tested local files were converted to Git blobs, committed in one tree on top of FABRIC0.14 and re-fetched from the branch.

Result:

`7/7 remote byte identity PASS`.

### Main non-claims

Still open:

- arbitrary convex polytope collision;
- GJK/EPA;
- true multipoint face manifolds;
- global MCP/NCP or semismooth solve;
- exact PGS order independence;
- production block-sparse backend;
- adaptive error-controlled time integration;
- exact simultaneous multi-impact localization;
- root-localized stick/slide events;
- fully autonomous main split without an explicit source change;
- rolling/torsional friction;
- production broadphase/thread pool;
- Construction/authority/persistence/network integration;
- full materialized DWS regression.

### Next wall

`FABRIC0.16 — GENERAL CONVEX MULTIPOINT MCP`.

Target:

```text
arbitrary convex support mapping
+
GJK / EPA
+
persistent multipoint manifold
+
graph-wide MCP/NCP
+
coupled friction cones
+
adaptive contact / separation / stick-slide localization
+
same-world parallel islands
+
broadphase
+
refinement / momentum / energy evidence
```


## DUAL-TRACK ROADMAP FREEZE — PHYSICAL CORE + FABRIC-BAKE

**Pre-freeze FABRIC0.15 head:** `381e2216661d07aed898f3a2bff0b9590fb5b4f5`.  
**FABRIC0.15 status:** `RESEARCH CANDIDATE CLOSED / EXACT_DOUBLE_PASS / DRAFT_REVIEW_CANDIDATE`.  
**Roadmap:** `docs/research/FABRIC_BAKE_ROADMAP_RU.md`.  
**Architecture:** `docs/research/FABRIC_BAKE_ARCHITECTURE_RU.md`.

После FABRIC0.15 FABRIC formalized as two parallel research lines:

```text
MAIN PHYSICAL LINE
FABRIC0.x
    ↓
FABRIC0.16 GENERAL CONVEX MULTIPOINT MCP
    ↓
future physical-core checkpoints

PARALLEL REDUCTION LINE
FABRIC-BAKE B0.x
    ↓
B0.0 BAKE FOUNDATION CONTRACTS
    ↓
B0.1 EXACT BOUNDARY REDUCTION
    ↓
B0.2 STRUCTURAL + REFINEMENT GUARDS + LOCAL UNBAKE
    ↓
B0.3 CONTACT/WRENCH BAKE
    ↓
B0.4 DYNAMIC ROM
B0.5 HYBRID BAKE
    ↓
B0.6 ADAPTIVE PHYSICAL FIDELITY
    ↓
B0.7 UNSEEN MACHINE SCALE
```

The two lines meet through `BRIDGE-1/2/3` before FABRIC1.

### Frozen BAKE invariants

1. `PhysicalBakeArtifact != canonical world truth`.
2. FABRIC is not added as a canonical source domain.
3. Source binding uses sorted `CanonicalSourceFrontier[]`, not necessarily one source.
4. `AuthorityEnvelope` forbids silent cross-authority mutable bake; unsafe case returns `NO_SAFE_BAKE`.
5. Fundamental `PhysicalBoundaryContract` remains acausal.
6. Physical `STALE` means execution forbidden.
7. Correctness is boundary-observable error, not internal state equality.
8. Approximate artifacts have deterministic `ValidatedDomain + ErrorEnvelope`; statistical “confidence” is not the authority contract.
9. `RefinementGuard` must conservatively detect hidden detail that needs to return before missed authoritative failure/event.
10. Reduction may legally return `NO_SAFE_BAKE`.
11. Presentation LOD and physical fidelity are orthogonal.
12. FABRIC-BAKE reports safe physical fidelity; global scheduler owns resource allocation.

### Predecessor gates

```text
B0.0:
FABRIC0.15 research checkpoint closed
+ RL0 provenance/invalidation semantics
+ Construction ownership boundary

B0.1:
FABRIC0.3–0.5 linear conservation/power foundations

B0.2:
FABRIC0.14 full 6DOF

B0.3 FINAL:
FABRIC0.16 general convex multipoint contact
+ stronger graph complementarity
```

### Parallel execution

B0.0, B0.1 and B0.2 may proceed in parallel with FABRIC0.16.

B0.3 prototype may use 0.15, but B0.3 final acceptance is blocked on 0.16.

Physical-core development must not stop for BAKE.

### FABRIC1 target

```text
FABRIC1
=
Constructible
+
Composable
+
Hybrid
+
Persistent
+
Reducible
+
Refinable
+
Deterministic
+
Causally scalable
```

Current next executable checkpoints are therefore simultaneously:

```text
PHYSICAL CORE:
FABRIC0.16 — GENERAL CONVEX MULTIPOINT MCP

FABRIC-BAKE:
B0.0 — BAKE FOUNDATION CONTRACTS
```


## FABRIC0.16 S1 — GENERAL CONVEX MANIFOLD + GRAPH LCP

**Predecessor frontier:** `962b9c1bbf7f04c7853f1fb0e36480cf54f3250d`  
**Design:** `docs/research/FABRIC0_16_GENERAL_CONVEX_MULTIPOINT_MCP_RU.md`  
**Evidence:** `validation/fabric0-compositional-world-fabric-v16-s1-validation.json`  
**Recovery note:** `docs/research/FABRIC0_16_PROGRESS_RU.md`  
**Status:** `IMPLEMENTED / EXACT_LINUX_DOUBLE_PASS / 110_110_PASS / RESEARCH_SLICE_ONLY / NOT_CLOSED`.

### S1 executable boundary

```text
convex vertices/faces
+
support mapping
+
GJK intersection
+
EPA penetration/witness
+
persistent clipped 1..4 point manifold
+
research sweep-and-prune broadphase
+
graph-wide normal active-set LCP
+
coupled Coulomb friction fixed point
```

Main graph falsifier:

```text
A
↕ 4 manifold rows
B
↕ 4 manifold rows
C

8 global normal rows
W[0,4] = -3.5
```

Frictionless pair impulses:

```text
A|B = 0.99999999975
B|C = 0.99999999975
```

Strong sliding falsifier:

```text
8/8 slide
coupling iterations = 253
max complementarity violation = 3.8684533357081426e-11
max cone violation = 6.938893903907228e-18
linear momentum error = 8.921809491438631e-16
angular momentum error = 3.553147333202946e-15
kinetic energy delta = -3.48593081473464
```

Exact runtime:

`Godot 4.7.1.stable.double.custom_build.a13da4feb`.

Acceptance:

```text
FABRIC0.16 General Convex Multipoint MCP S1 Acceptance:
PASS
110/110
```

Playground:

`FABRIC0_16_GENERAL_CONVEX_MULTIPOINT_MCP_S1_PLAYGROUND_PASS`.

Editor parse/compile scan: `CLEAN`.

### Findings closed in S1

- redundant face rows made the first semismooth generalized Jacobian singular;
- compact GDScript pivot control flow contained a hidden bug;
- one-pass tangent solve reopened normal complementarity;
- separate penetration witness lever arms could create artificial internal torque.

Accepted S1 uses explicit canonical active-set normal LCP, observable `1e-9` diagonal regularization, explicit pivot blocks, outer normal/tangent fixed point, and shared manifold impulse points.

### S1 non-claims

FABRIC0.16 is **not closed**. Still open:

- adaptive contact/separation event localization;
- root-localized stick/slide;
- same-world parallel island execution;
- refinement across event-driven convex manifold evolution;
- monolithic globally certified Signorini-Coulomb MCP/NCP;
- production broadphase/block-sparse/thread-pool backend.

### Next slice

```text
FABRIC0.16 S2
ADAPTIVE CONVEX CONTACT EVENTS
+
SAME-WORLD PARALLEL ISLANDS
```


## FABRIC0.16 S2 — ADAPTIVE CONVEX EVENTS + SAME-WORLD PARALLEL ISLANDS

**Accepted executable head:** `92588ac05a7fa5b3cedd64bb567436e82e3a0a0e`  
**Evidence:** `validation/fabric0-compositional-world-fabric-v16-s2-validation.json`  
**Status:** `IMPLEMENTED / EXACT_DOUBLE_PASS / 102_102_PASS / S1_110_110_REGRESSION / REMOTE_BYTE_IDENTITY_PASS / NOT_CLOSED`.

Highlights:

```text
CONTACT_APPEAR    t=0.50000000001455
CONTACT_DISAPPEAR t=0.10000000004657
STICK->SLIDE      t=0.15798543221899

persistent post-event manifold = 4 points
two same-world Godot Threads
parallel state error vs sequential = 0
reverse spawn signature = exact equal
```

Remote exact blobs:

```text
S2 5/5 PASS
S1 8/8 PRESERVED
```

Next wall:

`FABRIC0.16 S3 — UNIFIED EVENT-DRIVEN CONVEX TRAJECTORY + REFINEMENT`.


## FABRIC0.16 — RESEARCH CANDIDATE CLOSED

**Exact-tested executable head:** `3307d553c1c3c79cd9c15a5c565af7fef3f0400c`  
**Final evidence:** `validation/fabric0-compositional-world-fabric-v16-validation.json`  
**Status:** `RESEARCH_CANDIDATE_CLOSED / EXACT_DOUBLE_PASS / REMOTE_BYTE_IDENTITY_PASS / PROJECT_CONTROL_PASS`.

Closure gates:

```text
S1 110/110 PASS
S2 102/102 PASS
S3 101/101 PASS
editor CLEAN
Project Control SUCCESS

S3 3/3 exact remote
S2 5/5 preserved
S1 8/8 preserved
FABRIC0.15 7/7 preserved
```

Unified S3 topology:

```text
2 islands -> 1 -> 2
8 contact rows -> 12 -> 8
2 actual threads -> 1 -> 2
```

Reference event boundaries:

```text
CONTACT_APPEAR    ~0.51000000000058
SOURCE_RELEASE     0.7
CONTACT_DISAPPEAR ~0.70000000004948
```

Full-state and event-time errors strictly decrease from `1e-3` through `1e-9` against a `1e-11` reference. Energy ledger residual is zero; linear/angular momentum errors are zero on the closure trajectory.

FABRIC0.16 is closed as a research candidate only; production integration and stronger non-claims remain open.


## FABRIC0.17 — SIMULTANEOUS MULTI-IMPACT + GENERALIZED CONTACT WRENCH

**Successor branch:** `research/fabric0-17-simultaneous-impact-event-set-r1`  
**Predecessor closure:** FABRIC0.16 @ `ae781ab78f2e0688641f6a332a131b3fb759994f`.  
**Design:** `docs/research/FABRIC0_17_SIMULTANEOUS_MULTI_IMPACT_GENERALIZED_WRENCH_RU.md`.

```text
0.17-A SIMULTANEOUS IMPACT EVENT SET
0.17-B COUPLED SIMULTANEOUS IMPACT SOLVE
0.17-C GENERALIZED CONTACT WRENCH
0.17-D UNIFIED MULTI-IMPACT WRENCH TRAJECTORY
```

### 0.17-A current state

```text
executable HEAD:
9139a213ccee64d3bf1bb95ea32170027421b3b3

IMPLEMENTED CANDIDATE
EXACT LINUX DOUBLE PASS
77/77 PASS
REMOTE BYTE IDENTITY 4/4 PASS
FABRIC0.17 NOT CLOSED
```

Main falsifier:

```text
true roots:
C|L = 0.5
C|R = 0.5
P|Q = 0.5002

coarse 1e-3:
[C|L,C|R,P|Q]

1e-5 and finer:
simultaneous = [C|L,C|R]
deferred     = [P|Q]
```

Reference event `0.50000000000146`, deferred `0.50019999999931`.

Refinement error:

```text
1.5258774510584772e-6
→ 1.192238407998758e-8
→ 9.167711034763215e-11
```

Body-order reversal is exact identical at event-set identity/time boundary. Impact membership requires positive normal approach speed using full point velocity.

Regressions:

```text
0.16 S3 101/101
0.16 S2 102/102
0.16 S1 110/110
editor CLEAN
```

Next wall: `FABRIC0.17-B — COUPLED SIMULTANEOUS IMPACT SOLVE`.


### 0.17-B current state

```text
executable HEAD:
6456ca4a5ce936c7b4c2b11906c696982a091e24

COUPLED SIMULTANEOUS IMPACT SOLVE
IMPLEMENTED CANDIDATE
EXACT LINUX DOUBLE PASS
63/63 PASS
REMOTE BYTE IDENTITY 4/4 PASS
FABRIC0.17 NOT CLOSED
```

Accepted physical jump:

```text
one localized event set
→ one immutable pre-impact state
→ 8-row coupled manifold graph
→ one restitution LCP
→ one post-impact state
```

Symmetric elastic falsifier:

```text
C|L impulse ≈ 4
C|R impulse ≈ 4

L:+2, C:0, R:-2
→
L:-2, C:0, R:+2

linear momentum error  = 0
angular momentum error = 0
```

Sequential pair solve is falsified:

```text
forward != reverse
max state delta = 4
```

Off-center 6DOF stand produces non-zero angular velocities while preserving total linear/angular momentum.

Restitution evidence:

```text
e=0.0 -> final KE ≈ 0
e=0.5 -> final KE / initial KE ≈ 0.25
e=1.0 -> final KE ≈ initial KE
```

Under-refined near-coincident event sets fail closed with `EVENT_SET_NOT_REFINED_ENOUGH`.

Exact regression chain:

```text
0.17-A 77/77
0.16 S3 101/101
0.16 S2 102/102
0.16 S1 110/110
editor CLEAN
```

Exact remote preservation:

```text
B 4/4
A 4/4
S3 3/3
S2 5/5
S1 8/8
```

Next wall:

`FABRIC0.17-C — GENERALIZED CONTACT WRENCH`.


### 0.17-C current state

```text
executable HEAD:
edc021230dadf62e9bf5ffb4c17cc5f2d0140ba0

GENERALIZED CONTACT WRENCH
IMPLEMENTED CANDIDATE
EXACT LINUX DOUBLE PASS
76/76 PASS
REMOTE BYTE IDENTITY 4/4 PASS
FABRIC0.17 NOT CLOSED
```

Generalized friction coordinates:

```text
2 tangent force impulse DOF
2 rolling moment impulse DOF
1 torsional moment impulse DOF
```

Geometry-derived patch radius on acceptance stand:

```text
R_eff = 0.70710678118655
```

Admissible limits:

```text
|Pt|    <= mu_t   * Pn
|Mroll| <= mu_r   * Pn * R_eff
|Mspin| <= mu_tau * Pn * R_eff
```

Saturated probe reaches all three limits and dissipates:

```text
Delta KE = -3.31742638415729
energy ledger error = 2.220446049250313e-15
linear momentum error = 0
angular momentum error = 0
```

Pure-moment and pure-tangent falsifiers prove the moment and force channels are independent.

Normal support is resolved externally in C; normal/wrench recoupling is intentionally deferred.

Full regression:

```text
C 76/76
B 63/63
A 77/77
0.16 S3 101/101
0.16 S2 102/102
0.16 S1 110/110
editor CLEAN
```

Next:

`FABRIC0.17-D — UNIFIED MULTI-IMPACT WRENCH TRAJECTORY`.

### 0.17-D current state

`executable HEAD = 643b4bdc5d33756819869c3faacc1dccf1251a1f`

Status: `IMPLEMENTED CANDIDATE / EXACT DOUBLE PASS / 157/157 PASS / D 6/6 REMOTE EXACT / CONTROL BLOCKED EXTERNALLY / FABRIC0.17 NOT CLOSED`.

Integrated trajectory: first simultaneous set `[C|L,C|R]` near `0.5`, second `[P|Q,Q|S]` near `0.5002`; 8 normal rows per event.

Key integration falsifier: one-pass B→C reopens normal law by about `0.341108067` / `0.337395997`. The same-instant normal↔wrench fixed point reduces the full-post residual to `4.436535363e-10` / `2.296023451e-10`.

Graph-wide wrench cross-patch coupling is nonzero and strong (`~3.33` / `~3.45`). Whole-state and event-time refinement are strictly decreasing through `1e-9` against `1e-11` reference.

Reference whole-trajectory energy: `9.66625 -> 2.07687223207214`; ledger error `1.7763568394002505e-15`; linear/angular momentum errors `0`.

Exact replay, reverse body order and reverse event-member order are identical.

Full exact regression: `D 157/157; C 76/76; B 63/63; A 77/77; 0.16 S3 101/101; S2 102/102; S1 110/110; editor CLEAN`.

Project Control `#1836` failed twice on the exact D executable HEAD at architecture/ownership passport compatibility. D changes exactly six FABRIC research/test files from the previously green C boundary; failure reports unrelated G/ECO critical dependency drift in Matter/control paths. Classification: `EXTERNAL_CROSS_REF_CONTROL_DRIFT`.

Closure is intentionally withheld. Next action for 0.17 is repository-control recovery/recheck, not a fabricated 0.17-E.


### FABRIC0.17 final closure

```text
FABRIC0.17
RESEARCH CANDIDATE CLOSED

A  77/77 PASS
B  63/63 PASS
C  76/76 PASS
D 157/157 PASS

0.16 S3 101/101 PASS
0.16 S2 102/102 PASS
0.16 S1 110/110 PASS

EXACT LINUX DOUBLE PASS
REMOTE BYTE IDENTITY PASS
EDITOR CLEAN
PROJECT CONTROL PASS
NOT PRODUCTION ACCEPTED
```

Exact physics executable:

`643b4bdc5d33756819869c3faacc1dccf1251a1f`.

Exact physics tree:

`3d531be386502c34ad7c30da8a00c5df8f152906`.

Closure carrier:

`3cc14e0ff7a1e6ef1e456c0e428e4caff1dd3555`.

Harness regression repair was merged independently to main via PR #377, merge `718a9767da8b2bda986e1cadee3f7bc6d729f0d4`. Project Control #1851/#1852 on the harness fix and #1855 on the FABRIC closure carrier are SUCCESS.

The former G/ECO RED was a stale-checkout harness-regression bug, not a FABRIC physics failure. The fix changed only the two harness regression tests and did not weaken critical dependency semantics.

Next Physical Core checkpoint is not implicitly named here; it must be formalized separately in the roadmap before implementation.


### FABRIC0.18 roadmap frozen

```text
FABRIC0.17 ✅ RESEARCH CANDIDATE CLOSED
        ↓
FABRIC0.18 PERSISTENT CONTACT WRENCH DYNAMICS
        ├─ 0.18-A Persistent Wrench Contact State        🔵 STARTED
        ├─ 0.18-B Mode Transition Localization          ⚪
        ├─ 0.18-C Multicontact Persistent Wrench Graph  ⚪
        └─ 0.18-D Unified Persistent Contact Trajectory ⚪
```

Branch: `research/fabric0-18-persistent-contact-wrench-r1`.

Predecessor closure: `751c55e76f57b7a9ceef8f5bbda3dcf6d4fad1a0`.

Read: `docs/research/FABRIC0_18_PERSISTENT_CONTACT_WRENCH_DYNAMICS_RU.md`.

BRIDGE-1 is not a prerequisite for 0.18. Perform a Physical Core ↔ BAKE synchronization review before formalizing a post-0.18 successor.


### 0.18-A current state

```text
FABRIC0.18-A
PERSISTENT WRENCH CONTACT STATE

IMPLEMENTED CANDIDATE
EXACT LINUX DOUBLE PASS
53/53 PASS
REMOTE BYTE IDENTITY 3/3 PASS
FABRIC0.18 NOT CLOSED
```

Executable HEAD: `ee8658eefb8abe2e66e199678380c32b71c1f8dd`.

A establishes canonical persistent contact identity, age/epoch continuity, projected warm-start proposals, fresh-solve ownership of accepted impulse, post-solve mode classification and fail-closed mode consistency.

A 10,000-update bookkeeping probe remains exact with no hidden impulse carryover. This is not yet a physical no-creep proof.

Next: `FABRIC0.18-B — MODE TRANSITION LOCALIZATION`.
