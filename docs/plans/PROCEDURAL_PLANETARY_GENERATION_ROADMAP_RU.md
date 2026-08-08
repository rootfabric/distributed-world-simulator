# Procedural Planetary Generation Roadmap — от мега-казуального ядра до детальной геоморфологии

**Ветка:** `feature/g0-procedural-planetary-generation-lab`.
**Статус:** experimental roadmap; production terrain не заменяет.
**Архитектура:** `docs/architecture/PROCEDURAL_PLANETARY_GENERATION_FABRIC_RU.md`.
**High-resolution backend:** `docs/architecture/HIGH_RESOLUTION_DETAIL_GENERATOR_RU.md`.
**Validation:** `docs/validation/PROCEDURAL_PLANET_LAB_ACCEPTANCE_RU.md`.

---

## 1. Цель экспериментальной программы

Первая программа не пытается сразу создать красивую Землю.

Нужно доказать правильность общей логики:

```text
body-fixed geodesy
→ planetary addressing
→ deterministic provider graph
→ continuous fields
→ stable WorldFeatures
→ multi-LOD representation
→ surface + volume
→ progressive refinement
→ replaceable generators
```

Визуально первые stages могут быть намеренно простыми.

Основной критерий:

> Лучше один уродливый холм, который корректно существует на всех LOD, чем красивый terrain generator, который нельзя заменить и который ломается на границах chunks.

---

## 2. Изолированный world runtime

Рекомендуемый world:

```text
world_id: procedural_planet_lab
body_id: procedural-planet-lab-001
body_seed: 2026080801
recipe_id: casual-earthlike-v1
nominal_radius_m: 6000000.0
```

Экспериментальный active region:

```text
примерно 64 km × 32 km
```

Целевая демонстрационная река:

```text
примерно 40 km
```

Камера должна иметь возможность начать fly-in примерно с 30–50 km над active region и дойти до ground level.

Production `moon`, `earth`, `earth_moon`, Matter labs и сетевые scenes на ранних этапах не меняются.

---

# M0 — GeoKernel foundation

## G0 — Contracts freeze v0

### Цель

Ввести чистые data/domain contracts без mesh, SceneTree и renderer assumptions.

### Добавить концептуально

```text
PlanetDefinition
PlanetEnvironment
PlanetRecipe
IGeoProvider
GeoGenerationContext
GeoSurfaceQuery
GeoVolumeQuery
GeoSample
GeoFieldBundle
```

### Первая реализация

`FlatSurfaceProvider`.

### Acceptance

```text
[PASS] contracts работают headless
[PASS] exact provider ids/versions
[PASS] invalid dependency graph rejected
[PASS] GeoKernel не импортирует renderer classes
[PASS] provider можно заменить без изменения caller
```

### Не делать

- mountains;
- river;
- caves;
- streaming optimization.

---

## G1 — Geodesy + body shape

### Цель

Доказать корректную работу планетарного пространства.

### Реализация

```text
SphereBodyShapeProvider
GeodesyService
BodyFixedPosition
GeodeticPosition
LocalTangentFrame
```

### Тесты

```text
body → geodetic → body roundtrip
stable surface normal
stable altitude
stable tangent East/North/Up
large double-precision coordinates
pole/equator cases
```

### Visual Lab

Гладкая одноцветная сфера радиусом около 6000 km.

### Gate

Fly-in от десятков километров до поверхности не вызывает coordinate jitter, NaN и orientation discontinuity.

---

## G2 — Surface cells + LOD selection

### Цель

До сложного terrain доказать planetary subdivision и representation lifecycle.

### Реализация

```text
SurfaceCellKey
cube-sphere-compatible cell addressing
quadtree refinement
neighbor lookup
LOD selection
basic hysteresis
```

Terrain остаётся гладким.

### Debug

```text
cell boundaries
cell ids
LOD level
requested/active cells
```

### Gate

```text
[PASS] parent/children stable
[PASS] neighbor boundaries stable
[PASS] no cracks between same-level cells
[PASS] repeated fly-in/out does not leak cells
[PASS] LOD state does not affect GeoSample semantics
```

---

## G3 — Mega Casual Surface

### Цель

Первая процедурная поверхность, намеренно очень простая.

### Реализация

`CasualMacroTerrainProviderV1`:

```text
very low frequency deterministic noise
+ radial displacement
```

Пример диапазона:

```text
macro wavelength: kilometers
height amplitude: hundreds of meters
```

### Что должно быть видно

Большие мягкие холмы/горы.

### Gate

Одна и та же macro form сохраняется при fly-in через все LOD.

---

## G4 — Provider composition

### Цель

Доказать, что GeoKernel — композитор, а не монолитный generator.

### Providers

```text
BaseSurfaceProvider
CasualMacroTerrainProvider
CasualValleyProvider
```

### Обязательный эксперимент

Заменить `CasualMacroTerrainProviderV1` на `AlternativeMacroTerrainProviderV1`.

Нельзя менять:

