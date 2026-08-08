# Universal World Generation Fabric — status ledger

**Current branch:** `feature/g6-hydrology-fluid-surface-v0`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`

```text
G6.0 Fluid Contracts                   ACCEPTED
G6.1 CasualRiverProviderV1             ACCEPTED
G6.2 Cross-Cell / Cross-LOD Continuity ACCEPTED
G6.3 Runtime WaterSurfaceQuery         ACCEPTED
G6.4 Casual Visual River Lab           FIX3 IMPLEMENTED CANDIDATE
```

Fix2 automated evidence passed (`104 assertions` + scene smoke), and the manual run proved that G2 cell refinement works. It also exposed that selection detail alone is insufficient: the fixed sphere and resampled spline did not reveal new visible geometry.

Fix3 composes accepted G2 + G3 into the lab:

```text
G2 SurfaceLodSelector
        ↓
adaptive SurfaceCellKey leaves
        ↓
G3 CasualMacroTerrainProviderV1
        ↓
real adaptive macro-surface triangles
```

The fixed `SphereMesh` is hidden. The visible surface is rebuilt from selected leaves; newly introduced vertices sample canonical G3 `geo/surface-height-m`. A display-only x40 height exaggeration makes the 900 m macro relief readable on the 8-unit debug globe.

The river remains accepted G6 canonical/query truth rendered as a derived ribbon. Terrain carving by hydrology is intentionally deferred to G8 Geomorphology.

Automated gate:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_4_CASUAL_VISUAL_RIVER_LAB_TESTS.ps1
```

The gate now requires both runtime markers:

```text
G6.4 Adaptive Macro Surface: PASS (... far_triangles=... near_triangles=...)
G6.4 Casual Visual River Lab: PASS (...)
```

Manual gate:

```powershell
.\START_G6_4_VISUAL_RIVER_LAB.ps1
```

Use `W/S` to refine/coarsen. Acceptance now requires visible macro-surface geometry/relief refinement, not only a finer debug grid.

Next after G6.4: G6 full sync/regression acceptance, then G7 Semantic Field Fabric.
