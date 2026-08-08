# Procedural Planetary Generation Fabric — универсальная процедурная геоморфология планет

**Статус:** архитектурная доктрина экспериментальной ветки.
**Ветка:** `feature/g0-procedural-planetary-generation-lab`.
**База:** `main` на 2026-08-08.
**Назначение:** создать заменяемое детерминированное ядро генерации планетарного рельефа, географических признаков и объёмной геометрии без привязки к конкретному renderer, Matter backend, сети или одному типу планеты.
**Связанные архитектуры:** `DYNAMIC_MATTER_FABRIC_RU.md`, `REPRESENTATION_LOD_FABRIC_RU.md`.

---

## 1. Главная идея

Проект не должен иметь единственного монолитного `EarthTerrainGenerator` или `MoonTerrainGenerator`.

Целевая модель:

```text
PlanetDefinition
      +
PlanetRecipe
      ↓
GeoKernel
      ↓
provider graph
      ↓
continuous procedural world fields
      ↓
feature graph + surface + volume
      ↓
representation / detail / physics adapters
```

Конкретная планета — это рецепт из взаимозаменяемых providers.

```text
EarthLikeRecipe
├── Sphere/Ellipsoid body shape
├── Continental macro surface
├── Layered geology
├── Drainage hydrology
├── River geomorphology
├── Karst cave volume
└── Temperate detail

IceMoonRecipe
├── Sphere body shape
├── Cratered macro surface
├── Layered ice geology
├── No surface hydrology
├── Fracture volume
└── Ice detail

AsteroidRecipe
├── Irregular body shape
├── Rubble macro shape
├── Rubble geology
├── No hydrology
├── Natural voids
└── Regolith detail
```

GeoKernel не должен содержать ветвления вида `if planet_type == ...`.

---

## 2. Каноническая формула мира

Общий мир строится как:

```text
procedural deterministic baseline
+
persistent canonical modifications
=
authoritative world state
```

Процедурный baseline не сохраняется целиком как mesh или voxel allocation. Он восстанавливается из:

```text
world/body seed
planet recipe id
provider ids
provider versions
feature ids
feature parameters
```

Persistent modifications принадлежат существующему Matter/Construction/persistence миру и не смешиваются с presentation artifacts.

---

## 3. Неподвижные архитектурные инварианты

### 3.1. Generator != Renderer

GeoKernel описывает мир. Renderer только создаёт временное представление.

Запрещено помещать в core contracts:

```text
MeshInstance3D
ArrayMesh
Terrain3D
VoxelLodTerrain
RenderingServer RID
Material
Shader
```

### 3.2. LOD != World State

LOD меняет точность выборки и representation budget, но не географическую идентичность.

```text
same seed + same coordinate + same provider versions
→ same semantic world
```

При приближении гора уточняется, а не заменяется другой горой.

### 3.3. Features exist above chunks

Река, хребет, долина, берег, fault или canyon существуют как глобальные/региональные `WorldFeature`, а не генерируются независимо внутри каждого streaming chunk.

```text
RiverFeature #5001
────────────────────────────────────
 cell A | cell B | cell C | cell D
```

Chunk только делает spatial query к feature/field.

### 3.4. Determinism

Порядок запросов не влияет на результат.

```text
generate(A), generate(B)
==
generate(B), generate(A)
```

Нельзя использовать observer position, frame time, случайный global RNG или SceneTree order как часть канонической генерации.

### 3.5. Provider replacement

Каждый provider объявляет:

```text
provider_id
contract_version
generator_version
requires[]
provides[]
```

Потребитель работает через semantic outputs, а не concrete implementation.

Например `CasualRiverV1` и будущий `HydraulicRiverV4` могут оба предоставлять:

```text
river_distance
water_level
flow_direction
flow_strength
curvature
erosion
deposition
```

Остальные providers не должны знать, какой алгоритм вычислил значения.

### 3.6. Planet-independent coordinates

Канонические запросы используют body-fixed double-precision coordinates.

Geodetic latitude/longitude является adapter/query view, а не внутренней сеткой generator state.

### 3.7. Surface and Volume are separate contracts

Heightfield достаточен для огромной доли внешней поверхности, но не способен представить:

- caves;
- overhangs;
- tunnels;
- natural arches;
- excavation;
- detached interior surfaces.

Поэтому core с первого этапа различает:

```text
GeoSurfaceQuery
GeoVolumeQuery
```

Даже если ранний `GeoVolumeQuery` всего лишь возвращает `SOLID` ниже простого surface и `AIR` выше него.

---

## 4. Базовые contracts

Минимальный целевой набор:

```text
PlanetDefinition
PlanetEnvironment
PlanetRecipe

BodyFixedPosition
GeodeticPosition
LocalTangentFrame
SurfaceCellKey

GeoGenerationContext
GeoSample
GeoSurfaceSample
GeoVolumeSample
GeoFieldBundle

IGeoProvider
IBodyShapeProvider
ISurfaceProvider
IFeatureProvider
IGeologyProvider
IHydrologyProvider
IVolumeProvider
IDetailProvider
```

### PlanetDefinition

Определяет identity и общие физические параметры тела:

```text
body_id
body_seed
recipe_id
body_shape_id
nominal_radius_m
generator_manifest_version
```

### PlanetEnvironment

Не содержит Earth assumptions:

```text
gravity model
atmosphere parameters
temperature model
surface fluid catalog
weathering parameters
material catalog reference
```

Это позволяет в будущем подключать воду, метан, лёд, вакуумные тела и иные environment models.

### GeoGenerationContext

Запрос должен явно нести budgets и требуемую семантику:

```text
body_id
query_scope
target_resolution_m
max_geometric_error_m
feature_budget
volume_budget
detail_budget
collision_required
interior_required
generator_manifest_version
```

Budget не меняет canonical high-level features; он определяет, сколько refinement разрешено вычислить/материализовать.

---

## 5. Geodesy layer

`GeodesyService` должен поддерживать:

```text
body_to_geodetic()
geodetic_to_body()
get_surface_normal()
get_altitude()
get_local_tangent_frame()
```

Первый body shape:

```text
SphereBodyShapeProvider
```

Следующие реализации не должны требовать переписывания GeoKernel:

```text
EllipsoidBodyShapeProvider
IrregularBodyShapeProvider
```

Для локального generator patch строится tangent frame `East/North/Up`, поэтому локальные алгоритмы могут работать почти в обычном Cartesian пространстве, сохраняя глобальную привязку к криволинейному телу.

---

## 6. Planetary surface addressing

Для сферических/эллипсоидальных тел рекомендуется cube-sphere quadtree-compatible address, совместимый с уже существующей идеей CubeSphereGrid.

```text
SurfaceCellKey
- body_id
- face
- level
- x
- y
- grid_revision
```

Важно: `SurfaceCellKey` — адрес streaming/representation scope, а не источник terrain truth.

Geo fields остаются continuous и queryable независимо от выбранного LOD cell.

---

## 7. Provider graph

Providers образуют dependency graph:

```text
BodyShape
   ↓
MacroSurface
   ├──────────────┐
   ↓              ↓
Geology        Hydrology
   └───────┬──────┘
           ↓
    Geomorphology
           ↓
   ┌───────┼────────┐
   ↓       ↓        ↓
Surface  Volume   Materials
   └───────┼────────┘
           ↓
         Detail
```

Provider loader обязан валидировать dependency graph до runtime generation.

Если `RiverCliffProvider` требует `erosion` и `rock_hardness`, а в recipe нет providers, выдающих эти поля, recipe должен отклоняться как invalid configuration.

---

## 8. FeatureGraph

`WorldFeature` — стабильная семантическая сущность генерации.

Минимально:

```text
feature_id
feature_type
seed
parent_feature_id
bounds
generator_id
generator_version
parameters
```

Примеры:

```text
MountainRangeFeature
ValleyFeature
RiverFeature
CliffFeature
IslandFeature
ShoalFeature
CanyonFeature
CaveFeature
CraterFeature
FaultFeature
```

Feature может порождать дочерние features:

```text
MountainRange #10
└── Valley #231
    └── River #781
        ├── Cliff #1451
        │   └── Cave #1977
        ├── Island #1452
        └── GravelBar #1453
```

Это не означает, что каждый камень обязан быть persistent entity. FeatureGraph используется только для признаков, которым нужна стабильная identity, dependency или cross-cell continuity.

---

## 9. Field-based composition

Основное средство слабой связанности providers — semantic fields.

Например River provider может выдавать:

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
sediment
moisture
```

Cliff provider использует только нужные значения:

```text
slope
erosion
rock_hardness
```

Island provider:

```text
deposition
river_width
water_level
```

Vegetation provider в будущем:

```text
moisture
soil_depth
temperature
slope
```

Так алгоритмы можно заменять независимо.

---

## 10. Геология как условие, а не декорация

Ранний prototype использует `SOFT/MEDIUM/HARD`, но contract сразу должен позволять stable material IDs и физические свойства:

```text
material_id
density
hardness
erosion_resistance
porosity
fracture tendency
solubility
```

Будущий layered geology provider может давать strata и volumetric composition без изменения river/cliff contracts.

Река должна реагировать на geology fields, а не напрямую знать названия `granite` или `limestone`.

---

## 11. Heightfield + volumetric hybrid

Проект не должен выбирать единственную крайность «вся планета heightmap» или «вся планета dense voxels».

Целевая модель:

```text
macro/regional surface
→ cheap surface fields / height representation

