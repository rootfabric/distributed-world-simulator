# G6.4 — Casual Visual River Lab — FIX2 IMPLEMENTED CANDIDATE

**Дата:** 2026-08-09
**Ветка:** `feature/g6-hydrology-fluid-surface-v0`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Fix2 functional head:** `353a73f08f6d07840145e61f79b197e5773a73a2`

Первый graphical run показал рабочую river ribbon и PX/PZ seam, но representation была статической (`97 samples`) и не имела observer-driven LOD. Поэтому G6.4 не принят.

Fix2 использует accepted G2 LOD pipeline:

```text
observer -> BodyFixedPosition -> SurfaceLodSelector
         -> adaptive SurfaceCellKey leaves
         -> river representation LOD
         -> adaptive ribbon sample density
```

HUD: `Virtual altitude`, `Leaves`, `Max LOD`, `River samples`, `River representation LOD`.

Controls: `W/S` refine/coarsen, `A/D` orbit, `Q/E` pitch, `1..5` debug layers, `6` LOD grid.

Automated gate:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_4_CASUAL_VISUAL_RIVER_LAB_TESTS.ps1
```

It must prove:

```text
near.max_lod > far.max_lod
near.planned_river_samples > far.planned_river_samples
near.selection_hash != far.selection_hash
```

Manual acceptance must confirm visible refine/coarsen while FeatureId and FluidRegionId stay stable and the river remains continuous across PX/PZ.

Until both gates pass:

```text
G6.4 = FIX2 IMPLEMENTED CANDIDATE
```

Next after acceptance: `G6 FULL ACCEPTANCE`, including fresh main/G5/GLOBAL-P0/shared-baseline sync check.