# Procedural Planetary Generation — исполнительный план реализации

**Ветка программы:** `feature/g0-procedural-planetary-generation-lab`  
**Статус:** архитектурная программа зафиксирована; production runtime не изменён.  
**Назначение:** единый практический порядок реализации от пустого GeoKernel до fly-in, реки, скалы, пещеры, progressive detail и параллельного high-resolution backend.

Связанные документы:

- `docs/procedural/README_RU.md`
- `docs/procedural/STATUS_RU.md`
- `docs/architecture/PROCEDURAL_PLANETARY_GENERATION_FABRIC_RU.md`
- `docs/plans/PROCEDURAL_PLANETARY_GENERATION_ROADMAP_RU.md`
- `docs/architecture/HIGH_RESOLUTION_DETAIL_GENERATOR_RU.md`
- `docs/validation/PROCEDURAL_PLANET_LAB_ACCEPTANCE_RU.md`
- `docs/architecture/adr/ADR-019-procedural-planetary-generation-fabric.md`

> Каноническая нумерация G0–G19 в этом документе обязана совпадать с `PROCEDURAL_PLANETARY_GENERATION_ROADMAP_RU.md`. При расхождении roadmap является источником истины, а execution/status документы должны быть немедленно синхронизированы.

---

# 1. Что строим

Первая программа сознательно не пытается сразу получить реалистичную Землю. Она должна доказать архитектуру:

```text
body-fixed geodesy
→ planetary addressing
→ deterministic provider graph
→ replaceable generators
→ stable WorldFeatures
→ semantic fields
→ surface + volume
→ multi-LOD representation
→ progressive refinement
→ independent high-resolution backend
```

Первый сквозной сценарий:

```text
30–50 km altitude
→ одна и та же долина
→ длинная река
→ остров / отмель / cliff
→ посадка
→ локальная детализация
→ вход в процедурную пещеру
```

Весь сценарий должен использовать один world seed, одну body-fixed систему координат и один GeoKernel.

---

# 2. Неподвижные архитектурные правила

```text
Generator != Renderer
LOD != World State
Feature != Chunk
GeoKernel != planet-specific monolith
High-resolution detail != canonical topology
procedural baseline + persistent delta = authoritative world
renderer/cache artifact != canonical world state
network transport != generation semantics
```

Практическое следствие: река длиной 40 km существует как одна `RiverFeature`, а не как набор независимо сгенерированных рек в streaming cells. Пещера существует в `GeoVolume`, а не как декоративная дырка в mesh. HR backend может добавить трещины и гравий, но не имеет права самовольно открыть новый проходимый тоннель.

---

# 3. Как вести ветки

Архитектурная программа:

```text
feature/g0-procedural-planetary-generation-lab
```

Рекомендуемые короткие implementation branches:

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
feature/g12-geo-cache-scheduler
feature/g13-progressive-detail-contract
feature/g14-simple-detail-generator
feature/g15-planet-recipes
feature/g16-generator-substitution
```

После `G13 ACCEPTED` открыть параллельную ветку:

```text
feature/gh0-high-resolution-detail-generator
```

Future integration после первого прототипа:

```text
G17 Matter bridge
G18 Representation LOD integration
G19 Network manifest integration
```

---

# 4. SERIES A — фундамент

## G0 — Contracts freeze v0

### Реализовать

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
FlatSurfaceProvider
```

`GeoProviderDescriptor` минимум:

```text
provider_id
generator_version
requires[]
provides[]
deterministic
```

Validator provider graph должен ловить:

```text
missing dependency
duplicate incompatible output
cycle
unknown provider
invalid version
```

### Тесты

```text
same input → same sample
query order does not matter
invalid graph rejected
provider order canonicalized
core contracts have no Node/Mesh dependency
FlatSurfaceProvider can be replaced through contract
```

### Gate

Headless GeoKernel возвращает детерминированный sample и допускает замену provider без изменения caller.

---

## G1 — Geodesy + Body Shape

### Реализовать

