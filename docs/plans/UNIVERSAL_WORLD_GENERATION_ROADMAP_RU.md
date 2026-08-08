# Universal World Generation Fabric — roadmap после G3

**Дата:** 2026-08-08  
**База:** `feature/g3-casual-macro-surface @ bc58f650ffb43775667bf0d07cb361a98a40d294`  
**Связанный execution plan:** `docs/plans/UNIVERSAL_WORLD_GENERATION_EXECUTION_PLAN_RU.md`

---

## 1. Куда идём

Цель — не один terrain generator, а универсальная система world generation:

```text
recipe + providers + fields + features + mutations
                       |
                       v
                 canonical world
                       |
          +------------+------------+
          |            |            |
       network      simulation   representation
```

Она должна позволять без переписывания ядра собирать:

```text
Earth-like planet
Moon
ice/desert/lava worlds
ocean world
gas giant
irregular/hollow asteroid
asteroid belt
floating islands
cavern world
artificial megastructure region
mixed geology + construction world
```

---

# 2. Текущая точка

```text
G0 Geo Contracts                    DONE
G1 Geodesy + Body Shape             DONE
G2 Planetary Cells + LOD             DONE
G3 Casual Macro Surface              IMPLEMENTED + full test PASS reported
                                      |
                                      v
                              CURRENT FRONTIER
```

После G3 запрещено ломать принятые инварианты:

```text
canonical truth != renderer
canonical truth != LOD cell
camera != seed
LOD != geography
provider is replaceable
headless server can query world
```

---

# 3. Основная dependency graph

```text
G3
 |
 v
G4 Provider Composition / Replacement
 |
 +---------------------------> GR0-GR3 Representation Lab
 |
 v
G5 World Feature Graph
 |
 v
G6 Hydrology / Fluid Surface v0
 |
 v
G7 Semantic Field Fabric
 | \
 |  +------------------------> GD0-GD5 Detail Research
 |  +------------------------> GE0-GE4 Environment Fabric
 |
 v
G8 Geomorphology
 |
 v
G9 Layered Geology
 |
 v
G10 GeoVolume / SDF
 |
 v
G11 Heterogeneous Body Lab
 |
 v
G12 Scheduler / Cache / Provenance
 |
 v
G13 High Resolution Detail Contract Freeze
 |
 +---------------------------> GH0-GH6 Production Detail
 |
 +---------------------------> GM0-GM3 Dynamic Geology / Matter
 |
 +---------------------------> GN Network / Distributed Generation
 |
 v
GW0-GW5 Seamless Heterogeneous World Composition
```

---

# 4. Основной GEO track

| Stage | Цель | Ключевой результат | Что открывает |
|---|---|---|---|
| **G4** | Provider Composition / Replacement | recipe-driven generator graph | разные генераторы одной планеты |
| **G5** | World Feature Graph | stable identity крупных features | долины, кратеры, разломы, caves, острова |
| **G6** | Hydrology v0 | river + generic fluid region contracts | реки, озёра, будущие моря/лава |
| **G7** | Semantic Field Fabric | moisture/slope/material/climate-style fields | причинные биомы и detail |
| **G8** | Geomorphology | erosion/deposition/material transport | река реально формирует ландшафт |
| **G9** | Layered Geology | material/hardness/lithology | mining, caves, matter |
| **G10** | GeoVolume/SDF | canonical 3D volume geometry | overhangs, caves, floating islands |
| **G11** | Heterogeneous Body Lab | asteroid + floating island + hollow body | доказательство universal architecture |
| **G12** | Scheduler/Cache | async generation with provenance | тяжёлые generators и streaming |
| **G13** | Detail Contract Freeze | canonical detail patch API | production high-resolution generation |

---

# 5. G4 — следующий blocking stage

**Ветка:**

```text
feature/g4-provider-composition-replacement
```

## Обязательный scope

```text
provider graph
provider dependency validation
canonical ordering
recipe-driven composition
AlternativeMacroTerrainProviderV1
CasualValleyModifierProviderV1
provenance hash
```

## Acceptance

```text
swap provider via recipe only
GeoKernel unchanged
G2 cells unchanged
LOD unchanged
renderer caller unchanged
same graph -> same hash
invalid graph rejected
```

## Решение после G4

```text
ARCHITECTURE REVIEW A
```

Если replacement требует special-case в core — дальше не идти, исправить G4.

---

