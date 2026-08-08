# Procedural Planetary Generation Lab — индекс программы

**Program branch:** `feature/g0-procedural-planetary-generation-lab`
**Current implementation:** `feature/g0-geo-contracts`
**Current state:** `G0 ACCEPTED`

---

## С чего начинать после перерыва

1. [`STATUS_RU.md`](STATUS_RU.md) — текущее состояние и следующий gate.
2. [`../checkpoints/G0_GEO_CONTRACTS_CANDIDATE_RU.md`](../checkpoints/G0_GEO_CONTRACTS_CANDIDATE_RU.md) — исходный implementation checkpoint G0.
3. [`../checkpoints/G0_GEO_CONTRACTS_CLEANUP1_RU.md`](../checkpoints/G0_GEO_CONTRACTS_CLEANUP1_RU.md) — финальная cleanup/acceptance фиксация G0.
4. [`../plans/PROCEDURAL_PLANETARY_GENERATION_EXECUTION_PLAN_RU.md`](../plans/PROCEDURAL_PLANETARY_GENERATION_EXECUTION_PLAN_RU.md) — практический порядок G0–G19.
5. [`../architecture/PROCEDURAL_PLANETARY_GENERATION_FABRIC_RU.md`](../architecture/PROCEDURAL_PLANETARY_GENERATION_FABRIC_RU.md) — общая архитектурная доктрина.
6. [`../validation/PROCEDURAL_PLANET_LAB_ACCEPTANCE_RU.md`](../validation/PROCEDURAL_PLANET_LAB_ACCEPTANCE_RU.md) — сквозные acceptance invariants.
7. [`../architecture/HIGH_RESOLUTION_DETAIL_GENERATOR_RU.md`](../architecture/HIGH_RESOLUTION_DETAIL_GENERATOR_RU.md) — будущий параллельный high-resolution track.

---

## Где мы сейчас

```text
G0 Contracts Freeze v0
        ACCEPTED
          │
          ▼
G1 Geodesy + Body Shape
          │
          ▼
G2 Planetary Cells + LOD
          │
          ▼
G3 Mega Casual Surface
          │
          ▼
G4 Provider Replacement Review
          │
          ▼
G5 FeatureGraph
          │
          ▼
G6 Long River
          │
          ▼
G7 Semantic Fields
          │
          ▼
G8 Geomorphology
          │
          ▼
G9 Geology Lite
          │
          ▼
G10 GeoVolume
          │
          ▼
G11 Cave Fly-In
          │
          ▼
G12 Cache/Scheduler
          │
          ▼
G13 DetailPatch Contract
          ├───────────────┐
          ▼               ▼
G14→G16 MAIN GEO       GH0→GH6 HIGH RES
```

---

## Что доказал G0

Реализованы data-only contracts и сменный provider graph:

```text
PlanetDefinition
PlanetEnvironment
PlanetRecipe
GeoProviderDescriptor
GeoGenerationContext
GeoSurfaceQuery
GeoVolumeQuery
GeoFieldBundle
GeoSample
GeoProvider
FlatSurfaceProvider
GeoKernel
```

Ключевые свойства:

```text
same input → same sample
query order does not matter
provider order canonicalized
missing dependency rejected
duplicate output rejected
dependency cycle rejected
nondeterministic provider rejected
provider descriptor must match recipe
provider parameters are part of provenance
provider receives only declared requires[]
Surface and Volume contracts separated
Geo core has no renderer/mesh/SceneTree dependency
```

Acceptance result:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
editor import:                     PASS
G0 focused:                       PASS — 209 assertions
world/core regression:            PASS
201 / 201 discovered tests:       PASS
204 / 204 steps:                  PASS
Breakpoint :9081 collision noise: 0
```

---

## Главная парадигма

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

Истина мира — seed/recipe/provider versions/configuration, stable features и canonical persistent deltas. Mesh, collision mesh, LOD artifact, high-resolution patch и cache entry являются производными представлениями.

---

## Неизменяемые архитектурные правила

```text
Generator != Renderer
LOD != World State
Feature != Chunk
GeoKernel != planet-specific monolith
procedural baseline != persistent delta
high-resolution detail != canonical topology
provider parameters participate in provenance
providers consume only declared dependencies
```

---

## Следующее действие

Создать следующую implementation branch:

```text
feature/g1-geodesy-body-shape
```

и реализовать только геодезию/body-shape foundation — без mountains, rivers и LOD.