```text
IBodyShapeProvider
SphereBodyShapeProvider
BodyFixedPosition
GeodeticPosition
LocalTangentFrame
GeodesyService
```

Операции:

```text
body_to_geodetic()
geodetic_to_body()
surface_normal()
altitude()
local_tangent_frame()
```

Первая лабораторная планета:

```text
nominal_radius_m = 6_000_000
```

### Тесты

- equator/pole/arbitrary roundtrip;
- altitude roundtrip;
- tangent frame orthonormality;
- stable Up/East/North;
- double-precision coordinates;
- NaN/INF rejection.

### Gate

Fly-in к гладкой сфере от десятков километров до поверхности без coordinate discontinuity/jitter, связанного с логикой geodesy.

---

## G2 — Planetary Surface Cells + LOD

### Реализовать

```text
SurfaceCellKey
cube-sphere compatible addressing
quadtree parent/children
neighbor lookup
LOD selection
hysteresis
requested/building/active/retiring lifecycle
```

### Debug

```text
cell bounds
cell id
LOD
requested/building/active state
```

### Тесты

```text
parent/children stable
neighbors stable
same-level boundaries agree
fly-in/out does not leak cells
GeoSample semantics independent from LOD
```

### Gate

Гладкая планета стабильно уточняется и огрубляется при движении камеры.

---

## G3 — Mega Casual Macro Surface

### Реализовать

```text
CasualMacroTerrainProviderV1
```

Первая формула намеренно простая:

```text
very-low-frequency deterministic field
+ radial displacement
```

Масштаб: километровые wavelengths, сотни метров amplitude.

### Gate

Одна крупная гора/долина остаётся той же географической формой на всех LOD.

---

## G4 — Provider Composition / Replacement

### Реализовать композицию

```text
BaseSurfaceProvider
+ CasualMacroTerrainProviderV1
+ CasualValleyModifierProviderV1
```

Создать `AlternativeMacroTerrainProviderV1` и заменить основной macro provider только через recipe/config.

### Запрещено

```text
if planet_type == ...
if provider_id == ...
```

в GeoKernel/renderer для поддержки альтернативы.

### Gate

Provider replacement проходит без изменения GeoKernel, renderer и query callers.

### Architecture review A

После G4 остановиться и проверить, действительно ли core остаётся renderer-independent и provider-neutral. Только после этого идти в FeatureGraph.

---

# 5. SERIES B — река и причинная география

## G5 — WorldFeature + FeatureGraph

### Реализовать

```text
WorldFeature
FeatureId
FeatureBounds
FeatureGraph
FeatureQuery
ValleyFeature
```

Feature identity:

```text
feature_id
feature_type
seed
generator_version
bounds
parent_feature_id optional
```

Первая ValleyFeature: spline + width + depth falloff.

### Gate

Долина проходит через много cells, но имеет одну stable feature identity.

---

## G6 — Mega Casual River

### Реализовать

```text
RiverFeature
RiverSpline
CasualRiverProviderV1
WaterPresentationAdapter
```

Параметры v0:

```text
centerline
width(s)
depth(s)
water_level(s)
seed
```

Целевой RiverFeature:

```text
length ≈ 40 km
```

### Gate

Одна RiverFeature бесшовно проходит через десятки/сотни cells и сохраняет identity при fly-in/fly-out.

---

## G7 — Semantic Geo Fields

### Добавить channels

```text
river_distance
river_width
water_level
flow_direction
curvature
erosion
deposition
```

Первые erosion/deposition могут быть грубой аналитической эвристикой.

### Debug overlays

Каждый field должен визуализироваться независимо.

### Gate

Downstream provider использует `erosion/deposition`, ничего не зная о реализации river spline.

---

## G8 — Casual Geomorphology

### Отдельные providers

```text
CasualCliffProviderV1
CasualShoalProviderV1
CasualIslandProviderV1
CasualBankProviderV1
```

Простейшие правила:

```text
high erosion + slope → cliff
high deposition + wide river → shoal/island
low flow + deposition → bank/bar
```

### Gate