# 6. GR track — representation, начиная после G4

**Не blocking для G5.**

## GR0 — Surface Patch Renderer

**Ветка:**

```text
feature/gr0-surface-representation-lab
```

```text
17x17 sample patch
shared index topology
GeoSurfaceQuery -> mesh artifact
```

## GR1 — Budget + lifecycle

```text
REQUESTED
BUILDING
ACTIVE
RETIRING

max builds/frame
max upload bytes/frame
resource pool
cancellation
```

## GR2 — LOD transition

```text
v0 skirts
later stitching / geomorph
```

## GR3 — Visibility

```text
sphere horizon culling
engine frustum culling
interior occlusion later
```

### Источник идей

Cuberact Chunked LOD:

```text
TAKE:
fixed patch topology
hysteresis concepts
shared indices
skirts
build budget
pooling
horizon culling

DO NOT TAKE:
shader-owned world truth
Quad owns all responsibilities
camera-owned floating origin model
```

---

# 7. G5 — World Feature Graph

**Ветка:**

```text
feature/g5-world-feature-graph
```

Feature identity должна быть spatial-domain-neutral.

```text
WorldFeature
FeatureId
FeatureBounds
FeatureAnchor
FeatureRelation
FeatureGraph
FeatureQuery
```

Fixtures:

```text
ValleyFeature
CraterFeature
FaultFeature
```

Позже без смены контракта:

```text
RiverFeature
CaveFeature
OreVeinFeature
FloatingIslandFeature
StormFeature
AsteroidClusterFeature
```

---

# 8. G6 — Hydrology / Fluid Surface v0

**Ветка:**

```text
feature/g6-hydrology-fluid-surface-v0
```

Сначала реализовать простую реку:

```text
RiverFeature
RiverSpline
RiverChannelProfile
CasualRiverProviderV1
```

Одновременно создать generic contracts:

```text
FluidRegionId
FluidSurfaceDescriptor
WaterSurfaceQuery v0
```

Не делать CFD.

### Unlock

```text
river
lake prototype
ocean layer contract
lava/methane future fluids
```

---

# 9. G7 — Semantic Field Fabric

**Ветка:**

```text
feature/g7-semantic-field-fabric
```

Минимальный полезный набор:

```text
surface normal
slope
curvature
river distance
water level
moisture
erosion
deposition
soil depth
material id
rock hardness
```

Расширяемый namespace:

```text
climate/*
env/*
matter/*
hydro/*
geo/*
```

### Почему это важно

После G7 procedural detail может отвечать на вопрос:

```text
ПОЧЕМУ здесь дерево?
```

а не просто:

```text
потому что random() < 0.2
```

---

# 10. GD track — detail research после G7

**Ветка:**

```text
feature/gd0-deterministic-scatter-research
```

## GD0 Stable Scatter Cells

```text
stable cell
 -> stable jitter
 -> stable anchor id
```

## GD1 Random domains

```text
position
species
rotation
scale
variant
lod priority
```

Независимые deterministic streams.

## GD2 Semantic suitability

```text
TreeSuitability = moisture * soil * temperature_fit * slope_fit
```

## GD3 Stable density LOD

```text
20% subset
50% superset
100% full
```

Без reroll.

## GD4 MultiMesh

```text
patch + species + representation level
 -> MultiMesh
```

## GD5 Billboard / impostor

```text
full mesh
 -> simplified
 -> billboard
 -> none
```

### Источник идей

Godot Procedural Forest Demo.

Перенимаем pattern, не Node3D architecture.

---

# 11. G8 — Geomorphology

**Ветка:**

```text
feature/g8-causal-geomorphology
```

Минимальная причинная цепочка:

```text
RiverFeature
 -> erosion field
 -> bank cut
 -> deposition
 -> slope/material changes
 -> semantic fields
 -> detail suitability
```

Acceptance:

```text
outer bank != inner bank
sediment location stable
surface changes are canonical
renderer has no erosion logic
```

---

# 12. G9 — Layered Geology

**Ветка:**

```text
feature/g9-layered-geology-material-fields
```

```text
LithologyProvider
MaterialColumnQuery
material id
density
hardness
fracture tendency
porosity
OreVeinFeature v0
```

### Unlock

```text
meaningful mining
material-dependent caves
rock-specific detail
Matter integration
```

---

# 13. G10 — GeoVolume / SDF

**Ветка:**

