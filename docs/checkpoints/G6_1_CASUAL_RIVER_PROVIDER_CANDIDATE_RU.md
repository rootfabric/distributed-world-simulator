# G6.1 — CasualRiverProviderV1 — IMPLEMENTED CANDIDATE

**Дата:** 2026-08-08
**Ветка:** `feature/g6-hydrology-fluid-surface-v0`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Dependency:** `G6.0 Fluid Contracts — ACCEPTED after P0 sync`
**Решение:** `IMPLEMENTED CANDIDATE — WINDOWS FOCUSED ACCEPTANCE REQUIRED`

## Цель

G6.1 вводит первый deterministic hydrology provider поверх принятой G5/G6.0 foundation, не смешивая provider generation с cell/LOD, runtime query resolution или renderer.

```text
G5 WorldFeature(feature-type/river)
        + optional linked valley feature
        ↓
CasualRiverProviderV1
        ↓
FluidRegionId
RiverSpline
RiverChannelProfile
FluidSurfaceDescriptor
```

Главное архитектурное решение:

```text
G5 River FeatureId = semantic owner
G6 provider        = deterministic compiler
G6 output          = derived canonical geography contracts
```

Provider не создаёт новый `WorldFeature`, не пишет в `FeatureGraph` и не объявляет собственную authority.

## Отличие от старого G6 prototype

В reference-ветке `feature/g6-hydrology-fluid-surface` одновременно были смешаны provider, runtime water query, cross-cell/LOD proof и visual lab. Для staged-линии это слишком широкий checkpoint.

G6.1 забирает только provider idea и меняет направление зависимости:

```text
НЕ: provider -> новый RiverFeature
ДА: existing G5 RiverFeature -> provider -> G6 fluid geography
```

Это сохраняет `Feature != Cell` и не создаёт второй semantic identity layer.

## Provider contract

```text
provider id:      hydro-provider/casual-river-v1
provider version: 1.0.0
control points:   7
```

Вход: G5 river feature с semantic anchors `source`/`mouth`, опциональный связанный valley parent и canonical G6 `FluidType` (default `fluid-type/water`).

Выход: `FluidRegionId`, `RiverSpline`, `RiverChannelProfile`, `FluidSurfaceDescriptor` и deterministic provider manifest hash.

## Identity model

Fluid/spline stable keys выводятся из stable G5 `feature_id`, provider id и canonical fluid type, а не из representation address.

```text
river/valley geometry changes
    -> derived checksums may change
    -> provider manifest changes
    -> G5 FeatureId stays
    -> FluidRegionId stays
    -> RiverSpline.spline_id stays
    -> RiverChannelProfile.profile_id stays
```

Связанная valley не владеет river identity. Её checksum используется только как deterministic geometry salt. Если river имеет `parent_feature_id`, переданная valley обязана совпадать с parent.

## Casual geometry/profile v1

Provider строит семь body-frame control points между source и mouth. Для radial planetary anchors используется spherical direction interpolation с сохранением interpolated radius и deterministic meander в tangent plane.

Channel profile содержит samples `0.00 / 0.25 / 0.50 / 0.75 / 1.00`; width/depth/bank width растут к mouth и масштабируются по source-mouth distance.

Это casual baseline, не erosion solver и не hydrodynamics simulation.

## P0 boundaries

Canonical provider не зависит от и не владеет:

```text
SurfaceCellKey / LOD / camera / renderer
RandomNumberGenerator / randf / randi
network transport / RPC
authority registry
persistence
material ontology
canonical world mutation
```

Future material projection относится к P0 Unified Material Ontology; future authoritative mutations — к `WorldOperation / WorldTransactionPlan`.

## Deferred

```text
G6.2 cross-cell / cross-LOD continuity proof
G6.3 runtime WaterSurfaceQuery resolver
G6.4 visual river lab
full CFD / erosion / sediment transport
Matter/fluid authoritative mutation
```

## Focused acceptance

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_1_CASUAL_RIVER_PROVIDER_TESTS.ps1
```

Runner сначала повторяет G6.0 dependency gate (`G5 graph`, `G5 feature/cell identity`, `G6.0 fluid contracts`), затем запускает G6.1 suite.

G6.1 проверяет compile из G5 river/valley, валидность всех outputs, repeat/order determinism, geometry-without-identity-reroll, non-water projection, negative paths и отсутствие запрещённых runtime/representation dependencies.

До реального Windows/Godot 4.7.1 double результата:

```text
G6.1 = IMPLEMENTED CANDIDATE
```

После green focused run:

```text
G6.1 = ACCEPTED
next = G6.2 cross-cell / cross-LOD continuity
```

Full world regression остаётся на composed G6.1–G6.4 final gate, если focused run не потребует изменений shared runtime/contracts.
