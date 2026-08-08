# G6.4 — Casual Visual River Lab — IMPLEMENTED CANDIDATE

**Дата:** 2026-08-09
**Ветка:** `feature/g6-hydrology-fluid-surface-v0`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Dependencies:** `G6.0 / G6.1 / G6.2 / G6.3 — ACCEPTED`
**Решение:** `IMPLEMENTED CANDIDATE — WINDOWS AUTOMATED + GRAPHICAL MANUAL ACCEPTANCE REQUIRED`

## Цель

G6.4 — первый ручной visual checkpoint гидрологии. Он не вводит новую world truth, а визуализирует уже принятую canonical river geography и результаты `WaterSurfaceResolverV1`.

```text
G5 River FeatureId
        ↓
G6.1 canonical geography
        ↓
G6.3 WaterSurfaceQuery / WaterSurfaceSample
        ↓
G6.4 derived presentation
```

## Сцена

```text
res://scenes/labs/procedural/g6_4_casual_visual_river_lab.tscn
```

Script:

```text
res://scripts/labs/procedural/g6_4_casual_visual_river_lab.gd
```

Lab показывает planet-scale globe и seam-river fixture G6.2, проходящую через `PX/PZ`.

## Presentation layers

```text
blue ribbon     derived water surface
 yellow line    canonical centerline debug
 brown lines    bank guides
 red probe      WaterSurfaceSample normal
 green probe    WaterSurfaceSample flow direction
 magenta line   cube-face transition marker
```

Ширина ribbon намеренно presentation-exaggerated. Это зафиксировано явно:

```text
WIDTH_EXAGGERATION = 5200
BANK_EXAGGERATION  = 3600
```

Такое увеличение не меняет `RiverSpline`, `RiverChannelProfile`, `FluidRegionId` или `WaterSurfaceSample`.

## Runtime consumption rule

Каждая visual sample строится из:

```text
presentation sample point
        ↓
WaterSurfaceQuery.create(...)
        ↓
WaterSurfaceResolverV1.resolve(...)
        ↓
WaterSurfaceSample
        ↓
ribbon / bank / probe display
```

То есть renderer не пересчитывает собственную canonical ширину/normal/flow.

`CubeSphereAddressing` используется только для debug определения `PX/PZ` seam marker.

## Manual controls

```text
A / D      orbit longitude
Q / E      camera pitch
W / S      zoom
Space      auto-orbit on/off
R          camera reset

1          water ribbon
2          centerline
3          bank guides
4          query probes
5          seam markers
```

## Headless proof

При headless запуске lab обязана:

- собрать >= 80 visual samples;
- получить G6.3 query match для всех samples;
- построить water ribbon;
- построить centerline/bank/probe/seam presentation;
- увидеть обе cube faces `PX` и `PZ`;
- увидеть минимум один face transition;
- создать минимум пять query probes;
- завершиться кодом 0.

Expected output:

```text
G6.4 Casual Visual River Lab: PASS (...)
```

## P0 boundaries

G6.4 не владеет:

```text
FeatureId
FluidRegionId
SurfaceCellKey
AuthorityRegionId
InterestRegionId
persistence
network transport
world mutation
```

Запрещённое направление:

```text
mesh/ribbon/visual width -> canonical fluid truth
```

Разрешённое:

```text
canonical/query truth -> replaceable visual presentation
```

## Fresh synchronization note

Перед реализацией проверено, что `main` продолжает использовать:

```text
GLOBAL-P0-2026-08-08-R1
```

Отдельно существует свежий shared-baseline PR #43 с MW10 atomic-lock integration на G5 baseline. Он на момент реализации G6.4 ещё не merged. G6.4 не зависит от Matter runtime, поэтому checkpoint не блокируется им. Перед **full G6 acceptance** необходимо заново проверить G5/shared baseline и синхронизировать G6, если PR #43 или его эквивалент к тому моменту интегрирован.

## Automated Windows gate

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_4_CASUAL_VISUAL_RIVER_LAB_TESTS.ps1
```

Runner повторяет весь accepted chain через G6.3, затем запускает:

```text
G6.4 source/P0 contract gate
G6.4 headless scene smoke
```

## Manual graphical gate

После automated PASS:

```powershell
.\START_G6_4_VISUAL_RIVER_LAB.ps1
```

Нужно вручную подтвердить:

```text
water ribbon visible
river visually continuous
PX/PZ transition has no break/jump
centerline stays inside ribbon
bank guides remain continuous
query probe normals point outward
flow arrows follow river downstream
all debug toggles work
camera controls work
no renderer artifact changes canonical ids shown in HUD
```

## Acceptance decision

До automated + graphical evidence:

```text
G6.4 = IMPLEMENTED CANDIDATE
```

После green gate и ручного подтверждения:

```text
G6.4 = ACCEPTED
next = G6 FULL ACCEPTANCE
```

Full G6 acceptance после этого обязан включить fresh global/shared-baseline sync check и full world/core regression.
