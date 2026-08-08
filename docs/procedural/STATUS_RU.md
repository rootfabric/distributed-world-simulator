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
G6.3 Runtime WaterSurfaceQuery         IMPLEMENTED CANDIDATE
G6.4 Casual Visual River Lab           NEXT AFTER G6.3 ACCEPTANCE
```

Accepted tested heads:

```text
G6.1 b8f36d17dc8ba138e6b215968aa0e651eec9ccd1
G6.2 444811c0ac98a133844cd7ec0869a6cf0a261f11
```

G6.3 implementation candidate:

```text
22059af7b91c65245f7992936f1612d4503d8782
```

Canonical records:

```text
docs/checkpoints/G5_WORLD_FEATURE_GRAPH_ACCEPTED_RU.md
docs/checkpoints/G6_1_CASUAL_RIVER_PROVIDER_ACCEPTED_RU.md
docs/checkpoints/G6_2_CROSS_CELL_CROSS_LOD_CONTINUITY_ACCEPTED_RU.md
docs/checkpoints/G6_3_RUNTIME_WATER_SURFACE_QUERY_CANDIDATE_RU.md
```

## Accepted foundation through G6.2

G5 owns stable semantic `FeatureId`. G6.1 compiles G5 river semantics into canonical fluid geography:

```text
G5 River FeatureId
        ↓
CasualRiverProviderV1
        ↓
FluidRegionId
RiverSpline
RiverChannelProfile
FluidSurfaceDescriptor
```

G6.2 proved that one canonical river survives cube-sphere face/cell and LOD representation changes:

```text
PX / PZ seam
LOD 2 / 4 / 8 / 12
representation cell set changes
canonical river/fluid identities and checksums stay stable
```

Accepted Windows chain through G6.2:

```text
G5 World Feature Graph                 PASS — 249 assertions
G5 feature/cell identity               PASS — 94 assertions
G6.0 fluid contracts                   PASS — 169 assertions
G6.1 CasualRiverProviderV1             PASS — 74 assertions
G6.2 cross-cell/cross-LOD continuity   PASS — 86 assertions
git diff --check                       PASS
working tree                           clean
```

## G6.3 Runtime WaterSurfaceQuery — candidate

G6.3 adds the first read-only runtime world query over accepted hydrology geography.

```text
WaterSurfaceQuery
        ↓
WaterSurfaceResolverV1
        ↓
compiled canonical fluid geography
        ↓
WaterSurfaceSample
```

New runtime/service files:

```text
scripts/simulation/procedural/contracts/water_surface_sample.gd
scripts/simulation/procedural/hydrology/water_surface_resolver_v1.gd
```

Query inputs remain representation-independent:

```text
body_id
frame_id
position_m
max_distance_m
fluid_type_ids
```

The result can expose canonical feature/fluid identity, surface/centerline positions, normal, flow direction, width/depth/bank width and downstream position.

Deterministic multi-region winner:

```text
minimum distance_to_surface_m
then lexical FluidRegionId
```

Therefore candidate order/loading order cannot choose the result.

G6.3 deliberately has no:

```text
SurfaceCellKey
CubeSphereAddressing / cube face
LOD
renderer
InterestRegionId / AuthorityRegionId
server id / network peer
persistence owner
world mutation
```

Future BVH/grid/cache remains a derived acceleration backend only.

Focused validation:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_3_RUNTIME_WATER_QUERY_TESTS.ps1
```

Runner repeats G5 + G6.0 + G6.1 + G6.2 before G6.3.

Until the exact Windows run is green:

```text
G6.3 = IMPLEMENTED CANDIDATE
```

## Next

After G6.3 acceptance:

```text
G6.4 Casual Visual River Lab
  -> G6 full acceptance
  -> fresh GLOBAL-P0/main sync check
  -> G7 Semantic Field Fabric
```

G6.4 must render/inspect derived river presentation from the accepted provider/query contracts; renderer output must not become canonical fluid truth.

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
