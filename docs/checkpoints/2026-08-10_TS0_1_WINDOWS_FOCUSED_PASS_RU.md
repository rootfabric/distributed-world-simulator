# TS0.1 — Windows focused acceptance PASS

**Дата:** 2026-08-10  
**Ветка:** `feature/ts0-large-structural-visual-lab`  
**Tested head:** `9a3a2e7c8685a61cb1399bbbf6531b54de49925e`  
**Worktree:** `C:/Godot/lunar-world-double-godot-ts0`  
**Engine:** `Godot 4.7.1.stable.double.custom_build.a13da4feb`  
**Статус:** `WINDOWS FOCUSED PASS — VISUAL OBSERVATION + FULL BRANCH REGRESSION PENDING`

## Результат

В реальном Windows checkout выполнен:

```text
RUN_TS0_GRAPHICAL_TESTS.ps1
```

Результаты:

```text
TS0.0 deterministic large structural fixtures   PASS — 61 assertions
TS0.1 10k graphical proxy acceptance            PASS — 254 assertions
C22 compiled proxy graphical                     PASS — 35 assertions
C24 proxy mesh backend graphical                 PASS — 74 assertions
```

Fixture timings:

```text
CUBE_10K       10 648 parts   5886 ms
PYRAMID_10K    10 416 parts   5635 ms
```

Это подтверждает production-path contracts TS0.1 через существующие C22/C24 implementation, включая bounded HLOD presentation и C24 ArrayMesh backend. Production C22/C24 код самим TS0.1 не изменялся.

## Решение

```text
TS0.0 regression                         PASS
TS0.1 focused production-path            PASS
C22 graphical regression                 PASS
C24 graphical regression                 PASS
SOURCE_ACCEPTED                          false
```

`SOURCE_ACCEPTED` пока не выставляется. Остаются два gate:

1. ручная graphical observation `CUBE_10K` и `PYRAMID_10K` в `NEAR / MID / FAR`;
2. полный `RUN_WORLD_REGRESSION_TESTS.ps1` на этой ветке.

После обоих PASS TS0.1 можно перевести в `SOURCE_ACCEPTED` и перейти к TS0.2 — 100k visual scale gate.
