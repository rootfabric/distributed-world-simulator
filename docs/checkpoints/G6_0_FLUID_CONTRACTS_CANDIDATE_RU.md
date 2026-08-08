# G6.0 — Fluid Contracts — IMPLEMENTED CANDIDATE

**Дата:** 2026-08-08  
**Ветка:** `feature/g6-hydrology-fluid-surface-v0`  
**Base:** `feature/g5-world-feature-graph @ e7b10c09a6be879b25cd5c7ec8407832fd758ac2`  
**G5 accepted candidate:** `34be9d35e7f0a0e6c7a7c7c8bdd58b70c95413b4`  
**Решение:** `IMPLEMENTED_CANDIDATE`

## Цель

G6.0 вводит canonical fluid vocabulary поверх принятого G5 World Feature Graph, но ещё не генерирует русла и не рисует воду.

Главный invariant:

```text
FluidRegion != SurfaceCell
FluidRegion != renderer object
FluidRegion identity != quality/observer state
```

## Реализованные contracts

```text
FluidType
FluidRegionId
FluidSurfaceDescriptor
RiverSpline
RiverChannelProfile
WaterSurfaceQuery
```

### FluidRegionId

Canonical identity вычисляется только из:

```text
body_id
fluid_type_id
seed
generator_version
stable_key
```

В identity намеренно отсутствуют representation address, quality level, camera и renderer.

### FluidSurfaceDescriptor

Descriptor связывает canonical fluid region с:

```text
body_id
fluid_type_id
frame_id
optional source_feature_id
FeatureBounds-compatible bounds
surface_mode
reference_level_m
attributes
```

`source_feature_id` использует G5 `FeatureId` и остаётся optional, поэтому тот же generic fluid layer пригоден не только для рек.

### RiverSpline

`RiverSpline.spline_id` зависит от:

```text
fluid_region_id
stable spline key
```

но не от массива control points. Поэтому изменение canonical geometry/мутация русла меняет checksum, но не обязано создавать новую semantic river identity.

### RiverChannelProfile

Профиль задаётся canonical samples по нормализованной координате `t`:

```text
t
width_m
depth_m
bank_width_m
```

Samples сортируются и обязаны покрывать диапазон от `0.0` до `1.0`.

### WaterSurfaceQuery v0

Request DTO содержит:

```text
body_id
frame_id
position_m
max_distance_m
fluid_type_ids
```

По умолчанию query фильтрует `fluid-type/water`; список типов canonicalized как sorted unique. Runtime resolver появится в G6.3.

## Universal fluid groundwork

Baseline vocabulary уже разрешает:

```text
fluid-type/water
fluid-type/lava
fluid-type/methane
fluid-type/ammonia
```

Это contract namespace, а не закрытый enum: новые типы fluid могут добавляться без смены DTO schemas.

## Что намеренно НЕ входит в G6.0

```text
CasualRiverProviderV1          -> G6.1
cross-cell/cross-quality proof -> G6.2
runtime surface resolver       -> G6.3
visual river ribbon            -> G6.4
CFD / Navier-Stokes            -> post-baseline research
```

## Focused gate

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_FLUID_CONTRACT_TESTS.ps1
```

Runner выполняет:

```text
cold editor import
G5 World Feature Graph acceptance
G5 feature/cell identity acceptance
G6.0 fluid contracts acceptance
```

В connector environment Godot binary недоступен, поэтому runtime acceptance должен быть подтверждён независимым Windows-прогоном на Godot 4.7.1 double.

## Acceptance gate

G6.0 можно перевести в `ACCEPTED`, когда подтверждены:

```text
editor import                PASS
G5 dependency contracts      PASS
G5 feature/cell identity     PASS
G6.0 fluid contracts         PASS
```

Полный world regression для каждого внутреннего подпункта G6 не обязателен; он потребуется перед финальным `G6 ACCEPTED` после composition G6.1–G6.4.

## Следующий шаг

После focused acceptance G6.0:

```text
G6.1 — CasualRiverProviderV1
```

Он должен производить `FluidRegionId + FluidSurfaceDescriptor + RiverSpline + RiverChannelProfile` из stable G5 river/valley semantics, не из chunk-local state.
