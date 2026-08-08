# Procedural Planetary Generation — исполнительный план реализации

**Ветка программы:** `feature/g0-procedural-planetary-generation-lab`  
**Статус:** архитектурная программа зафиксирована; production runtime не изменён.  
**Назначение документа:** практический порядок реализации от пустого GeoKernel до fly-in, реки, скалы, пещеры и параллельного high-resolution detail generator.

Связанные документы:

- `docs/architecture/PROCEDURAL_PLANETARY_GENERATION_FABRIC_RU.md`
- `docs/plans/PROCEDURAL_PLANETARY_GENERATION_ROADMAP_RU.md`
- `docs/architecture/HIGH_RESOLUTION_DETAIL_GENERATOR_RU.md`
- `docs/validation/PROCEDURAL_PLANET_LAB_ACCEPTANCE_RU.md`
- `docs/procedural/STATUS_RU.md`
- `docs/architecture/adr/ADR-019-procedural-planetary-generation-fabric.md`

---

# 1. Главная цель

Сначала реализуется архитектурно правильный, но намеренно простой procedural world. Реализм откладывается до тех пор, пока не доказаны:

```text
determinism
+ body-fixed geodesy
+ stable planetary addressing
+ provider replacement
+ feature identity
+ continuous fields
+ LOD independence
+ surface/volume separation
+ progressive detail
```

Целевой первый вертикальный сценарий:

```text
камера 30–50 km над планетой
        ↓
видна крупная долина
        ↓
видна длинная река
        ↓
при приближении появляются береговые формы
        ↓
видны остров / отмель / cliff
        ↓
посадка рядом со скалой
        ↓
локальная детализация усиливается
        ↓
в скале есть простая объёмная пещера
        ↓
игрок может войти внутрь
```

Весь сценарий должен происходить в одном процедурном мире, от одного seed и через один GeoKernel.

---

# 2. Жёсткие правила реализации

Эти правила считаются архитектурными инвариантами программы.

## 2.1. Generator != Renderer

GeoKernel и providers возвращают данные/поля/feature semantics. Они не создают `MeshInstance3D`, collision nodes или scene hierarchy.

## 2.2. LOD != World State

LOD меняет плотность sampling и representation budget, но не географический смысл мира.

## 2.3. Feature != Chunk

Река, хребет, долина, скала, пещера и остров существуют независимо от текущих streaming cells.

## 2.4. High-resolution detail != canonical topology

Мелкий визуальный detail может быть производным artifact. Проходимая пещера, отверстие, существенный навес, изменяемая полость или topology-changing geometry должны принадлежать GeoVolume/WorldFeature/Matter.

## 2.5. Procedural baseline + persistent delta

Процедурный baseline не сохраняется как mesh. Изменения игрока в будущем хранятся отдельно.

## 2.6. Provider replacement обязателен

Любой крупный генераторный слой должен быть заменяем через контракт, без `if planet_type == ...` в GeoKernel.

---

# 3. Организация веток

Архитектурная ветка:

```text
feature/g0-procedural-planetary-generation-lab
```

Рекомендуется не вести всю реализацию одним огромным diff. После фиксации архитектуры каждый gate выполняется короткой feature-веткой от актуальной согласованной базы.

Рекомендуемые ветки:

```text
feature/g0-geo-contracts
feature/g1-geodesy-body-shape
feature/g2-planetary-cells-lod
feature/g3-casual-macro-surface
feature/g4-provider-composition
feature/g5-world-feature-graph
feature/g6-casual-river
feature/g7-geo-fields
feature/g8-casual-geomorphology
feature/g9-geology-lite
feature/g10-geo-volume
feature/g11-casual-cave
feature/g12-progressive-detail
feature/g13-detail-patch-contract
feature/g14-detail-budget-streaming
feature/g15-planet-recipes
feature/g16-generator-substitution-acceptance
```

После G13 отдельно открывается:

```text
feature/gh0-high-resolution-detail-generator
```

HR track не должен изменять GeoKernel contracts без отдельного архитектурного review.

---

# 4. Фаза A — фундамент GeoKernel

## G0 — Contracts freeze v0

### Цель

Создать чистое domain/data ядро без SceneTree и rendering dependencies.

### Реализовать

Минимальные типы:

