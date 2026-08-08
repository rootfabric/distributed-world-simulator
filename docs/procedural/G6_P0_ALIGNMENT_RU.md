# G6 Hydrology / Fluid Surface v0 — P0 alignment

**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Branch:** `feature/g6-hydrology-fluid-surface-v0`
**Local role:** hydrology/fluid semantic, query and derived-presentation layer above G5 World Feature Graph
**Current stage:** `G6.4 Casual Visual River Lab — FIX2 IMPLEMENTED CANDIDATE`
**Fix2 functional head:** `353a73f08f6d07840145e61f79b197e5773a73a2`
**Next after acceptance:** `G6 FULL ACCEPTANCE`

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
G2 SurfaceLodSelector (representation only)
        ↓
G6.4 replaceable derived presentation
```

Required invariants:

```text
FluidRegion != SurfaceCell
FluidRegion != AuthorityRegion
FluidRegion != InterestRegion
FluidRegion != renderer object
Fluid identity != LOD / quality / observer state
query/index/cache != canonical identity
visual width != canonical channel width
G5 River FeatureId remains semantic owner
```

## Fix2 reason and boundary

First graphical G6.4 run proved ribbon/seam/query presentation but exposed a static fixed-density representation (`97 samples`). Fix2 therefore reuses accepted G2 LOD rather than adding a private hydrology LOD system.

```text
observer -> BodyFixedPosition -> SurfaceLodSelector
         -> adaptive SurfaceCellKey leaf cover
         -> river representation_lod
         -> adaptive visual sample density
```

The following stay stable across refine/coarsen:

```text
FeatureId
FluidRegionId
RiverSpline
WaterSurfaceQuery semantics
```

## GLOBAL-P0 synchronization

The checkpoint remains on `GLOBAL-P0-2026-08-08-R1`. G6 is currently not behind `feature/g5-world-feature-graph`. Before full G6 acceptance, main/G5/shared baseline must be checked again for the MW10 integration or a newer global revision.

## P0-2 Spatial Domain Fabric

G6.2 already proved canonical river continuity through `PX/PZ` and LOD `2 / 4 / 8 / 12`. G6.4 fix2 now consumes G2 addressing/LOD only for derived representation.

Forbidden inversion remains:

```text
SurfaceCellKey / cube face / selected LOD
        X
        ↓
FeatureId / FluidRegionId
```

## P0-3 / P0-4 / P0-5

G6.4 does not create material ontology, authority, persistence, network transport or world mutation. It is read-only presentation. Future NX8 may choose which representation segments are interesting to a client, but `interest region != FluidRegionId` and `client visibility != river existence`.

## Accepted foundation

```text
G6.1 CasualRiverProviderV1             ACCEPTED — 74 assertions
G6.2 cross-cell/cross-LOD continuity   ACCEPTED — 86 assertions
G6.3 runtime WaterSurfaceQuery         ACCEPTED — 79 assertions
```

## Fix2 visual proof

Scene:

```text
res://scenes/labs/procedural/g6_4_casual_visual_river_lab.tscn
```

Visual/HUD additions:

```text
adaptive SurfaceCellKey LOD grid
Virtual altitude
Leaf count
Max LOD
River sample count
River representation LOD range
```

Headless proof must require:

```text
near max_lod > far max_lod
near planned_river_samples > far planned_river_samples
near selection_hash != far selection_hash
```

## Merge / composition gate

```text
[PASS] GLOBAL-P0-2026-08-08-R1 checkpoint
[PASS] Feature != SurfaceCell
[PASS] FluidRegion != SurfaceCell / AuthorityRegion / InterestRegion
[PASS] G6.1 Windows acceptance — 74 assertions
[PASS] G6.2 Windows continuity acceptance — 86 assertions
[PASS] G6.3 Windows runtime query acceptance — 79 assertions
[PASS] G6.4 fix2 changes representation only
[PENDING WINDOWS] G6.4 fix2 source/headless adaptive LOD gate
[PENDING MANUAL] G6.4 graphical refine/coarsen observation
[PENDING FULL G6] fresh main + G5/shared-baseline sync check, then full world/core regression
```