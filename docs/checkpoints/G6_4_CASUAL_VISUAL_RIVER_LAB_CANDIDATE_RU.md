# G6.4 — Casual Visual River Lab — FIX4 IMPLEMENTED CANDIDATE

**Дата:** 2026-08-09
**Ветка:** `feature/g6-hydrology-fluid-surface-v0`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Fix3 Windows-tested head:** `3a5427fb1ccdad8e2a63650c5c253a0ac1fcf298`
**Fix4 functional head:** `1beb592d421b8919d637b9bb0e156762ee11d970`

Fix3 автоматикой доказал реальную adaptive geometry:

```text
far LOD        1
near LOD       9
far triangles  120
near triangles 4176
```

Ручной прогон дошёл до LOD 10, но новая поверхность визуально оставалась слишком гладкой. Причина: Fix3 visual recipe использовал только четыре octave accepted G3 provider, то есть источники detail заканчивались примерно на `75 km` wavelength. Дополнительные полигоны уже не могли показать отсутствующие частоты.

Fix4 не меняет accepted G3 provider. Меняется только debug recipe:

```text
base wavelength    600 km
octaves            8
persistence        0.58
minimum signal     ~4.6875 km
```

Теперь при `W` refine должны появляться не только более мелкие G2 cells и дополнительные triangles, но и новые high-frequency macro-height features.

Отдельно устранена ошибка standalone запуска:

```text
[breakpoint_runtime] could not listen on 127.0.0.1:9081
```

`BreakpointRuntimeBridge` для G6.4 не нужен. `START_G6_4_VISUAL_RIVER_LAB.ps1` и G6.4 automated runner временно выставляют `BREAKPOINT_RUNTIME_DISABLED=1` и затем восстанавливают предыдущее окружение.

Automated gate:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_4_CASUAL_VISUAL_RIVER_LAB_TESTS.ps1
```

Expected adaptive marker includes:

```text
octaves=8
min_signal_km=4.688
```

Manual gate:

```powershell
.\START_G6_4_VISUAL_RIVER_LAB.ps1
```

Acceptance requires visible higher-frequency relief during refine, coarsening on `S`, stable `FeatureId`/`FluidRegionId`, and continuous PX/PZ river presentation. River valley carving remains deferred to G8 Geomorphology.

Until automated + manual Fix4 evidence is green:

```text
G6.4 = FIX4 IMPLEMENTED CANDIDATE
```

Next after acceptance: `G6 FULL ACCEPTANCE` with fresh main/G5/GLOBAL-P0/shared-baseline sync check.