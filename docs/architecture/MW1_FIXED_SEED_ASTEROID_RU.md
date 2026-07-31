# MW1 — детерминированное объёмное тело астероида

**Checkpoint:** `v17.1.0-simulation-mw1-fixed-seed-asteroid`
**Статус поставки:** implementation candidate
**Base:** принятый `v17.0.0-simulation-mw0-matter-contracts`, delivery `fix1`
**Ветка:** `feature/mw1-fixed-seed-asteroid`
**Следующий этап:** MW2 — sparse matter cells, bricks and query service

## 1. Назначение

MW1 доказывает, что лабораторный астероид радиусом 1000 метров может существовать как детерминированное объёмное поле без полного voxel allocation, `SceneTree`, mesh, collision и зависимости от наблюдателя.

Канонический запрос имеет вид:

```text
MatterSample sample(body-local position)
```

Он возвращает MW0-контракт с:

- signed-distance approximation;
- occupancy;
- bulk density;
- нормализованным составом;
- integrity;
- temperature;
- porosity;
- semantic flags.

## 2. Зафиксированная identity

```text
body_id:             body/asteroid-mw0
body_frame_id:       body/asteroid-mw0/fixed
generator_id:        matter-generator/fixed-seed-asteroid
generator_version:   1.0.0
generator_seed:      2026073101
reference_radius_m:  1000
root bounds radius:  1450 m
```

`MatterBodyDefinition.metadata` связывает тело с:

- checksum generator profile;
- hash stable feature catalog.

Изменение seed, profile или feature catalog без изменения body checksum считается несовместимой конфигурацией.

## 3. Форма — не шумовой шар

Каноническое поле строится в следующем порядке:

```text
reference ellipsoid
+ three deterministic directional deformation bands
+ stable additive lobes
- stable impact crater volumes
- stable enclosed natural void
```

### 3.1. Reference ellipsoid

Базовые осевые масштабы:

```text
X: 1.12
Y: 0.94
Z: 1.04
```

Это создаёт исходную крупную форму, которая не зависит от текущей камеры, streaming window или render origin.

### 3.2. Directional deformation

Три слоя value noise вычисляются только из:

```text
body-local direction
seed
channel
frequency
```

Они не содержат mutable RNG state. Порядок запросов не влияет на результат.

### 3.3. Stable features

MW1 фиксирует семь features:

```text
matter-feature/asteroid-mw1/lobe-a
matter-feature/asteroid-mw1/lobe-b
matter-feature/asteroid-mw1/crater-a
matter-feature/asteroid-mw1/crater-b
matter-feature/asteroid-mw1/natural-void-a
matter-feature/asteroid-mw1/ore-lens-a
matter-feature/asteroid-mw1/ice-pocket-a
```

Их координаты слегка смещаются детерминированным hash field от seed, но identity и semantic role остаются стабильными.

Stable feature ID нужен для:

- diagnostics;
- future migration;
- survey results;
- selective regeneration;
- persistence provenance;
- сравнения разных версий генератора.

## 4. Геологическая модель MW1

MW1 не претендует на полную планетологическую модель. Он фиксирует минимальную неоднородную геологию, достаточную для MW2–MW4.

### 4.1. Shells

```text
0–14 m from local field boundary:
    compacted regolith + fractured basalt

14–72 m:
    fractured basalt + basalt

deeper:
    basaltic interior
```

Геологическая глубина оценивается через отрицательное расстояние до **solid envelope** — формы после внешних деформаций и кратеров, но до вычитания закрытых внутренних пустот. Это O(1) запрос и не требует ray search до внешней поверхности. Благодаря этому стены естественной полости сохраняют глубинную породу и не превращаются ошибочно в поверхностный реголит.

### 4.2. Resource features

Железо-никелевая линза и ледяной карман задаются отдельными ellipsoid influence fields. Внутри них состав плавно меняется, а MW0 `MatterComposition` остаётся нормализованным.

### 4.3. Bulk density

Сначала определяется specific volume смеси по mass fractions:

```text
specific_volume = Σ(mass_fraction / material_density)
solid_density   = 1 / specific_volume
bulk_density    = solid_density × (1 - porosity)
```

Это позволяет вычислять массу неоднородного тела через один sampler, не создавая отдельную таблицу density voxels.

## 5. Natural void

`natural-void-a` является закрытой внутренней полостью. Она доказывает, что каноническая геометрия уже поддерживает topology сложнее heightfield:

- точка внутри полости возвращает vacuum;
- центр астероида остаётся occupied;
- порода непосредственно за стеной полости классифицируется по глубине до внешнего solid envelope;
- внешний surface query ищет самый внешний переход vacuum → matter и не принимает внутреннюю полость за поверхность тела.

Полость пока неизменяема. Persistent mutations начинаются после MW2/MW4.

## 6. Детерминированное поле

`DeterministicField3D` использует integer hash в безопасном 64-bit диапазоне и trilinear value noise.

Гарантии MW1:

- отсутствует глобальный RNG;
- отсутствует mutable cache, влияющий на значение;
- одинаковые `position + seed + channel` дают одинаковый результат;
- другой channel создаёт независимое поле;
- генератор работает headless и без SceneTree.

Детерминизм зафиксирован для одной generator version. Смена алгоритма требует новой версии generator profile.

## 7. Surface query

`surface_radius_m(direction)` нужен для diagnostics и будущего meshing bootstrap.

Алгоритм:

1. начинает в гарантированно пустом root bound;
2. идёт к центру фиксированным числом шагов;
3. выбирает первый внешний переход в matter;
4. уточняет его bisection;
5. игнорирует внутренние void transitions.

Sampler не вызывает этот алгоритм для каждой точки. Это отдельный, более дорогой запрос.

## 8. Mass integration

`MatterBodyMassIntegrator` выполняет детерминированную midpoint integration по фиксированной cubic grid.

Результат — checksum-protected `MatterBodyMassEstimate`:

- resolution;
- bounds и voxel edge;
- occupied sample count;
- approximate volume;
- total mass;
- center of mass;
- mass by material.

Материальная сумма обязана совпадать с total mass в относительной tolerance. Integrator является тестовым/аналитическим инструментом MW1, а не будущим production storage.

## 9. Golden control fixture

Зафиксированы 128 body-fixed coordinates:

- центр;
- оси;
- внешние точки;
- центры stable features;
- детерминированное облако дополнительных точек.

Для каждой точки строится quantized integer signature. В manifest хранится canonical SHA-256:

```text
d5d4b6cde3b4685757bef65bd86dbfb36cc7c08416a802f4d5f4bf8fd5de5f57
```

Quantization отделяет generator regression от несущественного platform-specific textual formatting float.

## 10. Граница этапа

MW1 добавляет только domain/generation/analysis code.

Не входят:

- sparse bricks;
- materialized edits;
- mesh и Transvoxel;
- collision;
- runtime world или отдельная сцена астероида;
- изменение Луны;
- Item Graph transfer;
- persistence;
- authority/network replication;
- fracture и body splitting.

## 11. Focused gate

```powershell
$godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_MW1_FIXED_SEED_ASTEROID_TESTS.ps1 -GodotPath $godot
```

Проверяются:

- profile и feature contracts;
- deterministic field properties;
- same seed/version replay;
- different-seed divergence;
- golden fixture;
- query-order independence;
- closed outer surface;
- natural void;
- resource compositions;
- 600 random body-local samples;
- material references;
- mass integration replay;
- convergence 16³ → 20³;
- mass/material balance;
- negative configuration fences.

После focused PASS требуется MW0, A3 и M6 regression.
