# Universal World Generation Fabric — execution plan после G3

**Дата:** 2026-08-08  
**База:** `feature/g3-casual-macro-surface @ bc58f650ffb43775667bf0d07cb361a98a40d294`  
**Статус базы:** G0–G2 приняты как архитектурная основа; G3 реализован и полный acceptance успешно пройден пользователем.  
**Назначение документа:** скорректировать развитие procedural-направления после G3 с учётом разбора Cuberact Chunked LOD, Godot Procedural Forest Demo и общей идеологии PlanetSimulator.

---

## 1. Главная цель

Мы больше не строим «генератор землеподобной планеты».

Мы строим **Universal World Generation Fabric** — систему, в которой конкретный мир является композицией заменяемых генераторов, полей, feature-графов, environment-провайдеров, material/matter-слоёв и representation backend'ов.

Одна и та же архитектура должна позволять выразить:

```text
Earth-like planet
Moon / airless rocky body
ice world
desert world
ocean world
lava world
gas giant without solid playable surface
irregular asteroid
hollow asteroid
asteroid belt
floating islands
ring world fragments
artificial megastructure
procedural cavern world
planet with local anomalous gravity
planet with exotic atmosphere
world with changing geology
mixed natural + player-built world
```

Ни один из этих вариантов не должен требовать переписывания `GeoKernel`, сетевого протокола или базовых query-callers.

---

## 2. Что уже нельзя ломать после G3

G0–G3 доказали несколько правильных фундаментальных инвариантов.

### 2.1 Canonical truth не принадлежит renderer

```text
Geo provider
    -> canonical fields

Surface cells / volume cells
    -> representation scope

Mesh / MultiMesh / shader / billboard
    -> derived presentation
```

GPU не является источником истины мира.

### 2.2 LOD не меняет географию

Одна и та же body-fixed координата должна давать тот же canonical результат независимо от:

```text
camera
LOD
cell owner
mesh subdivision
client graphics settings
query order
```

### 2.3 Генераторы заменяемы

Provider обязан быть заменяем через recipe/config и descriptor contract, а не через hardcoded `if planet_type == ...`.

### 2.4 Canonical procedural identity должна переживать streaming

Unload/reload representation не должен создавать новый мир.

### 2.5 G2 grid revision v1 замораживается

Текущее cube-sphere addressing считается стабильным `grid_revision v1`.

Идея spherified cube из Cuberact полезна как отдельный будущий `grid_revision v2` research, но не должна менять уже принятую семантику `SurfaceCellKey` задним числом.

---

# 3. Универсальная модель мира

## 3.1 Не каждый мир обязан иметь поверхность

Текущие `GeoSurfaceQuery` и `GeoVolumeQuery` правильны именно потому, что это разные запросы.

Дальнейшая архитектура должна разрешать body capabilities:

```text
surface
volume
fluid layers
atmosphere / gas volume
gravity field
thermal field
radiation field
magnetic field
procedural object population
dynamic matter mutations
```

Мир может иметь любую комбинацию.

Примеры:

```text
Earth:
surface + geology volume + ocean + atmosphere + gravity

Moon:
surface + geology volume + gravity

Ocean world:
seafloor surface + water volume + atmosphere + gravity

Gas giant:
atmosphere/gas volume + gravity + cloud layers
NO required solid surface

Asteroid:
volume geometry + local gravity
optional radial surface convenience query

Floating island:
free volumetric body + atmosphere context + gravity field

Asteroid belt:
population of many independent bodies
NO single enclosing surface
```

---

## 3.2 WorldBody и WorldDomain

После G4 следует постепенно ввести generic vocabulary поверх текущего `PlanetDefinition`, не ломая его.

Предлагаемые контракты:

```text
WorldDomainId
WorldBodyDefinition
WorldBodyCapabilities
WorldFrame
WorldRecipe
WorldPopulationRecipe
```

`PlanetDefinition` остаётся рабочим специализированным контрактом для текущего planetary path и может позже стать adapter/factory к `WorldBodyDefinition`.

Не требуется мигрировать G0–G3 немедленно.

### WorldBodyCapabilities