Cliffs/islands/shoals возникают через semantic fields, а не через прямые зависимости на `CasualRiverProviderV1`.

---

## G9 — Geology Lite

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

Fields:

```text
rock_hardness
material_id
strata_hint
```

### Gate

Одна и та же RiverFeature создаёт разные формы берегов при смене geology profile без изменения river identity.

### Visual milestone B

После G9 должен существовать первый интересный river-valley fly-in:

```text
altitude
→ recognizable valley
→ ~40 km river
→ islands/shoals
→ cliff zones
→ visibly different soft/hard geology behavior
```

---

# 6. SERIES C — объём, пещера и инфраструктура дорогих генераторов

## G10 — GeoVolume Contract

### Реализовать

```text
IVolumeProvider
GeoVolumeQuery
GeoVolumeSample
```

Channels v0:

```text
signed_distance
density or matter class
material_id
hardness
```

Первая семантика:

```text
below procedural surface → SOLID
above procedural surface → AIR
```

### Gate

Volume query детерминирован и не требует построенного mesh.

---

## G11 — Mega Casual Cave

### Реализовать

```text
CaveFeature
CasualCaveVolumeProviderV1
```

Первая cave geometry:

```text
sphere/capsule SDF primitives
boolean subtraction from base volume
```

Feature linkage:

```text
RiverFeature
→ CliffFeature
→ CaveFeature
```

### Gate

```text
cave stable across reload
entrance agrees between surface and volume adapters
no teleport/load transition
player/spectator can enter real volume cavity
```

### Visual milestone C

```text
fly to river
→ land near cliff
→ approach entrance
→ enter cave
```

---

## G12 — Cache + Generation Scheduler Boundaries

### Цель

Подготовить систему к дорогим поздним generators до появления настоящего HR backend.

### Кэши

```text
FeatureCache
FieldCache
SurfaceSampleCache
VolumeSampleCache
RepresentationArtifactCache
```

Cache key обязан включать versioned provenance:

```text
body/recipe
provider manifest
scope
resolution/error tier
source/dependency hash
```

### Scheduler boundary

```text
data generation
    !=
main-thread scene commit
```

### Gate

Повторный fly-in использует cache, но canonical sample не зависит от наличия cache entry или порядка build jobs.

---

## G13 — Progressive Detail Contract Freeze

### Это главный fork point программы

### Ввести

```text
DetailPatchRequest
DetailPatchContext
DetailPatchArtifact
DetailSemanticMask
DetailBudget
IDetailProvider
```

`DetailPatchContext` должен включать достаточно локального semantic context:

```text
body_id
world_seed
patch_id
body-fixed anchor
local tangent frame
bounds
requested scale/error
surface samples/normals
slope/curvature
geology/material fields
river/erosion/deposition fields
nearby stable feature descriptors
volume boundary hints
source/generator versions
```

В contract нельзя протаскивать:

```text
SceneTree
MeshInstance3D
camera object
network peer
mutable renderer state
```

### Recorded fixtures

Минимум:

```text
flat_plain
river_inner_bank
river_outer_cliff
hard_rock_cliff
cave_entrance
cave_interior
```

Рекомендуемые масштабы fixture:

```text
20×20 m
100×100 m
500×500 m stress
```

### Gate

Stub `IDetailProvider` можно заменить fake detail backend без изменения GeoKernel/representation selection contract. Recorded `DetailPatchContext` позволяет тестировать detail backend без запуска планеты.

### После G13

Открывается параллельная ветка:

```text
feature/gh0-high-resolution-detail-generator
```

---

# 7. SERIES D — основной Geo track после fork

## G14 — Simple Detail Generator

### Реализовать дешёвый reference backend

```text
large rocks
small rocks
gravel descriptors
simple bank micro displacement
material masks
```

Пример progressive policy:

```text
> 2 km       macro only
200–2000 m  feature silhouettes
20–200 m    large detail
2–20 m      physical near detail
< 2 m       dense local detail / micro material
```

### Gate

Повышение detail добавляет новые deterministic detail, не переролливая уже существующие крупные детали.

---

