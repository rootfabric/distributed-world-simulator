# Universal World Generation Fabric — status ledger

**Current branch:** `feature/g6-hydrology-fluid-surface-v0`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`

```text
G6.0 Fluid Contracts                   ACCEPTED
G6.1 CasualRiverProviderV1             ACCEPTED
G6.2 Cross-Cell / Cross-LOD Continuity ACCEPTED
G6.3 Runtime WaterSurfaceQuery         ACCEPTED
G6.4 Casual Visual River Lab           FIX2 IMPLEMENTED CANDIDATE
```

Fix2 functional head:

```text
353a73f08f6d07840145e61f79b197e5773a73a2
```

The first graphical lab rendered the river but exposed a static 97-sample representation. Fix2 reuses accepted G2 `SurfaceLodSelector` for observer-driven SurfaceCellKey refinement, an adaptive LOD grid, and adaptive river sample density. Canonical FeatureId/FluidRegionId remain independent of LOD.

Automated gate:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_4_CASUAL_VISUAL_RIVER_LAB_TESTS.ps1
```

Manual gate:

```powershell
.\START_G6_4_VISUAL_RIVER_LAB.ps1
```

Use `W/S` to refine/coarsen, `6` to toggle the LOD grid, and watch `Max LOD` + `River samples` in HUD. G6.4 remains unaccepted until both gates pass.

Next: G6 full sync/regression acceptance, then G7 Semantic Field Fabric.