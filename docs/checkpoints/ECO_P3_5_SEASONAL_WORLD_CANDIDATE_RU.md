# ECO / P3.5 — Seasonal World — CANDIDATE

Статус: `CANDIDATE / RESEARCH_ONLY / TARGETED LINUX PASS / P3.4 ACCEPTANCE + EXACT WINDOWS CANONICAL PENDING`.

Ветка: `feature/eco-evolutionary-ecology`.

Parent P3.4 implementation head: `bb4e85eb26e23dc513fd16d17c5e02d9d629dc45`.

Parent P3.4 candidate aggregate:

```text
a4464e5d42fb4a9e29c4a6ddfcb4c338ecbb4547bcd8bd80f430a7565df90813
```

Exact P3.4 targeted source result:

```text
2651bb4da195af4c1d2ba7f6b09ef9bdc9e459f9206c32ef1e9eb0dbddd6b293
```

## Цель

P3.5 добавляет детерминированное время к непрерывному P3.4 environment, не превращая сезоны в enum и не вводя зависимость от frame/timestep history.

Canonical environmental state вычисляется напрямую:

```text
seasonal_environment = f(P3.4 baseline, time_years, season_config)
```

а не так:

```text
state[n+1] = state[n] + seasonal_delta * dt
```

Поэтому один и тот же `time_years` даёт один и тот же result независимо от количества промежуточных вызовов.

## Cycle contract

```text
period_years > 0
epoch_year = finite
phase_x_slope = finite
phase_y_slope = finite
phase_altitude_slope = finite
```

Global phase:

```text
relative = (time_years - epoch_year) / period_years
cycle_index = floor(relative)
global_phase01 = relative - floor(relative)
```

Для cross-platform canonical hash не используется `sin/cos`. Seasonal waveform — piecewise-linear triangle:

```text
triangle(phase) = 1 - 4 * abs(phase - 0.5)
```

Она непрерывна в cycle wrap и использует только базовую арифметику.

## Spatial seasonal phase

Каждый P3.4 patch получает local phase из его непрерывных координат:

```text
local_phase = wrap01(
    global_phase
  + phase_x_slope * dx
  + phase_y_slope * dy
  + phase_altitude_slope * d_altitude
)
```

Это позволяет без дискретного `north/south hemisphere` enum получать spatial phase shifts, включая противоположные или сдвинутые циклы при соответствующей конфигурации координат.

## Channel contract

У каждого канала:

```text
amplitude >= 0
phase_offset = finite, canonical modulo 1
```

Текущее значение:

```text
value(t) = clamp(
    P3.4_baseline_value
  + amplitude * triangle(local_phase + phase_offset),
    P3.4_min,
    P3.4_max
)
```

Каналы:

```text
temperature_c
moisture
light
nutrients
```

Для `moisture/light/nutrients` amplitude ограничена `<= 1`, и итог всегда остаётся `[0,1]`.

## Resource-mediated response bridge

P3.5 не вводит species-name fitness table. Вместо этого текущие environmental ratios масштабируют базовый resource supply:

```text
seasonal light      -> P3.1 light supply
seasonal moisture   -> P3.1 water supply
seasonal nutrients  -> P3.1 nutrient supply
```

Focused test показывает, что при одинаковом растении seasonal light minimum меняет существующий P3.1 `growth_factor` с `1.0` до `0.6` только через supply limitation.

Это уже даёт life-history/resource response без scripted winner и без отдельного biome lookup.

## Доказанные свойства

```text
same P3.4 + same time + same config -> same result_hash
fresh processes -> same aggregate
P3.4 source dictionary unchanged
periodic patch state repeats after one period
absolute time/cycle index remain in result identity
negative time wraps deterministically
spatial y phase shift changes local season continuously
per-channel phase offsets work independently
phase offsets canonicalize modulo one cycle
no cumulative drift from intermediate evaluations
P3.4 channel bounds preserved
normalized resource channels stay [0,1]
seasonal resource bridge is deterministic
P3.1 growth response can change through seasonal resource limitation
P3.4 edge topology preserved
seasonal edge environmental deltas recomputed
empty environment remains valid
malformed/tampered state fails closed
no global RNG consumption
```

## Targeted exact-Godot evidence

Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

P3.4 parent regression:

```text
ECO.P3.4 Environmental Gradient: PASS (56 assertions)
aggregate_hash=a4464e5d42fb4a9e29c4a6ddfcb4c338ecbb4547bcd8bd80f430a7565df90813
```

P3.5 A/B/C were byte-identical:

```text
ECO.P3.5 Seasonal World: PASS (74 assertions)
aggregate_hash=255912c4da9f1296d11f9e64bf91812ae3d32dff2726b4866c4ba761be8b8c83
phase0_hash=2ee8d7c6dc55a7c55af35cc945b0b85f79cc27fe0145b921eb5b9f0023b5d060
quarter_hash=3e9ae067e034b4a4ce4b149ee0306ecfae7d12189d82d55e6d2e5e541dab1bb2
half_hash=aec09a3a29d5c528140e70d79cd7970e3d3d09ee9e4f848d854cd205bc13b790
empty_hash=8d87247c14199a2c65d17389658c89067f8787a262253b8ecc03db9926f9f620
parent_p3_4=a4464e5d42fb4a9e29c4a6ddfcb4c338ecbb4547bcd8bd80f430a7565df90813
source_p3_4=2651bb4da195af4c1d2ba7f6b09ef9bdc9e459f9206c32ef1e9eb0dbddd6b293
```

Fresh-process log SHA-256:

```text
ca5368cec1477975fe89aa138111f24b61907eb410a47effcf1962e88e92e5d9
```

Exact local Git blobs:

```text
scripts/research/ecology/plant_seasonal_world_v1.gd
649d26457ac8383f890f0dfca890353cc200ee7e

tests/research/ecology/eco_p3_5_seasonal_world_acceptance.gd
c91ed0c25c418be1a7c7c4352423b7214c8706f8
```

## Canonical gate

`RUN_ECO_P3_5_TESTS.ps1` intentionally requires factual P3.4 validation status beginning with `ACCEPTED`.

Current state does not satisfy that predicate, therefore targeted Linux evidence cannot be used to accept P3.5.

Strict sequence remains:

```text
P3.3 Windows canonical -> accept P3.3
P3.4 Windows canonical -> accept P3.4
P3.5 Windows canonical -> accept P3.5
P3.6 Disturbance & Succession
```