Capability-set, а не фиксированный planet type:

```text
geo/surface-query
geo/volume-query
environment/gravity-field
environment/atmosphere-field
environment/fluid-field
environment/thermal-field
population/procedural-anchors
matter/dynamic-mutation
```

Provider graph проверяет зависимости по capabilities/fields.

---

# 4. PlanetRecipe превращается в World Recipe Graph

Recipe не должен быть названием биома или класса планеты.

Правильная семантика:

```text
WorldRecipe
  |
  +-- reference/body shape
  +-- macro geometry
  +-- feature generators
  +-- geology/material providers
  +-- fluid providers
  +-- atmosphere providers
  +-- environment physics providers
  +-- detail generators
  +-- population generators
  +-- mutation layers
  +-- representation profiles
```

Пример Earth-like recipe:

```text
SphereBodyShape
  -> ContinentalMacroSurface
  -> Plate/LithologyProvider
  -> DrainageProvider
  -> RiverFeatureProvider
  -> GeomorphologyProvider
  -> Soil/MoistureProvider
  -> TemperateDetailProvider
  -> OceanLayerProvider
  -> NitrogenOxygenAtmosphereProvider
  -> RadialGravityProvider
```

Пример floating-islands recipe:

```text
ReferenceSphere only for world frame
  -> FloatingIslandPopulationProvider
       -> each anchor creates VolumeBody
  -> SDFIslandGeometryProvider
  -> FractureGeologyProvider
  -> LocalWaterfallFeatureProvider
  -> ExoticVegetationDetailProvider
  -> UniformAtmosphereProvider
  -> CustomGravityFieldProvider
```

Пример asteroid belt:

```text
OrbitalDomain
  -> Stable3DBodyPopulationProvider
  -> AsteroidRecipeSelector
       -> rubble pile
       -> metallic asteroid
       -> ice asteroid
       -> hollow asteroid
  -> per-body VolumeGeometry
  -> per-body local gravity
```

---

# 5. После G3: обязательная последовательность core

## G4 — Provider Composition / Replacement

**Не расширять G4 декоративными системами.** Это архитектурный gate.

### Реализовать

```text
BaseSurfaceProvider
CasualMacroTerrainProviderV1
CasualValleyModifierProviderV1
AlternativeMacroTerrainProviderV1
recipe-driven composition
canonical provider ordering
provider graph validation
```

### Усилить acceptance

```text
replace macro provider through recipe only
GeoKernel caller unchanged
G2 addressing unchanged
LOD selector unchanged
renderer caller unchanged
same provider graph -> same provenance hash
provider order canonicalized
missing capability rejected
cycle rejected
duplicate incompatible field rejected
```

### Gate

После G4 мы должны доказать:

> «мир определяется композицией генераторов, а не классом Planet».

После gate — **Architecture Review A**.

---

# 6. GR-track — Surface Representation Lab (параллельно после G4)

Вдохновение: лучшие низкоуровневые идеи Cuberact Chunked LOD.

Это НЕ GeoKernel и НЕ canonical world truth.

## GR0 — Minimal Surface Patch Renderer

```text
SurfaceCellKey
  -> canonical GeoSurface samples
  -> SurfacePatchArtifact
  -> MeshInstance3D
```

Первая topology:

```text
16 x 16 quads
17 x 17 samples
shared index buffer
```

### Взять из Cuberact как идеи

```text
fixed power-of-two patch topology
shared index topology
visual skirts
presentation resource pool
per-frame build budget
horizon culling for spherical body
later: parent/child sample reuse optimization
```

### Не брать

```text
Quad owning LOD + renderer + culling + chunk
shader as canonical terrain truth
origin shifting as world model
camera-owned coordinate system
incorrect nearest sphere distance formula
```

## GR1 — Representation lifecycle budget

Связать с уже имеющимся:

```text
REQUESTED
BUILDING
ACTIVE
RETIRING
```

Добавить:

```text
max_builds_per_frame
max_upload_bytes_per_frame
max_active_mesh_bytes
cancellation
revive-before-destroy
```

## GR2 — Transition quality

v0:

```text
skirts
```

