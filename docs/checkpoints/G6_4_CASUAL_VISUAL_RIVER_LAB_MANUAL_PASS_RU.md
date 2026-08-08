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

Manual graphical evidence считается пройденным, но G6.4 ещё не переводится в окончательный `ACCEPTED`, пока Fix4 не пройдёт повторный automated gate на том же актуальном дереве.

Следующий checkpoint уже начат: `G6 FULL ACCEPTANCE`. Его runner сначала повторно запускает G6.4 Fix4 gate, поэтому один полный прогон может закрыть оставшийся automated evidence G6.4 и затем весь G6.
