# G6 — Hydrology / Fluid Surface v0 — IMPLEMENTED CANDIDATE

**Дата:** 2026-08-08
**Ветка:** `feature/g6-hydrology-fluid-surface`
**Base:** `feature/g5-world-feature-graph @ e7b10c09a6be879b25cd5c7ec8407832fd758ac2`
**Implementation candidate:** `68dc5158347989c6d16564993144106d2a294516`
**Решение:** `IMPLEMENTED CANDIDATE — WINDOWS FULL ACCEPTANCE REQUIRED`

## Цель

G6 вводит canonical hydrology / fluid geography поверх принятого G5 World Feature Graph.

Главный invariant:

```text
River / Fluid Region != representation cell
River / Fluid Region != LOD
Fluid truth != renderer
```

G6 не является CFD и не пытается решать Navier–Stokes. Он фиксирует identity, geometry/query contracts и простую deterministic модель поверхности/течения, которую позже можно развить или заменить без изменения G5 feature identity.

## Реализованные canonical contracts

```text
FluidRegionId
FluidSurfaceDescriptor
RiverSpline
RiverChannelProfile
WaterSurfaceQuery
WaterSurfaceSample
RiverFeature
CasualRiverProviderV1
```

### FluidRegionId

Identity детерминированно зависит от:

```text
body_id
fluid_type_id
seed
generator_version
stable_key
```

и не зависит от:

```text
SurfaceCellKey
LOD
camera
renderer
streaming state
query order
```

Generic namespace уже допускает не только воду:

```text
fluid/water
fluid/methane
future: lava / hydrocarbons / other fluids
```

### FluidSurfaceDescriptor

Generic descriptor хранит:

```text
fluid_region_id
body_id
frame_id
fluid_type_id
bounds
surface_mode
surface_parameters
attributes
```

v0 modes:

```text
fluid-surface-mode/local-spline
fluid-surface-mode/constant-level
fluid-surface-mode/free-surface
```

Это задел для river/lake/ocean/lava-lake/methane-sea/subsurface-pocket без hardcoded planet/world types.

## River semantics

`RiverSpline` хранит ordered canonical control points и поддерживает:

```text
river-spline-interpolation/linear
river-spline-interpolation/spherical-radial
```

Для planetary river используется spherical-radial interpolation с arc-length based normalized distance.

`RiverChannelProfile` задаёт простой v0 профиль source -> mouth:

```text
width
depth
flow speed
bank falloff
```

`RiverFeature` строится как обычный G5 `WorldFeature` типа `feature-type/river`. Значит одна река остаётся одной G5 feature независимо от количества cells, через которые она проходит.

## CasualRiverProviderV1

```text
provider id      hydro-provider/casual-river-v1
provider version 1.0.0
```

Provider:

1. принимает canonical spline/profile;
2. создаёт `FluidSurfaceDescriptor`;
3. создаёт G5 `RiverFeature`;
4. может установить feature в `FeatureGraph`;
5. отвечает на `WaterSurfaceQuery`;
6. возвращает explicit `WaterSurfaceSample`.

Query возвращает:

```text
feature_id
fluid_region_id
surface position
surface normal
flow vector
channel width/depth
distance to centerline
source-to-mouth normalized distance
inside_channel
```

Ни cell, ни LOD не являются входом query.

## Mega Casual River fixture

Acceptance fixture создаёт планетарную реку на body radius `6,000,000 m`.

Она:

```text
9 stable spline control points
longitude 34° -> 58°
crosses cube-sphere PX/PZ seam
length > 1,000 km
source radius > mouth radius
width 60 -> 180 m
depth 3 -> 9 m
flow 1.2 -> 2.4 m/s
```

Это намеренно architecture fixture, а не production hydrology simulation.

## Critical cell / LOD gate

Река адресуется через существующий G2 `CubeSphereAddressing` на:

```text
LOD 2
LOD 4
LOD 8
LOD 12
```

