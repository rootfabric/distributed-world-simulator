# После G3 — Universal World Generation Fabric

**База:** `feature/g3-casual-macro-surface @ bc58f650ffb43775667bf0d07cb361a98a40d294`

Этот документ — короткая точка входа в скорректированную программу после успешной реализации и тестирования G3.

Основные документы:

```text
docs/plans/UNIVERSAL_WORLD_GENERATION_EXECUTION_PLAN_RU.md
docs/plans/UNIVERSAL_WORLD_GENERATION_ROADMAP_RU.md
```

---

## Что изменилось в стратегии

G0–G3 не переписываются.

Они считаются фундаментом:

```text
G0 contracts
G1 geodesy/body shape
G2 planetary cells/LOD
G3 canonical macro surface
```

После G3 программа перестаёт рассматриваться как разработка одного planetary terrain generator.

Цель:

```text
Universal World Generation Fabric
```

где конкретный мир — это recipe из независимых providers.

---

## Главный принцип

```text
new fantasy world
     !=
new engine special case

new fantasy world
     =
new recipe/providers/features/environment/detail backends
```

Core не должен знать про типы вроде:

```text
EARTH
MOON
ASTEROID
FLOATING_ISLAND
OCEAN_PLANET
```

Вместо этого мир определяется capabilities и provider graph.

---

## Ближайший blocking path

```text
G3 successful
  |
  v
record G3 accepted evidence
  |
  v
G4 Provider Composition / Replacement
  |
  v
G5 World Feature Graph
  |
  v
G6 Hydrology / Fluid Surface v0
  |
  v
G7 Semantic Field Fabric
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
G12 Scheduler / Cache
  |
  v
G13 Detail Contract Freeze
```

---

## Параллельные tracks

```text
GR — surface/volume representation, LOD, pooling, budgets
GD — deterministic scatter/detail research
GE — atmosphere, gravity, ocean, environment physics
GH — production high-resolution detail
GM — dynamic geology + Matter mutations
GN — network/distributed generation + handoff
GW — seamless heterogeneous world composition
```

---

## Что взято из Cuberact

Как reference для representation:

```text
fixed patch topology
shared indices
visual skirts
build budget
presentation pooling
sphere horizon culling
```

Не переносится его architecture, где planet/chunk/rendering тесно связаны.

---

## Что взято из Procedural Forest Demo

Как reference для high-resolution/detail:

```text
stable deterministic scatter cells
stable jitter
separate random domains
weighted variants
semantic density masks
stable density LOD
MultiMesh batching
geometry -> billboard LOD
observer-centered grass
async generation
coherent wind
```

Но в нашем проекте:

```text
raycast -> GeoSurfaceQuery
bitmap truth -> semantic fields
Vector3.UP -> LocalTangentFrame.Up
full regenerate -> streaming lifecycle
camera affects representation only
```

---

## Проверочные миры программы

Roadmap специально требует не только Earth-like fixture.

Обязательные architecture proofs:

```text
Earth-like planet
mineable irregular asteroid
hollow asteroid/body
floating island
asteroid belt
water world
mixed geology + player construction
```

Если эти миры собираются новыми recipes/providers без special-case в GeoKernel, архитектура выполняет цель проекта.

---

## Network doctrine

По сети передаём преимущественно:

```text
identity
recipe/provenance
versions
mutations
materialized entities
authority revisions
handoff state
```

Локально производим:

```text
terrain meshes
MultiMesh vegetation
billboards
grass
visual microdetail
```

Это позволяет строить миры планетарного масштаба без сетевой репликации всей геометрии.

---

## Mutation doctrine

```text
procedural baseline
+
sparse authoritative mutation journal
=
current world truth
```

Добыча, туннели и разрушение не должны менять seed исходного мира.

---

## Итог

Следующий непосредственный implementation stage остаётся:

```text
G4 — Provider Composition / Replacement
```

Параллельно после G4 можно открыть:

```text
GR0 — Surface Representation Lab
GE0 — Environment Field Contracts
```

После G7:

```text
GD0 — Deterministic Scatter Research
```

Это сохраняет темп разработки и одновременно ведёт проект к универсальному симулятору миров, а не к одному специализированному terrain engine.