# Procedural Planetary Generation Lab — индекс программы

**Program branch:** `feature/g0-procedural-planetary-generation-lab`
**Current implementation:** `feature/g1-geodesy-body-shape`
**Current state:** `G1 IMPLEMENTED CANDIDATE`

---

## С чего начинать после перерыва

1. [`STATUS_RU.md`](STATUS_RU.md) — текущее состояние и следующий gate.
2. [`../checkpoints/G1_GEODESY_BODY_SHAPE_CANDIDATE_RU.md`](../checkpoints/G1_GEODESY_BODY_SHAPE_CANDIDATE_RU.md) — текущий implementation checkpoint G1.
3. [`../checkpoints/G0_GEO_CONTRACTS_CLEANUP1_RU.md`](../checkpoints/G0_GEO_CONTRACTS_CLEANUP1_RU.md) — принятый G0 baseline.
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
   IMPLEMENTED CANDIDATE
          │
          │ full-checkout acceptance
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

```text
versioned provider graph
canonical provider ordering
same input → same sample
query-order independence
provider parameter provenance
Surface / Volume contract split
no renderer/mesh/SceneTree dependency in Geo core
full world/core regression PASS
```

G0 accepted head:

```text
7632ed576a3c0d9007c0ff1296d1d89cd43756d7
```

---

## Что добавляет G1

Canonical coordinate contracts:

```text
BodyFixedPosition
GeodeticPosition
LocalTangentFrame
```

Replaceable body-shape boundary:

```text
BodyShapeProvider
SphereBodyShapeProvider
```

Provider-neutral service:

```text
GeodesyService
├── body_to_geodetic()
├── geodetic_to_body()
├── surface_normal()
├── altitude()
└── local_tangent_frame()
```

First lab body:

```text
radius = 6_000_000 m
shape  = body-shape/sphere-v1
```

Coordinate convention:

```text
+Y              north pole
longitude 0°    +X
longitude +90°  +Z
latitude         [-90°, +90°]
longitude        [-180°, +180°)
```

At exact poles longitude is canonicalized to `0°`.

Local tangent semantics:

```text
Up    = surface normal
East  = increasing longitude tangent
North = East × Up
```

Shape identity, contract/generator versions and `PlanetDefinition.checksum` participate in `body_shape_manifest_hash`.

---

## G1 verification so far

Exact-engine isolated harness:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
cold editor import:       PASS
G1 deep smoke:            PASS — 76 assertions
```

The smoke covered equator/poles, arbitrary roundtrips, altitude, surface normals, tangent-frame orthogonality/handedness, double precision and invalid-value rejection.

G1 remains `IMPLEMENTED CANDIDATE` until the full project checkout passes:

```text
RUN_G1_FULL_ACCEPTANCE.ps1
```

---

## Главная парадигма

```text
PlanetDefinition + PlanetRecipe
              ↓
       body shape + geodesy
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

World truth is seed/recipe/provider versions/configuration, stable features and canonical persistent deltas. Mesh, collision mesh, LOD artifact, high-resolution patch and cache entry are derived representations.

---

## Неизменяемые архитектурные правила

```text
Generator != Renderer
LOD != World State
Feature != Chunk
GeoKernel != planet-specific monolith
procedural baseline != persistent delta
high-resolution detail != canonical topology
body shape != renderer mesh
body-shape identity/version participates in provenance
```

---

## Следующее действие

On the full Windows checkout:

```powershell
.\RUN_G1_FULL_ACCEPTANCE.ps1
```

After `G1 ACCEPTED`, create:

```text
feature/g2-planetary-cells-lod
```

G2 adds cube-sphere compatible addressing, quadtree parent/children, neighbors, LOD selection/hysteresis and cell lifecycle without changing G1 geodesy semantics.