```text
renderer
streaming
SurfaceCellKey
GeoKernel call sites
```

### Gate

Provider replacement проходит тесты и visual lab.

---

# M1 — Feature world

## G5 — WorldFeature + FeatureGraph

### Цель

Перевести крупные географические признаки выше уровня chunks.

### Первый feature

```text
ValleyFeature
```

Параметры:

```text
feature_id
seed
centerline
width
depth
bounds
```

### Реализация

Простейший analytic carve по расстоянию до centerline.

### Gate

Одна ValleyFeature пересекает множество cells и имеет непрерывную форму.

---

## G6 — Mega Casual River

### Цель

Получить первую длинную procedural river без реальной hydrology simulation.

### RiverFeature

```text
feature_id
centerline spline
width function
depth function
water_level
seed
```

### Runtime

Surface provider просто вырезает русло по signed/unsigned distance к centerline.

Water presentation может быть максимально простой.

### Gate

40 km river:

```text
[PASS] пересекает множество cells
[PASS] не рвётся на границах
[PASS] stable feature id
[PASS] deterministic same seed
[PASS] видна с regional и local LOD
```

---

## G7 — River fields

### Цель

Отвязать downstream generators от concrete river implementation.

### Поля v0

```text
river_distance
river_side
river_width
river_depth
water_level
flow_direction
flow_strength
curvature
erosion
deposition
```

В первой версии erosion/deposition могут быть очень грубыми analytic heuristics.

### Debug views

Обязательная визуализация:

```text
river_distance
curvature
erosion
deposition
```

### Gate

Другой provider может читать fields, не имея ссылки на `CasualRiverProvider`.

---

## G8 — Casual geomorphology

### Цель

Доказать причинную композицию features.

### Providers

```text
CasualCliffProvider
CasualShoalProvider
CasualIslandProvider
CasualRiverTerraceProvider
```

### Правила v0

Примерно:

```text
outer bend + high erosion → cliff candidate
inner bend + deposition → shoal
wide river + deposition peak → island
```

Результат может быть визуально грубым.

### Gate

Feature output объясним через debug fields, а не случайные chunk-local decisions.

---

## G9 — Geology Lite

### Цель

Ввести влияние материала без сложной geological simulation.

### Materials v0

```text
SOFT
MEDIUM
HARD
```

### Provider

`SimpleGeologyProviderV1` создаёт крупные deterministic regions/strata.

### Реакция geomorphology

```text
SOFT → wider banks / deposition
HARD → narrow cuts / stronger cliff retention
```

### Gate

При той же RiverFeature замена geology profile меняет форму берега без изменения river identity.

---

# M2 — Volumetric world

## G10 — GeoVolume contract implementation

### Цель

Мир перестаёт быть архитектурно ограничен heightfield.

### V0

```text
below surface → SOLID
above surface → AIR
```

Опционально возвращаются:

```text
signed_distance
density
material_id
hardness
```

### Gate

Volume query детерминирован и не требует построенного mesh.

---

## G11 — Mega Casual Cave

### Цель

Доказать natural interior без отдельной сцены/teleport.

### CaveProvider v0

Пещера = несколько analytic sphere/capsule SDF subtraction primitives.

### Feature linkage

```text
RiverFeature
→ CliffFeature
→ CaveFeature
```

Причина пока может быть фиксированной rule/config, но identity/dependency должны быть настоящими.

### Visual goal

```text
fly to river
→ approach cliff
→ see cave entrance
→ enter cave
```

### Gate

```text
[PASS] cave is one GeoVolume world
[PASS] no loading teleport
[PASS] cave stable across reload
[PASS] surface/volume adapters agree at entrance
```

---

# M3 — Streaming and refinement

## G12 — Cache + generation scheduler boundaries

### Цель

Подготовить систему к дорогим поздним providers.

### Кэши

```text
FeatureCache
FieldCache
SurfaceSampleCache
VolumeSampleCache
RepresentationArtifactCache
```

### Правило

Cache key обязан включать все versioned dependencies:

```text
body/recipe
provider manifest
scope
resolution/error tier
source/dependency hash
```

### Scheduler

Data generation выполняется отдельно от main-thread scene commit.

### Gate

Повторный fly-in использует cache и не меняет canonical results.

---

## G13 — Progressive detail contract

### Цель

Заморозить API, через который позднее будет независимо развиваться high-resolution generator.

### Ввести

```text
DetailPatchRequest
DetailPatchContext
DetailPatchArtifact
DetailSemanticMask
DetailBudget
```

### Важно

На этом этапе high-resolution generator может быть stub:

```text
returns no detail
```

Главное — contract.

### Gate

Stub backend можно заменить на fake-detail backend без изменения GeoKernel/renderer selection contract.

После acceptance G13 допускается отдельная параллельная ветка:

```text
feature/gh0-high-resolution-detail-generator
```

---

## G14 — Simple Detail Generator

### Цель

Проверить progressive refinement на простой реализации.

### Генерировать

```text
large rocks
small rocks
gravel descriptors
simple bank micro displacement
material masks
```

