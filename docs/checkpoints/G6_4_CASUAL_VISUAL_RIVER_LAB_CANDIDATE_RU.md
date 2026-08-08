# G6.4 — Casual Visual River Lab — FIX2 IMPLEMENTED CANDIDATE

**Дата:** 2026-08-09
**Ветка:** `feature/g6-hydrology-fluid-surface-v0`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Dependencies:** `G2 / G6.0 / G6.1 / G6.2 / G6.3 — ACCEPTED`
**Fix2 functional head:** `353a73f08f6d07840145e61f79b197e5773a73a2`
**Решение:** `FIX2 IMPLEMENTED CANDIDATE — WINDOWS AUTOMATED + GRAPHICAL ADAPTIVE-LOD ACCEPTANCE REQUIRED`

## Почему понадобился fix2

Первый graphical run подтвердил, что lab реально показывает:

```text
water ribbon
canonical centerline
bank guides
query probes
PX/PZ seam
```

Наблюдалось:

```text
samples: 97
query probes: 7
seam transitions: 1
faces: PX / PZ
```

Но визуальная река была статической полосой: observer distance не менял representation density, не было активного LOD cover. Поэтому G6.4 не принят.

## Fix2

Fix2 использует уже принятый G2 LOD pipeline:

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

Это именно representation LOD, а не новый river generator.

Canonical invariants:

```text
FeatureId       unchanged by LOD
FluidRegionId   unchanged by LOD
RiverSpline     unchanged by LOD
query semantics unchanged by LOD
```

## Visual additions

Scene:

```text
res://scenes/labs/procedural/g6_4_casual_visual_river_lab.tscn
```

Теперь показывает:

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

При `W` observer приближается к поверхности: G2 leaf cover refine-ится, `Max LOD` и river sample density должны расти. При `S` representation coarsen-ится.

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

Runner:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_4_CASUAL_VISUAL_RIVER_LAB_TESTS.ps1
```

Fix2 source gate требует использование:

```text
SurfaceLodPolicy
SurfaceLodSelector
BodyFixedPosition
adaptive river representation_lod
SurfaceLodGrid
```

Headless scene smoke дополнительно вычисляет far и near profiles и обязан доказать:

```text
near.max_lod > far.max_lod
near.planned_river_samples > far.planned_river_samples
near.selection_hash != far.selection_hash
```

Runner требует явный runtime marker:

```text
G6.4 Casual Visual River Lab: PASS (... max_lod=... river_lod=.....)
```

Parse/load error не может считаться PASS.

## Manual graphical acceptance

После automated PASS:

```powershell
.\START_G6_4_VISUAL_RIVER_LAB.ps1
```

Нужно проверить:

```text
LOD grid виден
W -> клетки около observer дробятся
W -> Max LOD растёт
W -> River samples растёт
S -> клетки coarsen-ятся
S -> River samples уменьшается
FeatureId не меняется
FluidRegionId не меняется
river остаётся непрерывной на PX/PZ
centerline/banks/probes остаются согласованными
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

До повторного automated + graphical LOD evidence:

```text
G6.4 = FIX2 IMPLEMENTED CANDIDATE
```

После green gate:

```text
G6.4 = ACCEPTED
next = G6 FULL ACCEPTANCE
```

Перед full G6 acceptance остаётся обязательным fresh main/G5/GLOBAL-P0/shared-baseline sync check.