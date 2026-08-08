# Session Summary — Procedural Generation Asset Research

**Дата:** 2026-08-08  
**Ветка:** `feature/g4-provider-composition-replacement`

## Цель сессии

Проверить внешние procedural/environment assets не как готовые world systems, а как библиотеку механизмов, которые можно позже адаптировать к Universal World Generation Fabric.

Главный вывод:

```text
не искать один готовый generator на каждый biome

искать reusable mechanisms
и собирать мир из providers + fields + features + representations
```

---

## 1. Forest / high-resolution detail

Подтверждён важный reference:

```text
Godot Procedural Forest Demo
```

Полезные механизмы:

```text
stable deterministic scatter cells
stable jitter
independent random domains
weighted variants
semantic density masks
stable density LOD
MultiMesh batching
mesh/billboard LOD
observer-local grass
async generation
coherent vegetation wind
```

Решение:

```text
TAKE patterns
DO NOT TAKE its Node3D/world ownership architecture as core
```

Для проекта это будущий источник идей для `GD/GH` detail tracks после появления semantic fields и detail contracts.

---

## 2. Water

### Rivers

Главный reference:

```text
Waterways
```

Полезные механизмы:

```text
spline river geometry
flow direction/maps
width/profile control
foam representation
surface height/flow query concepts
```

Это хорошо ложится на будущие:

```text
RiverFeature
RiverSpline
FluidRegion
FluidSurfaceQuery
```

### Sea / ocean

References:

```text
godot4-oceanfft
Ocean3D-style deterministic wave/buoyancy patterns
Boujie-style ocean LOD/horizon/shore rendering
```

Полезно разделять:

```text
canonical ocean/fluid state
        !=
ocean representation
```

Для корабля/физики нужен query API воды; FFT/Gerstner/foam/SSR/billboard/horizon относятся к presentation.

---

## 3. Winter / snow / ice

References/ideas:

```text
Deformable Snow
snow/sand activity-map track examples
volume/SDF ice geometry
```

Из исследования выведены reusable concepts:

```text
SoftSurfaceOverlay
LocalSurfaceActivityOverlay
AccumulationField
```

Они должны работать не только для снега:

```text
snow
sand
mud
ash
alien dust
```

Для ледников нужны также:

```text
snow depth
ice thickness
freeze/melt thermal state
crevasses
ice caves
overhangs
```

---

## 4. Jungle / dense ecology

References:

```text
Tree3D-style procedural branching
RopeGenMesh3D-style rope/path mesh
MeshPath3D-style distribution along paths
foliage wind/trampling shader patterns
Quaternius nature assets as test fixtures
```

Ключевое архитектурное наблюдение:

```text
Forest Demo answers: WHERE is the plant?
procedural species generator answers: WHAT geometry represents it?
```

Для jungle нужна причинная композиция:

```text
humidity
temperature
soil
water proximity
solar exposure
        ↓
large trees
        ↓
canopy openness/shadow
        ↓
undergrowth
        +
vines / roots / ferns / moss
```

`canopy openness` полезно рассматривать как semantic field, а не случайный vegetation preset.

---

## 5. Desert

References:

```text
Infinigen as algorithm/reference catalogue
Terrain3D-style texture detiling + foliage LOD
canyon/desert packs as validation fixtures
```

Главное решение:

```text
DO NOT build DesertGenerator world type
```

Вместо этого:

```text
SedimentProvider
WindTransportProvider
DuneFormationProvider
AridVegetationProvider
DesertSurfaceDetailProvider
```

Это позволяет тем же механизмам создавать:

```text
sand dunes
ash dunes
snow dunes
alien granular dunes
```

---

## 6. Wetlands / swamp

Болото рассматривается как состояние полей:

```text
high water table
high soil saturation
slow drainage
standing shallow water
organic sediment
suitable vegetation
fog/humidity context
```

Reusable concepts:

```text
SaturationField
ShallowFluidRegion
WetSurfacePresentation
```

Не нужен hardcoded `SWAMP` planet/biome branch в core.

---

## 7. Volcano / lava

Нужные canonical mechanisms:

```text
VolcanicFeature
crater/caldera/fissure/vent
lava region / flow channel
thermal field
ash deposition
gas/steam emission
SDF lava tubes
```

Visual references нужны для:

```text
cooling crust
emissive cracks
heat haze
steam/ash plume
```

Но lava shader никогда не должен быть источником simulation truth.

---

## 8. Clouds / storms

Нужное разделение:

```text
environment/weather canonical fields
        !=
volumetric cloud renderer
```

Canonical candidates:

```text
humidity
pressure
wind
cloud density
precipitation
storm intensity
lightning risk
fog
```

Presentation:

```text
volumetric clouds
cloud shadows
rain/snow particles
lightning visuals
storm illumination
```

---

## 9. Caves / stalactites

Главный фундамент:

```text
GeoVolume / SDF
```

Нужные features/detail:

```text
cave tunnel
chamber
shaft
underground fluid region
seepage/drip zone
stalactite/stalagmite anchors
ore/mineral relations
```

Stalactites/mites можно рассматривать как deterministic growth scatter, зависящий от:

```text
ceiling/floor geometry
seepage
mineral content
age/growth parameters
```

---

## 10. Coral reefs

Риф — не отдельный magic biome generator.

Suitability строится из:

```text
depth
light
water temperature
clarity
current
wave exposure
substrate
```

Detail population:

```text
stable coral colony anchors
branching organic geometry
species variants
kelp/path-driven forms
reef debris
underwater density LOD
```

Branching generator может быть переиспользован для:

```text
trees
roots
vines
corals
fungus
alien organic/mineral structures
```

---

## 11. Общая мозаика reusable mechanisms

По итогам сессии сформирован следующий каталог потенциальных primitives:

```text
AccumulationField
LocalSurfaceActivityOverlay
SoftSurfaceOverlay
SaturationField
ThermalField
AtmosphericVolumeField
EnvironmentalSuitability
BranchingGrowthGenerator
PathDrivenGeometry
StableScatterDomain
DensityLodPolicy
RepresentationImpostorPipeline
```

Эти primitives важнее списка конкретных Earth biomes.

---

## 12. Архитектурный вывод

Целевая формула мира расширена до:

```text
WORLD =
    geometry
  + geology
  + fluids
  + climate/environment fields
  + material transport
  + ecology/suitability
  + procedural populations
  + sparse mutations/interactions
  + representation
```

И такие понятия как:

```text
forest
jungle
tundra
desert
swamp
coast
glacier
reef
volcanic field
```

должны по возможности быть устойчивыми результатами композиции полей/providers, а не hardcoded world classes.

---

## 13. Timing decision — важнейший итог сессии

Найденные references **не надо интегрировать немедленно**.

Сначала:

```text
G4-G13 base generation fabric
simple casual representations
architecture acceptance
```

Потом:

```text
post-baseline detail/beauty pass
```

В первом приближении допустимы простые условные модели воды, леса, снега, лавы, пещер, рифа и прочих environments.

Только после стабилизации contracts и streaming имеет смысл тратить время на:

```text
production water
complex vegetation
snow deformation
advanced clouds
photoreal materials
high-quality cave detail
reef ecology presentation
```

Полный порядок и acceptance зафиксированы в:

```text
docs/plans/POST_BASELINE_WORLD_DETAIL_PLAN_RU.md
```
