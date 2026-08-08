# Post-Baseline World Detail Plan

**Дата:** 2026-08-08  
**Ветка фиксации:** `feature/g4-provider-composition-replacement`  
**Назначение:** зафиксировать порядок развития процедурной генерации после исследования reference-ассетов воды, леса, зимы, джунглей, пустыни, льда, болот, вулканизма, погоды, пещер и рифов.

---

## 1. Главное решение

Проект не должен пытаться сразу получить production-картинку каждого типа мира.

Порядок разработки фиксируется так:

```text
сначала универсальная базовая генерация
        ↓
простые deterministic/casual representations
        ↓
architecture + contracts + composition + streaming accepted
        ↓
только затем отдельный detail/beauty pass
        ↓
адаптация лучших механизмов найденных reference-ассетов
```

То есть найденные ассеты сейчас являются **reference library**, а не списком немедленных зависимостей.

Главный критерий ранних этапов:

> Простой визуальный прототип считается достаточным, если он доказывает правильную canonical архитектуру и может позже быть заменён на более качественный renderer/generator без изменения world truth и core contracts.

---

## 2. Что разрешено делать казуально на первом проходе

На базовых стадиях специально разрешаются упрощённые реализации:

```text
river          = простой spline + плоская/ленточная water surface
ocean          = sphere/plane envelope + простой wave shader
forest         = несколько примитивных деревьев/камней через stable scatter
jungle         = те же anchors + условный dense vegetation preset
snow           = coverage field + простой белый material overlay
glacier        = простая ice mass / analytic shape
swamp          = shallow water + wet ground + reeds markers
desert         = sand material + простые dune/noise forms
volcano        = crater/fissure feature + emissive lava strip
cloud/storm    = простые volume/proxy cells + precipitation markers
cave           = простой SDF tunnel/chamber
stalactites    = deterministic cone-like anchors
reef           = branching/rock-like scatter under water
```

Цель этого слоя — не art quality.

Цель:

```text
identity
composition
determinism
query contracts
causal fields
LOD independence
streaming lifecycle
network derivation
mutation compatibility
```

---

## 3. Что НЕ делать до завершения базовой fabric

До завершения базового world-generation path нельзя превращать текущую работу в polishing-проект.

Не блокируют core stages:

```text
photoreal water
FFT ocean
production foam
full deformable snow
photoreal jungle canopy
procedural unique tree geometry at planet scale
realistic aeolian dune transport
full cloud scattering
complex lava viscosity simulation
high-end cave decoration
production coral ecosystem visuals
final PBR terrain material stack
```

Также нельзя вводить hard dependency на внешний addon только ради картинки, если тот начинает диктовать:

```text
world coordinates
chunk ownership
canonical terrain format
camera-dependent world truth
network state
LOD identity
```

---

## 4. Base-first dependency order

Текущая основная последовательность сохраняется:

```text
G4 Provider Composition / Replacement
 ↓
G5 World Feature Graph
 ↓
G6 Hydrology / Fluid Surface v0
 ↓
G7 Semantic Field Fabric
 ↓
G8 Geomorphology
 ↓
G9 Layered Geology
 ↓
G10 GeoVolume / SDF
 ↓
G11 Heterogeneous Body Lab
 ↓
G12 Scheduler / Cache / Provenance
 ↓
G13 Detail Contract Freeze
```

На этих стадиях качество representation может оставаться намеренно простым.

Параллельные `GR`, `GE`, `GD` labs должны доказывать контракты и scalability, но также не обязаны немедленно становиться production-art системами.

---

## 5. Beauty/Detail Gate

После того как базовая генерация принята хотя бы на уровне G13 и существуют стабильные contracts для detail artifacts, открывается отдельный этап:

```text
POST-BASELINE DETAIL / BEAUTY PASS
```

Перед его началом должны быть доказаны:

```text
provider replacement without core special-case
stable feature identity
semantic fields available to detail generators
surface + volume queries
scheduler/cancellation/cache lifecycle
stable deterministic scatter identity
representation != canonical truth
network can derive visual detail locally
mutation overlays do not destroy baseline seed identity
```

После этого внешний reference может безопасно влиять на алгоритмы presentation/detail, не ломая фундамент.

---

## 6. Reference mosaic: что использовать после baseline

Ни один элемент ниже не считается обязательной runtime dependency. Перед переносом конкретного кода/арта отдельно проверяются текущая лицензия, Godot compatibility и технические ограничения.

### 6.1 Forest / vegetation

**Godot Procedural Forest Demo**

Брать идеи:

```text
stable scatter cells
stable jitter
independent random domains
weighted variants
semantic density masks
stable density LOD
MultiMesh batching
mesh -> simplified -> billboard -> none
observer-local grass representation
async generation patterns
coherent wind
```

Не переносить Node3D/world ownership architecture как основу мира.

### 6.2 Rivers

**Waterways**

Брать идеи:

```text
spline-driven river surface
width profile
flow direction / flow map
foam representation
bank-following mesh
height/flow query concepts
```

Canonical river остаётся `RiverFeature/RiverSpline/FluidSurfaceQuery`, внешний river mesh — только representation.

### 6.3 Ocean / sea

References:

```text
godot4-oceanfft
Ocean3D-style deterministic ocean/buoyancy patterns
Boujie-style horizon/LOD/shore presentation
```

Брать идеи:

```text
wave spectrum / Gerstner / FFT presentation
continuous ocean LOD
horizon coverage
whitecaps / foam
underwater presentation
shared wave query for buoyancy where appropriate
near/far quality separation
```

Не делать camera-following mesh canonical ocean state.

### 6.4 Snow / soft surfaces

References:

```text
Deformable Snow examples
snow/sand track activity-map examples
```

Брать идеи:

```text
local deformation map
interaction stamps
foot/wheel/drag tracks
surface displacement overlay
coverage presentation
```

Обобщить в reusable:

```text
LocalSurfaceActivityOverlay
SoftSurfaceOverlay
```

для snow/sand/mud/ash/alien dust.

### 6.5 Jungle / organic geometry

References:

```text
Tree3D-style procedural branching
RopeGenMesh3D-style path geometry
MeshPath3D-style distribution along curves
foliage wind/trampling shaders
```

Брать идеи:

```text
procedural species variants
vines / lianas / roots
path-grown organic geometry
canopy + undergrowth causal relation
wind response
temporary trampling field
```

### 6.6 Desert

References:

```text
Infinigen as offline algorithm catalogue
Terrain3D-style detiling/foliage LOD ideas
Canyon/desert asset packs as validation fixtures
```

Брать идеи:

```text
sediment availability
wind-driven surface structure
dune forms
sparse vegetation suitability
rock/talus scatter
large-scale material detiling
```

Production desert должен быть композицией providers, а не `DesertGenerator` world type.

### 6.7 Ice / glaciers

Брать/исследовать:

```text
snow/ice accumulation fields
soft-surface interaction overlays
volume/SDF ice mass
crevasses
ice caves
overhangs
crack/depth/frost presentation
```

Canonical concepts:

```text
surface/snow-depth-m
surface/ice-thickness-m
thermal state
melt/freeze regions
```

### 6.8 Swamps / wetlands

Композиция:

```text
water table
soil saturation
slow drainage
standing shallow water
organic sediment
reeds/vegetation suitability
mist/fog context
```

Reusable modules:

```text
SaturationField
ShallowFluidRegion
WetSurfacePresentation
```

### 6.9 Volcanoes / lava

Брать идеи:

```text
crater/caldera/fissure/vent features
SDF lava tubes
thermal fields
emissive cooling-crust presentation
ash deposition
steam/gas plume presentation
```

Не делать lava shader источником simulation truth.

### 6.10 Clouds / storms

Брать идеи:

