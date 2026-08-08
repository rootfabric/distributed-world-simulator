# G6 Hydrology / Fluid Surface v0 — P0 alignment

**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Branch:** `feature/g6-hydrology-fluid-surface-v0`
**Local role:** hydrology/fluid semantic, query and derived-presentation layer above G5 World Feature Graph
**Current stage:** `G6.4 Casual Visual River Lab — IMPLEMENTED CANDIDATE`
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

## GLOBAL-P0 synchronization

At G6.4 implementation start `main` still reports:

```text
global_revision = GLOBAL-P0-2026-08-08-R1
```

G6 carries the same global revision/config. The branch does not edit the canonical global plan locally.

The global ledger was created before the active G6 line and still does not enumerate G6 in `active_sync_branches`. This does not block isolated source development while byte/revision alignment remains valid, but full G6 acceptance requires a fresh main/global check.

A second fresh shared-baseline condition is now explicit: PR #43 carries the independently validated MW10 atomic-lock fix onto the shared G5 baseline. At G6.4 implementation time it is still open. G6.4 is presentation-only and does not depend on Matter, so it may proceed; **full G6 acceptance must re-check G5 and synchronize G6 if that shared-baseline fix (or its equivalent) lands.**

## P0-2 Spatial Domain Fabric

G6.2 already proved canonical river continuity through `PX/PZ` and LOD `2 / 4 / 8 / 12`.

G6.4 is allowed to call `CubeSphereAddressing` only to display/debug the seam. It must not convert cube face/cell into river/fluid identity.

```text
canonical river
        ↓
G2 addressing for debug presentation

NOT:
SurfaceCellKey / cube face -> FluidRegionId
```

Future `WorldAddress` can accelerate candidate discovery without replacing `FeatureId` or `FluidRegionId`.

## P0-3 Unified Material Ontology

G6 still uses `FluidType` as baseline fluid vocabulary. G6.4 may create Godot `StandardMaterial3D` presentation resources, but shader/material resource identity is not `MaterialDefinitionId` and is never canonical fluid identity.

## P0-4 Cross-Domain World Transaction Model

G6.4 is read-only presentation:

```text
canonical/query truth -> mesh/debug presentation
```

It does not commit fluid, Matter, Item or Construction mutations. Future pumping/freezing/flooding/excavation must use the common durable world-operation path.

## P0-5 NX7 / NX8 / NX9

G6.4 creates no authority registry, network transport or persistence layer.

NX8 may later select which river visual segments/query results are worth sending/rendering, but:

```text
interest region != FluidRegionId
LOD/ribbon/mesh patch != FluidRegionId
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

## G6.4 implemented boundary

Scene:

```text
res://scenes/labs/procedural/g6_4_casual_visual_river_lab.tscn
```

Presentation consumes accepted data through:

```text
CasualRiverProviderV1.compile(...)
WaterSurfaceQuery.create(...)
WaterSurfaceResolverV1.resolve(...)
WaterSurfaceSample
```

Visual layers:

```text
water ribbon
canonical centerline
bank guides
query normal/flow probes
PX/PZ seam marker
planet globe
```

Presentation width is explicitly exaggerated for visibility on the globe. Exaggeration factors are display configuration only and must never feed canonical contracts/query results.

G6.4 must not derive a new `FeatureId`, `FluidRegionId`, `SurfaceCellKey` ownership model or renderer-local river truth.

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
[PASS] G6.4 does not modify accepted G6.0–G6.3 production semantics
[PENDING WINDOWS] G6.4 automated headless/source gate
[PENDING MANUAL] G6.4 graphical observation
[PENDING FULL G6] fresh main + G5/shared-baseline sync check, then full world/core regression
```
