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

## Why fix2 exists

Первый graphical G6.4 run подтвердил ribbon/seam/query presentation, но показал, что visual river оставалась статической полосой (`97 samples`) и не реагировала на observer distance. Это было недостаточно для visual proof уже принятой G2/G6.2 LOD doctrine.

Fix2 подключает accepted G2 representation path вместо декоративного distance switch:

```text
observer position
        ↓
BodyFixedPosition
        ↓
SurfaceLodSelector
        ↓
adaptive SurfaceCellKey leaf cover
        ↓
representation_lod per river segment
        ↓
adaptive sample density / LOD grid
```

При этом:

```text
FeatureId unchanged
FluidRegionId unchanged
RiverSpline unchanged
WaterSurfaceSample semantics unchanged
```

## GLOBAL-P0 synchronization

At G6.4 implementation start `main` still reports:

```text
global_revision = GLOBAL-P0-2026-08-08-R1
```

G6 carries the same global revision/config. The branch does not edit the canonical global plan locally.

G6 is currently not behind `feature/g5-world-feature-graph`. Before full G6 acceptance, G5/main/shared baseline must be checked again and G6 synchronized if the MW10 integration or a newer global revision has landed.

## P0-2 Spatial Domain Fabric

G6.2 already proved canonical river continuity through `PX/PZ` and LOD `2 / 4 / 8 / 12`.

G6.4 fix2 now consumes G2 addressing/LOD for **derived representation**:

```text
canonical river
        ↓
SurfaceLodSelector + CubeSphereAddressing
        ↓
visual leaf cover / ribbon density
```

Forbidden inversion remains:

```text
SurfaceCellKey / cube face / selected LOD
        X
        ↓
FeatureId / FluidRegionId
```

Thus the visual representation may refine/coarsen while canonical river truth remains stable.

## P0-3 Unified Material Ontology

G6 still uses `FluidType` as baseline fluid vocabulary. G6.4 may create Godot `StandardMaterial3D` resources, but shader/material resource identity is never canonical fluid identity.

## P0-4 Cross-Domain World Transaction Model

G6.4 remains read-only presentation:

```text
canonical/query truth -> adaptive mesh/debug presentation
```

It does not commit fluid, Matter, Item or Construction mutations.

## P0-5 NX7 / NX8 / NX9

G6.4 creates no authority registry, network transport or persistence layer. Future NX8 may choose which river representation cells/segments are interesting to a client, but:

```text
interest region != FluidRegionId
selected LOD != FluidRegionId
ribbon patch != FluidRegionId
client visibility != river existence
```

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

## G6.4 fix2 visual boundary

Scene:

```text
res://scenes/labs/procedural/g6_4_casual_visual_river_lab.tscn
```

Visual layers:

```text
water ribbon
canonical centerline
bank guides
query normal/flow probes
PX/PZ seam marker
adaptive SurfaceCellKey LOD grid
HUD: virtual altitude / leaf count / max LOD / river sample count / river LOD range
```

Headless fix2 proof must compare a far and near observer and require:

```text
near max_lod > far max_lod
near planned_river_samples > far planned_river_samples
near selection_hash != far selection_hash
```

This verifies representation adaptation without changing canonical identities.

## Stop conditions

Global architecture review is required if G6 needs any of:

- permanent river identity from `SurfaceCellKey`;
- private fluid authority registry;
- private global material ontology;
- query cache/index as canonical state;
- visual mesh as canonical truth;
- camera/LOD-dependent canonical identity;
- durable mutation in procedural cache only;
- cross-domain mutation through best-effort RPC chains.

## Merge / composition gate

```text
[PASS] GLOBAL-P0-2026-08-08-R1 matched main at G6.4 implementation start
[PASS] Feature != SurfaceCell
[PASS] FluidRegion != SurfaceCell / AuthorityRegion / InterestRegion
[PASS] G6.1 Windows acceptance — 74 assertions
[PASS] G6.2 Windows continuity acceptance — 86 assertions
[PASS] G6.3 Windows runtime query acceptance — 79 assertions
[PASS] G6.4 fix2 does not modify accepted G6.0–G6.3 production semantics
[PENDING WINDOWS] G6.4 fix2 source/headless adaptive LOD gate
[PENDING MANUAL] G6.4 graphical refine/coarsen observation
[PENDING FULL G6] fresh main + G5/shared-baseline sync check, then full world/core regression
```