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

## G6.4 Casual Visual River Lab — fix2 candidate

Первый graphical run подтвердил, что derived ribbon, centerline, banks, query probes и PX/PZ seam визуально работают, но выявил design gap: representation была статической — `97 samples`, без observer-driven LOD. Поэтому G6.4 не принят и получил fix2.

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

Canonical `FeatureId`, `FluidRegionId`, `RiverSpline` и `WaterSurfaceSample` от LOD не зависят.

Scene:

```text
res://scenes/labs/procedural/g6_4_casual_visual_river_lab.tscn
```

Теперь lab показывает:

```text
water ribbon
canonical centerline debug
bank guides
query normal / flow probes
PX/PZ cube-face transition marker
rainbow active SurfaceCellKey LOD grid
HUD: virtual altitude / leaves / max LOD / river samples / river LOD range
```

`W/S` теперь не только меняет zoom: virtual observer проходит через реальный `SurfaceLodSelector`, поэтому при приближении leaf cover дробится, `Max LOD` растёт и river sample density увеличивается. При удалении representation coarsen-ится.

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

Headless smoke теперь дополнительно обязан доказать:

```text
near max LOD > far max LOD
near river sample count > far river sample count
near selection hash != far selection hash
```

Manual launch after automated PASS:

```powershell
.\START_G6_4_VISUAL_RIVER_LAB.ps1
```

G6.4 остаётся `FIX2 IMPLEMENTED CANDIDATE`, пока automated Windows gate и повторная graphical LOD-проверка не пройдут.

## Synchronization / shared baseline

`main` всё ещё использует `GLOBAL-P0-2026-08-08-R1` для этого checkpoint. Shared-baseline MW10 integration не является зависимостью visual lab; перед full G6 acceptance G5/main/shared baseline проверяется заново.

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