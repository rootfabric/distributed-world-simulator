# G8.4 Erosion / Deposition Baseline — Candidate

**Architecture:** `GLOBAL-P0-2026-08-10-R2`
**Project Control:** `PC0-2026-08-10-R1`
**Branch:** `feature/g8-geomorphology`

Parent checkpoint: **G8.3 Banks and Floodplain Shaping — ACCEPTED**.

## Цель

Добавить пятый signed geomorphology component как статическую процедурную redistribution baseline поверх принятой композиции valley + river + banks/floodplain.

Это не физическая sediment simulation: G8.4 не ведёт массу осадков, не интегрирует процесс по времени и не записывает Matter mutation.

## Входы

```text
geo/surface-height-m
geo/valley-influence
geo/river-distance-m
geo/river-width-m
```

`geo/fluid-surface-distance-m` остаётся неиспользованным: текущий accepted field — distance semantic, а не signed canonical water elevation.

## Поперечные зоны

```text
normalized_distance = river_distance_m / (river_width_m * 0.5)

0.0 .. 1.0     channel: erosion/deposition = 0
1.0 .. 1.35    erosion smooth rise
1.35           erosion peak
1.35 .. 2.0    erosion smooth fall
2.0            zero handoff
2.0 .. 3.25    deposition smooth rise
3.25           deposition peak
3.25 .. 5.5    deposition smooth fall
>= 5.5         zero
```

Формула:

```text
signed_weight = deposition_weight - erosion_weight

erosion_deposition_delta_m =
    erosion_deposition_max_delta_m
  * signed_weight
  * valley_influence
```

Отрицательное значение означает erosion, положительное — deposition. Амплитуда ограничена уже принятым G8.0 profile field `erosion_deposition_max_delta_m`.

## Композиция

G8.4 вызывает accepted G8.3 на том же semantic bundle/profile, сохраняет exact:

```text
valley_delta_m
river_channel_delta_m
bank_delta_m
floodplain_delta_m
```

и записывает только:

```text
erosion_deposition_delta_m
```

## Границы ответственности

G8.4 не владеет:

- sediment inventory или conservation ledger;
- time integration;
- Matter mutation / persistent terrain damage;
- SurfaceCellKey / LOD / camera representation;
- authority / interest routing;
- material ontology;
- persistence или network replication.

## Acceptance

Сначала:

```powershell
.\RUN_G8_4_EROSION_DEPOSITION_TESTS.ps1 -GodotPath $Godot
```

При PASS, без fetch/reset на том же checkout:

```powershell
.\RUN_G8_4_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

Полный PASS открывает **G8.5 Cross-Cell / Cross-LOD Geomorphology Invariance**.
