# G6 Hydrology / Fluid Surface v0 — P0 alignment

**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Branch:** `feature/g6-hydrology-fluid-surface-v0`
**Local role:** hydrology/fluid semantic and query layer above G5 World Feature Graph
**Current stage:** `G6.3 Runtime WaterSurfaceQuery Resolver — IMPLEMENTED CANDIDATE`
**Next after acceptance:** `G6.4 Casual Visual River Lab`

## Canonical boundary

```text
G5 WorldFeature / FeatureId
        ↓
G6.1 deterministic fluid geography compiler
        ↓
FluidRegionId / FluidSurfaceDescriptor / RiverSpline / RiverChannelProfile
        ↓
G6.3 read-only query resolver
        ↓
WaterSurfaceSample
        ↓
G6.4 derived presentation
```

Обязательные инварианты:

```text
FluidRegion != SurfaceCell
FluidRegion != AuthorityRegion
FluidRegion != InterestRegion
FluidRegion != renderer object
Fluid identity != LOD / quality / observer state
query/index/cache != canonical identity
G5 River FeatureId remains semantic owner
```

## GLOBAL-P0 synchronization

Перед G6.3 повторно проверен `main`:

```text
global_revision = GLOBAL-P0-2026-08-08-R1
```

G6 продолжает использовать byte-equivalent global program/network config этой revision. Локальная G6-ветка не редактирует global plan самостоятельно.

Канонический global ledger пока был создан до появления активной G6-линии и его `active_sync_branches` не перечисляет G6. Это не блокирует source development при совпадающей revision, но перед полным G6 acceptance/merge требуется свежая проверка `main`; если появится новая global revision, она сначала фиксируется в `main`, затем синхронно переносится в G6.

## P0-2 Spatial Domain Fabric

G6.2 уже доказал, что canonical river geography переживает `PX/PZ` seam и LOD `2 / 4 / 8 / 12` без identity reroll.

G6.3 сохраняет ту же границу. Query получает:

```text
body_id
frame_id
position_m
max_distance_m
fluid_type_ids
```

и НЕ получает:

```text
SurfaceCellKey
cube face
LOD
InterestRegionId
AuthorityRegionId
server id
```

Будущий `WorldAddress`/Spatial Domain Fabric сможет ускорить поиск подходящих fluid candidates, но mapping/index не заменяет `FeatureId` или `FluidRegionId`.

## P0-3 Unified Material Ontology

G6 `FluidType` пока остаётся baseline semantic vocabulary для query/filtering.

```text
fluid-type/water
fluid-type/methane
...
```

Это не новая глобальная material ontology. Future `MaterialDefinitionId` должен проецироваться в fluid domain отдельно. Rendering shader/material name никогда не становится canonical fluid identity.

G6.3 поэтому возвращает `fluid_type_id`, но не создаёт competing material definitions.

## P0-4 Cross-Domain World Transaction Model

`WaterSurfaceResolverV1` read-only:

```text
query -> derived sample
```

Он не commit-ит:

```text
fluid mutation
Matter mutation
Item mutation
Construction mutation
```

Будущая выемка/замерзание/перекачка/затопление должны идти через общий `WorldOperation / WorldTransactionPlan` или существующий durable authority path, а не через query service или best-effort RPC chain.

## P0-5 NX7 / NX8 / NX9

G6.3 не создаёт authority registry.

NX8 позже может выбирать:

```text
какие fluid regions/query results/visual segments интересны клиенту
какой replication/query budget им дать
```

но:

```text
interest region != FluidRegionId
query cache != FluidRegionId
LOD/ribbon/mesh patch != FluidRegionId
```

NX9 может менять I/O/cache scheduling, но не query semantics или canonical fluid identity.

## G6.1 / G6.2 accepted foundation

```text
G6.1 CasualRiverProviderV1             ACCEPTED — 74 assertions
G6.2 cross-cell/cross-LOD continuity   ACCEPTED — 86 assertions
```

G6.1 не создаёт второй WorldFeature; G6.2 не создаёт RiverChunkId.

## G6.3 implemented boundary

Новые элементы:

```text
WaterSurfaceSample
WaterSurfaceResolverV1
```

Resolver валидирует composition G6.1 outputs и выбирает deterministic answer:

```text
minimum distance_to_surface_m
        ↓ tie
lexical FluidRegionId
```

Это исключает зависимость от query/registration order.

Spline query accuracy v1 использует фиксированные radial/spherical subdivisions внутри canonical spline segment. Это локальный compute-detail resolver, не LOD и не spatial identity.

Запрещено делать canonical truth из:

```text
resolver subdivision count
future BVH/grid/index
cache key
query batch
client interest set
```

## G6.4 boundary after acceptance

G6.4 сможет визуализировать реку и debug query samples, но обязано потреблять:

```text
G6.1 canonical geography
G6.3 WaterSurfaceSample/query result
```

Renderer не должен повторно выводить собственную river identity или собственную fluid truth.

## Stop conditions

Нужен global architecture review, если G6 понадобится:

- permanent river identity из SurfaceCellKey;
- private fluid authority registry;
- private global material ontology;
- query cache/index как canonical state;
- visual mesh как canonical truth;
- durable mutation только в procedural cache;
- identity, зависящая от camera/LOD/query order;
- cross-domain mutation через best-effort RPC chain.

## Merge / composition gate

```text
[PASS] GLOBAL-P0-2026-08-08-R1 matches main at G6.3 implementation start
[PASS] Feature != SurfaceCell
[PASS] FluidRegion != SurfaceCell / AuthorityRegion / InterestRegion
[PASS] G6.1 Windows acceptance — 74 assertions
[PASS] G6.2 Windows continuity acceptance — 86 assertions
[PASS] G6.3 does not modify accepted G6.0/G6.1/G6.2 production semantics
[PENDING WINDOWS] G6.3 runtime WaterSurfaceQuery focused acceptance
[NEXT] G6.4 Casual Visual River Lab
```

Перед full G6 acceptance требуется ещё одна fresh main/global revision check.