```text
PlanetDefinition
PlanetEnvironment
PlanetRecipe
GeoKernel
IGeoProvider
GeoProviderDescriptor
GeoGenerationContext
GeoSurfaceQuery
GeoVolumeQuery
GeoSample
GeoFieldBundle
```

Минимальный provider:

```text
FlatSurfaceProvider
```

### Обязательные свойства provider descriptor

```text
provider_id
generator_version
requires[]
provides[]
deterministic
```

### Реализовать validator provider graph

Он должен обнаруживать:

```text
missing dependency
duplicate provider output
cyclic dependency
unknown provider id
invalid generator version
```

### Тесты

```text
same input → same GeoSample
invalid graph rejected
provider order normalized deterministically
no Node/Mesh dependency in contracts
provider replacement works through interface
```

### Gate G0

GeoKernel headless принимает `FlatSurfaceProvider`, возвращает стабильный sample и может заменить его альтернативным provider без изменения caller.

### После G0 НЕ делать

Реки, горы, LOD, визуальную красоту.

---

## G1 — Geodesy + Body Shape

### Цель

Сделать корректную геодезическую основу для планет разной формы.

### Реализовать

```text
IBodyShapeProvider
SphereBodyShapeProvider
BodyFixedPosition
GeodeticPosition
LocalTangentFrame
GeodesyService
```

Минимальные операции:

```text
body_to_geodetic()
geodetic_to_body()
surface_normal()
altitude()
local_tangent_frame()
```

### Первая планета

```text
radius = 6_000_000 m
```

### Тесты

- equator roundtrip;
- pole roundtrip;
- arbitrary latitude/longitude;
- altitude ± values;
- tangent frame orthonormality;
- double precision на больших body-fixed координатах;
- отсутствие NaN/INF.

### Visual check

Гладкая сфера; камера может двигаться от десятков километров до поверхности.

### Gate G1

Координатная система и tangent frame не зависят от renderer origin и не дают заметного jitter в лаборатории.

---

## G2 — Planetary Surface Cells + LOD lifecycle

### Цель

Доказать planet-scale addressing до появления сложного terrain.

### Реализовать

```text
SurfaceCellKey
cube-sphere face addressing
quadtree parent/children
neighbor lookup
LOD selector
basic hysteresis
active/requested cell lifecycle
```

### Важно

`SurfaceCellKey` — адрес representation/streaming, а не identity feature.

### Debug modes

```text
cell bounds
cell id
LOD level
requested
building
active
retiring
```

### Тесты

- parent/children roundtrip;
- stable neighbors;
- no same-LOD edge gaps;
- repeated fly-in/fly-out;
- no leaked cell records;
- same GeoSample независимо от выбранного cell LOD.

### Gate G2

Гладкая сфера стабильно уточняется и огрубляется при движении камеры.

---

# 5. Фаза B — первая намеренно примитивная география

## G3 — Mega Casual Macro Surface

### Цель

Впервые получить горы/холмы, но не тратить время на реализм.

### Реализовать

```text
CasualMacroTerrainProviderV1
```

Принцип:

```text
low-frequency deterministic field
→ radial displacement
```

Типичный масштаб:

```text
wavelength: несколько километров
amplitude: сотни метров
```

### Gate G3

Одна крупная форма визуально остаётся той же при переходах от дальнего LOD к близкому.

---

## G4 — Provider Composition

### Цель

Доказать, что генератор — композиция слоёв, а не монолит.

### Реализовать минимум

```text
BaseSurfaceProvider
CasualMacroTerrainProviderV1
CasualValleyModifierProviderV1
```

### Обязательный тест подмены

Заменить:

```text
CasualMacroTerrainProviderV1
```

на:

```text
AlternativeMacroTerrainProviderV1
```

не меняя:

```text
GeoKernel
renderer
cell streaming
query callers
```

### Gate G4

Подмена provider проходит как configuration/recipe change.

---

# 6. Фаза C — WorldFeature и река

## G5 — WorldFeature / FeatureGraph

### Цель

Отделить долговременные географические признаки от streaming cells.

### Реализовать

```text
WorldFeature
FeatureId
FeatureBounds
FeatureGraph
FeatureQuery
```

Минимальная feature:

```text
ValleyFeature
```

Поля identity:

```text
feature_id
feature_type
seed
generator_version
bounds
parent_feature_id optional
```

### Первый ValleyFeature

Простой spline + width + depth falloff.

### Gate G5