далее research:

```text
edge stitching
transition meshes
geomorphing
```

## GR3 — Visibility

```text
SphereHorizonVisibilityPolicy
frustum delegated to engine where possible
optional occlusion for interiors
```

### Gate GR

Orbit -> ground -> orbit без дырок, runaway allocations и изменения canonical geography.

---

# 7. G5 — World Feature Graph + Spatial Feature Identity

Оригинальную идею FeatureGraph сохранить, но сразу сделать её пригодной не только для рек.

## Реализовать

```text
WorldFeature
FeatureId
FeatureType
FeatureBounds
FeatureAnchor
FeatureGraph
FeatureQuery
FeatureRelation
```

Feature не обязан быть surface-only.

Примеры:

```text
valley spline
river
crater
fault
cave system
ore vein
floating island
volcanic conduit
reef
storm cell
asteroid cluster
artificial ruin zone
```

### Feature identity

```text
feature_id
feature_type
seed
generator_version
bounds
parent_feature_id optional
relations[]
```

### Gate

Одна feature пересекает много representation cells, но сохраняет одну identity.

---

# 8. G6 — Hydrology / Fluid Surface v0

Сохранить исходную цель «Mega Casual River», но не привязывать контракт только к рекам.

## Реализовать сначала

```text
RiverFeature
RiverSpline
RiverChannelProfile
WaterSurfaceQuery v0
CasualRiverProviderV1
```

Добавить generic задел:

```text
FluidRegionId
FluidSurfaceDescriptor
fluid_type_id
level / local surface
bounds
```

Это позволит позже выразить:

```text
river
lake
ocean
lava lake
methane sea
subsurface water pocket
```

### Не делать пока

Полную CFD/гидродинамику.

G6 создаёт canonical fluid geography, а не симулятор Navier-Stokes.

---

# 9. G7 — Semantic Field Fabric

Это критически важный этап после разбора Forest Demo.

Детализация мира не должна зависеть от нарисованной `biome_mask.png`.

Она должна читать причинные поля.

## Namespace должен позволять providers создавать

```text
geo/surface-height-m
geo/surface-normal
geo/slope
geo/curvature

hydro/river-distance-m
hydro/water-level-m
hydro/moisture
hydro/drainage

climate/temperature-k
climate/humidity
climate/precipitation
climate/insolation

geo/erosion
geo/deposition
geo/soil-depth-m

matter/material-id
matter/rock-hardness
matter/fracture-tendency
matter/porosity

env/pressure-pa
env/wind-vector
env/radiation
```

Не обязательно реализовать все поля в G7. Но contract/namespace не должен закрывать их добавление.

### Gate

Consumer запрашивает semantic field по контракту, не зная конкретный provider.

---

# 10. GD-track — Deterministic Detail Research (можно начать после G7)

Вдохновение: Godot Procedural Forest Demo, но собственная архитектура.

Это исследовательский lab до production GH-track.

## GD0 — Stable Scatter Cells

В локальном tangent frame создать deterministic grid кандидатов:

```text
StableDetailCell
  -> deterministic jitter
  -> stable anchor id
```

Запрещено:

```text
randf()
camera in seed
query order in seed
cell regeneration reroll
```

## GD1 — Independent random domains

Для одного anchor разные свойства получают независимые deterministic streams:

```text
POSITION_X
POSITION_Y
SPECIES
ROTATION
SCALE
VARIANT
LOD_PRIORITY
```

Изменение алгоритма scale не должно менять species/position.

## GD2 — Semantic suitability

Forest-style texture mask заменить на field expression:

```text
TreeSuitability =
  moisture
  * soil_depth
  * temperature_fit
  * slope_fit
  * biome_fit
```

Пример:

```text
reed -> wet + flat + near water
pine -> cool + adequate soil + slope < limit
lichen -> exposed rock + low soil
```

## GD3 — Stable Density LOD

Каждый anchor имеет deterministic `refinement_priority`.

```text
quality 0.2 -> deterministic subset
quality 0.5 -> superset
quality 1.0 -> full set
```

Главный invariant:

> увеличение detail quality добавляет anchors, а не переролливает существующие.

