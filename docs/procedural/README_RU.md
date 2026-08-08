# Procedural Planetary Generation Lab — индекс экспериментальной ветки

**Ветка:** `feature/g0-procedural-planetary-generation-lab`.  
**Дата основания:** 2026-08-08.  
**Назначение:** зафиксировать архитектуру и последовательность разработки универсального procedural planetary generator до начала production implementation.

---

# С чего начинать

Если задача — продолжить реализацию после перерыва, читать в таком порядке:

1. [`STATUS_RU.md`](STATUS_RU.md) — где мы сейчас и какой gate следующий.
2. [`../plans/PROCEDURAL_PLANETARY_GENERATION_EXECUTION_PLAN_RU.md`](../plans/PROCEDURAL_PLANETARY_GENERATION_EXECUTION_PLAN_RU.md) — что конкретно реализовать и проверить на этом gate.
3. [`../validation/PROCEDURAL_PLANET_LAB_ACCEPTANCE_RU.md`](../validation/PROCEDURAL_PLANET_LAB_ACCEPTANCE_RU.md) — общие acceptance invariants.
4. [`../architecture/PROCEDURAL_PLANETARY_GENERATION_FABRIC_RU.md`](../architecture/PROCEDURAL_PLANETARY_GENERATION_FABRIC_RU.md) — архитектурная доктрина, если возникает спор о границах системы.
5. [`../plans/PROCEDURAL_PLANETARY_GENERATION_ROADMAP_RU.md`](../plans/PROCEDURAL_PLANETARY_GENERATION_ROADMAP_RU.md) — полная стратегическая карта G0–G19.

Текущий следующий gate:

```text
G0 — Contracts freeze v0
recommended branch: feature/g0-geo-contracts
```

---

# Документы

## Status ledger

[`STATUS_RU.md`](STATUS_RU.md)

Единая точка фиксации:

```text
current stage
accepted/rejected gates
next branch
implementation commit
validation result
known debt
next gate
```

После каждого G/GH stage этот файл обязан обновляться.

## Исполнительный план

[`../plans/PROCEDURAL_PLANETARY_GENERATION_EXECUTION_PLAN_RU.md`](../plans/PROCEDURAL_PLANETARY_GENERATION_EXECUTION_PLAN_RU.md)

Практический порядок реализации, тестов, architecture reviews, milestones и parallel fork после G13.

## Архитектурная доктрина

[`../architecture/PROCEDURAL_PLANETARY_GENERATION_FABRIC_RU.md`](../architecture/PROCEDURAL_PLANETARY_GENERATION_FABRIC_RU.md)

Определяет:

- GeoKernel;
- PlanetRecipe;
- provider graph;
- geodesy/body-fixed contracts;
- FeatureGraph;
- semantic fields;
- surface/volume split;
- deterministic baseline;
- границу с Matter и Representation LOD;
- parallel-development doctrine.

## ADR

[`../architecture/adr/ADR-019-procedural-planetary-generation-fabric.md`](../architecture/adr/ADR-019-procedural-planetary-generation-fabric.md)

Фиксирует решения, которые нельзя размывать implementation shortcuts.

## Стратегическая дорожная карта

[`../plans/PROCEDURAL_PLANETARY_GENERATION_ROADMAP_RU.md`](../plans/PROCEDURAL_PLANETARY_GENERATION_ROADMAP_RU.md)

Каноническая последовательность:

```text
G0  contracts
→ G1  geodesy/body shape
→ G2  planetary cells/LOD
→ G3  mega-casual surface
→ G4  provider composition/replacement
→ G5  FeatureGraph
→ G6  mega-casual river
→ G7  semantic fields
→ G8  casual geomorphology
→ G9  geology lite
→ G10 GeoVolume
→ G11 cave
→ G12 cache/scheduler boundaries
→ G13 progressive detail contract freeze
→ G14 simple detail generator
→ G15 multiple planet recipes
→ G16 generator substitution acceptance
```

После G13 параллельно стартует HR-track. После первого prototype отдельно идут:

```text
G17 Matter bridge
G18 Representation LOD integration
G19 Network manifest integration
```

## High-Resolution Detail Generator

[`../architecture/HIGH_RESOLUTION_DETAIL_GENERATOR_RU.md`](../architecture/HIGH_RESOLUTION_DETAIL_GENERATOR_RU.md)