Долина пересекает много cells, но существует как одна feature identity.

---

## G6 — Mega Casual River

### Цель

Создать длинную реку без настоящей гидрологии.

### Реализовать

```text
RiverFeature
RiverSpline
CasualRiverProviderV1
WaterPresentationAdapter
```

Простейшие параметры:

```text
centerline
width(s)
depth(s)
water_level(s)
seed
```

Целевая длина лабораторной реки:

```text
~40 km
```

### Важно

Река не создаётся отдельно каждым cell.

### Gate G6

Один RiverFeature бесшовно пересекает десятки/сотни cells и сохраняет identity при fly-in/out.

---

## G7 — Semantic Geo Fields

### Цель

Перестать заставлять downstream generators знать внутреннее устройство RiverProvider.

### Реализовать RiverField

Минимальные channels:

```text
river_distance
river_width
water_level
flow_direction
curvature
erosion
deposition
```

Пока erosion/deposition могут быть очень грубыми.

### Debug visualization

Каждый channel должен иметь отдельный визуальный overlay.

### Gate G7

Независимый provider может использовать `erosion/deposition`, ничего не зная о spline implementation.

---

# 7. Фаза D — причинная геоморфология

## G8 — Casual Geomorphology

### Реализовать отдельными providers

```text
CasualCliffProviderV1
CasualShoalProviderV1
CasualIslandProviderV1
CasualBankProviderV1
```

Пример правил:

```text
high erosion + slope → cliff
high deposition + wide river → shoal/island
low flow + deposition → beach/bar
```

### Gate G8

Река порождает связанные береговые формы через semantic fields, а не прямые вызовы конкретных генераторов.

---

## G9 — Geology Lite

### Цель

Добавить причинность через материал, но без полноценной геологической симуляции.

### Реализовать

```text
SimpleGeologyProviderV1
```

Первая классификация:

```text
SOFT
MEDIUM
HARD
```

Дополнительные fields:

```text
rock_hardness
material_id
strata_hint
```

### Проверка

На HARD участке река должна давать более узкий/крутой профиль, на SOFT — более широкий и пологий.

### Gate G9

Geomorphology реагирует на geology через контрактные поля.

---

# 8. Фаза E — переход от surface к volume

## G10 — GeoVolume Contract

### Цель

Снять ограничение heightfield-only до реализации реальной пещеры.

### Реализовать

```text
GeoVolumeQuery
GeoVolumeSample
IVolumeProvider
```

Минимальные channels:

```text
signed_distance
matter_class
material_id
hardness
```

Первая реализация:

```text
ниже surface → SOLID
выше surface → AIR
```

### Gate G10

Любая точка пространства может быть определена как volume sample без обращения к renderer mesh.

---

## G11 — Mega Casual Cave

### Цель

Доказать topology-changing procedural geometry.

### Реализовать

```text
CaveFeature
CasualCaveVolumeProviderV1
```

Первая пещера:

```text
несколько sphere/capsule SDF
boolean subtraction из базового volume
```

Связать её с конкретным CliffFeature через FeatureGraph.

### Visual acceptance

```text
fly-in
→ cliff
→ visible entrance
→ approach
→ enter cave
```

### Gate G11

Пещера является volume/feature truth, а не декоративной дырой в mesh.

---

# 9. Фаза F — progressive detail

## G12 — Detail hierarchy

### Цель

Разделить географическую истину и всё более плотное представление.

Ввести уровни:

```text
D0 GEO/MACRO      kilometers → tens of meters
D1 STRUCTURAL     hundreds → meters
D2 PHYSICAL       meters → ~10 cm
D3 MICRO VISUAL   < ~10 cm
```

Для каждого результата явно отмечать:

```text
visual_relevance
collision_relevance
simulation_relevance
canonical_relevance
```

### Gate G12

При приближении detail добавляется, но уже существующие крупные features не меняют identity/location.

---

## G13 — DetailPatchContext freeze

### Это ключевой fork point программы.

После G13 основной planet generator и high-resolution generator могут развиваться параллельно.

### Реализовать immutable-ish input contract

```text
DetailPatchContext
```

Он должен содержать достаточный локальный контекст, например:

```text
body_id
world_seed
patch_id
body-fixed anchor
local tangent frame
bounds
requested_detail_scale
surface samples
surface normals
slope
curvature
geology fields
material fields
river fields
erosion/deposition
nearby stable feature descriptors
volume boundary hints
generator/source versions
```

