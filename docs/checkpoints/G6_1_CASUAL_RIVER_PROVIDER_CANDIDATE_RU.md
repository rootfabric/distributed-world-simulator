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

Главное архитектурное решение этого checkpoint:

```text
G5 River FeatureId = semantic owner
G6 provider       = deterministic compiler
G6 output         = derived canonical geography contracts
```

Provider не создаёт новый `WorldFeature`, не пишет в `FeatureGraph` и не объявляет собственную authority.

## Почему не перенесён целиком старый G6 prototype

В reference-ветке `feature/g6-hydrology-fluid-surface` одновременно были смешаны provider, runtime water query, cross-cell/LOD proof и visual lab.

Для текущей staged-линии это слишком широкий checkpoint. G6.1 намеренно забирает только provider idea и адаптирует её к уже принятому G6.0 контракту.

Дополнительно исправлено направление зависимости:

```text
НЕ:
provider -> создаёт новый RiverFeature

А:
existing G5 RiverFeature -> provider -> G6 fluid geography
```

Это сохраняет `Feature != Cell` и не создаёт второй semantic identity layer.

## Provider contract

```text
provider id:      hydro-provider/casual-river-v1
provider version: 1.0.0
control points:   7
```

Вход:

- валидный G5 `WorldFeature` типа `feature-type/river`;
- semantic anchors `source` и `mouth`;
- опциональный связанный G5 `valley` parent;
- canonical G6 `FluidType`, по умолчанию `fluid-type/water`.

Выход:

- `FluidRegionId`;
- `RiverSpline`;
- `RiverChannelProfile`;
- `FluidSurfaceDescriptor`;
- deterministic provider manifest hash.

## Identity model

Fluid/spline stable keys выводятся из stable G5 `feature_id`, provider id и canonical fluid type, а не из representation address.

Следовательно:

```text
river geometry changes
    -> spline/profile/surface checksum may change
    -> provider manifest changes
    -> G5 FeatureId stays
    -> FluidRegionId stays
    -> RiverSpline.spline_id stays
    -> RiverChannelProfile.profile_id stays
```

Это позволяет позже улучшать русло, учитывать geology/erosion или authoritative mutations, не превращая каждую геометрическую ревизию в новую реку.

## Valley semantics

Связанная valley не владеет river identity. Её checksum используется только как deterministic geometry salt.

Поэтому изменение формы/semantic revision долины может изменить производную форму русла, но не имеет права reroll-ить stable river/fluid identity.

Если river имеет `parent_feature_id`, переданная valley обязана совпадать с этим parent.

## Casual geometry v1

Provider строит семь body-frame control points между source и mouth.

Для radial planetary anchors используется spherical direction interpolation с сохранением interpolated radius. Между endpoints добавляется deterministic meander в tangent plane.

Meander зависит только от canonical source/valley payload + provider version.

Нет:

```text
RandomNumberGenerator
randf/randi
camera state
SurfaceCellKey
LOD
query order
renderer
network transport
```

Это deliberately casual baseline, а не erosion solver и не hydrodynamics simulation.

## Channel profile v1

Профиль задаёт deterministic samples:

```text
t = 0.00
    0.25
    0.50
    0.75
    1.00
```

Width/depth/bank width плавно растут от source к mouth и масштабируются по source-mouth distance.

Профиль является первым casual baseline и позже может быть заменён более физически обоснованным provider без изменения G6.0 contracts.

## P0 boundaries

G6.1 не создаёт:

- `RiverChunkId`;
- authority registry;
- persistence owner;
- network RPC path;
- renderer truth;
- отдельную material ontology;
- authoritative fluid mutation.

`FluidType` пока остаётся G6 semantic vocabulary. Его projection на общий `MaterialDefinitionId` относится к P0 Unified Material Ontology.

Будущие mutations относятся к общему `WorldOperation / WorldTransactionPlan`, а не к provider cache.

## Что намеренно НЕ входит в G6.1

```text
G6.2 cross-cell / cross-LOD continuity proof
G6.3 runtime WaterSurfaceQuery resolver
G6.4 visual river lab
full CFD / erosion / sediment transport
Matter/fluid authoritative mutation
```

То есть G6.1 не сокращает и не обходит следующие gates.

## Focused acceptance

Запуск:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_1_CASUAL_RIVER_PROVIDER_TESTS.ps1
```

Runner сначала повторяет принятый dependency gate G6.0:

```text
G5 World Feature Graph
G5 feature/cell identity
G6.0 fluid contracts
```

затем запускает новый focused G6.1 suite.

G6.1 test проверяет минимум:

- manifest/P0 revision;
- compile из G5 river + linked valley;
- валидность всех G6.0 output contracts;
- deterministic repeated compile;
- независимость от unrelated feature/query order;
- geometry revision меняет checksum, но не identity;
- valley revision не reroll-ит identity;
- explicit non-water fluid projection;
- precise rejection non-river/missing mouth/wrong support feature;
- отсутствие cell/LOD/renderer/network/runtime-random dependencies в provider source.

## Acceptance decision

До реального Windows/Godot 4.7.1 double результата:

```text
G6.1 = IMPLEMENTED CANDIDATE
```

После green focused run можно зафиксировать:

```text
G6.1 = ACCEPTED
next = G6.2 cross-cell / cross-LOD continuity
```

Полный world regression по прежнему можно оставить на composed G6.1–G6.4 final gate, если focused run не обнаружит необходимость менять shared runtime/contracts.
