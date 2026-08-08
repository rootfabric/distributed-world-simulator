# Procedural Planetary Generation Lab — индекс экспериментальной ветки

**Ветка:** `feature/g0-procedural-planetary-generation-lab`.
**Дата основания:** 2026-08-08.
**Назначение:** зафиксировать архитектуру и последовательность разработки универсального procedural planetary generator до начала production implementation.

## Документы

### Архитектурная доктрина

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

### ADR

[`../architecture/adr/ADR-019-procedural-planetary-generation-fabric.md`](../architecture/adr/ADR-019-procedural-planetary-generation-fabric.md)

Фиксирует решения, которые нельзя размывать implementation shortcuts.

### Пошаговая дорожная карта

[`../plans/PROCEDURAL_PLANETARY_GENERATION_ROADMAP_RU.md`](../plans/PROCEDURAL_PLANETARY_GENERATION_ROADMAP_RU.md)

Развитие начинается с намеренно простого ядра:

```text
G0 contracts
→ G1 geodesy
→ G2 cells/LOD
→ G3 mega-casual surface
→ G4 provider composition
→ G5 FeatureGraph
→ G6 mega-casual river
→ G7 semantic fields
→ G8 casual geomorphology
→ G9 geology lite
→ G10 volume
→ G11 cave
→ G12 cache/scheduler boundaries
→ G13 detail contract freeze
→ G14 simple detail
→ G15 multi-planet recipes
→ G16 generator substitution acceptance
```

### High-Resolution Detail Generator

[`../architecture/HIGH_RESOLUTION_DETAIL_GENERATOR_RU.md`](../architecture/HIGH_RESOLUTION_DETAIL_GENERATOR_RU.md)

Отдельный backend для локальной детализации вплоть до сантиметрового visual/physical масштаба.

После G13 рекомендуемая независимая ветка:

```text
feature/gh0-high-resolution-detail-generator
```

Она должна работать на записанных `DetailPatchContext` fixtures и не зависеть от полного planetary runtime.

### Acceptance и debug observability

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

## Главная парадигма в одном блоке

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

Истина:

```text
seed + recipe/provider versions + stable features + canonical persistent deltas
```

Не истина:

```text
mesh
collision mesh
impostor
LOD artifact
high-resolution presentation patch
shader detail
cache entry
```

## Почему первые generators будут «мега-казуальными»

На ранних этапах качество algorithms сознательно занижено, чтобы проверить архитектуру.

Примеры:

```text
mountain = low-frequency radial noise
river = predefined/procedural spline + simple carve
geology = SOFT/MEDIUM/HARD regions
cave = analytic sphere/capsule SDF subtraction
island = deposition threshold heuristic
```

После стабилизации contracts их можно независимо заменить:

```text
CasualRiver → MeanderingRiver → DrainageRiver → HydraulicRiver
SimpleGeology → LayeredGeology → advanced geological model
SimpleDetail → HighResolutionDetailGenerator
```

## Первый большой proof-of-concept

`G11 River Valley Fly-In + Cave`:

```text
30–50 km altitude
→ regional valley
→ long river
→ island/shoal/cliff
→ land near cliff
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

## Граница с существующими ветками

До отдельного integration checkpoint ветка не должна менять production generators `moon`, `earth`, `earth_moon`.

Она использует существующие фундаментальные решения проекта, где применимо:

- double precision;
- body-fixed frames;
- CubeSphere addressing concepts;
- async data-only generation/main-thread commit boundaries;
- Dynamic Matter Fabric;
- Representation LOD Fabric.

Но новый GeoKernel не должен зависеть от concrete existing lunar terrain implementation.

## Следующее действие

Начать код только с `G0 — Contracts freeze v0`.

Первый implementation patch должен быть маленьким и доказать:

```text
PlanetDefinition
PlanetRecipe
IGeoProvider
GeoKernel
FlatSurfaceProvider
provider dependency validation
determinism tests
```

Ни рек, ни гор, ни пещер в G0 делать не требуется.