## GD4 — MultiMesh batching

Группировка:

```text
patch + asset class + representation level
```

## GD5 — Billboard / impostor pipeline

Идея из Forest Demo:

```text
full mesh
 -> simplified mesh
 -> billboard/impostor
 -> none
```

Geometry LOD и density LOD независимы.

---

# 11. G8 — Geomorphology / Material Transport

Теперь FeatureGraph и semantic fields начинают причинно менять поверхность.

## Минимум

```text
river erosion
bank profile
sediment deposition
talus / scree tendency
cliff exposure
local smoothing/deposition
```

Результат должен быть выражен canonical fields/features, а не renderer hacks.

### Gate

Река физически формирует долину/берег, а detail generators затем видят результат через semantic fields.

---

# 12. G9 — Layered Geology + Material Semantics

## Реализовать

```text
GeologyLayer
LithologyProvider
MaterialColumnQuery
RockPropertyFields
OreFeature / VeinFeature v0
```

Минимальные свойства:

```text
material_id
density
hardness
fracture tendency
porosity
thermal properties optional
```

### Главное

Surface appearance не должна быть единственным представлением материала.

Геология нужна серверу, Matter, mining, caves и construction interaction.

---

# 13. G10 — GeoVolume / SDF Foundation

Это переломный этап: мир перестаёт быть heightfield-only.

## Реализовать generic volume query

```text
GeoVolumeQuery
  -> density / signed distance
  -> material
  -> optional gradients
```

Canonical volume provider не зависит от Voxel Tools.

Backend candidates:

```text
SimpleSdfProvider
AnalyticalVolumeProvider
VoxelToolsAdapter later
```

## Что G10 должен открыть

```text
caves
overhangs
arches
tunnels
hollow asteroids
floating islands
detached rock bodies
underground cavities
```

### Gate

Один world body имеет surface convenience query и независимую volume truth; cave/overhang нельзя потерять при смене representation LOD.

---

# 14. G11 — Heterogeneous Body Lab

Не делать ещё одну Землю.

Нужно доказать универсальность архитектуры тремя намеренно разными fixtures.

## Fixture A — irregular asteroid

```text
radius ~500 m
volume/SDF geometry
craters
material layers
local gravity
cave pocket
```

## Fixture B — floating island

```text
detached volume
flat-ish inhabited top
fractured bottom
water source / waterfall marker
vegetation suitability
```

## Fixture C — hollow body

```text
outer shell
inner cavern surface
opening connecting exterior/interior
```

### Gate

Ни один fixture не требует special-case в GeoKernel/query callers.

---

# 15. GE-track — Environment / Atmosphere / Physics Fabric

Этот track можно развивать параллельно после G4; часть stages требует G7 semantic field fabric.

## GE0 — Environment Field Contracts

```text
GravityFieldQuery
AtmosphereFieldQuery
ThermalFieldQuery
RadiationFieldQuery
FluidFieldQuery
```

## GE1 — Gravity providers

```text
RadialGravityProvider
UniformGravityProvider
MultiBodyGravityProvider
CustomFieldGravityProvider
```

Это позволяет:

```text
planet gravity
asteroid local gravity
rotating habitat pseudo-gravity
floating-island fantasy gravity
zero-g zones
```

## GE2 — Atmosphere canonical profile

Canonical:

```text
composition
pressure
density
temperature
wind
scale / bounds
```

Renderer отдельно:

```text
AtmosphereRendererFast
AtmosphereRendererScattering
AtmosphereRendererExotic
```

Shader не является atmosphere truth.

## GE3 — Ocean / global fluid envelope

```text
fluid composition
surface/volume
pressure with depth
buoyancy inputs
```

## GE4 — Environmental gameplay composition

Environment queries должны быть доступны:

```text
player
AI
ship
physics
items
construction
life support
weather
```

### Gate GE

Один и тот же body recipe можно запустить:

```text
no atmosphere
Earth-like atmosphere
thick toxic atmosphere
water envelope
custom gravity
```

без изменений GeoKernel.

---

# 16. G12 — Generation Scheduler / Cache / Provenance

