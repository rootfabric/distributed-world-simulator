# TS0 P0 alignment + TS0.0 deterministic large structural fixtures

**Дата:** 2026-08-10
**Ветка:** `feature/ts0-large-structural-visual-lab`
**Base:** `T1A.3 SOURCE_ACCEPTED @ 5e051f67bf6987a354de5b565da1448be6b0b4db`
**Global revision:** `GLOBAL-P0-2026-08-10-R2`
**Статус:** `SOURCE ACCEPTED — WINDOWS FOCUSED + FULL BRANCH REGRESSION PASS`

## Причина корректировки

Предварительный TS0 plan задавал `block_size_m = 2.0`. Проверка существующего C22 representation path показала, что его occupancy/internal-face-culling/greedy-meshing fast path принимает structural cell как grid voxel только при:

```text
bounding_box_m = [1, 1, 1]
identity rotation
integer local position
```

Блок `2 x 2 x 2 m` ушёл бы в `FALLBACK_QUAD` path и TS0 измерял бы не тот backend, который должен доказать масштабируемость C22/C24.

Коррекция:

```text
TS0 structural cell = 1.0 m
TS0 local section size = 8.0 m
representation fast path = C22_UNIT_AXIS_GRID
```

`section_size_m` остаётся только derived representation policy и не становится canonical world/spatial/authority identity.

## TS0.0 scope

Реализован data-only builder:

```text
config profile
    ↓
stable coordinate identities
    ↓
ConstructionPartRecord[]
    ↓
ConstructSnapshot
    ↓
canonical checksum
```

Никаких `Node3D`, mesh/resource, network RPC, persistence или собственного Item/Operation store TS0.0 не создаёт.

Canonical identity:

```text
part/ts0/<profile>/xNNNN-yNNNN-zNNNN
item/ts0/<profile>/xNNNN-yNNNN-zNNNN
construct/ts0/<profile>
```

Порядок обхода builder не влияет на snapshot: `ConstructSnapshot.create()` канонически сортирует parts по `part_id`.

## Закреплённые profiles

```text
CUBE_10K          22^3                    10 648
PYRAMID_10K       sum(k^2), k=1..31       10 416
CUBE_100K         46^3                    97 336
PYRAMID_100K      sum(k^2), k=1..67      102 510
CUBE_1M_RESEARCH  100^3                1 000 000
```

Pinned canonical checksums:

```text
CUBE_10K
6afcb91d403e0e380f33ad202748f6f7524843188036d9e083e1cbe315672a4f

PYRAMID_10K
39babb3e29949f48fb2df1ddc89c24f6a16e46760939a5b009c29bfbbe5464bf

CUBE_100K
4aebed994f09f578ae241a9c8adb677eb5cf81d1581aea99491921c6f685e084

PYRAMID_100K
4a721061894d65b7bee1d9502a331e0879e4ce5a8047cfe53650460e07b636e6

CUBE_1M_RESEARCH
bfdefbbefc2cde42e713ff6eefbe63c88d35777a4ce9f7deb0d9d25318035543
```

## Почему TS0.0 не материализует 100k/1M в focused runner

TS0.0 — contract/determinism stage, а не scale runtime gate.

Полная double-build + full `ConstructSnapshot.validate()` для 100k уже превращает focused contract test в многоминутный scale workload. Поэтому граница зафиксирована явно:

```text
TS0.0:
  full materialization + forward/reverse determinism
  CUBE_10K
  PYRAMID_10K

TS0.2:
  full 100k materialization
  C22/C24 compilation
  representation/HLOD metrics

TS0.4:
  explicit 1M materialization research probe
```

100k и 1M profiles уже имеют deterministic formulas, stable identity policy и pinned canonical checksums, но не являются TS0.0 runtime blockers.

## Focused validation

Первичный exact-contract harness использовал точный engine build:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
```

Результат:

```text
Editor import                                      PASS
TS0.0 deterministic fixture acceptance            PASS — 61 assertions
CUBE_10K forward/reverse canonical checksum        PASS
PYRAMID_10K forward/reverse canonical checksum     PASS
C22 unit-grid compatibility probes                 PASS
100k profile formulas/checksum pins                PASS
1M research profile non-blocking guard             PASS
```

Затем тот же checkpoint проверен на реальном Windows worktree:

```text
worktree      C:/Godot/lunar-world-double-godot-ts0
engine        Godot 4.7.1.stable.double.custom_build.a13da4feb
runner        RUN_TS0_FIXTURE_TESTS.ps1

CUBE_10K      10 648 parts   5958 ms   PASS
PYRAMID_10K   10 416 parts   5595 ms   PASS
assertions                       61/61   PASS
```

## Full branch regression

После focused PASS выполнен полный branch regression в том же Windows worktree на принятом TS0.0 source state.

```text
runner: RUN_WORLD_REGRESSION_TESTS.ps1
result: PASS
summary: All world/core regression tests through NX4 client prediction and reconciliation passed.
CLI tail: 6 PASS, 0 FAIL
report: artifacts/test-results/world-regression-summary.json
```

Этим закрыт последний gate TS0.0 `SOURCE_ACCEPTED`.

## Known TS0.3 gap

Проверкой до implementation подтверждено: текущий C22 `recompile_incremental()` сначала вызывает полный `compile_construct()`, а уже потом выводит invalidation plan.

TS0.3 должен разделить:

```text
semantic dirty detection
        ↓
actual affected-section rebuild
```

и доказать, что локальная 10x10x10 mutation не вызывает полный rebuild всех section artifacts.

Это не блокирует TS0.0/TS0.1/TS0.2.

## Решение

```text
TS0 P0 grid alignment        PASS
TS0.0 implementation        COMPLETE
Focused exact-contract      PASS
Windows focused             PASS — 61/61
Full branch regression      PASS
SOURCE_ACCEPTED              true
MAIN_INTEGRATED              false
COMPOSITION_VERIFIED         false
PRODUCTION_READY             false
next                        TS0.1 — 10k graphical proof through existing C22/C24 path
```