```text
volumetric cloud density representation
coverage/height layers
storm cells
wind/humidity/pressure-driven weather
rain/snow zones
lightning presentation/events
cloud shadowing
fog volumes
```

Canonical weather должен существовать как environment fields; cloud renderer — производная presentation.

### 6.11 Caves / stalactites

Главный фундамент:

```text
GeoVolume / SDF
```

Брать идеи:

```text
cave tunnels/chambers/shafts
material-aware volume
seepage/drip suitability
stalactite/stalagmite deterministic anchors
underground water/fog
```

### 6.12 Coral reefs / underwater ecology

Композиция suitability:

```text
depth
light
water temperature
clarity
current
wave exposure
substrate
```

Брать идеи:

```text
stable colony anchors
branching organic generator
species variants
underwater density LOD
kelp/path-driven geometry
reef debris scatter
```

---

## 7. Универсальные модули, которые должны получиться из мозаики

Вместо множества biome-specific hacks желательно получить переиспользуемые primitives.

### AccumulationField

```text
snow
ash
sand
silt
salt
organic debris
```

### LocalSurfaceActivityOverlay

```text
footprints
tyre tracks
drag marks
dents
surface disturbance
```

### SaturationField

```text
wet soil
mud
swamp
seepage
shoreline wetness
```

### ThermalField

```text
lava
hot rock
geothermal vents
melt zones
warm fluids
```

### AtmosphericVolumeField

```text
cloud
fog
storm
ash plume
cave mist
```

### BranchingGrowthGenerator

```text
trees
roots
vines
coral
fungus
alien organic/mineral forms
```

### PathDrivenGeometry

```text
river strips
roots
vines
lava channels
kelp
organic strands
```

### EnvironmentalSuitability

Один общий causal pattern для размещения vegetation, reef colonies, cave growth, snow/ice detail и других populations.

---

## 8. Production-detail order после baseline

Рекомендуемый порядок наведения качества:

```text
D0 reference/fixture freeze
 ↓
D1 terrain/material presentation quality
 ↓
D2 physical scatter quality: rocks/trees/logs
 ↓
D3 visual scatter quality: grass/plants/debris
 ↓
D4 water: rivers/coast/ocean presentation
 ↓
D5 weather + snow/ice + wetness
 ↓
D6 volumetric local detail: caves/ice/lava
 ↓
D7 biome/ecology compositions: jungle/swamp/desert/reef
 ↓
D8 full LOD/impostor/async/wind/activity optimization
 ↓
D9 composition + performance + network validation
```

Это не обязано заменять существующие `GD/GH/GE/GR` названия веток; это порядок quality-pass поверх уже принятых контрактов.

---

## 9. Acceptance для каждого beautification generator

Каждый красивый backend должен пройти одинаковый gate:

```text
same canonical input -> stable output identity
camera changes representation only
quality/LOD does not reroll canonical anchors
provider can be disabled/replaced by recipe/profile
headless simulation does not require visual addon
no external addon owns global world coordinates
no addon changes GeoKernel/network contracts
streaming unload/reload reproduces the same world
network sends identity/recipe/mutations, not millions of visual instances
```

Если внешний ассет не укладывается в этот gate, из него берётся только локальный алгоритм/идея либо он остаётся reference-only.

---

## 10. Итоговая doctrine

```text
BASE FIRST
BEAUTY SECOND
```

Первое приближение мира может выглядеть казуально и условно.

Это сознательное решение, потому что сейчас дороже всего доказать:

```text
универсальность
заменяемость
детерминизм
масштабирование
геодезию
volume/surface composition
streaming
network compatibility
mutations
```

После того как этот фундамент стабилен, найденная библиотека ассетов и алгоритмов превращается в ускоритель качества, а не в архитектурный долг.

Целевая формула:

```text
canonical world fabric
      +
replaceable high-quality detail backends
      =
любые миры от простых прототипов до production-планет
```
