# Checkpoint C7 — Spatial Construct

**Дата:** 2026-07-31
**Статус:** ACCEPTED
**База:** `C6 @ 2837835`, C5 commit `29cd8b1`
**Рекомендуемая ветка:** `feature/c7-spatial-construct`

## Цель

Сделать первый пространственный construct, где помещение, ограждение, проёмы, двери и инженерные сети выводятся из реальных parts/bonds и строгого Space Graph, а не из mesh, scene tree или имени prefab.

## Реализовано

- section definitions и вычисляемые section states;
- opening graph с дверями, окнами и внешним пространством;
- space definitions и состояния `HABITABLE/DEGRADED/EXPOSED/INACTIVE`;
- utility graph `POWER/DATA/WATER/AIR/HEAT` с dependencies и quorum;
- derived building state `ACTIVE/DEGRADED/INACTIVE`;
- activation LOD `DORMANT/SUMMARY/FUNCTIONAL`;
- C5 capability/affordance compilation для occupancy, доступа и utilities;
- checksum-pinned spatial commands;
- replay-safe profile store и persistence/rebuild.

## Контрольный дом

```text
foundation + floor + 4 walls + roof
├── exterior door
├── exterior window
├── POWER utility
└── DATA utility depends POWER
        ↓
space/house/main
```

Поведение:

```text
intact:             ACTIVE / HABITABLE / FUNCTIONAL
exterior door open: DEGRADED, CLOSE_DOOR available
wall destroyed:     EXPOSED / INACTIVE / SUMMARY
window destroyed:   EXPOSED / INACTIVE / SUMMARY
power destroyed:    enclosure retained, POWER+DATA offline
roof degraded:      DEGRADED, SHELTER retained
partial build:      INACTIVE / DORMANT, no behavior
repair:             ACTIVE profile restored at newer revision
```

## Проверки

```text
C7 contracts:    PASS — 105 assertions
C7 integration:  PASS — 120 assertions
C7 total:        PASS — 225 assertions
C1 compatibility: PASS — 66 assertions
C2A compatibility: PASS — 137 assertions
C3 compatibility: PASS — 194 assertions
C4 compatibility: PASS — 268 assertions
C5 compatibility: PASS — 204 assertions
C6 compatibility: PASS — 218 assertions
Editor parse:     PASS
```

C2B focused, network/runtime, полный world regression и main-scene CLI должны быть повторены на полном checkout.

## Gate принятия

```text
C1/C2A/C2B/C3/C4/C5/C6 compatibility PASS
C7 focused PASS — 225 assertions
Network N0–M4 PASS
World regression PASS — 115/115 tests, 118 steps
Main-scene CLI PASS — 6/6
git diff --check PASS
```


## Внешняя приёмка

```text
C7 contracts:     PASS — 105 assertions
C7 integration:   PASS — 120 assertions
C7 total:         PASS — 225 assertions
C1/C2A/C2B/C3/C4/C5/C6: PASS
Network N0–M4:    PASS
World regression: PASS — 115/115 tests, 118 steps
Main-scene CLI:   PASS — 6/6
git diff --check: PASS
```

Reviewed delivery SHA-256: `5a4cebb21587ed8c4b54852145b6a018445438866bc1908d5cf9bcc4fe9aee87`.
