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

The first graphical lab proved ribbon/seam/query presentation but exposed a static 97-sample representation. Fix2 now uses the accepted G2 `SurfaceLodSelector` so observer distance changes the active SurfaceCellKey cover and river sample density while FeatureId / FluidRegionId / RiverSpline remain stable.

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

HUD shows `Virtual altitude`, `Leaves`, `Max LOD`, `River samples`, and `River representation LOD range`.

Automated gate:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_4_CASUAL_VISUAL_RIVER_LAB_TESTS.ps1
```

After automated PASS:

```powershell
.\START_G6_4_VISUAL_RIVER_LAB.ps1
```

Acceptance requires visible refine/coarsen plus stable canonical IDs. After G6.4: fresh main/G5/GLOBAL-P0/shared-baseline check, full G6 regression, then G7 Semantic Field Fabric.