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
G6.3 IMPLEMENTED CANDIDATE — runtime WaterSurfaceQuery resolver
G6.4 NEXT — after G6.3 focused acceptance
```

Global revision:

```text
GLOBAL-P0-2026-08-08-R1
```

Start here:

1. `docs/procedural/STATUS_RU.md`
2. `docs/checkpoints/G6_3_RUNTIME_WATER_SURFACE_QUERY_CANDIDATE_RU.md`
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
G6.3 runtime WaterSurfaceQuery — CANDIDATE
        ↓
G6.4 casual visual river lab
```

Accepted hydrology rule:

```text
G5 FeatureId = semantic river owner
G6.1 provider = deterministic canonical geography compiler
G6.2 cell/LOD = representation addressing only
G6.3 query resolver = read-only derived world service
```

## G6.3 candidate

New query flow:

```text
body/frame position + max distance + fluid filter
        ↓
WaterSurfaceQuery
        ↓
WaterSurfaceResolverV1
        ↓
WaterSurfaceSample
```

The caller receives fluid/feature identity, nearest canonical surface, surface normal, flow direction, channel dimensions and downstream position without knowing a surface cell, cube face, LOD, renderer patch, interest region or server owner.

Multiple eligible fluids are resolved deterministically by distance and then lexical `FluidRegionId`, so load/order differences do not change the result.

Focused Windows validation:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_3_RUNTIME_WATER_QUERY_TESTS.ps1
```

This runner rechecks the entire accepted dependency chain through G6.2 before G6.3.

## Next visual milestone

After G6.3 acceptance, `G6.4 Casual Visual River Lab` becomes the first manual visual hydrology checkpoint. Its mesh/debug presentation must consume accepted G6 query/geography contracts rather than becoming world truth.

## Detail / asset research doctrine

```text
BASE FIRST
BEAUTY SECOND
```

Photoreal water, foam, FFT waves and production shoreline remain deferred. Early checkpoints optimize for canonical identity, deterministic composition, query correctness, LOD independence and replaceable presentation.