## G15 — Multiple PlanetRecipe Acceptance

Минимум два рецепта.

```text
CasualEarthLikeV1
- Sphere
- CasualMacroTerrain
- CasualRiver
- SimpleGeology
- CasualCaves
- SimpleDetail
```

```text
DryRockyWorldV1
- Sphere
- TerracedMacroTerrain
- rare/no hydrology
- HardGeology
- FractureCaves
- RockyDetail
```

### Gate

Один GeoKernel и один lab runtime запускают обе планеты только configuration/recipe composition.

---

## G16 — Generator Substitution Acceptance

Обязательно заменить минимум:

```text
MacroTerrain V1 → V2
River V1 → AlternativeRiver V1
Geology V1 → LayeredGeology stub
Detail stub/simple → alternative detail backend
```

### Gate

```text
no planet-specific branches in GeoKernel
no provider-specific branches in renderer
same validation harness works across recipes
incompatible contract versions fail before generation
```

### Definition of Done первой программы

```text
[PASS] body-fixed geodesy
[PASS] planetary cells/LOD
[PASS] deterministic replaceable providers
[PASS] stable FeatureGraph
[PASS] 40 km RiverFeature
[PASS] field-driven cliffs/islands/shoals
[PASS] geology affects form
[PASS] GeoVolume independent of mesh
[PASS] enterable cave
[PASS] cache/scheduler independence
[PASS] frozen DetailPatchContext fixtures
[PASS] progressive local detail
[PASS] multiple recipes
[PASS] generator substitution acceptance
```

---

# 8. HIGH-RESOLUTION TRACK — параллельно после G13

Отдельная ветка:

```text
feature/gh0-high-resolution-detail-generator
```

Она работает прежде всего на recorded fixtures, а не на полном planet runtime.

## GH0 — Contract + Fixture Harness

Реализовать standalone runner/lab для:

```text
DetailPatchRequest
DetailPatchContext
DetailPatchArtifact
fixture serialization
deterministic hash
```

Gate:

```text
same fixture → canonical-equivalent descriptors
```

---

## GH1 — Structural 100 m Patch

Добавить:

```text
large rock anchors
bank cuts
ledge descriptors
fracture families
boulder/talus anchors
```

Без сантиметрового шума.

Gate: соседние patches и разные requested detail scales сохраняют крупные anchors.

---

## GH2 — Decimeter Physical Detail

Добавить collision-budgeted:

```text
rocks
small holes
small steps
gravel clusters
small channels
```

Проверять collision count и generation cost отдельно от visual detail.

---

## GH3 — Material Micro Detail

Добавить преимущественно presentation-level detail:

```text
normal detail
roughness variation
wetness
sediment masks
micro displacement
decals/scatter where appropriate
```

Микродеталь не становится canonical geometry только потому, что визуально заметна.

---

## GH4 — Volumetric Refinement Adapter

Доказать границу:

```text
derived local detail
vs
canonical topology/volume refinement
```

Если HR algorithm обнаруживает/предлагает topology-changing form, он создаёт explicit promotion proposal. Он не мутирует GeoVolume/Matter напрямую.

---

## GH5 — Performance Budgets

Проверить targets примерно:

```text
2 m
0.5 m
0.1 m
0.02 m visual
```

Собирать:

```text
generation ms
peak RAM
artifact bytes
triangle count
instance count
collision count
cache hit latency
```

---

## GH6 — Main Geo Composition

Подключить HR backend в `procedural_planet_lab` через тот же `IDetailProvider` contract.

Gate:

> GeoKernel не изменяется ради подключения high-resolution backend.

---

# 9. Future integration — не смешивать с первым prototype

## G17 — Matter Bridge

```text
procedural GeoVolume baseline
+
persistent Matter deltas
```

## G18 — Representation LOD Integration

Использовать существующий Representation LOD Fabric для macro/regional/local/volume/HR artifacts.

## G19 — Network Manifest Integration

Синхронизировать только необходимые canonical inputs/provenance:

```text
recipe id
provider manifest versions
feature provenance
persistent deltas
```

