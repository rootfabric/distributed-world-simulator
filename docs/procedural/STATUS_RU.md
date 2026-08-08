# Universal World Generation Fabric — status ledger

**Current branch:** `feature/g6-hydrology-fluid-surface-v0`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`

```text
G6.0 Fluid Contracts                   ACCEPTED
G6.1 CasualRiverProviderV1             ACCEPTED
G6.2 Cross-Cell / Cross-LOD Continuity ACCEPTED
G6.3 Runtime WaterSurfaceQuery         ACCEPTED
G6.4 Casual Visual River Lab           FIX4 IMPLEMENTED CANDIDATE
```

Fix3 automated Windows gate passed on `3a5427fb1ccdad8e2a63650c5c253a0ac1fcf298`: G2 selection refined from far LOD 1 to near LOD 9 and G3 surface triangles from 120 to 4176. The manual run reached LOD 10, but additional terrain detail remained visually inconclusive because the Fix3 lab recipe used only four G3 octaves: `600 / 300 / 150 / 75 km` wavelengths.

Fix4 keeps the accepted G3 provider unchanged and changes only the visual-lab recipe:

```text
G3 base wavelength      600 km
G3 octave count         8
G3 persistence          0.58
minimum source signal   ~4.7 km
```

This lets increasing G2 LOD expose genuinely new height-field frequencies instead of only adding triangles over a ~75 km-limited field.

Standalone G6.4 launches now set `BREAKPOINT_RUNTIME_DISABLED=1`, because the visual lab does not require the MCP runtime bridge and must not fail when `127.0.0.1:9081` is already occupied.

Run:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_4_CASUAL_VISUAL_RIVER_LAB_TESTS.ps1
.\START_G6_4_VISUAL_RIVER_LAB.ps1
```

Manual acceptance requires visible higher-frequency macro detail during `W` refine, coarsening on `S`, stable FeatureId/FluidRegionId, and continuous PX/PZ river presentation.

River-valley carving remains deferred to G8 Geomorphology. Next after G6.4 acceptance: G6 full sync/regression gate, then G7 Semantic Field Fabric.