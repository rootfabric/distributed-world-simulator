# Procedural Planetary Generation Lab — индекс программы

**Program branch:** `feature/g0-procedural-planetary-generation-lab`  
**Current implementation:** `feature/g0-geo-contracts`  
**Current state:** `G0 IMPLEMENTED CANDIDATE`

---

## С чего начинать после перерыва

1. [`STATUS_RU.md`](STATUS_RU.md) — текущее состояние и следующий gate.
2. [`../checkpoints/G0_GEO_CONTRACTS_CANDIDATE_RU.md`](../checkpoints/G0_GEO_CONTRACTS_CANDIDATE_RU.md) — что именно реализовано в G0 и как проверено.
3. [`../plans/PROCEDURAL_PLANETARY_GENERATION_EXECUTION_PLAN_RU.md`](../plans/PROCEDURAL_PLANETARY_GENERATION_EXECUTION_PLAN_RU.md) — практический порядок G0–G19.
4. [`../architecture/PROCEDURAL_PLANETARY_GENERATION_FABRIC_RU.md`](../architecture/PROCEDURAL_PLANETARY_GENERATION_FABRIC_RU.md) — общая архитектурная доктрина.
5. [`../validation/PROCEDURAL_PLANET_LAB_ACCEPTANCE_RU.md`](../validation/PROCEDURAL_PLANET_LAB_ACCEPTANCE_RU.md) — сквозные acceptance invariants.
6. [`../architecture/HIGH_RESOLUTION_DETAIL_GENERATOR_RU.md`](../architecture/HIGH_RESOLUTION_DETAIL_GENERATOR_RU.md) — будущий параллельный high-resolution track.

---

## Где мы сейчас

```text
G0 Contracts Freeze v0
    IMPLEMENTED CANDIDATE
          │
          │ full-checkout acceptance required
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

## Что уже доказал G0

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

Exact-engine focused result:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
editor import: PASS
G0 focused:   PASS — 209 assertions
hygiene:      PASS
```

G0 остаётся `IMPLEMENTED CANDIDATE`, пока не пройдёт полная regression композиция на полном checkout.

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

Сначала независимо принять G0 на полном checkout:

```text
RUN_G0_GEO_CONTRACTS_TESTS.ps1
existing world/core regression
git diff --check
```

После `G0 ACCEPTED` создать:

```text
feature/g1-geodesy-body-shape
```

и реализовать только геодезию/body-shape foundation — без mountains, rivers и LOD.