Отдельный backend для локальной детализации вплоть до сантиметрового visual/physical масштаба.

После G13 рекомендуемая независимая ветка:

```text
feature/gh0-high-resolution-detail-generator
```

Она работает на recorded `DetailPatchContext` fixtures и не требует полного planetary runtime.

Канонический HR порядок:

```text
GH0 Contract + Fixture Harness
→ GH1 Structural 100 m Patch
→ GH2 Decimeter Physical Detail
→ GH3 Material Micro Detail
→ GH4 Volumetric Refinement Adapter
→ GH5 Performance Budgets
→ GH6 Main Geo Composition
```

## Acceptance и debug observability

[`../validation/PROCEDURAL_PLANET_LAB_ACCEPTANCE_RU.md`](../validation/PROCEDURAL_PLANET_LAB_ACCEPTANCE_RU.md)

Определяет:

- determinism;
- order independence;
- cross-cell continuity;
- LOD semantic compatibility;
- provider replacement;
- debug field views;
- River Valley Fly-In scenario;
- high-resolution fixture acceptance.

---

# Главная парадигма

```text
PlanetDefinition + PlanetRecipe
              ↓
           GeoKernel
              ↓
     versioned provider graph
              ↓
      deterministic fields
              ↓
          FeatureGraph
              ↓
      Surface + GeoVolume
              ↓
    representation selection
       /              \
macro/regional       local detail
                         ↓
              HighResolution backend

procedural baseline
        +
persistent Matter/Construction deltas
        =
authoritative world
```

## Что является истиной мира

```text
seed
+ recipe/provider versions
+ stable features
+ canonical persistent deltas
```

Не является истиной мира:

```text
mesh
collision mesh
impostor
LOD artifact
high-resolution presentation patch
shader detail
cache entry
```

---

# Почему первые generators намеренно «мега-казуальные»

На ранних этапах качество algorithms сознательно простое, чтобы проверить архитектуру.

Примеры:

```text
mountain = low-frequency radial noise
river = spline + simple carve
geology = SOFT/MEDIUM/HARD regions
cave = analytic sphere/capsule SDF subtraction
island = deposition threshold heuristic
```

После стабилизации contracts можно независимо заменить:

```text
CasualRiver → MeanderingRiver → DrainageRiver → HydraulicRiver
SimpleGeology → LayeredGeology → advanced geological model
SimpleDetail → HighResolutionDetailGenerator
```

---

# Первый большой proof-of-concept

`G11 — River Valley Fly-In + Cave`:

```text
30–50 km altitude
→ regional valley
→ long river
→ island/shoal/cliff
→ land near cliff
→ cave entrance
→ enter generated cave
```

Визуальное качество на этом checkpoint вторично.

Обязательны:

```text
one seed
stable body-fixed coordinates
cross-cell river continuity
stable features
replaceable providers
multi-LOD semantic continuity
real volume cave
```

---

# Главный параллельный fork

После `G13 ACCEPTED`:

```text
                         DetailPatchContext
                                │
                 ┌──────────────┴──────────────┐
                 ▼                             ▼
             MAIN GEO TRACK                HIGH-RES TRACK
             G14 → G15 → G16               GH0 → ... → GH6
```

Это позволяет отдельно разрабатывать сверхдетальную генерацию на 20×20 / 100×100 / 500×500 m fixtures, не блокируя planet-scale генератор.

---

# Граница с существующими ветками

До отдельного integration checkpoint программа не меняет production generators `moon`, `earth`, `earth_moon`.

Она использует существующие фундаментальные решения проекта, где применимо:

- double precision;
- body-fixed frames;
- CubeSphere addressing concepts;
- async data-only generation/main-thread commit boundaries;
- Dynamic Matter Fabric;
- Representation LOD Fabric.

Но новый GeoKernel не зависит от конкретной текущей lunar terrain implementation.

---

# Следующее действие

Начать код только с `G0 — Contracts freeze v0`.

Первый implementation patch должен доказать:

```text
PlanetDefinition
PlanetRecipe
IGeoProvider
GeoKernel
FlatSurfaceProvider
provider dependency validation
determinism tests
```

Ни рек, ни гор, ни пещер в G0 не требуется.
