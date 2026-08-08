# G6.4 — Casual Visual River Lab — FIX2 IMPLEMENTED CANDIDATE

**Дата:** 2026-08-09
**Ветка:** `feature/g6-hydrology-fluid-surface-v0`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Dependencies:** `G2 / G6.0 / G6.1 / G6.2 / G6.3 — ACCEPTED`
**Fix2 functional head:** `353a73f08f6d07840145e61f79b197e5773a73a2`
**Решение:** `FIX2 IMPLEMENTED CANDIDATE — WINDOWS AUTOMATED + GRAPHICAL ADAPTIVE-LOD ACCEPTANCE REQUIRED`

## Почему понадобился fix2

Первый graphical run подтвердил, что lab реально показывает water ribbon, canonical centerline, bank guides, query probes и `PX/PZ` seam. Наблюдалось `97 samples`, `7 query probes`, `1 seam transition`, `PX / PZ`.

Но визуальная река была статической полосой: observer distance не менял representation density, не было активного LOD cover. Поэтому G6.4 не принят.

## Fix2

```text
canonical G6 river
        ↓
BodyFixedPosition(observer)
        ↓
SurfaceLodSelector
        ↓
adaptive SurfaceCellKey leaves
        ↓
representation LOD per river segment
        ↓
adaptive ribbon sample density
```

Canonical invariants:

```text
FeatureId       unchanged by LOD
FluidRegionId   unchanged by LOD
RiverSpline     unchanged by LOD
query semantics unchanged by LOD
```

Scene:

```text
res://scenes/labs/procedural/g6_4_casual_visual_river_lab.tscn
```

Visual layers:

```text
blue ribbon       derived water representation
yellow line       canonical centerline
brown lines       bank guides
red/green         query normal / flow
magenta           PX/PZ seam
rainbow grid      active SurfaceCellKey LOD cover
```

HUD:

```text
Virtual altitude
Leaves / leaf budget
Max LOD
River samples
River representation LOD min..max
FeatureId
FluidRegionId
```

Controls:

```text
A / D      orbit
Q / E      pitch
W / S      zoom + refine/coarsen
Space      auto-orbit
R          reset
1          water ribbon
2          centerline
3          bank guides
4          query probes
5          seam marker
6          LOD grid
```

## Automated proof

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_4_CASUAL_VISUAL_RIVER_LAB_TESTS.ps1
```

Headless scene smoke must prove:

```text
near.max_lod > far.max_lod
near.planned_river_samples > far.planned_river_samples
near.selection_hash != far.selection_hash
```

Runner requires explicit marker:

```text
G6.4 Casual Visual River Lab: PASS (... max_lod=... river_lod=.....)
```

Parse/load error cannot count as PASS.

## Manual graphical acceptance

After automated PASS:

```powershell
.\START_G6_4_VISUAL_RIVER_LAB.ps1
```

Verify:

```text
LOD grid visible
W -> nearby cells refine
W -> Max LOD grows
W -> River samples grows
S -> cells coarsen
S -> River samples shrinks
FeatureId stable
FluidRegionId stable
river continuous across PX/PZ
centerline/banks/probes remain aligned
```

## Architecture boundary

Allowed:

```text
SurfaceLodSelector -> representation choice
SurfaceCellKey -> visual addressing
LOD -> mesh/sample density
```

Forbidden:

```text
LOD -> FeatureId
LOD -> FluidRegionId
SurfaceCellKey -> canonical river owner
renderer mesh -> canonical fluid truth
```

## Decision

```text
G6.4 = FIX2 IMPLEMENTED CANDIDATE
```

After green automated + graphical gate:

```text
G6.4 = ACCEPTED
next = G6 FULL ACCEPTANCE
```

Before full G6 acceptance a fresh main/G5/GLOBAL-P0/shared-baseline sync check remains mandatory.