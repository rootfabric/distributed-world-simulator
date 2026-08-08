# G6.2 — Cross-cell / Cross-LOD Continuity — IMPLEMENTED CANDIDATE

**Дата:** 2026-08-08
**Ветка:** `feature/g6-hydrology-fluid-surface-v0`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Dependency:** `G6.1 CasualRiverProviderV1 — ACCEPTED`
**Implementation candidate:** `322265247bb0a01bf7bdd814adca2ead30b124c9`
**Fix1 candidate:** `a3efb5dd314ef6c2e7d3b5d75d118402e7b45117`
**Решение:** `IMPLEMENTED CANDIDATE — FIX1 WINDOWS FOCUSED ACCEPTANCE REQUIRED`

## Цель

G6.2 доказывает, что canonical river geography не зависит от того, какими G2 `SurfaceCellKey` и LOD она в данный момент представлена.

```text
G5 River FeatureId
        ↓
G6.1 CasualRiverProviderV1
        ↓
canonical FluidRegion / RiverSpline / ChannelProfile / FluidSurface
        ↓
G2 CubeSphereAddressing
        ↓
LOD-dependent representation cells
```

Обязательное направление зависимости:

```text
canonical river -> representation addressing
```

Запрещённое направление:

```text
SurfaceCellKey / LOD -> river identity
```

## Acceptance fixture

Добавлен deterministic seam-river fixture:

```text
body radius:       6,000,000 m
source longitude:  34°
mouth longitude:   58°
expected seam:     PX / PZ
LOD proof:          2 / 4 / 8 / 12
```

Река создаётся как обычный G5 `WorldFeature(feature-type/river)` и компилируется уже принятым G6.1 provider. Отдельный `RiverChunkId` не вводится.

## Что должно оставаться неизменным

На всех LOD и после любых G2 addressing calls обязаны сохраняться:

```text
FeatureId
FluidRegionId
RiverSpline.spline_id
RiverChannelProfile.profile_id
provider manifest hash
RiverSpline checksum
FluidSurfaceDescriptor checksum
```

При этом representation set должен реально меняться:

```text
LOD 2 cell set != LOD 12 cell set
```

и spline должен адресоваться хотя бы на двух cube faces:

```text
PX
PZ
```

## Архитектурная граница

G6.2 не добавляет production hydrology runtime. Это acceptance/proof checkpoint.

Не добавляются:

```text
runtime WaterSurfaceQuery resolver
renderer
river mesh
RiverChunkId
new authority registry
new persistence owner
new network transport
```

Принятые G6.0 contracts и G6.1 provider не изменены.

## Fix1 после первого Windows focused run

Первый Windows запуск на Godot `4.7.1.stable.double.custom_build.a13da4feb` подтвердил dependency chain и 85 из 86 assertions G6.2. Единственный failure был в manifest meta-check `G6.2 LOD proof levels pinned`.

Причина: `JSON.parse_string()` возвращает JSON numeric values как generic numeric Variant values, а тест напрямую сравнивал parsed array с типизированным `Array[int] = [2, 4, 8, 12]`. Manifest содержал правильные значения; canonical continuity assertions не падали.

Fix1 нормализует каждый parsed LOD через `int(lod_value)` перед сравнением. Production provider/contracts, fixture geography и continuity semantics не изменены.

Одновременно удалены trailing whitespace в этом checkpoint, обнаруженные `git diff --check`.

## Новые файлы

```text
RUN_G6_2_CROSS_CELL_CONTINUITY_TESTS.ps1
RUN_G6_2_CROSS_CELL_CONTINUITY_TESTS.sh
config/procedural/g6-2-cross-cell-cross-lod-continuity.v1.json
tests/procedural/fixtures/g6_2_cross_cell_river_fixture.gd
tests/procedural/hydrology/g6_2_cross_cell_cross_lod_continuity_acceptance.gd
validation/g6-2-cross-cell-cross-lod-continuity-validation.json
```

## Focused acceptance

На Windows checkout:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_2_CROSS_CELL_CONTINUITY_TESTS.ps1
```

Runner сначала повторяет весь accepted dependency chain:

```text
G5 World Feature Graph
G5 feature/cell identity
G6.0 Fluid Contracts
G6.1 CasualRiverProviderV1
```

и только затем запускает G6.2 continuity gate.

## Acceptance criteria

```text
G5 graph                         PASS 249
G5 feature/cell identity         PASS 94
G6.0 fluid contracts             PASS 169
G6.1 CasualRiverProviderV1       PASS 74
G6.2 continuity                  PASS 86
working tree                     CLEAN
git diff --check                 PASS
```

Если Fix1 focused run зелёный, checkpoint можно перевести в:

```text
G6.2 = ACCEPTED
next = G6.3 runtime WaterSurfaceQuery resolver
```

Full world regression по-прежнему остаётся composed final gate для G6.1–G6.4, если G6.2 не выявит необходимость менять shared accepted runtime/contracts.
