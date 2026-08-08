# G6.3 — Runtime WaterSurfaceQuery Resolver — IMPLEMENTED CANDIDATE

**Дата:** 2026-08-08
**Ветка:** `feature/g6-hydrology-fluid-surface-v0`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Dependencies:** `G6.0 / G6.1 / G6.2 — ACCEPTED`
**Implementation candidate:** `22059af7b91c65245f7992936f1612d4503d8782`
**Решение:** `IMPLEMENTED CANDIDATE — WINDOWS FOCUSED ACCEPTANCE REQUIRED`

## Цель

G6.3 переводит принятую canonical river geography из набора data contracts в runtime query service.

Caller задаёт только semantic/world-frame query:

```text
WaterSurfaceQuery
├── body_id
├── frame_id
├── position_m
├── max_distance_m
└── fluid_type_ids
```

Resolver возвращает либо deterministic no-match, либо canonical `WaterSurfaceSample`.

```text
WaterSurfaceQuery
        ↓
WaterSurfaceResolverV1
        ↓
compiled G6.1 geography
        ↓
WaterSurfaceSample
```

## Новые production contracts/services

```text
scripts/simulation/procedural/contracts/water_surface_sample.gd
scripts/simulation/procedural/hydrology/water_surface_resolver_v1.gd
```

Resolver id/version:

```text
hydro-resolver/water-surface-v1
1.0.0
```

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

G6.3 намеренно не вводит flow speed. В текущем G6.1 `RiverChannelProfile` канонически хранит width/depth/bank width; скорость/расход должны появляться через последующие semantic fields/physics, а не как случайная новая truth в resolver.

## Runtime algorithm v1

Каждый compiled G6.1 river candidate валидируется на композицию:

```text
FluidRegionId
  == RiverSpline.fluid_region_id
  == RiverChannelProfile.fluid_region_id
  == FluidSurfaceDescriptor.fluid_region_id

source_feature_id
  == FluidSurfaceDescriptor.source_feature_id

RiverSpline.frame_id
  == FluidSurfaceDescriptor.frame_id
```

Затем resolver:

1. фильтрует candidate по `body_id`, `frame_id`, `fluid_type_ids`;
2. ищет ближайшую точку canonical `RiverSpline`;
3. интерполирует `RiverChannelProfile` по `downstream_t`;
4. вычисляет ближайшую точку поверхности воды и нормаль;
5. возвращает sample, если `distance_to_surface_m <= max_distance_m`;
6. если подходят несколько fluid regions, выбирает deterministic winner.

Tie-break:

```text
minimum distance_to_surface_m
        ↓ equal within epsilon
lexical FluidRegionId
```

Поэтому порядок регистрации/загрузки candidates не влияет на результат.

## Planetary curve approximation

G6.0 `RiverSpline` остаётся неизменённым data contract. Чтобы не превращать query resolver в прямой chord-through-planet approximation, каждый canonical spline segment runtime-v1 детерминированно делится на 16 radial/spherical micro-segments.

Это implementation detail query accuracy:

```text
CURVE_SUBDIVISIONS_PER_SEGMENT = 16
```

Он не является LOD, world identity или streaming address и позже может быть заменён более точным analytic/index backend без изменения query/sample contracts.

## P0 boundaries

G6.3 не получает и не создаёт:

```text
SurfaceCellKey
CubeSphereAddressing
LOD
cube face
InterestRegionId
AuthorityRegionId
server id
renderer mesh/patch
network peer/RPC
persistence owner
```

Resolver read-only:

```text
query -> derived answer
```

Он не commit-ит world mutation и не владеет authority/persistence.

Future BVH/grid/spatial index/cache разрешены только как derived acceleration layer. Они не могут стать canonical fluid identity или authority route.

Это соответствует `GLOBAL-P0-2026-08-08-R1`:

```text
CANONICAL WORLD != PRESENTATION
CANONICAL WORLD != TRANSPORT
CANONICAL WORLD != COMPUTE
identity != LOD
spatial location != authority route
```

## Focused acceptance matrix

Новый test:

```text
tests/procedural/hydrology/g6_3_runtime_water_surface_query_acceptance.gd
```

Проверяет:

```text
manifest/global revision
exact query on canonical river
valid WaterSurfaceSample
FeatureId / FluidRegionId propagation
width / depth / downstream_t
unit surface normal / flow direction
max_distance near match
far no-match
fluid type filtering
body/frame filtering
water + methane deterministic tie-break
candidate-order independence
sample checksum determinism
invalid query rejection
broken compiled composition rejection
source boundary scan
```

Focused runner сначала повторяет весь accepted dependency chain:

```text
G5 World Feature Graph
G5 feature/cell identity
G6.0 Fluid Contracts
G6.1 CasualRiverProviderV1
G6.2 cross-cell / cross-LOD continuity
```

и затем запускает G6.3.

Windows command:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_3_RUNTIME_WATER_QUERY_TESTS.ps1
```

До реального Windows/Godot результата:

```text
G6.3 = IMPLEMENTED CANDIDATE
```

После green focused run:

```text
G6.3 = ACCEPTED
next = G6.4 Casual Visual River Lab
```

## Deferred intentionally

```text
BVH / spatial query acceleration
network replication / interest selection
authoritative fluid mutation
fluid material ontology projection
river mesh / shader / foam
G6.4 visual lab
full G6 regression/composition gate
```

G6.4 должен потреблять этот resolver/sample contract для debug/visual proof, а не повторно вычислять собственную canonical river truth.
