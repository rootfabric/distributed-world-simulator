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
G6.4 Casual Visual River Lab           FIX2 IMPLEMENTED CANDIDATE
G6 Full Acceptance                     NEXT AFTER G6.4 ACCEPTANCE
```

G6.4 fix2 functional head:

```text
353a73f08f6d07840145e61f79b197e5773a73a2
```

Accepted tested heads:

```text
G6.1 b8f36d17dc8ba138e6b215968aa0e651eec9ccd1
G6.2 444811c0ac98a133844cd7ec0869a6cf0a261f11
G6.3 974fc6682abac058ea158cf11efbf44501805817
```

## G6.4 Casual Visual River Lab — fix2 candidate

Первый graphical run подтвердил derived ribbon/centerline/banks/query probes и `PX/PZ` seam, но выявил design gap: visual river была статической полосой с `97 samples`, без observer-driven LOD. Поэтому G6.4 не принят.

Fix2 подключает уже принятый G2 representation pipeline:

```text
canonical G6 river
        ↓
G2 SurfaceLodSelector
        ↓
adaptive SurfaceCellKey leaf cover
        ↓
local river representation LOD
        ↓
adaptive ribbon sample density + LOD grid
```

Canonical `FeatureId`, `FluidRegionId`, `RiverSpline` и query semantics от LOD не зависят.

Scene:

```text
res://scenes/labs/procedural/g6_4_casual_visual_river_lab.tscn
```

Теперь lab показывает:

```text
water ribbon
canonical centerline
bank guides
query normal / flow probes
PX/PZ seam marker
rainbow active SurfaceCellKey LOD grid
HUD: virtual altitude / leaves / max LOD / river samples / river LOD range
```

Controls:

```text
A/D orbit
Q/E pitch
W/S zoom + refine/coarsen
Space auto-orbit
R reset
1 water
2 centerline
3 banks
4 query probes
5 seam markers
6 LOD grid
```

Automated gate:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_4_CASUAL_VISUAL_RIVER_LAB_TESTS.ps1
```

Headless fix2 proof requires:

```text
near max LOD > far max LOD
near river sample count > far river sample count
near selection hash != far selection hash
explicit PASS marker with max_lod and river_lod range
```

Manual launch after automated PASS:

```powershell
.\START_G6_4_VISUAL_RIVER_LAB.ps1
```

G6.4 remains `FIX2 IMPLEMENTED CANDIDATE` until both the automated Windows gate and graphical refine/coarsen observation pass.

## Synchronization / shared baseline

`GLOBAL-P0-2026-08-08-R1` remains the checkpoint revision. G6 is currently not behind `feature/g5-world-feature-graph`. Before full G6 acceptance, main/G5/shared baseline is checked again for the MW10 integration or newer global revision.

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
SurfaceLodSelector changes representation only
spatial location != authority route
canonical truth != representation
```