К этому моменту генераторы становятся тяжёлыми.

Нужен общий scheduler.

## Job identity

```text
request_id
world/body id
generator_version
recipe_hash
region key
requested_resolution
semantic dependencies
priority
generation epoch
```

## Lifecycle

```text
REQUESTED
 -> BUILDING
 -> READY
 -> ACTIVE
 -> RETIRING
```

Дополнительно:

```text
CANCELLED
STALE
FAILED
```

## Worker rule

Worker получает pure data.

Godot SceneTree/render resources создаются main-thread/presentation layer.

## Cache key

Cache обязан включать provenance:

```text
world seed
recipe hash
generator versions
region identity
resolution class
mutation revision
```

Cache — производный artifact, не authoritative truth.

---

# 17. G13 — High Resolution Detail Contract Freeze

Только после G5–G12 detail generator получает достаточно причинного контекста.

## DetailPatchContext

Минимум:

```text
body/world identity
stable patch identity
body-fixed origin
local tangent frame
bounds
requested resolution
recipe hash
semantic field access
feature query access
material/geology access
environment access
mutation revision
```

## DetailPatchArtifact

Разделить output:

```text
A canonical/physical descriptors
B derived physical representation descriptors
C visual-only descriptors
```

### ScatterDescriptor

```text
anchor_id
class_id
variant_id
body_fixed_position
local_transform
scale
suitability
refinement_priority
physical_class
collision_class
representation_profile_id
provenance
```

Запрещено хранить в canonical descriptor:

```text
Mesh
PackedScene
MultiMeshInstance3D
Camera3D
```

---

# 18. GH-track — Production High Resolution Generation

## GH0 — Contracts + deterministic fixtures

Плоский fixture, slope fixture, river bank fixture, cliff fixture, cave fixture.

## GH1 — Structural Detail

Canonical крупные формы:

```text
large boulders
rock formations
ledges
river cuts
large fractures
scree/talus zones
```

## GH2 — Physical Scatter

```text
trees
large bushes
rocks
fallen logs
physical debris
```

Stable anchor IDs обязательны.

## GH3 — Visual Scatter / Microdetail

```text
grass
flowers
small plants
leaf litter
small gravel
micro decals
```

Большая часть может быть observer-relative и visual-only.

## GH4 — Volumetric Detail

```text
small cave recesses
fracture openings
undercuts
small voids
```

## GH5 — Representation / Performance

Использовать лучшие идеи Forest Demo:

```text
MultiMesh batching
stable density LOD
geometry LOD
billboards / impostors
async generation
observer-centered ephemeral grass
wind visual field
interaction displacement field
```

## GH6 — Composition gate

Проверить совместно:

```text
macro geography
river
geomorphology
geology
volume/cave
physical scatter
visual scatter
atmosphere
fluid/environment
```

---

# 19. GM-track — Dynamic Geology / Matter Mutations

Процедурный мир не должен быть immutable.

Главный принцип:

```text
Procedural baseline
      +
Sparse authoritative mutation layers
      =
Current world truth
```

Не менять seed генератора после каждого удара киркой.

## GM0 — Mutation contracts

```text
GeoMutationId
GeoMutationOperation
GeoMutationBounds
GeoMutationRevision
```

Типы v0:

```text
remove volume
add/deposit material
replace material
fracture marker
thermal state delta optional
```

## GM1 — Mutation overlay query

```text
base provider
 -> mutation overlay
 -> current GeoVolume/Surface result
```

## GM2 — Matter integration

Excavated material должен стать domain material/item state через существующую item/matter архитектуру, а не просто исчезнуть визуально.

## GM3 — Promotion boundary

Procedural anchor может быть promoted в persistent/networked entity, если игрок начинает с ним взаимодействовать.

Пример:

```text
procedural boulder descriptor
        ↓ mining/contact
materialized world entity
        ↓
Item/Matter/Construction domain ownership
```

Это позволяет не хранить миллионы неиспользуемых деревьев/камней как сетевые сущности.

---

# 20. GN-track — Network / Distributed World Generation

## 20.1 Что передаём по сети

