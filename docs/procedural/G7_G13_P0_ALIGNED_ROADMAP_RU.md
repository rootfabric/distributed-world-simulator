# G7–G13 — P0-aligned roadmap Universal World Generation Fabric

**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Upstream accepted:** `G6 Hydrology / Fluid Surface v0 — SOURCE_ACCEPTED`
**Current next checkpoint:** `G7 Semantic Field Fabric`

## 1. Цель продолжения

Следующая линия должна превратить уже принятые G3/G5/G6 semantics в универсальный набор composable географических полей, а затем на этой основе строить рельеф, геологию, объёмные структуры и разные типы небесных тел.

Главная архитектурная формула остаётся:

```text
canonical procedural semantics
        != representation cells / LOD
        != renderer
        != authority routing
        != persistence backend
        != network transport
```

И дополнительно:

```text
Geo baseline + sparse authoritative Matter mutations = current world truth
```

## 2. P0 guards перед G7

G7 не является разрешением создать второй Spatial/WorldQuery/Material/Authority foundation.

Обязательные границы:

```text
SemanticFieldId != SurfaceCellKey
SemanticFieldId != LOD
SemanticFieldId != AuthorityRegionId
SemanticFieldId != InterestRegionId
SemanticFieldQuery != universal WorldQuery Fabric
FluidTypeId != MaterialDefinitionId
Geo provider != persistence owner
Geo provider != network owner
Geo provider != authority owner
```

G7 должен быть domain-level semantic fabric, который позже подключается к общим P0/P1 foundation через adapters.

## 3. G7 — Semantic Field Fabric

### G7.0 — Semantic Field Contracts

Ввести минимальные generic contracts:

```text
SemanticFieldId
SemanticFieldDescriptor
SemanticFieldValueType
SemanticFieldDomain
SemanticFieldQuery
SemanticFieldSample
SemanticFieldBundle
SemanticFieldProvenance
```

Типовые поля первого набора:

```text
geo/surface-height-m
geo/slope
geo/curvature
geo/valley-influence
geo/river-distance-m
geo/river-width-m
geo/fluid-surface-distance-m
geo/drainage-potential
geo/continentalness
geo/temperature-baseline
geo/moisture-baseline
```

Важно: перечисление полей — vocabulary, а не hardcoded planet types.

### G7.1 — Upstream adapters

Подключить принятые источники без переноса ownership:

```text
G3 macro surface provider
    -> semantic field adapter

G5 WorldFeatureGraph
    -> feature-derived field adapter

G6 Fluid / river geography
    -> fluid-derived field adapter
```

Например, `river-distance-m` вычисляется из G5/G6 river semantics, но не создаёт новую River identity.

### G7.2 — Composition / Provenance

Доказать deterministic composition:

```text
base field
 + feature-derived modifier
 + hydrology-derived modifier
 -> final semantic field bundle
```

Каждый sample должен объяснять provenance: provider/version/source feature/source fluid region/config hash.

G7 не вводит scheduler/cache ownership — только deterministic composition contract. Реальный scheduler/cache остаётся G12.

### G7.3 — Cross-cell / Cross-LOD invariance

Acceptance должен доказать:

- один world point даёт те же canonical semantic values независимо от SurfaceCellKey;
- LOD меняет только число/плотность representation samples;
- PX/PZ и другие cube-sphere seams не меняют semantic value;
- один river/valley feature пересекает много cells без смены identity;
- query order не влияет на result/provenance.

### G7.4 — Semantic Field Lab

Сделать диагностический lab, где один и тот же участок можно переключать между полями:

```text
height
slope
curvature
river distance
moisture proxy
continentalness
```

Lab — derived visualization. Его colors/mesh/resolution не входят в canonical checksum.

### G7 acceptance

```text
contracts PASS
G3/G5/G6 adapter composition PASS
cross-face continuity PASS
LOD invariance PASS
provenance determinism PASS
full world regression PASS
P0 ownership audit PASS
```

## 4. G8 — Geomorphology

G8 начинает изменять procedural baseline рельеф через semantic fields.

Ownership G8:

```text
valley incision
river channel incision
banks
floodplain shaping
ridge/valley response
erosion/deposition baseline
```

Не ownership G8:

```text
player excavation
persistent terrain damage
Matter transactions
material ontology
```

Целевая композиция:

```text
G3 macro height
 + G7 drainage / river / slope fields
 -> G8 geomorphology modifiers
 -> canonical procedural surface baseline
```

Главный acceptance: river из G6 действительно получает valley/channel/banks в terrain baseline без превращения river mesh в источник истины.

## 5. G9 — Layered Geology

G9 строит subsurface geological semantics:

