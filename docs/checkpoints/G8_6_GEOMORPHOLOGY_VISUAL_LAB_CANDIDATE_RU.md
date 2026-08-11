# G8.6 — Geomorphology Visual Lab — candidate

**Architecture:** `GLOBAL-P0-2026-08-10-R2`
**Project Control:** `PC0-2026-08-10-R1`
**Branch:** `feature/g8-geomorphology`

## Parent

`G8.5 Cross-Cell / Cross-LOD Geomorphology Invariance — ACCEPTED`

Tested head:

```text
6cc0c2b5ff1bc21a5b488a8492ef8cce28fa4736
```

## Цель

Показать принятую G8 geomorphology на масштабе, где физически различимы русло шириной десятки метров, bank shoulder, floodplain и erosion/deposition, не превращая presentation mesh или LOD в canonical truth.

Visual Lab центрируется на реальном переходе принятой G6 river spline через PX/PZ cube-sphere seam и строит локальный corridor `440 m × 1600 m`, 33×17 = 561 canonical samples.

## Визуальные режимы

```text
1  resolved surface height
2  total deformation
3  valley incision
4  river channel incision
5  bank shaping
6  floodplain shaping
7  erosion / deposition
```

Дополнительно:

```text
G       source G3 geometry / resolved G8 geometry
F       canonical river overlay
X       PX/PZ representation seam overlay
W / S   zoom + derived presentation LOD
A / D   yaw
Q / E   pitch
Space   auto orbit
R       reset
```

Presentation LOD использует те же 561 canonical samples:

```text
LOD0 stride 1  -> 33×17
LOD1 stride 2  -> 17×9
LOD2 stride 4  -> 9×5
LOD3 stride 8  -> 5×3
```

Camera, color mode, mesh density, overlays и 3.5× vertical display exaggeration не входят в canonical geomorphology truth/checksum.

## First Windows attempt / FIX1

Первый exact-Windows focused run на head:

```text
87acbc69854336fa52b5b4c66069ec56a555c1a4
```

прошёл editor import и принятый G8.5 invariance regression:

```text
G8.5 Cross-Cell / Cross-LOD Geomorphology Invariance: PASS (150 assertions)
```

После этого G8.6 contract harness остановился на:

```text
G8.6 Geomorphology Visual Lab Contracts: FAIL (35 assertions, 1 failures)
- source grid pinned
```

Это не geomorphology/runtime regression. Manifest содержит правильный `source_grid: [33, 17]`. Причина в test harness: `JSON.parse_string()` декодирует JSON numbers как `float`, а GDScript Array equality type-sensitive, поэтому `[33.0, 17.0] != [33, 17]`.

Поведение отдельно воспроизведено на exact Godot `4.7.1.stable.double.custom_build.a13da4feb` Linux double build.

FIX1 implementation commit:

```text
05757e69b7e73139226c68702f4bb81c31840469
```

FIX1 меняет только acceptance harness: проверяет размер массива и приводит оба значения `source_grid` к `int` перед сравнением. Manifest, lab runtime, geomorphology formulas, canonical truth, identity и presentation behavior не менялись.

## Automated sequence

После sync latest branch на одном clean checkout:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_G8_6_GEOMORPHOLOGY_VISUAL_LAB_TESTS.ps1 `
    -GodotPath $Godot

.\RUN_G8_6_AUTOMATED_ACCEPTANCE.ps1 `
    -GodotPath $Godot
```

Второй runner включает свежий world/core regression. Между focused PASS и automated runner нельзя делать `fetch/reset`.

## Graphical launch

```powershell
& $Godot `
    --path . `
    res://scenes/labs/procedural/g8_6_geomorphology_visual_lab.tscn
```

## Manual acceptance

Нужно подтвердить:

1. `G` заметно переключает source ↔ resolved geometry, а HUD `Truth hash` не меняется.
2. `1..7` показывают разные ожидаемые формы полного G8 deformation.
3. `W/S` меняют LOD/mesh-grid, но `Canonical samples=561` и `Truth hash` остаются неизменными.
4. При включённом `X` magenta PX/PZ seam пересекает поверхность без видимого геометрического разрыва.
5. При включённом `F` cyan river overlay согласован с channel/bank/floodplain формой.

Только focused FIX1 + automated + manual graphical PASS переводят G8.6 в ACCEPTED и открывают `G8 Full Acceptance`.