Предпочтительно:

```text
world/body identity
recipe id/hash
generator versions
seed/provenance
active region revisions
mutation operations
materialized entity state
server authority epochs
handoff state
```

Не передавать постоянно:

```text
каждый procedural mesh vertex
каждую травинку
каждый visual-only tree instance
```

## 20.2 Deterministic client materialization

Если client имеет совместимую recipe/version:

```text
server: canonical identity + revision
client: derived local representation
```

Для несовместимых/authoritative complex states сервер может прислать snapshot/artifact descriptor.

## 20.3 Server interest regions

Region ownership должен быть выражен через stable spatial identity, а не scene nodes.

```text
WorldDomain
 -> Body
 -> spatial region / cells / volume regions
```

## 20.4 Server handoff

При переходе между серверами сохраняются:

```text
body_id
world frame
entity identity
mutation revisions
construction/item aggregate identity
recipe provenance
```

Representation на новом сервере/клиенте пересобирается.

## 20.5 Asteroid belt

Пояс астероидов не должен означать «один сервер знает миллион тел».

Использовать stable space population cells:

```text
SpacePopulationCell
  -> deterministic body anchors
  -> nearby bodies materialized
  -> far field summarized
```

Это тот же принцип, что stable scatter в Forest Demo, но в 3D space domain.

---

# 21. GC-track — Complex Objects / Construction Composition

Natural world и player-built world должны сосуществовать.

## Не смешивать

```text
GeoVolume != ConstructionAggregate
Terrain rock != ship block graph
```

## Общий spatial composition layer

```text
World region
  |
  +-- generated geology
  +-- mutation overlay
  +-- fluid/environment
  +-- construction aggregates
  +-- items/entities
  +-- procedural anchors
```

### Distant representation

Большая станция:

```text
10k authoritative blocks
 -> cluster representation
 -> proxy mesh / HLOD
 -> far silhouette
```

Это тот же принцип representation separation, что у terrain/detail.

### Collision/query composition

Gameplay query должен уметь получить ближайшую physical surface независимо от источника:

```text
geology
construction
ship
item
```

но ownership изменений остаётся в соответствующем domain.

---

# 22. GW-track — Seamless Large World / Heterogeneous Composition

После G12 + GM + GN можно переходить к большим composition labs.

## GW0 — Earth-like composition

```text
planet
macro terrain
river
geology
detail
ocean
atmosphere
```

## GW1 — Asteroid lab

```text
space -> asteroid proxy -> detailed body -> cave -> mining
```

## GW2 — Asteroid belt

```text
far population summary
 -> body anchors
 -> nearby body materialization
 -> server handoff
```

## GW3 — Floating islands

```text
free volumes
custom gravity
atmosphere
waterfalls
vegetation
```

## GW4 — Water world

```text
orbit -> atmosphere -> ocean surface -> underwater -> seabed -> cave
```

## GW5 — Mixed natural + construction

```text
approach planet/station
 -> distant proxy
 -> detailed region
 -> construction interior
 -> terrain excavation
 -> persistent/networked mutation
```

---

# 23. Reference patterns из Cuberact

Использовать как идеи:

```text
chunked LOD
hysteresis
fixed patch topology
shared indices
split/build budget
visual skirts
presentation pooling
sphere horizon culling
```

Не принимать как architecture:

```text
Quad owns everything
shader owns terrain truth
floating-origin camera owns coordinates
single planet-specific class
```

Cuberact — reference implementation для representation, не dependency ядра.

---

# 24. Reference patterns из Procedural Forest Demo

Особенно ценны:

```text
deterministic candidate cells
hash-based stable jitter
separate random domains
weighted species selection
semantic/mask-driven density
chunk grouping
MultiMesh batching
stable density LOD
geometry -> billboard LOD
billboard generation tooling
observer-centered grass materialization
async transform generation
coherent global wind
visual interaction displacement
```

Но переписать под наши правила:

```text
raycast placement -> GeoSurfaceQuery
Vector3.UP -> LocalTangentFrame.Up
bitmap biome truth -> semantic fields
full regeneration -> incremental patch lifecycle
camera-dependent world -> camera-dependent representation only
Node3D generator -> pure data generator + presentation adapter
```