```text
strata / layers
lithology
fault influence
ore/resource potential
porosity
hardness/fracture projections
thermal/geochemical baseline hooks
```

### Обязательный P0-3 gate

Formal G9 material acceptance нельзя закрывать независимым namespace вроде:

```text
"rock"
"iron"
"water"
```

Нужен bridge к `MaterialDefinitionId` / shared composition model.

До готовности P0 Material Ontology разрешено разрабатывать geometry/layer topology и abstract material references, но не объявлять G9 material semantics production-canonical.

```text
G9 topology can proceed
G9 material truth requires P0-3 bridge
```

## 6. G10 — GeoVolume / SDF

Цель: выйти за рамки height field.

```text
caves
arches
overhangs
floating islands
asteroid voids
subsurface chambers
cliffs with true volume
```

Canonical procedural representation может использовать SDF/implicit volume/CSG-like descriptors, но:

```text
GeoVolume != Matter storage
GeoVolume != authoritative excavation state
```

GM в дальнейшем означает `Geo <-> Matter Integration`, а не вторую реализацию Matter.

## 7. G11 — Heterogeneous Body Lab

Один composition lab должен доказать, что foundation не привязана к Earth-like planet.

Минимальный matrix:

```text
Earth-like sphere
small irregular asteroid
floating-island body / field
water-dominant world
ice/methane-like body
body with non-default environment/gravity parameters
```

Проверяется, что замена recipe/providers меняет мир, но не generic caller contracts.

Это важный checkpoint идеи симулятора: генераторы должны позволять строить произвольные фантазийные миры без `if earth / if asteroid` в generic kernel.

## 8. G12 — Scheduler / Cache / Provenance

Только после доказательства semantic correctness вводится production-oriented execution layer.

G12 владеет:

```text
generation work scheduling
provider dependency execution
cache keys
cache invalidation
provenance manifests
budget accounting adapters
```

G12 НЕ владеет:

```text
authority
persistence semantics
world identity
network ownership
canonical transaction commit
```

G12 должен быть совместим с будущими:

```text
NX8 shared interest/replication budget
P1 World Work / Budget Fabric
promotion / dormancy / demotion
```

но не реализовывать эти foundation приватно.

## 9. G13 — Detail Contract Freeze

G13 фиксирует contract boundary перед массовым production detail generation.

К этому моменту downstream должен иметь стабильные интерфейсы для:

```text
surface
features
fluids
semantic fields
geomorphology
geology
volume/SDF
provenance
representation requests
```

После G13 можно безопаснее масштабировать библиотеки генераторов/биомов/ассетов, потому что content generation перестаёт диктовать фундаментальные runtime interfaces.

## 10. Скорректированная последовательность

```text
G6 Hydrology / Fluid Surface             SOURCE_ACCEPTED
        ↓
G7 Semantic Field Fabric                 NEXT
        ↓
G8 Geomorphology
        ↓
G9 Layered Geology
        │   formal material gate -> P0 Unified Material Ontology
        ↓
G10 GeoVolume / SDF
        ↓
G11 Heterogeneous Body Lab
        ↓
G12 Scheduler / Cache / Provenance
        ↓
G13 Detail Contract Freeze
        ↓
Geo <-> Matter composition / production detail tracks
```

## 11. Параллельные работы

Можно вести параллельно, пока они не захватывают canonical ownership:

```text
GR0+ representation experiments
GE0+ environment/atmosphere field contracts
asset/detail generator research
forest/vegetation presentation research
network tuning
construction/item development
```

Representation/detail research может потреблять G7 fields раньше G13, но не должно заставлять semantic identity зависеть от renderer/LOD/camera.

## 12. Merge / composition gates

Каждый G7+ checkpoint перед SOURCE_ACCEPTED обязан подтвердить:

```text
GLOBAL revision == main
GLOBAL config byte-equivalent
local P0 alignment current
no duplicate foundation ownership
identity independent from cell/LOD/rendering/network
headless semantic execution possible
focused contracts PASS
parent G-stage regression PASS
world/core regression PASS
clean worktree
git diff --check PASS
status dimensions remain distinct
```

Для стадий с cross-domain semantics дополнительно:

```text
G9  -> Material Ontology composition gate
G10 -> Geo/Matter ownership audit
G12 -> Authority/Persistence/Work-Budget ownership audit
```

## 13. Ближайший implementation checkpoint

Начинать не с erosion/geology, а с G7.0:

```text
G7.0 Semantic Field Contracts + Registry Vocabulary
```

Первый candidate должен быть маленьким и доказать generic field identity/value/provenance без scheduler/cache/network/persistence. После него — G7.1 adapters к уже принятым G3/G5/G6.