Проверяется:

```text
multiple representation cells      PASS
PX/PZ seam crossing                PASS
cell set changes with LOD          PASS
River FeatureId unchanged          PASS
FluidRegionId unchanged            PASS
provider manifest unchanged        PASS
canonical query has no cell/LOD    PASS
```

Следовательно:

```text
representation address changes
canonical hydrology identity does not
```

## Numeric query note

Во время acceptance выявлено, что 8 fixed refinement iterations для nearest-point поиска на длинной сферической дуге недостаточно для 10 m query tolerance.

Исправлено без изменения identity model:

```text
SPHERICAL_COARSE_STEPS      24
SPHERICAL_REFINEMENT_STEPS  24
```

Поиск остаётся deterministic и не использует random/camera/LOD state.

## Architecture boundary gate

Canonical G6 source проверяется на отсутствие:

```text
SurfaceCellKey
SurfaceLodSelector
MeshInstance3D
ImmediateMesh
Camera3D
RenderingServer
RandomNumberGenerator
randf / randi
EARTH / MOON / OCEAN_PLANET special cases
```

Renderer находится только в отдельном lab.

G6 также не меняет frozen G0–G5 architecture paths и не меняет production/runtime/network/Matter paths.

## Exact-engine local evidence

```text
Godot Engine v4.7.1.stable.double.custom_build.a13da4feb
cold editor import                         PASS
G6 hydrology/fluid surface                PASS — 161 assertions
G6 river/cell LOD identity                PASS — 72 assertions
G6 visual lab headless                    PASS
G5 World Feature Graph regression         PASS — 249 assertions
G5 feature/cell identity regression       PASS — 94 assertions
G5 visual lab regression                  PASS — 4 features
G6 focused Linux wrapper                  PASS
```

Canonical demo identities from the exact-engine run:

```text
River FeatureId:
world-feature/river/06b304e6f75095a01a53ed92ef2e7223e0e3101e7bd899364276d180b3a82e9e

FluidRegionId:
fluid-region/water/71681d4c24899b2ba8ee38ba7a6169b6c43785106a5e45c08dc39718d4a0a65a

Provider manifest:
de2f230a9e4f7f7d0a0e67f6d14261046ce5dae775378a19ea9c3441f6c5e76d
```

## Byte-exact publication evidence

Implementation was published as one commit over the exact G5 head. GitHub/local blob SHA matches were checked for the canonical spline, provider, both acceptance tests, focused runner, full gate and visual lab scene.

```text
implementation commit:
68dc5158347989c6d16564993144106d2a294516
```

The implementation diff contains only new G6 files; G0–G5 source is untouched.

## Visual lab

```text
res://scenes/labs/procedural/g6_hydrology_fluid_surface_lab.tscn
```

Lab draws a deliberately exaggerated blue ribbon from the canonical spline.

```text
canonical width = 60 -> 180 m
visual lab width scale = x120
```

The exaggeration is presentation-only and never feeds canonical state.

## Full Windows acceptance

Run from a clean/full checkout:

```powershell
.\RUN_G6_FULL_ACCEPTANCE.ps1
```

Gate includes:

```text
G5 accepted dependency focused gate
G6 focused contracts/query/LOD/lab gate
full world/core regression
Breakpoint :9081 current-run noise audit
git diff --check
G0-G5 architecture freeze
production/runtime/network/Matter scope freeze
```

Expected final line:

```text
G6 full acceptance gate: PASS
```

Until that real Windows run is provided, G6 remains `IMPLEMENTED CANDIDATE` rather than `ACCEPTED`.

## Next after acceptance

```text
G7 — Semantic Field Fabric
```

G7 may expose hydrology-derived semantic fields such as:

```text
hydro/river-distance-m
hydro/water-level-m
hydro/moisture
hydro/drainage
```

but those fields are deliberately not made canonical G6 responsibilities.
