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
G6.3 ACCEPTED
G6.4 FIX2 IMPLEMENTED CANDIDATE — adaptive visual river LOD
G6 FULL ACCEPTANCE NEXT after G6.4
```

G6.4 fix2 functional head:

```text
353a73f08f6d07840145e61f79b197e5773a73a2
```

Global revision:

```text
GLOBAL-P0-2026-08-08-R1
```

Start here:

1. `docs/procedural/STATUS_RU.md`
2. `docs/checkpoints/G6_4_CASUAL_VISUAL_RIVER_LAB_CANDIDATE_RU.md`
3. `validation/g6-4-casual-visual-river-lab-validation.json`
4. `docs/checkpoints/G6_3_RUNTIME_WATER_SURFACE_QUERY_ACCEPTED_RU.md`
5. `docs/checkpoints/G6_2_CROSS_CELL_CROSS_LOD_CONTINUITY_ACCEPTED_RU.md`
6. `docs/checkpoints/G6_1_CASUAL_RIVER_PROVIDER_ACCEPTED_RU.md`
7. `docs/procedural/G6_P0_ALIGNMENT_RU.md`

## Current architecture

```text
G5 canonical River FeatureId
        ↓
G6.1 canonical river geography
        ↓
G6.2 cell/LOD identity continuity proof
        ↓
G6.3 runtime WaterSurfaceQuery
        ↓
G2 SurfaceLodSelector (representation only)
        ↓
G6.4 adaptive visual river lab
```

## Why G6.4 fix2

Первый graphical run показал рабочую river ribbon, centerline, banks, query probes и `PX/PZ` seam, но representation оставалась статической полосой с фиксированными `97 samples`.

Fix2 использует accepted G2 LOD pipeline:

```text
observer
  -> BodyFixedPosition
  -> SurfaceLodSelector
  -> active SurfaceCellKey leaves
  -> river representation LOD
  -> adaptive ribbon sample density
```

Scene:

```text
res://scenes/labs/procedural/g6_4_casual_visual_river_lab.tscn
```

Controls:

```text
W/S zoom + refine/coarsen
A/D orbit
Q/E pitch
Space auto-orbit
R reset
1 water
2 centerline
3 banks
4 probes
5 seam
6 LOD grid
```

HUD shows:

```text
Virtual altitude
Leaves
Max LOD
River samples
River representation LOD range
```

Canonical identity remains independent of representation:

```text
FeatureId unchanged
FluidRegionId unchanged
RiverSpline unchanged
WaterSurfaceQuery semantics unchanged
```

Automated gate:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_4_CASUAL_VISUAL_RIVER_LAB_TESTS.ps1
```

After automated PASS:

```powershell
.\START_G6_4_VISUAL_RIVER_LAB.ps1
```

Acceptance requires visible refine/coarsen: near observer must produce higher `Max LOD` and more river samples than far observer while FeatureId and FluidRegionId stay stable.

After G6.4:

```text
G6 FULL ACCEPTANCE
  -> fresh main/G5/GLOBAL-P0/shared-baseline check
  -> full world/core regression
  -> G7 Semantic Field Fabric
```

## Detail doctrine

```text
BASE FIRST
BEAUTY SECOND
```

Photoreal water/foam/shoreline is still deferred; this lab proves canonical continuity plus adaptive replaceable representation.