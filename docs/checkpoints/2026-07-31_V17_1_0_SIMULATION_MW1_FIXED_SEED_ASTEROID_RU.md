# v17.1.0 — Simulation MW1 Fixed-Seed Asteroid

Дата: `2026-07-31`
Статус: `ACCEPTED`
Base checkpoint: `v17.0.0-simulation-mw0-matter-contracts`, delivery `fix1`
Ветка: `feature/mw1-fixed-seed-asteroid`
Checkpoint: `v17.1.0-simulation-mw1-fixed-seed-asteroid`
Build ID: `mw1-fixed-seed-asteroid`

## Реализовано

- детерминированный integer-hash/value-noise field;
- versioned fixed-seed asteroid profile;
- stable feature catalog;
- reference ellipsoid и directional deformation;
- две additive lobes;
- два impact craters;
- закрытая natural void;
- железо-никелевая линза;
- ледяной карман;
- observer-independent `MatterSample` query;
- отдельный outer surface query;
- checksum-protected mass estimate;
- midpoint mass/material integration;
- 128-point golden fixture;
- focused Windows/Linux runners.

## Независимая приёмка

```text
MW1 focused:    3685 assertions PASS
MW0 regression: 2011 assertions PASS
A3 regression:  12/12 PASS
M6 regression:  10/10 PASS
ZIP safety:     PASS, 23 files
SHA-256:        35F8CECAD252777D80DFFC1A8DDB4EE6E4E667448669C0F397ADC4CBBCF8827E
```

Неблокирующая рекомендация по доказуемому root bounds закрывается в MW2.

## Identity

```text
body_id:             body/asteroid-mw0
body_frame_id:       body/asteroid-mw0/fixed
generator_id:        matter-generator/fixed-seed-asteroid
generator_version:   1.0.0
generator_seed:      2026073101
reference_radius_m:  1000
root_bounds_m:       ±1450
```

## Golden fixture

```text
control points: 128
hash: d5d4b6cde3b4685757bef65bd86dbfb36cc7c08416a802f4d5f4bf8fd5de5f57
```

## Acceptance targets

```text
coarse mass integration: 16³ midpoint samples
fine mass integration:   20³ midpoint samples
maximum relative delta:  10%
mass range:              5e12 … 2e13 kg
max center offset:       250 m
```

Эти пределы являются regression gate для текущего engineering generator, а не научной оценкой конкретного реального астероида.

## Boundary

Production runtime не изменён:

```text
Moon runtime changed:       false
world catalog changed:      false
mesh/collision added:       false
Item Graph changed:         false
network authority changed:  false
```

MW1 работает только через pure/headless domain queries.

## Проверка

```powershell
$godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_MW1_FIXED_SEED_ASTEROID_TESTS.ps1 -GodotPath $godot
.\RUN_MW0_MATTER_CONTRACTS_TESTS.ps1
.\RUN_A3_SINGLE_SERVER_MULTIPLAYER_TESTS.ps1 -GodotPath $godot
.\RUN_M6_DEDICATED_RECOVERY_TESTS.ps1 -GodotPath $godot

git diff --check
```

## Локальная проверка поставки

Без Godot runtime выполнена независимая численная проверка алгоритма и статический аудит поставки:

```text
control fixture:              PASS
control hash:                 d5d4b6cde3b4685757bef65bd86dbfb36cc7c08416a802f4d5f4bf8fd5de5f57
96 outer surface directions:  PASS
600 deterministic samples:    PASS, 98 occupied / 502 vacuum
natural void wall geology:    PASS
16³ estimated mass:           1.1663502603056426e13 kg
20³ estimated mass:           1.1745644330684455e13 kg
relative mass delta:          0.699337774%
material mass balance:        PASS
JSON/preload/docs/static:     PASS
git diff --check:             PASS
focused Godot:                NOT RUN
```

Focused Godot и MW0/A3/M6 regression должны быть подтверждены на double-precision build перед приёмкой.

## Acceptance criteria

1. MW1 runner завершён с exit code `0`.
2. Golden control hash совпадает.
3. Same-seed samples и mass estimate повторяются точно.
4. Different seed меняет feature catalog и fixture hash.
5. Центр occupied, root bounds vacuum, outer surface замкнута.
6. Natural void возвращает vacuum.
7. Ore/ice feature centers содержат ожидаемые материалы.
8. 16³ и 20³ mass estimates сходятся в пределах 10%.
9. Material mass sum совпадает с total mass.
10. MW0/A3/M6 regression остаются PASS.
11. Parser/preload errors отсутствуют.
12. `git diff --check` остаётся PASS.

После независимого PASS MW1 можно принять и открыть `feature/mw2-sparse-matter-storage`.
