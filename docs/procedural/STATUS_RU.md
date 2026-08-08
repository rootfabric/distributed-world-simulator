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
G6.4 Casual Visual River Lab           IMPLEMENTED CANDIDATE
G6 Full Acceptance                     NEXT AFTER G6.4 ACCEPTANCE
```

Accepted tested heads:

```text
G6.1 b8f36d17dc8ba138e6b215968aa0e651eec9ccd1
G6.2 444811c0ac98a133844cd7ec0869a6cf0a261f11
G6.3 974fc6682abac058ea158cf11efbf44501805817
```

Current G6.4 record:

```text
docs/checkpoints/G6_4_CASUAL_VISUAL_RIVER_LAB_CANDIDATE_RU.md
validation/g6-4-casual-visual-river-lab-validation.json
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

## G6.4 Casual Visual River Lab — candidate

G6.4 is the first manual visual hydrology checkpoint.

Scene:

```text
res://scenes/labs/procedural/g6_4_casual_visual_river_lab.tscn
```

Presentation flow:

```text
accepted G6.1 canonical geography
        ↓
accepted G6.3 WaterSurfaceQuery / WaterSurfaceSample
        ↓
replaceable G6.4 presentation
```

The lab renders a planet-scale globe and the accepted G6.2 seam-river with:

```text
water ribbon
canonical centerline debug
bank guides
query normal / flow probes
PX/PZ cube-face transition marker
```

Water/bank widths are deliberately exaggerated only in display space so the kilometer-scale river is visible on an 8-unit globe. Canonical width/depth/bank values remain those returned by `WaterSurfaceSample`.

Controls:

```text
A/D orbit
Q/E pitch
W/S zoom
Space auto-orbit
R reset
1 water
2 centerline
3 banks
4 query probes
5 seam markers
```

Automated gate:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_4_CASUAL_VISUAL_RIVER_LAB_TESTS.ps1
```

Manual launch after automated PASS:

```powershell
.\START_G6_4_VISUAL_RIVER_LAB.ps1
```

G6.4 remains `IMPLEMENTED CANDIDATE` until both the automated Windows gate and manual graphical observation pass.

## Synchronization / shared baseline

`main` still uses `GLOBAL-P0-2026-08-08-R1` at G6.4 implementation start.

A fresh shared-baseline PR #43 exists for MW10 atomic lock release on G5. It is currently open and is not a G6.4 dependency. Before full G6 acceptance the G5/main/shared baseline must be checked again and G6 synchronized if that fix or a newer global revision has landed.

## Next after G6.4 acceptance

```text
G6 FULL ACCEPTANCE
  -> fresh main/G5/GLOBAL-P0 sync check
  -> full world/core regression
  -> G6 composition/freeze review
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
visual mesh != canonical truth
visual width != canonical channel width
spatial location != authority route
canonical truth != representation
```