Не реплицировать mesh как истину мира.

---

# 10. Единый Procedural Planet Lab

Не плодить отдельные ad-hoc scenes для каждого G-stage. Один lab расширяется постепенно:

```text
procedural_planet_lab
```

Финальный fly-in acceptance первой программы:

```text
1. Spawn spectator at ~50 km.
2. Recognize same macro valley at far LOD.
3. Descend to ~10 km; long river becomes readable.
4. Descend to ~1 km; islands/cliffs visible.
5. Descend to ~100 m; detail refinement visible.
6. Land near selected cliff.
7. Confirm stable anchors/features after refinement.
8. Approach cave entrance.
9. Enter cave.
10. Exit and fly back to altitude.
11. Repeat route; confirm no identity/cache/LOD corruption.
```

---

# 11. Debug observability

Начиная с ранних stages поддерживать debug modes:

```text
F1  normal
F2  surface cells
F3  LOD
F4  provider outputs
F5  features
F6  river field
F7  erosion/deposition
F8  geology
F9  volume/SDF
F10 detail layers
F11 cache/build state
F12 generation timing
```

Конкретные hotkeys могут измениться при конфликте с текущим проектом; сами debug views обязательны.

---

# 12. Общие автоматические инварианты

На каждом stage проверять:

## Determinism

```text
same seed + same versions + same coordinates = same logical result
```

## Query-order independence

```text
A then B == B then A
```

## Cross-cell continuity

Cell boundaries не меняют Feature semantics.

## LOD semantic compatibility

Fine representation уточняет coarse, а не создаёт другую географию.

## Cache independence

Cache hit и cache miss дают один canonical result.

## Provider isolation

Provider не читает camera/SceneTree/network mutable state как источник canonical randomness.

## Provenance

Generator/provider versions входят в fixture/cache/artifact provenance.

---

# 13. Что не делать в первой программе

Сознательно отложить:

```text
real tectonics
full hydraulic erosion
full sediment simulation
climate simulation
vegetation ecology
dynamic rivers
realistic karst evolution
centimeter geometry planet-wide
planet-wide voxel allocation
production Matter persistence composition
terrain networking
```

Архитектура должна позволять добавить это позднее новыми providers/backends.

---

# 14. Порядок реальной работы

## Серия A

```text
STEP 1  G0 contracts + FlatSurfaceProvider
STEP 2  G1 sphere/geodesy
STEP 3  G2 planetary cells/LOD
STEP 4  G3 mega-casual macro terrain
STEP 5  G4 provider replacement proof
```

После STEP 5 — architecture review.

## Серия B

```text
STEP 6  G5 FeatureGraph + ValleyFeature
STEP 7  G6 ~40 km RiverFeature
STEP 8  G7 semantic RiverField
STEP 9  G8 cliffs/islands/shoals
STEP 10 G9 geology lite
```

После STEP 10 — river-valley fly-in review.

## Серия C

```text
STEP 11 G10 GeoVolume
STEP 12 G11 CaveFeature
STEP 13 G12 cache/scheduler boundaries
STEP 14 G13 DetailPatch contract + fixtures
```

После STEP 14 — открыть HR track.

## Серия D — параллельная

```text
MAIN GEO                         HIGH RESOLUTION
G14 SimpleDetail                GH0 fixture harness
G15 PlanetRecipes               GH1 structural patch
G16 substitution acceptance     GH2 physical detail
                                 GH3 material micro detail
                                 GH4 volume refinement adapter
                                 GH5 performance budgets
                                 GH6 main composition
```

Future integration только после acceptance первой программы:

```text
G17 → G18 → G19
```

---

# 15. Как закрывать каждый stage

Каждый G/GH stage обязан оставить запись в `docs/procedural/STATUS_RU.md`:

```text
stage
branch
base commit
implementation commit
checkpoint/tag if used
validation commands
assertion/test counts
visual acceptance result
known debt
next gate
decision: CANDIDATE / ACCEPTED / REJECTED
```

Этап не считается закрытым только потому, что картинка выглядит правильно.
