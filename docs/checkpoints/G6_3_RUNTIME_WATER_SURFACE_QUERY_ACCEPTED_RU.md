# G6.3 — Runtime WaterSurfaceQuery Resolver — ACCEPTED

**Ветка:** `feature/g6-hydrology-fluid-surface-v0`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Implementation candidate:** `22059af7b91c65245f7992936f1612d4503d8782`
**Windows-tested head:** `974fc6682abac058ea158cf11efbf44501805817`
**Решение:** `ACCEPTED`

## Результат

G6.3 принят как первый read-only runtime query service над canonical hydrology geography.

```text
WaterSurfaceQuery
        ↓
WaterSurfaceResolverV1
        ↓
compiled G6.1 canonical geography
        ↓
WaterSurfaceSample
```

Caller использует только:

```text
body_id
frame_id
position_m
max_distance_m
fluid_type_ids
```

и не обязан знать `SurfaceCellKey`, cube face, LOD, renderer patch, interest region, authority region или server id.

## Windows acceptance

Environment:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
Windows
```

Focused chain:

```text
G5 World Feature Graph                 PASS — 249 assertions
G5 feature/cell identity               PASS — 94 assertions
G6.0 fluid contracts                   PASS — 169 assertions
G6.1 CasualRiverProviderV1             PASS — 74 assertions
G6.2 cross-cell/cross-LOD continuity   PASS — 86 assertions
G6.3 runtime WaterSurfaceQuery         PASS — 79 assertions
git diff --check                       PASS
working tree                           CLEAN
```

## Accepted runtime semantics

`WaterSurfaceResolverV1`:

- валидирует composition между `FluidRegionId`, `RiverSpline`, `RiverChannelProfile`, `FluidSurfaceDescriptor` и source `FeatureId`;
- фильтрует candidates по body/frame/fluid type;
- вычисляет ближайшую canonical river surface;
- возвращает validated `WaterSurfaceSample`;
- не mutates canonical world state;
- не владеет authority/persistence/network transport.

Deterministic winner для нескольких подходящих fluid regions:

```text
minimum distance_to_surface_m
        ↓ tie
lexical FluidRegionId
```

Порядок регистрации/загрузки candidates не влияет на ответ.

## Accepted query result

`WaterSurfaceSample` содержит:

```text
source_feature_id
fluid_region_id
body_id / frame_id
fluid_type_id
query_position_m
centerline_position_m
surface_position_m
surface_normal
flow_direction
channel_width_m
channel_depth_m
bank_width_m
distance_to_centerline_m
distance_to_surface_m
downstream_t
inside_channel
checksum
```

Flow speed намеренно не добавлен как новая canonical truth: текущий G6.1 profile канонически задаёт width/depth/bank width, а velocity/flow physics должны прийти через последующие semantic fields/physics layers.

## Planetary curve approximation

Resolver v1 использует фиксированное deterministic subdivision canonical spline segments:

```text
CURVE_SUBDIVISIONS_PER_SEGMENT = 16
```

Это compute-detail resolver, а не LOD, streaming address или identity. В будущем его можно заменить analytic/BVH/index backend без изменения query/sample contract.

## GLOBAL-P0 boundary

Подтверждено отсутствие canonical зависимости от:

```text
SurfaceCellKey
CubeSphereAddressing
LOD
cube face
InterestRegionId
AuthorityRegionId
renderer
network peer / RPC
persistence owner
```

Future spatial index/cache разрешён только как derived acceleration layer.

## Следующий checkpoint

```text
G6.4 — Casual Visual River Lab
```

G6.4 должен потреблять accepted G6.1 geography и G6.3 query/sample API. Визуальный river ribbon/debug presentation не становится canonical fluid truth.

Перед полным G6 acceptance требуется fresh `main` / GLOBAL-P0 revision check.
