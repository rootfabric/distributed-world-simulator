# Universal World Generation Fabric — entrypoint

Current branch:

```text
feature/g6-hydrology-fluid-surface-v0
```

Status:

```text
G6.0 ACCEPTED
G6.1 ACCEPTED
G6.2 ACCEPTED
G6.3 ACCEPTED
G6.4 FIX2 IMPLEMENTED CANDIDATE
```

G6.4 fix2 functional head:

```text
353a73f08f6d07840145e61f79b197e5773a73a2
```

Fix2 exists because the first graphical river lab rendered correctly but remained a static `97 samples` strip. It now reuses accepted G2 `SurfaceLodSelector` for observer-driven SurfaceCellKey refinement and adaptive river representation density.

Run:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_4_CASUAL_VISUAL_RIVER_LAB_TESTS.ps1
```

Then:

```powershell
.\START_G6_4_VISUAL_RIVER_LAB.ps1
```

Use `W/S` to refine/coarsen and `6` for the LOD grid. Watch `Max LOD` and `River samples` in HUD. FeatureId and FluidRegionId must stay stable.

After G6.4 acceptance: full G6 sync/regression gate, then G7 Semantic Field Fabric.