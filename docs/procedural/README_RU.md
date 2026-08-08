# Universal World Generation Fabric — entrypoint

Current implementation branch:

```text
feature/g6-hydrology-fluid-surface-v0
```

Current state:

```text
G6.0 ACCEPTED
G6.1 ACCEPTED
G6.2 ACCEPTED
G6.3 ACCEPTED
G6.4 FIX4 IMPLEMENTED CANDIDATE
```

Fix3 Windows automated gate passed on `3a5427fb1ccdad8e2a63650c5c253a0ac1fcf298`, but the manual close-up remained visually inconclusive because the visual G3 recipe contained only four octaves and therefore no source frequencies below roughly 75 km.

Fix4 keeps accepted G3 provider code unchanged and changes only the debug recipe:

```text
600 km base wavelength
8 octaves
0.58 persistence
~4.7 km minimum source wavelength
```

The lab still composes three independent representation layers:

```text
G2 SurfaceLodSelector
        -> adaptive SurfaceCellKey cover

accepted G3 CasualMacroTerrainProviderV1
        -> adaptive macro terrain mesh + higher-frequency lab recipe

accepted G6 canonical river + WaterSurfaceQuery
        -> adaptive derived water ribbon
```

Standalone G6.4 runs temporarily set `BREAKPOINT_RUNTIME_DISABLED=1`, so the unrelated MCP runtime bridge cannot fail the visual lab because port `127.0.0.1:9081` is occupied.

Run:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_4_CASUAL_VISUAL_RIVER_LAB_TESTS.ps1
.\START_G6_4_VISUAL_RIVER_LAB.ps1
```

Manual expectation: `W` shrinks the LOD grid and must reveal genuinely new macro-height structure; `S` coarsens it. FeatureId and FluidRegionId must stay stable. River valley carving is not part of G6.4 and remains scheduled for G8 Geomorphology.

Global revision: `GLOBAL-P0-2026-08-08-R1`.