### Уровни

Пример policy:

```text
> 2 km    macro only
200–2000 m feature silhouettes
20–200 m large detail
2–20 m    physical near detail
< 2 m     dense local detail / micro material
```

### Gate

При приближении новые детали добавляются детерминированно; уже существующие крупные детали не прыгают и не меняют identity/position.

---

# M4 — Replaceability and planet recipes

## G15 — Multiple PlanetRecipe acceptance

### Recipe A — Casual Earthlike

```text
Sphere
CasualMacroTerrain
CasualRiver
SimpleGeology
CasualCaves
SimpleDetail
```

### Recipe B — Dry Rocky

```text
Sphere
TerracedMacroTerrain
No/rare Hydrology
HardGeology
FractureCaves
RockyDetail
```

### Gate

Один GeoKernel и один lab runtime запускают обе планеты только конфигурацией.

Запрещены planet-specific branches в core.

---

## G16 — Generator substitution acceptance

### Обязательные замены

```text
MacroTerrain V1 → V2
River V1 → AlternativeRiver V1
Geology V1 → LayeredGeology stub
Detail stub → HighResolution backend stub
```

### Gate

Downstream contracts остаются совместимыми или явно отклоняют несовместимую contract version до runtime generation.

---

# M5 — Future integration, not part of first prototype

## G17 — Matter bridge

Только после proof-of-concept GeoVolume.

```text
procedural GeoVolume baseline
+
persistent Matter deltas
```

Не смешивать с G0–G16.

## G18 — Representation LOD integration

Использовать существующий RL Fabric для:

```text
macro proxy
regional mesh
local mesh
volumetric detail
high-resolution artifacts
```

## G19 — Network manifest integration

Синхронизировать:

```text
recipe id
provider manifest versions
feature provenance
persistent deltas
```

---

# 3. Параллельный High-Resolution track

После G13 development graph становится:

```text
MAIN GEO TRACK
G13 → G14 → G15 → G16 → ...
  │
  └──────── stable DetailPatch contract
                   │
                   ▼
HIGH-RES TRACK
GH0 contracts fixture
 → GH1 100m patch lab
 → GH2 cm–dm geometry
 → GH3 material micro detail
 → GH4 collision promotion
 → GH5 performance budgets
 → GH6 composition acceptance
```

High-resolution track не должен ожидать готовности всей планеты.

Он получает записанный fixture `DetailPatchContext` и генерирует один локальный patch offline/headless/visual lab.

---

# 4. Что считать первым большим milestone

## `G11 — River Valley Fly-In + Cave Acceptance`

Пользователь стартует примерно в 30–50 km над active region.

```text
regional mountains/valley
        ↓
long river
        ↓
island / shoal / cliff
        ↓
land near cliff
        ↓
cave entrance
        ↓
enter cave
```

Мир может быть стилизованно простым.

Но должно быть доказано:

```text
one seed
one body-fixed coordinate system
one feature graph
replaceable providers
multi-LOD surface
continuous fields
volume interior
no chunk-local geography
```

После этого имеет смысл серьёзно инвестировать в визуальную реалистичность.

---

# 5. Что сознательно запрещено оптимизировать слишком рано

До G11 не является целью:

```text
cinematic terrain quality
real hydraulic erosion
millions of rocks
GPU compute generator
perfect water rendering
photogrammetry-style materials
production network replication
full persistence
```

Оптимизация разрешена только если без неё нельзя доказать lifecycle/LOD correctness.

---

# 6. Branch/checkpoint policy

Основная planning/architecture ветка:

```text
feature/g0-procedural-planetary-generation-lab
```

После начала кода каждый крупный этап рекомендуется вести короткоживущей веткой:

```text
feature/g1-planetary-geodesy
feature/g2-planetary-surface-cells
feature/g3-casual-macro-surface
feature/g4-geo-provider-composition
feature/g5-world-feature-graph
feature/g6-casual-river
...
```

High-resolution направление после contract freeze:

```text
feature/gh0-high-resolution-detail-generator
```

Каждый checkpoint должен иметь:

```text
focused tests
negative contract tests
determinism tests
order-independence tests
visual acceptance where applicable
regression against current accepted main
```

---

# 7. Критерий готовности к усложнению алгоритмов

Переход от «mega casual» к realistic providers разрешается только после подтверждения:

```text
[PASS] replaceability
[PASS] determinism
[PASS] cross-cell continuity
[PASS] LOD semantic stability
[PASS] provider dependency validation
[PASS] surface/volume separation
[PASS] debug observability
[PASS] cache/version provenance
```

После этого качество можно повышать независимо:

```text
CasualRiver
→ MeanderingRiver
→ DrainageRiver
→ HydraulicRiver
```

```text
SimpleGeology
→ LayeredGeology
→ Tectonic/stratigraphic model
```

```text
SimpleDetail
→ HighResolutionDetailGenerator
→ specialized biome/geology detail backends
```

Фундамент при этом не должен меняться.