---

# 25. Универсальные acceptance invariants

Эти тесты должны постепенно стать обязательными для всех новых generators.

## Determinism

```text
same recipe + same seed + same versions -> same canonical result
query order does not change result
thread/job completion order does not change result
```

## LOD independence

```text
LOD changes representation only
coarse/fine shared world sample agrees
```

## Stable refinement

```text
higher detail = superset/refinement
not reroll
```

## Renderer independence

```text
headless server produces same canonical descriptors
```

## Network independence

```text
visual quality change does not alter gameplay checksum
```

## Mutation stability

```text
baseline recipe unchanged
mutation journal reproduces current state
```

## Cross-domain composition

```text
geology mutation does not silently mutate construction ownership
construction does not rewrite GeoProvider state
```

## Handoff

```text
same body/entity/mutation identity before and after server handoff
```

---

# 26. Ближайшие реальные шаги от текущей точки

## Шаг 1 — закрыть G3 как accepted checkpoint

Поскольку пользователь подтвердил успешный full acceptance, оформить accepted evidence/ledger на ветке реализации перед началом G4.

## Шаг 2 — G4 Provider Composition / Replacement

Это следующий blocking stage.

Предлагаемая ветка:

```text
feature/g4-provider-composition-replacement
```

## Шаг 3 — параллельно открыть GR0

```text
feature/gr0-surface-representation-lab
```

Не блокирует G5.

## Шаг 4 — после G4 начать G5 FeatureGraph

```text
feature/g5-world-feature-graph
```

Уже с generic feature identity.

## Шаг 5 — G6 Hydrology v0

Сделать реку первым fluid feature, но не закрывать архитектуру на river-only.

## Шаг 6 — G7 Semantic Field Fabric

После него открыть:

```text
feature/gd0-deterministic-scatter-research
feature/ge0-environment-field-contracts
```

## Шаг 7 — G8/G9 причинный рельеф + geology

После этого Forest-style detail начинает зависеть от реальной географии.

## Шаг 8 — G10/G11 volume + heterogeneous body proof

Это ключевой gate для фантастических миров.

## Шаг 9 — G12 scheduler/cache

До production high-detail.

## Шаг 10 — G13 + GH

Только после freeze detail contracts превращать research scatter в production generator.

---

# 27. Критерий успеха программы

Программа считается архитектурно успешной не тогда, когда получилась одна красивая Земля.

Она успешна, если новые фантазии реализуются **новыми recipes/providers**, а не переписыванием ядра.

Проверочный вопрос для любого нового мира:

> «Можно ли сделать это новым provider/feature/environment/detail/representation backend, сохранив GeoKernel, networking identity, streaming lifecycle и domain ownership?»

Если да — архитектура работает.

Если для каждого нового типа мира нужно добавлять `if world_type == ...` в ядро — архитектура деградирует.

---

# 28. Целевая схема

```text
                          WORLD RECIPE
                               |
              +----------------+----------------+
              |                |                |
              v                v                v
        Geometry/Geo       Environment       Populations
        Providers           Providers         Providers
              |                |                |
       +------+-----+     +----+----+      +----+-----+
       |            |     |         |      |          |
    Surface       Volume Gravity Atmos.  Bodies     Detail
       |            |      Fluid Climate  Anchors    Anchors
       +------+-----+           |            |          |
              |                 |            |          |
              +-----------------+------------+----------+
                                |
                                v
                         CANONICAL WORLD
                                |
                  +-------------+-------------+
                  |             |             |
                  v             v             v
             Mutations      Entities      Construction
                  |             |             |
                  +-------------+-------------+
                                |
                                v
                      NETWORK / HANDOFF STATE
                                |
                                v
                       REPRESENTATION FABRIC
                                |
            +-------------------+-------------------+
            |                   |                   |
            v                   v                   v
        Terrain Mesh       MultiMesh Detail    Proxy / HLOD
            |                   |                   |
            +-------------------+-------------------+
                                |
                                v
                              CLIENT
```

Это и есть направление после G3.