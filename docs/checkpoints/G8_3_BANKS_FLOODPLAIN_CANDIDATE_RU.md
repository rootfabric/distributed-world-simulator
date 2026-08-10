# G8.3 Banks and Floodplain Shaping — Candidate

**Architecture:** `GLOBAL-P0-2026-08-10-R2`
**Project Control:** `PC0-2026-08-10-R1`
**Branch:** `feature/g8-geomorphology`

Parent checkpoint: **G8.2 River Channel Incision — ACCEPTED**.

## Цель

Добавить процедурные береговые плечи и широкую пойменную форму поверх уже принятой композиции G8.1 valley + G8.2 river channel, не смешивая этот этап с erosion/deposition и не вводя новые foundation ownership.

## Входы

```text
geo/surface-height-m
geo/valley-influence
geo/river-distance-m
geo/river-width-m
```

`geo/fluid-surface-distance-m` намеренно не используется как абсолютный уровень воды: текущая принятая семантика описывает расстояние до fluid surface, но не signed canonical water elevation.

## Нормализация зон

```text
normalized_distance = river_distance_m / (river_width_m * 0.5)
```

Зоны:

```text
0.0 .. 1.0     channel — bank/floodplain = 0
1.0 .. 1.5     bank smooth rise
1.5            bank peak
1.5 .. 2.0     bank smooth fall
2.0 .. 2.5     floodplain smooth entry
2.5 .. 4.5     floodplain full core
4.5 .. 6.0     floodplain smooth fade
>= 6.0         no G8.3 shaping
```

Формулы:

```text
bank_delta_m = +bank_max_delta_m
             * bank_weight
             * valley_influence

floodplain_delta_m = -floodplain_max_delta_m
                   * floodplain_weight
                   * valley_influence
```

Профильные пределы уже заморожены контрактом G8.0. G8.3 не добавляет новые поля profile и остаётся заменяемым generator layer.

## Композиция

G8.3 вызывает принятый G8.2 generator на том же semantic bundle/profile, сохраняет его exact valley и river components и добавляет только:

```text
bank_delta_m
floodplain_delta_m
```

`erosion_deposition_delta_m` остаётся нулевым до G8.4.

## Архитектурные границы

G8.3 не владеет и не зависит от:

- SurfaceCellKey / LOD / camera representation;
- AuthorityRegion / InterestRegion;
- Matter mutation / persistent terrain damage;
- MaterialDefinitionId / material ontology;
- persistence durability;
- network replication ownership.

## Acceptance

Сначала:

```powershell
.\RUN_G8_3_BANKS_FLOODPLAIN_TESTS.ps1 -GodotPath $Godot
```

При PASS, на том же clean checkout без fetch/reset:

```powershell
.\RUN_G8_3_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

Только полный PASS открывает **G8.4 Erosion / Deposition Baseline**.