```text
feature/g10-geovolume-sdf-foundation
```

```text
GeoVolumeQuery
signed distance / density
material
optional gradient
```

Backends:

```text
SimpleSdfProvider first
VoxelToolsAdapter research later
```

### Ключевой unlock

```text
heightfield-only world ENDS here
```

После G10 можно корректно выразить:

```text
cave
overhang
arch
floating island
hollow asteroid
underground chamber
```

---

# 14. G11 — Heterogeneous Body Lab

**Ветка:**

```text
feature/g11-heterogeneous-body-lab
```

Три acceptance fixtures:

### A. Asteroid

```text
~500 m
irregular SDF
crater
cave
materials
local gravity
```

### B. Floating island

```text
detached volume
habitable top
fractured underside
water source
vegetation context
```

### C. Hollow body

```text
outer surface
inner surface
connecting opening
```

Gate:

```text
NO world-type special cases in GeoKernel
```

---

# 15. GE track — environment / atmosphere / physics

Можно открыть после G4, полноценную composition — после G7.

## GE0 Environment Contracts

**Ветка:**

```text
feature/ge0-environment-field-contracts
```

```text
GravityFieldQuery
AtmosphereFieldQuery
ThermalFieldQuery
RadiationFieldQuery
FluidFieldQuery
```

## GE1 Gravity

```text
RadialGravityProvider
UniformGravityProvider
MultiBodyGravityProvider
CustomGravityFieldProvider
```

## GE2 Atmosphere

Canonical:

```text
composition
pressure
density
temperature
wind
```

Presentation:

```text
FastAtmosphereRenderer
ScatteringAtmosphereRenderer
```

## GE3 Ocean / Fluid Envelope

```text
fluid composition
surface
volume
pressure by depth
buoyancy inputs
```

## GE4 Physics composition

Environment fields consumed by:

```text
player
AI
ship
items
construction
life support
```

---

# 16. G12 — Scheduler / Cache / Provenance

**Ветка:**

```text
feature/g12-generation-scheduler-cache
```

```text
job identity
priority
cancellation
stale result rejection
cache
provenance
mutation revision
```

Worker produces data only.

Main/presentation thread creates engine objects.

---

# 17. G13 — Detail Contract Freeze

**Ветка:**

```text
feature/g13-high-resolution-detail-contracts
```

```text
DetailPatchContext
DetailPatchArtifact
ScatterDescriptor
RepresentationProfileId
```

Canonical scatter descriptor stores identity/data, not Mesh/PackedScene.

---

# 18. GH production detail track

| Stage | Что добавляем |
|---|---|
| **GH0** | deterministic fixtures/contracts |
| **GH1** | structural rock detail |
| **GH2** | physical scatter: trees, boulders, logs |
| **GH3** | visual scatter: grass, plants, gravel |
| **GH4** | volumetric local detail |
| **GH5** | MultiMesh, density LOD, billboard, async, wind |
| **GH6** | full detail composition gate |

## Важное разделение

```text
canonical / physical
    !=
visual-only
```

Трава может существовать только у клиента.

Крупный валун, который можно добывать, должен иметь stable anchor и promotion path.

---

# 19. GM — dynamic geology / Matter

## GM0 Mutation Contracts

```text
GeoMutationId
bounds
revision
operation
material delta
```

## GM1 Query Overlay

```text
procedural baseline + mutations = current truth
```

## GM2 Matter integration

```text
excavate rock
 -> remove world volume
 -> create material state/item
```

## GM3 Procedural Anchor Promotion

```text
procedural boulder
 -> player interacts
 -> persistent networked entity
```

Не превращать миллионы untouched procedural objects в серверные entities заранее.

---

# 20. GN — network / distributed generation

Главный network contract:

```text
SEND:
identity
recipe hash
versions
seed/provenance
mutation deltas
materialized entities
authority/handoff revisions

DERIVE LOCALLY:
meshes
billboards
grass
most visual scatter
```

## Region identity

```text
WorldDomain
 -> body
 -> surface/volume/space population region
```

## Handoff

Сохранять across servers:

```text
body_id
entity_id
mutation revision
recipe provenance
construction/item aggregate identity
```

Representation rebuilds locally.

---

# 21. Space population — для asteroid belts

Лес дал полезный pattern stable scatter, который масштабируется и в космос.

```text
SpacePopulationCell
 -> deterministic body candidates
 -> stable asteroid anchor ids
 -> local materialization by interest
```