volumetric exceptions and editable areas
→ SDF / sparse Matter representation
```

GeoVolume baseline должен быть queryable даже там, где volumetric mesh никогда не строится.

Пещера представляется как volume subtraction/feature, а не как отдельная загруженная сцена.

---

## 12. Representation separation

Существующая Representation LOD Fabric сохраняет силу.

```text
Geo canonical procedural baseline
        ↓
feature/field summaries
        ↓
presentation artifacts
```

Mesh, collision proxy, HLOD, impostor, baked material tile и high-resolution patch являются производными artifacts.

Они могут быть удалены и перестроены без изменения мира.

---

## 13. High-Resolution Detail Generator — отдельный backend

Высокодетальная генерация должна быть физически и организационно отделена от GeoKernel.

GeoKernel обязан уметь выдать компактный `DetailPatchContext`:

```text
body identity
patch identity
body-fixed transform/local tangent frame
surface/volume base field
feature envelopes
gerology/material fields
hydrology/erosion/deposition fields
semantic masks
seed domain
target resolution
budgets
```

Детальный генератор получает этот context и может независимо создавать:

```text
small terrain displacement
rock formations
cracks
gravel descriptors
small erosion channels
debris
material masks
micro-collision candidates
scatter anchors
```

Подробная архитектура вынесена в `HIGH_RESOLUTION_DETAIL_GENERATOR_RU.md`.

Главное правило:

> High-resolution presentation никогда молча не становится canonical world truth.

Если деталь должна влиять на digging, collision, fluid flow или persistent Matter, она должна быть либо детерминированной частью `GeoVolume` baseline, либо явно promoted в canonical feature/matter channel.

---

## 14. Detail refinement ladder

Условная лестница:

```text
D0 planetary/macro      100 km → 2 km
D1 regional             5 km → 100 m
D2 local structural     500 m → 5 m
D3 near physical        20 m → 0.1 m
D4 micro visual         < 0.1 m
```

Границы не являются жёсткими API constants; это policy/profile.

Разделяются:

```text
visual relevance
collision relevance
simulation relevance
matter relevance
```

Например 3 мм трещина может быть D4 visual-only, а 20 см отверстие — D3 physical/volume.

---

## 15. Parallel development doctrine

После стабилизации core contracts разработка должна раскладываться на независимые ветки:

```text
GeoKernel / geodesy / fields
          │
          ├── macro terrain providers
          ├── hydrology providers
          ├── geology providers
          ├── cave/volume providers
          ├── high-resolution detail backend
          └── renderer/streaming adapters
```

Ни одна specialized ветка не должна менять core contract без отдельного versioned proposal.

Рекомендуемая будущая ветка высокодетального генератора:

```text
feature/gh0-high-resolution-detail-generator
```

Она должна стартовать после freeze минимального `DetailPatchContext`, но может работать параллельно почти со всеми поздними G-этапами.

---

## 16. Integration with Matter

До отдельного integration gate GeoKernel не владеет Matter persistence.

Будущая композиция:

```text
GeoVolume procedural baseline
+
Matter persistent sparse deltas
=
canonical physical volume
```

Generator version должен входить в provenance. Нельзя менять provider algorithm так, чтобы существующая persistent excavation начала применяться к другой базовой геометрии без migration/version fence.

---

## 17. Integration with network

GeoKernel не знает RPC/ENet/server/client.

Network может передавать:

```text
world/body seed
recipe/manifest version
stable feature descriptors where required
persistent deltas
representation artifacts/cache manifests
```

Клиент способен восстанавливать procedural baseline локально при совпадающих generator versions.

Canonical disagreement из-за разных generator manifests является protocol/configuration error, а не визуальным mismatch.

---

## 18. Что сознательно не входит в раннее ядро

На ранних G-этапах запрещено раздувать scope:

```text
real tectonic simulation
full hydraulic erosion simulation
climate simulation
dynamic rivers
sediment physics
ecosystems
centimeter geometry everywhere
full Matter integration
production multiplayer replication
```

Но contracts не должны блокировать их будущее подключение.

---

## 19. Архитектурный критерий успеха

Фундамент считается удачным, если можно выполнить одновременно:

1. заменить `CasualMacroTerrainProvider` на другой provider без изменения streaming/renderer;
2. заменить `CasualRiverProvider` на более сложный, сохранив downstream geomorphology;
3. добавить планету без `if planet == X` в GeoKernel;
4. получить одну и ту же RiverFeature через десятки surface cells без seams;
5. видеть одну и ту же гору от десятков километров до метров;
6. добавить volumetric cave без переписывания surface contracts;
7. подключить отдельный high-resolution backend без изменения macro generator;
8. в будущем наложить Matter deltas поверх procedural baseline;
9. удалить все presentation artifacts и восстановить их без изменения canonical world.

Если любой из этих сценариев требует переписать GeoKernel, dependency boundaries выбраны неправильно.
