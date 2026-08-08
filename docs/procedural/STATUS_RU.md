# Universal World Generation Fabric — status ledger

**Program foundation:** G0–G3 Procedural Planetary Generation
**Current implementation branch:** `feature/g6-hydrology-fluid-surface-v0`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`

## Current state

```text
G0 Contracts Freeze                    ACCEPTED
G1 Geodesy + Body Shape                BASELINE
G2 Planetary Surface Cells + LOD       ACCEPTED
G3 Mega Casual Macro Surface           ACCEPTED
G4 Provider Composition / Replacement  ACCEPTED
G5 World Feature Graph                 ACCEPTED
G6.0 Fluid Contracts                   ACCEPTED
G6.1 CasualRiverProviderV1             ACCEPTED
G6.2 Cross-Cell / Cross-LOD Continuity ACCEPTED
G6.3 Runtime WaterSurfaceQuery         ACCEPTED
G6.4 Casual Visual River Lab           NEXT — UNBLOCKED
```

Accepted tested heads:

```text
G6.1 b8f36d17dc8ba138e6b215968aa0e651eec9ccd1
G6.2 444811c0ac98a133844cd7ec0869a6cf0a261f11
G6.3 974fc6682abac058ea158cf11efbf44501805817
```

Canonical records:

```text
docs/checkpoints/G5_WORLD_FEATURE_GRAPH_ACCEPTED_RU.md
docs/checkpoints/G6_1_CASUAL_RIVER_PROVIDER_ACCEPTED_RU.md
docs/checkpoints/G6_2_CROSS_CELL_CROSS_LOD_CONTINUITY_ACCEPTED_RU.md
docs/checkpoints/G6_3_RUNTIME_WATER_SURFACE_QUERY_ACCEPTED_RU.md
```

## Accepted hydrology foundation through G6.3

```text
G5 River FeatureId
        ↓
G6.1 CasualRiverProviderV1
        ↓
FluidRegionId / RiverSpline / RiverChannelProfile / FluidSurfaceDescriptor
        ↓
G6.2 representation continuity proof
        ↓
G6.3 WaterSurfaceResolverV1
        ↓
WaterSurfaceSample
```

G6.2 proved that canonical river identity survives cube-sphere face/cell and LOD representation changes. G6.3 then accepted a read-only runtime query service that resolves canonical fluid surface information from body/frame coordinates without requiring representation addressing.

Accepted Windows chain:

```text
G5 World Feature Graph                 PASS — 249 assertions
G5 feature/cell identity               PASS — 94 assertions
G6.0 fluid contracts                   PASS — 169 assertions
G6.1 CasualRiverProviderV1             PASS — 74 assertions
G6.2 cross-cell/cross-LOD continuity   PASS — 86 assertions
G6.3 runtime WaterSurfaceQuery         PASS — 79 assertions
git diff --check                       PASS
working tree                           clean
```

## G6.3 accepted runtime query

Query input:

```text
body_id
frame_id
position_m
max_distance_m
fluid_type_ids
```

Output can expose:

```text
source_feature_id
fluid_region_id
fluid_type_id
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
```

Deterministic multi-region winner:

```text
minimum distance_to_surface_m
then lexical FluidRegionId
```

The accepted resolver has no canonical dependency on `SurfaceCellKey`, cube face, LOD, renderer, interest/authority regions, server id, network transport or persistence.

Future BVH/grid/cache remains a derived acceleration backend only.

## Next — G6.4 Casual Visual River Lab

G6.4 is now unblocked and is the first manual visual hydrology checkpoint.

It must consume accepted G6.1 canonical geography and G6.3 query/sample contracts:

```text
canonical river + WaterSurfaceSample
        ↓
derived debug/visual river presentation
```

Expected lab goals:

```text
simple deterministic water ribbon
canonical centerline debug
channel width/bank debug
query probe markers
manual camera/player observation
PX/PZ seam continuity proof
presentation remains replaceable
```

G6.4 must not introduce a new river identity, authority layer, persistence model or renderer-owned world truth.

After G6.4:

```text
G6 full acceptance
  -> fresh main/GLOBAL-P0 sync check
  -> full world/core regression
  -> G7 Semantic Field Fabric
```

## Invariants

```text
Generator != Renderer
LOD != World State
Feature != SurfaceCell
FluidRegion != SurfaceCell
FluidRegion != AuthorityRegion
FluidRegion != InterestRegion
query/index/cache != canonical identity
spatial location != authority route
canonical truth != representation
procedural baseline + sparse authoritative mutations = current world truth
```
