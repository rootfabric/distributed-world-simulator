# G6 Hydrology / Fluid Surface v0 — P0 alignment

**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Branch:** `feature/g6-hydrology-fluid-surface-v0`
**Local role:** hydrology/fluid semantic, query and derived-presentation layer above G5 World Feature Graph
**Current stage:** `G6.3 Runtime WaterSurfaceQuery Resolver — ACCEPTED`
**Next stage:** `G6.4 Casual Visual River Lab`

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

Перед G6.3 `main` был повторно проверен:

```text
global_revision = GLOBAL-P0-2026-08-08-R1
```

G6 использует byte-equivalent global program/network config этой revision. Локальная G6-ветка не редактирует global plan самостоятельно.

Канонический global ledger был создан до появления активной G6-линии и его `active_sync_branches` пока не перечисляет G6. Это не блокирует source development при совпадающей revision. Перед full G6 acceptance требуется fresh `main` check; если global revision изменится, новая revision сначала фиксируется в `main`, затем синхронно переносится в G6.

## P0-2 Spatial Domain Fabric

G6.2 доказал, что canonical river geography переживает `PX/PZ` seam и LOD `2 / 4 / 8 / 12` без identity reroll.

G6.3 принят с query contract:

```text
body_id
frame_id
position_m
max_distance_m
fluid_type_ids
```

без:

```text
SurfaceCellKey
cube face
LOD
InterestRegionId
AuthorityRegionId
server id
```

Будущий `WorldAddress`/Spatial Domain Fabric сможет ускорить выбор fluid candidates, но mapping/index не заменяет `FeatureId` или `FluidRegionId`.

## P0-3 Unified Material Ontology

G6 `FluidType` остаётся baseline semantic vocabulary для query/filtering:

```text
fluid-type/water
fluid-type/methane
...
```

Это не конкурирующая material ontology. Future `MaterialDefinitionId` должен проецироваться в fluid domain отдельно. Rendering shader/material name никогда не становится canonical fluid identity.

## P0-4 Cross-Domain World Transaction Model

`WaterSurfaceResolverV1` принят как read-only service:

```text
query -> derived sample
```

Он не commit-ит fluid/Matter/Item/Construction mutation. Будущая выемка, замерзание, перекачка и затопление должны идти через общий durable world-operation path, а не через query service или best-effort RPC chain.

## P0-5 NX7 / NX8 / NX9

G6 не создаёт authority registry.

NX8 позже может выбирать, какие fluid regions/query results/visual segments интересны клиенту и какой replication budget им дать, но:

```text
interest region != FluidRegionId
query cache != FluidRegionId
LOD/ribbon/mesh patch != FluidRegionId
```

NX9 может менять I/O/cache scheduling, но не canonical fluid/query semantics.

## Accepted G6 foundation

```text
G6.1 CasualRiverProviderV1             ACCEPTED — 74 assertions
G6.2 cross-cell/cross-LOD continuity   ACCEPTED — 86 assertions
G6.3 runtime WaterSurfaceQuery         ACCEPTED — 79 assertions
```

G6.3 accepted tested head:

```text
974fc6682abac058ea158cf11efbf44501805817
```

Accepted runtime query semantics:

```text
minimum distance_to_surface_m
        ↓ tie
lexical FluidRegionId
```

Candidate registration order does not affect the winner. Fixed spline subdivisions are compute-detail only; future BVH/grid/index/cache remains a derived acceleration layer and cannot become canonical identity or authority.

## G6.4 boundary

G6.4 may add Godot presentation/runtime-lab code, but it must consume accepted canonical geography/query contracts.

Allowed:

```text
simple water ribbon mesh
debug centerline
width/bank guides
query probe markers
camera/player lab
LOD/cell debug overlay
```

Forbidden:

```text
mesh instance = river identity
renderer patch = FluidRegionId
camera position changes canonical river
visual LOD changes canonical query result
lab owns authority/persistence
new river truth recomputed only inside renderer
```

G6.4 is a presentation proof, not a second hydrology implementation.

## Stop conditions

Нужен global architecture review, если G6 понадобится:

- permanent river identity из SurfaceCellKey;
- private fluid authority registry;
- private global material ontology;
- query cache/index как canonical state;
- visual mesh as canonical truth;
- durable mutation только в procedural cache;
- identity, зависящая от camera/LOD/query order;
- cross-domain mutation через best-effort RPC chain.

## Merge / composition gate

```text
[PASS] GLOBAL-P0-2026-08-08-R1 matched main at G6.3 implementation start
[PASS] Feature != SurfaceCell
[PASS] FluidRegion != SurfaceCell / AuthorityRegion / InterestRegion
[PASS] G6.1 Windows acceptance — 74 assertions
[PASS] G6.2 Windows continuity acceptance — 86 assertions
[PASS] G6.3 Windows runtime query acceptance — 79 assertions
[NEXT] G6.4 Casual Visual River Lab
[PENDING FULL G6] fresh main/global revision check + full regression/composition gate
```