### Нельзя передавать

```text
MeshInstance3D
SceneTree nodes
renderer-specific material instances
mutable global state
camera object
network peer
```

### Fixtures

Зафиксировать минимум:

```text
flat_plain_100m
river_inner_bank_100m
river_outer_cliff_100m
hard_rock_cliff_100m
cave_entrance_100m
```

### Gate G13

HR generator может полностью тестироваться на записанном `DetailPatchContext` без запуска планеты.

---

# 10. Параллельный High-Resolution track

После G13 открыть:

```text
feature/gh0-high-resolution-detail-generator
```

## GH0 — Fixture harness

Читает recorded DetailPatchContext и генерирует локальный patch вне planet runtime.

## GH1 — Structural detail

Добавляет:

```text
ledges
fracture families
boulders
talus
small erosion cuts
rock clusters
```

Масштаб примерно метры → десятки сантиметров.

## GH2 — Physical near detail

Добавляет collision-relevant формы только в пределах согласованного physical budget.

Например:

```text
20–50 cm rocks
small steps
walkable ledges
shallow channels
```

## GH3 — Micro visual detail

Не mesh-first. Использовать:

```text
material masks
normal detail
procedural roughness
micro displacement where appropriate
decals
small non-canonical scatter
```

## GH4 — Promotion boundary

Любая новая форма, которая меняет topology/gameplay, не остаётся HR artifact.

Она должна быть promoted/requested в:

```text
GeoVolume / WorldFeature / Matter
```

## GH5 — Determinism + nesting

Обязательное правило:

```text
coarse patch features ⊂ finer patch features
```

Крупный камень, появившийся на 5 m detail, не должен исчезнуть при переходе к 50 cm detail.

## GH6 — Performance budgets

Измерять отдельно:

```text
CPU generation ms
GPU/upload cost
vertex count
instance count
collision count
RAM/cache footprint
```

## GH7 — Mainline integration

HR generator подключается как один из DetailProvider backends. GeoKernel не меняется ради его интеграции.

---

# 11. Фаза G — budgets, streaming и recipes

## G14 — Detail budget + cache

Ввести:

```text
DetailBudget
GeoGenerationBudget
DetailPatchCache
```

Бюджеты должны определять количество работы, но не world identity.

Пример:

```text
far: detail_budget = 0.02
regional: 0.10
near: 0.50
contact: 1.00
```

Gate: изменение budget меняет качество/стоимость, но не переносит реку, cliff или cave.

---

## G15 — PlanetRecipe profiles

Создать минимум два radically different recipes.

### CasualEarthLikeV1

```text
SphereBodyShape
CasualMacroTerrain
CasualRiver
SimpleGeology
CasualCave
TemperateDetail placeholder
```

### DryRockyWorldV1

```text
SphereBodyShape
TerracedMacroTerrain
SparseDryChannel
HardGeology
FractureCavity
RockyDetail placeholder
```

Gate: одна лаборатория и один GeoKernel запускают оба recipe.

---

## G16 — Generator substitution acceptance

Это финальная проверка архитектуры первой программы.

Нужно последовательно заменить минимум:

```text
macro surface provider
river provider
geology provider
detail provider
```

без изменений общих callers и renderer contract.

Gate:

```text
[PASS] no planet-type branching in GeoKernel
[PASS] no provider-specific branching in renderer
[PASS] same validation harness works for both recipes
[PASS] deterministic fixtures versioned
```

---

# 12. Отдельный Fly-In Acceptance Scenario

После каждого визуального этапа не создавать новый ad-hoc lab. Расширять один:

```text
procedural_planet_lab
```

Финальный сценарий первой программы:

```text
1. Spawn spectator at ~50 km altitude.
2. Confirm same macro valley visible at far LOD.
3. Descend to ~10 km; river becomes readable.
4. Descend to ~1 km; islands/cliffs become distinguishable.
5. Descend to ~100 m; structural detail appears.
6. Land near selected cliff.
7. Confirm near-detail refinement without feature relocation.
8. Approach cave entrance.
9. Enter cave.
10. Move back outside and climb to altitude again.
11. Confirm no identity/seam/cache corruption after roundtrip.
```

---

# 13. Debug UI, обязательный с ранних этапов

Рекомендуемые режимы:

