# FABRIC COMPLEX2-C — Articulated + Rotating Coupled Motion

**Статус:** ✅ EXACT VERIFIED  
**Ветка:** `feature/fabric-complex2-modular-machine-r1`  
**Exact code subject:** `bfc9109a240b513dd6866da04bcad3fd8de4b275`  
**TREE:** `1a676742b30179967ab7fe5ad4084a3b5cb42b75`  
**Evidence:** `validation/FABRIC_COMPLEX2_C_COUPLED_MOTION_EXACT_EVIDENCE.md`

## Зачем нужен C

После COMPLEX2-A машина уже умела двигаться, принимать contact events, терять модули и менять representations. COMPLEX2-B добавил реальный compliant spring/damper envelope. Но оставался важный falsifier: движущиеся узлы могли существовать как независимые локальные состояния без доказательства, что движение одного узла физически передаётся другим.

COMPLEX2-C закрывает именно это.

## Coupled mechanical subject

Используются уже существующие moving modules:

```text
module 08  shoulder   ARTICULATED
module 09  elbow      ARTICULATED
module 10  shaft      ROTATING
module 11  carriage   TRANSLATING
```

Их native coordinates переводятся в общий generalized path space:

```text
shoulder angle -> path displacement using 0.42 m/rad
elbow angle    -> path displacement using 0.31 m/rad
shaft angle    -> path displacement using 0.09 m/rad
carriage       -> translation directly in metres
```

Это позволяет одной reciprocal mechanical system связывать angular и translational subsystems без смешивания единиц внутри solver.

Полное состояние:

```text
q[4] + v[4] = 8 physical states
```

## Canonical coupling graph

```text
shoulder <-> elbow
elbow    <-> shaft
shaft    <-> carriage
shoulder <-> carriage
```

Каждая связь имеет stiffness + damping и обязана быть reciprocal. Из canonical records компилируются симметричные `K` и `C` matrices.

Любая non-reciprocal связь fail-closed:

```text
COMPLEX2C_NONRECIPROCAL_COUPLING
```

## FULL vs DYNAMIC_ROM

`DYNAMIC_ROM` не хранит отдельную истину. Он использует заранее compiled `M/K/C`.

FULL reference каждый timestep заново собирает эти matrices из canonical coupling records.

Затем оба пути выполняют один и тот же implicit-midpoint step.

Exact результат:

```text
max |ACTIVE - FULL| = 0
```

## Почему implicit midpoint

Для линейной reciprocal spring/damper system этот integrator позволяет напрямую проверять дискретный energy identity:

```text
E1 - E0
= external boundary work
- damping dissipation
```

Exact measured maximum residual:

```text
5.273559366969494e-16 J
```

То есть энергия не появляется из-за переключения evaluator или coupling implementation.

## Реальная передача движения

Главный causal probe прикладывает force только к shoulder.

При couplings:

```text
shaft path peak     0.0467785669 m
carriage peak       0.0464149146 m
```

В контрольной системе, где coupling links удалены:

```text
shaft peak     0
carriage peak  0
```

Следовательно, downstream motion возникает через mechanical graph, а не через скрытый direct drive.

## Mid-motion evaluator transition

Envelope не останавливает машину перед сменой representation.

```text
0..149    COMPILED DYNAMIC_ROM
step 150  DYNAMIC_ROM -> FULL
150..229  FULL canonical evaluator
step 230  FULL -> DYNAMIC_ROM
230..649  COMPILED DYNAMIC_ROM
```

В обоих переходах сохраняются все `q + v`.

State packet содержит schema hash + checksum. Corrupt packet rejected:

```text
COMPLEX2C_STATE_PACKET_CHECKSUM_MISMATCH
```

Exact physical handoff errors:

```text
[0, 0]
```

## BRIDGE-2 integration

COMPLEX2-C расширяет только существующий DYNAMIC backend hash. Новый region/owner не создаётся.

По-прежнему существует ровно пять representation kinds:

```text
FULL
STRUCTURAL_BAKE
CONTACT_BAKE
DYNAMIC_ROM
HYBRID_BAKE
```

В runtime выполняются два реальных representation swap events между DYNAMIC и FULL regions. Между swap events runtime продолжает stepping.

Exact:

```text
representation event ledger = 2
swap handoff error = 0
mixed/FULL runtime delta = 0
final five-kind arrangement restored
```

COMPLEX2-B HYBRID compliant backend при этом не изменяется.

## Certified envelope

Observed peaks:

```text
shoulder  0.2304349697 rad
elbow     0.2198972800 rad
shaft     0.7201419706 rad
carriage  0.0696275307 m
```

После drive release энергия монотонно уменьшается. Финальная энергия меньше 2% peak energy.

Out-of-envelope cases требуют refinement:

```text
force limit
-> COMPLEX2C_REFINEMENT_REQUIRED_FORCE

native articulation range
-> COMPLEX2C_REFINEMENT_REQUIRED_NATIVE_RANGE

path speed
-> COMPLEX2C_REFINEMENT_REQUIRED_SPEED
```

## Exact acceptance

```text
FABRIC COMPLEX2-C Coupled Motion Acceptance:
PASS (66 assertions)
```

Integrated deterministic hash двух независимых exact runs:

```text
433345db30f8b59e5da67d83cc3a737f546305563029f0f38ca583988e96a995
```

## Visual lab

```text
res://scenes/labs/fabric/complex2c_coupled_motion_lab.tscn
```

Space переключает evidence samples вокруг drive, representation transitions и final ringdown. Visual layer не является canonical writer.

## Что дальше

```text
COMPLEX2-A ✅
COMPLEX2-B ✅
COMPLEX2-C ✅
      ↓
COMPLEX2-D — Independent Structural Support Failure
```

`FABRIC0.19` после C всё ещё не авторизован: новый generic physical primitive пока не потребовался.
