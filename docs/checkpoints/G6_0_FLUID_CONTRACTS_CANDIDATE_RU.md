# G6.0 — Fluid Contracts — ACCEPTED

**Дата:** 2026-08-08
**Ветка:** `feature/g6-hydrology-fluid-surface-v0`
**Base:** `feature/g5-world-feature-graph @ e7b10c09a6be879b25cd5c7ec8407832fd758ac2`
**G5 accepted candidate:** `34be9d35e7f0a0e6c7a7c7c8bdd58b70c95413b4`
**Accepted candidate head:** `5deb455113a62a201b2c5441509917fd9ac6ca9e`
**Acceptance validation commit:** `b0dce09d4d0324c6b28bbcfef2a24cd38e940af1`
**Решение:** `ACCEPTED`

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
seed
generator_version
stable_key
frame_id
optional source_feature_id
FeatureBounds-compatible bounds
surface_mode
reference_level_m
attributes
```

Descriptor не доверяет opaque `fluid_region_id`: validation повторно выводит `FluidRegionId` из canonical identity fields и отклоняет mismatch. Это исключает состояние, где ID относится, например, к lava-region, а DTO объявляет water-region.

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

## Static scope check

Accepted candidate compare against exact G5 base:

```text
status        ahead
behind        0
changed files 21
GeoKernel     unchanged
G5 contracts  unchanged
renderer deps none
network deps  none
```

Два commits после первоначального implementation candidate `dcab2405051c537e170548fb399b98c4913b0a0f` до `5deb455113a62a201b2c5441509917fd9ac6ca9e` меняли только checkpoint/validation metadata; production contracts не изменялись.

## Focused acceptance evidence

Независимый Windows-прогон выполнен пользователем **дважды** на:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
Windows
2026-08-08
```

Команда:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_FLUID_CONTRACT_TESTS.ps1
```

Оба запуска дали одинаковый результат:

```text
cold editor import             PASS
G5 World Feature Graph         PASS (249 assertions)
G5 feature/cell identity       PASS (94 assertions)
G6.0 fluid contracts           PASS (169 assertions)
focused gate                   PASS
```

Ошибок G6.0 не зафиксировано. Повторяемость focused gate подтверждена одинаковыми assertion counts в обоих прогонах.

## Acceptance decision

Все обязательные условия checkpoint выполнены:

```text
editor import                PASS
G5 dependency contracts      PASS
G5 feature/cell identity     PASS
G6.0 fluid contracts         PASS
```

Полный world regression для внутреннего подпункта G6.0 не требуется по принятому gate; он остаётся обязательным перед финальным `G6 ACCEPTED` после composition G6.1–G6.4.

Итог:

```text
G6.0 — Fluid Contracts
ACCEPTED
```

## Следующий шаг

```text
G6.1 — CasualRiverProviderV1
```

Он должен производить `FluidRegionId + FluidSurfaceDescriptor + RiverSpline + RiverChannelProfile` из stable G5 river/valley semantics, не из chunk-local state.

G6.1 обязан сохранить принципы G6.0:

- canonical river/fluid identity не зависит от representation cell, LOD, observer или renderer;
- один и тот же semantic river должен быть выводим одинаково из соседних cells;
- provider остаётся data/domain layer и не получает зависимости на SceneTree, renderer, network transport или GeoKernel mutation;
- геометрия может уточняться в следующих стадиях без смены semantic river identity.
