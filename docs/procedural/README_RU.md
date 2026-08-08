# Universal World Generation Fabric — entrypoint

Current implementation:

```text
feature/g6-hydrology-fluid-surface-v0
```

Current state:

```text
G3 ACCEPTED
G4 ACCEPTED — Architecture Review A PASS
G5 ACCEPTED
G6.0 ACCEPTED
G6.1 ACCEPTED
G6.2 ACCEPTED
G6.3 ACCEPTED — runtime WaterSurfaceQuery resolver
G6.4 NEXT — Casual Visual River Lab
```

Global revision:

```text
GLOBAL-P0-2026-08-08-R1
```

Start here:

1. `docs/procedural/STATUS_RU.md`
2. `docs/checkpoints/G6_3_RUNTIME_WATER_SURFACE_QUERY_ACCEPTED_RU.md`
3. `docs/checkpoints/G6_2_CROSS_CELL_CROSS_LOD_CONTINUITY_ACCEPTED_RU.md`
4. `docs/checkpoints/G6_1_CASUAL_RIVER_PROVIDER_ACCEPTED_RU.md`
5. `docs/procedural/G6_P0_ALIGNMENT_RU.md`
6. `docs/checkpoints/G5_WORLD_FEATURE_GRAPH_ACCEPTED_RU.md`
7. `docs/procedural/NEXT_AFTER_G3_UNIVERSAL_WORLD_GENERATION_RU.md`
8. `docs/plans/UNIVERSAL_WORLD_GENERATION_EXECUTION_PLAN_RU.md`
9. `docs/plans/UNIVERSAL_WORLD_GENERATION_ROADMAP_RU.md`

## Current architecture

```text
G0 contracts / GeoKernel
        ↓
G1 body-fixed geodesy
        ↓
G2 cube-sphere cells + LOD
        ↓
G3 canonical macro surface
        ↓
G4 recipe-driven provider composition
        ↓
G5 canonical World Feature Graph
        ↓
G6.0 canonical fluid contracts
        ↓
G6.1 deterministic river provider
        ↓
G6.2 cross-cell/cross-LOD continuity — ACCEPTED
        ↓
G6.3 runtime WaterSurfaceQuery — ACCEPTED
        ↓
G6.4 casual visual river lab — NEXT
```

Accepted hydrology rule:

```text
G5 FeatureId = semantic river owner
G6.1 provider = deterministic canonical geography compiler
G6.2 cell/LOD = representation addressing only
G6.3 query resolver = read-only derived world service
G6.4 renderer/lab = derived presentation only
```

## Accepted G6.3 runtime query

Windows-tested head:

```text
974fc6682abac058ea158cf11efbf44501805817
```

Accepted chain:

```text
G5 World Feature Graph                 PASS — 249
G5 feature/cell identity               PASS — 94
G6.0 fluid contracts                   PASS — 169
G6.1 CasualRiverProviderV1             PASS — 74
G6.2 cross-cell/cross-LOD continuity   PASS — 86
G6.3 runtime WaterSurfaceQuery         PASS — 79
git diff --check                       PASS
working tree                           clean
```

Runtime flow:

```text
body/frame position + max distance + fluid filter
        ↓
WaterSurfaceQuery
        ↓
WaterSurfaceResolverV1
        ↓
WaterSurfaceSample
```

The caller receives canonical fluid/feature identity and derived surface information without knowing a surface cell, cube face, LOD, renderer patch, interest region or server owner.

Multiple eligible fluids are resolved deterministically by distance and then lexical `FluidRegionId`.

## Next visual milestone — G6.4

`G6.4 Casual Visual River Lab` is now unblocked. It is the first manual visual hydrology checkpoint.

The lab should provide deliberately simple, replaceable presentation:

```text
water ribbon from accepted RiverSpline
channel width/bank visualization
canonical centerline debug
WaterSurfaceQuery probe markers
manual camera/player observation
PX/PZ seam continuity inspection
```

The visual layer must consume accepted G6.1/G6.3 data rather than creating a second river model.

After G6.4:

```text
G6 full acceptance
  -> fresh main/GLOBAL-P0 sync check
  -> full world/core regression
  -> G7 Semantic Field Fabric
```

## Detail / asset research doctrine

```text
BASE FIRST
BEAUTY SECOND
```

Photoreal water, foam, FFT waves and production shoreline remain deferred. Early checkpoints optimize for canonical identity, deterministic composition, query correctness, LOD independence and replaceable presentation.
