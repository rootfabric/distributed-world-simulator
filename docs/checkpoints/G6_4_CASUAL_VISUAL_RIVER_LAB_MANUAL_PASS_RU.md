# G6.4 Casual Visual River Lab — FIX4 MANUAL GRAPHICAL PASS

**Дата:** 2026-08-09
**Ветка:** `feature/g6-hydrology-fluid-surface-v0`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Fix4 functional head:** `1beb592d421b8919d637b9bb0e156762ee11d970`

Ручной Windows-прогон Fix4 подтвердил observer-driven refinement от приблизительно `LOD 6` на `812.7 km` virtual altitude до `LOD 10` на `42.2 km`.

Пользователь визуально подтвердил:

```text
adaptive SurfaceCellKey grid refines
higher-frequency macro irregularities appear at close range
water ribbon remains visible
PX/PZ river presentation remains continuous
FeatureId remains stable
FluidRegionId remains stable
```

Деталь остаётся намеренно тонкой: это diagnostic G3 macro/detail recipe, а не готовый локальный terrain generator. River-valley carving, erosion и bank shaping остаются за `G8 Geomorphology`.

Fix4 использует тот же принятый `CasualMacroTerrainProviderV1`, но в visual-lab recipe выставляет 8 octave, что даёт минимальную исходную длину волны около `4.6875 km`. Accepted G3 provider code не изменён.

## Статус

Manual graphical evidence пройден. Windows automated Fix4 gate позднее также прошёл на head `7cb3c69bbca276c815b27563fa494ac35b078779`: dependency chain G5→G6.3 PASS, G6.4 contracts PASS (158 assertions), adaptive macro surface PASS (`far_lod=1`, `near_lod=9`, `far_triangles=120`, `near_triangles=4176`, `octaves=8`, `min_signal_km=4.688`) и visual lab runtime marker PASS.

Формальная запись `G6.4 ACCEPTED` выполняется после очистки repo hygiene (`git diff --check`) от старого markdown whitespace; runtime-код после успешного Fix4 automated run не менялся.

Следующий checkpoint уже начат: `G6 FULL ACCEPTANCE`. Его текущий blocker находится не в G6.4, а в shared MW10 baseline: PR #43 ещё не интегрирован в G5.
