# FABRIC R5.2 / T3 — Battery from Cells + Materials

**Статус:** EXACT T3 PASS / fresh review + verifier pending.

## Цель

T3 — первый полноценный functional assembly:

```text
Matter materials
      ↓ characterized electrochemical profile
cell geometry + manufacturing quality
      ↓
96 real cell components (12S8P)
      ↓ compile
12 series-group states + common temperature
      ↓
Battery BehaviorCapsule
```

Battery не получает готовые gameplay stats. Capacity/resistance/current/mass/thermal behavior выводятся из materials + geometry + quality.

## Simulation floor

T3 намеренно не моделирует атомы/электрохимию ab initio. Используется characterized electrochemical profile, привязанный к canonical Matter material checksum:

- voltage window;
- specific charge capacity;
- effective electronic conductivity;
- contact resistivity;
- maximum current density;
- resistance temperature coefficient;
- safe temperature domain.

Это versioned physical primitive, а не rarity bonus.

## Cell derivation

```text
active mass = material density × active volume

capacity =
  active mass
  × specific_capacity
  × quality

base resistance =
  path_length / (conductivity × electrode_area)
  + contact_resistivity / electrode_area

cell resistance =
  base resistance / quality

max current =
  current_density_limit
  × electrode_area
  × quality

thermal capacity =
  active mass × active-material Cp
  + case mass × case-material Cp

passive thermal conductance =
  case k × surface_area / wall_thickness
```

Manufacturing quality changes utilization/contact/current capability, but does not invent or remove mass.

## Why 12 state charges, not one magic SOC

Each parallel group can aggregate to one charge state if all enabled cells share the same chemistry and have compatible conductance/capacity scaling.

```text
8 parallel cells → one group charge
×
12 series groups
=
12 charge states
+ 1 pack temperature
```

This lets one damaged/disabled cell change only its affected series group while remaining far cheaper than 96 per-cell states.

Compiler refuses unsafe reduction when:

- mixed electrochemical profiles occur inside one parallel group;
- geometry makes conductance/capacity ratios incompatible;
- a complete series group is electrically open.

## Runtime

Prepared capsule stores only group aggregates:

- capacity;
- equivalent resistance;
- OCV voltage window;
- current limit;
- temperature coefficient.

Each execute receives caller-owned state and returns next state. Capsule does not own persistent canonical charge.

Energy audit uses midpoint OCV for the linear voltage curve so:

```text
chemical energy decrease
=
electrical energy delivered
+
resistive heat
```

within floating-point tolerance.

## Material / quality / damage tests

T3 compares:

1. LFP-like characterized active material;
2. NMC-like characterized active material;
3. same pack with lower manufacturing quality;
4. same pack with one electrically-disabled cell.

Expected derived consequences:

- chemistry changes voltage and specific energy;
- lower quality lowers capacity/current and increases resistance, without changing mass;
- disabled cell lowers affected group capacity/current and raises resistance; old capsule becomes invalid.

## Non-claims

T3 does not yet claim:

- atom-level electrochemistry;
- dynamic SOH/cycle aging;
- cell thermal gradients;
- active pump/radiator cooling;
- arbitrary mixed-chemistry parallel aggregation;
- runaway/venting chemistry.

Those are downstream fidelity layers. T3 proves component/material/quality → compact stateful battery behavior.


## Exact T3 result — run 35539756495

```text
SUBJECT_HEAD = bf41370633b17a0462bbb4340b112a381d87d86f
SUBJECT_TREE = aafaa5183c6b66bd75ac4fb10f854dd240acc305

samples = 3/3 PASS
aggregate job = 106155278113
artifact = 10614232565
digest = sha256:4e0d6cf14e38a9a02efa332b36383990c006b0db92d3ed9f5089408a14510db8

deterministic hash =
c46528cdcc0d17f250c605abcf430dbc16a52f3ae42868fdf15f6ac75ec743e0
```

### Базовый 12S8P pack

```text
cells                  = 96
series groups          = 12
parallel cells/group   = 8

detailed source ops    = 768
compiled ops           = 42

runtime state:
  12 group charges
  1 temperature
  = 13 scalars

source cell traversals / capsule execute = 0
```

Derived LFP-like pack characteristics:

```text
nominal voltage        = 38.4 V
empty/full voltage     = 33.6 / 43.2 V
capacity               ≈ 23.62 Ah
max continuous current = 69.48 A
R pack @ reference     ≈ 6.22 mΩ
mass                   = 5.184 kg
full energy            ≈ 907 Wh
specific energy        ≈ 175 Wh/kg
thermal capacity       ≈ 6739 J/K
passive thermal K      = 24 W/K
```

NMC-like material profile with the same topology/geometry derives:

```text
specific energy ≈ 278 Wh/kg
```

No battery-level energy-density stat is assigned manually.

### Full 96-cell reference vs capsule

2048 sequential charge/discharge/thermal steps:

```text
max voltage error      = 2.13e-14 V
max heat error         = 2.44e-15 J
max charge-state error = 0
max temperature error  = 0
max energy residual    = 5.82e-10 J
```

Detailed reference traversals:

```text
2048 × 96 = 196608 cell traversals
```

Capsule:

```text
source cell traversals / execute = 0
```

Observed hot-loop runtime on this runner set:

```text
96-cell detailed reference ≈ 249 µs/call
12-group capsule           ≈ 22.8 µs/call
observed speedup           ≈ 10.9×
```

Timing is observational, not a universal budget.

### Quality and damage are structural causes

Lower manufacturing quality (`quality_scale=0.85`) derives:

```text
capacity    ↓ 85043.52 C → 72286.992 C / group
resistance  ↑
max current ↓ 69.48 A → 59.058 A
mass        unchanged
```

One electrically-disabled cell:

```text
active cells 96 → 95
affected group capacity ↓ to 74027.52 C
affected group resistance ↑
pack current limit 69.48 A → 60.48 A
physical mass unchanged
old capsule → rejected
rebuilt capsule → executes
```

### Conservative reduction boundary

Compiler refuses compact one-charge-per-parallel-group reduction for:

```text
mixed chemistry in one parallel group
→ BATTERY_PARALLEL_PROFILE_MISMATCH

geometry that breaks conductance/capacity synchrony
→ BATTERY_PARALLEL_SOC_SYNCHRONY_UNSAFE

electrically open series group
→ BATTERY_SERIES_GROUP_OPEN
```

This is intentional: unsafe aggregation does not get silently averaged.


## Damage state reconstruction

Fresh review выявил, что простого rebuild новой capsule недостаточно: необходимо доказать перенос caller-owned state через capacity-losing topology mutation.

T3 теперь использует conservative projector:

```text
old group charge / old capacity = synchronized SOC
        ↓ one cell disconnects
new group charge = same SOC × new active capacity

difference:
  detached charge
  detached chemical energy
```

`detached charge/energy` не исчезают: projector явно возвращает их вызывающему canonical mutation layer как состояние отключённой части. Температура сохраняется. Проекция разрешена только для capacity loss при неизменном group electrochemical profile; capacity gain или chemistry change требуют более детального reconstruction / `NO_SAFE_BAKE`.
