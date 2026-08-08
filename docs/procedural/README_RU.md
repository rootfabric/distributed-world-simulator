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
G6.4 FIX3 IMPLEMENTED CANDIDATE
```

G6.4 now proves three separate representation layers without moving canonical truth into rendering:

```text
G2 SurfaceLodSelector
        -> adaptive SurfaceCellKey cover

G3 CasualMacroTerrainProviderV1
        -> adaptive macro terrain mesh

G6 canonical river + WaterSurfaceQuery
        -> adaptive derived water ribbon
```

The previous fix2 manual run proved that the LOD grid refined, but the fixed sphere did not gain new visible detail. Fix3 hides that fixed sphere and rebuilds the visible surface from G2 leaves using G3 body-fixed macro-height samples. Near views therefore contain more actual terrain triangles and expose more sampled relief.

Run:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_4_CASUAL_VISUAL_RIVER_LAB_TESTS.ps1
.\START_G6_4_VISUAL_RIVER_LAB.ps1
```

Manual expectation: `W` must not only shrink the LOD grid but also visibly refine the macro surface itself. River valley carving is not part of G6.4 and remains scheduled for G8 Geomorphology.

Canonical detail:

```text
FeatureId / FluidRegionId / RiverSpline / G3 height samples
```

Derived presentation detail:

```text
SurfaceCellKey cover / terrain triangles / ribbon tessellation / debug grid
```

Global revision: `GLOBAL-P0-2026-08-08-R1`.