```text
F1 normal
F2 surface cells
F3 LOD
F4 provider outputs
F5 features
F6 river field
F7 erosion/deposition
F8 geology
F9 volume/SDF
F10 detail layers
F11 cache/build state
F12 generation timing
```

Debug overlays являются частью acceptance infrastructure, а не временным удобством.

---

# 14. Автоматическая проверка на каждом этапе

Каждый stage должен иметь focused runner и общий regression subset.

Минимальные общие свойства:

## Determinism

```text
same seed + same versions + same coordinates = same logical result
```

## Query order independence

```text
A → B == B → A
```

## Cell independence

Соседние cells не могут менять Feature identity или semantics.

## LOD compatibility

Более детальное представление уточняет coarse representation, но не заменяет географию другой.

## Provider isolation

Provider нельзя заставлять читать renderer/network mutable state.

## Version visibility

Generator version всегда входит в provenance результата/fixture/cache key.

---

# 15. Что сознательно запрещено делать слишком рано

До завершения первой программы не требуется:

```text
real tectonic simulation
full hydraulic erosion
climate simulation
real sediment transport
vegetation ecology
dynamic rivers
fully realistic karst simulation
centimeter mesh over entire region
planet-wide SDF allocation
Matter persistence integration
network replication of generated terrain
```

Эти возможности должны подключаться новыми providers/backends позднее.

---

# 16. Точки, после которых можно распараллеливать работу

```text
G0 accepted
├─ provider implementations можно писать параллельно

G2 accepted
├─ renderer/LOD experiments можно вести отдельно

G7 accepted
├─ geomorphology generators можно разрабатывать независимо

G10 accepted
├─ cave/volume backends можно развивать независимо

G13 accepted
├─ MAIN PLANET TRACK
└─ HIGH-RESOLUTION DETAIL TRACK  ← ключевой fork
```

Главный fork:

```text
                         G13 DetailPatchContext
                                  │
                   ┌──────────────┴──────────────┐
                   ▼                             ▼
            PLANET / GEO TRACK              HR DETAIL TRACK
            G14/G15/G16...                  GH0/GH1/GH2...
```

---

# 17. Рекомендуемый порядок реальной работы сейчас

Не начинать с всей программы сразу.

Первая реализационная серия:

```text
STEP 1  G0 contracts + FlatSurfaceProvider
STEP 2  G1 sphere/geodesy
STEP 3  G2 cube-sphere cells + LOD
STEP 4  G3 casual macro hills
STEP 5  G4 provider replacement proof
```

После этого сделать первый архитектурный review.

Вторая серия:

```text
STEP 6  G5 FeatureGraph + ValleyFeature
STEP 7  G6 40 km RiverFeature
STEP 8  G7 RiverField + debug overlays
STEP 9  G8 cliffs/islands/shoals
STEP 10 G9 geology lite
```

После этого должен появиться первый интересный river-valley fly-in.

Третья серия:

```text
STEP 11 G10 GeoVolume
STEP 12 G11 CaveFeature
STEP 13 G12 progressive detail hierarchy
STEP 14 G13 DetailPatchContext + fixtures
```

После G13 открыть HR track.

Четвёртая серия идёт параллельно:

```text
PLANET TRACK                 HR TRACK
G14 budget/cache             GH0 fixture harness
G15 recipes                  GH1 structural detail
G16 substitution             GH2 physical detail
                             GH3 micro detail
                             GH4 promotion boundary
                             GH5 determinism
                             GH6 performance
                             GH7 integration
```

---

# 18. Definition of Done первой программы

Первая procedural generation program считается архитектурно доказанной, когда:

```text
[PASS] spherical body + body-fixed geodesy
[PASS] planetary cells and LOD
[PASS] deterministic replaceable providers
[PASS] stable FeatureGraph
[PASS] 40 km river crossing many cells
[PASS] semantic fields drive cliffs/islands/shoals
[PASS] geology changes resulting forms
[PASS] GeoVolume exists independently from surface renderer
[PASS] cave can be entered
[PASS] progressive detail refines one stable place
[PASS] DetailPatchContext frozen and fixture-tested
[PASS] second PlanetRecipe works without GeoKernel branching
[PASS] HR backend can be developed from fixtures independently
[PASS] fly-in/fly-out scenario survives repeated roundtrips
```

После этого можно увеличивать реализм сколько угодно, не меняя базовую парадигму.
