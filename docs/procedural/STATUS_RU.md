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

Fix2 reuses accepted G2 `SurfaceLodSelector` to drive adaptive SurfaceCellKey leaves, LOD grid and river sample density. The first graphical run's static `97 samples` result is explicitly rejected as insufficient for G6.4 acceptance.

Automated gate:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_4_CASUAL_VISUAL_RIVER_LAB_TESTS.ps1
```

Manual launch after automated PASS:

```powershell
.\START_G6_4_VISUAL_RIVER_LAB.ps1
```

Required manual proof: LOD grid visible; W increases Max LOD and River samples; S coarsens them; FeatureId/FluidRegionId remain stable; PX/PZ stays continuous.

After G6.4: fresh main/G5/GLOBAL-P0/shared-baseline check, full G6 regression, then G7 Semantic Field Fabric.