LOD:

```text
very far: statistical/cluster proxy
far: body proxy
near: full body representation
very near: detailed GeoVolume + mutations
```

Это отдельный population provider, а не гигантская spherical terrain map.

---

# 22. Complex object composition

Природный и построенный мир разделены по ownership:

```text
Geo/Matter
Construction
Items
Entities
Fluids
```

Но spatial queries композиционны.

Большая станция:

```text
10k blocks authoritative graph
 -> cluster mesh
 -> proxy/HLOD
 -> far representation
```

Планета/астероид:

```text
canonical fields + mutations
 -> patch mesh
 -> proxy
```

Один и тот же принцип representation separation.

---

# 23. Seamless composition milestones

## GW0 — Earth-like

```text
orbit
 -> atmosphere
 -> terrain
 -> river
 -> forest/detail
 -> cave
```

## GW1 — Mineable asteroid

```text
space proxy
 -> detailed asteroid
 -> cave
 -> excavation
 -> material persistence
```

## GW2 — Asteroid belt

```text
far belt
 -> stable body population
 -> near asteroid
 -> server handoff
```

## GW3 — Floating islands

```text
volume bodies
 -> custom gravity
 -> atmosphere
 -> vegetation
 -> water features
```

## GW4 — Water world

```text
orbit
 -> atmosphere
 -> ocean
 -> underwater
 -> seabed
 -> geology/cave
```

## GW5 — Natural + construction

```text
terrain
 + mining mutation
 + player structure
 + ship/station
 + persistent network state
```

---

# 24. Ближайший рабочий порядок

```text
NOW
 |
 +-- 1. Record G3 ACCEPTED evidence
 |
 +-- 2. G4 Provider Composition / Replacement       [BLOCKING]
 |      |
 |      +-- GR0 Surface Representation Lab          [PARALLEL]
 |
 +-- 3. G5 World Feature Graph                      [BLOCKING]
 |
 +-- 4. G6 Hydrology v0                             [BLOCKING]
 |
 +-- 5. G7 Semantic Field Fabric                    [BLOCKING]
 |      |
 |      +-- GD0 Deterministic Scatter Research      [PARALLEL]
 |      +-- GE0 Environment Contracts               [PARALLEL]
 |
 +-- 6. G8 Geomorphology
 |
 +-- 7. G9 Layered Geology
 |
 +-- 8. G10 GeoVolume / SDF
 |
 +-- 9. G11 Heterogeneous Body Lab
 |
 +-- 10. G12 Scheduler / Cache
 |
 +-- 11. G13 Detail Contracts
 |       |
 |       +-- GH production detail
 |       +-- GM mutations/Matter
 |       +-- GN distributed generation
 |
 +-- 12. GW seamless composition labs
```

---

# 25. Что можно разрабатывать параллельно

### После G4

```text
MAIN: G5
PARALLEL: GR0/GR1 representation
PARALLEL: GE0 contracts
```

### После G7

```text
MAIN: G8 -> G9
PARALLEL: GD0-GD3 deterministic scatter
PARALLEL: GE1-GE3 environment
```

### После G10

```text
MAIN: G11 -> G12
PARALLEL: VoxelToolsAdapter research
PARALLEL: GM0 mutation contract research
```

### После G13

```text
GH detail
GM dynamic matter
GN networking
```

---

# 26. Stop conditions

Остановить развитие stage и исправить architecture, если возникает хотя бы одно:

```text
new world requires hardcoded planet type in GeoKernel
camera affects canonical identity
LOD changes canonical geography
renderer/shader becomes only source of terrain truth
network requires shipping all visual geometry
mutation changes generator seed instead of overlay state
procedural detail rerolls when quality changes
server requires rendering to answer gameplay query
construction ownership leaks into geology provider
```

---

# 27. Целевой результат

Идеальная конечная формула:

```text
WORLD =
    Recipe
  + Stable spatial identity
  + Provider graph
  + Feature graph
  + Semantic fields
  + Environment fields
  + Material/volume truth
  + Sparse mutations
  + Materialized entities

VIEW =
    WORLD
  -> interest
  -> representation budget
  -> local artifacts
```

При такой модели новая фантазия космоса становится новой композицией providers:

```text
не новый движок,
не новый network protocol,
не новый GeoKernel,
а новый WorldRecipe.
```

Это основной критерий всей дальнейшей roadmap.