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

Первый exact-Windows focused run на head `87acbc69854336fa52b5b4c66069ec56a555c1a4` прошёл editor import и G8.5 invariance `PASS (150 assertions)`, после чего contract harness остановился на `source grid pinned` (`35 assertions, 1 failure`). Manifest был корректен; причиной оказалась type-sensitive Array equality после JSON decode. FIX1 `05757e69b7e73139226c68702f4bb81c31840469` приводит оба JSON numeric значения к `int` и не меняет runtime.

## Second Windows attempt / FIX2

Второй exact-Windows run на head:

```text
666a56e104b521c642afd3168f9d3e3b3f1d9ad4
```

дошёл дальше:

```text
editor import                                               PASS
G8.5 Cross-Cell / Cross-LOD Geomorphology Invariance       PASS (150 assertions)
G8.6 Geomorphology Visual Lab Contracts                    PASS (35 assertions)
G8.6 headless semantic / geomorphology lab                  FAIL
```

Headless smoke сообщил:

```text
G8_6_COMPONENT_NOT_VISIBLE_IN_CORRIDOR
component = river_channel_delta_m
```

Это уже ошибка локального presentation corridor, но не G8.2/G8.4 runtime. Accepted G6 river spline хранит реальную radial elevation. В районе выбранного PX/PZ seam centerline находится примерно на `+70 m` относительно `Fixture.RADIUS_M`, тогда как исходный G8.6 lab после нахождения seam делал проекцию обратно на `Fixture.RADIUS_M`. Поскольку G6 `river_distance_m` — полный 3D distance до centerline, все 561 samples оказались ниже канала и G8.2 корректно выдавал нулевой `river_channel_delta_m`.

FIX2 runtime commit:

```text
6d461ea5b201047cf12f1d284fb08e93ceae1689
```

FIX2 реализован отдельным presentation-only wrapper:

```text
res://scripts/labs/procedural/g8_6_geomorphology_visual_lab_fix2.gd
```

Он:

- находит PX/PZ seam на той же radial interpolation, что использует G6 resolver;
- сохраняет настоящий radius G6 centerline вместо принудительного `Fixture.RADIUS_M`;
- строит локальный tangent/cross frame в этой точке;
- семплирует corridor на centerline radius;
- не меняет accepted G8.1–G8.5 geomorphology runtime, формулы или canonical identity.

Headless smoke **не ослаблен**: он всё ещё требует ненулевую видимость каждого из пяти deformation components.

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

Только focused FIX2 + automated + manual graphical PASS переводят G8.6 в ACCEPTED и открывают `G8 Full Acceptance`.
