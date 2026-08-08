# Procedural Planetary Generation — status ledger

**Program branch:** `feature/g0-procedural-planetary-generation-lab`
**Current implementation branch:** `feature/g1-geodesy-body-shape`
**Purpose:** единая точка фиксации прогресса программы.

---

## Текущее состояние

```text
PROGRAM: Procedural Planetary Generation Fabric
G0: ACCEPTED
G1: IMPLEMENTED CANDIDATE
G1 ISOLATED EXACT-ENGINE SMOKE: PASS — 76 assertions
PRODUCTION RUNTIME CHANGED: NO
PRODUCTION TERRAIN CHANGED: NO
CURRENT GATE: G1 full-checkout acceptance
NEXT AFTER G1 ACCEPTED: G2 — Planetary Surface Cells + LOD
```

G1 добавляет только canonical body/geodetic coordinates, сменный body-shape provider и geodesy service. Planetary LOD, terrain generation, mountains, rivers, caves и production-world integration намеренно отсутствуют.

---

## G0 — accepted foundation

```text
stage:                  G0 — Contracts freeze v0
branch:                 feature/g0-geo-contracts
accepted head:          7632ed576a3c0d9007c0ff1296d1d89cd43756d7
program base branch:    feature/g0-procedural-planetary-generation-lab
decision:               ACCEPTED
production worlds:      unchanged
production terrain:     unchanged
renderer dependency:    none
SceneTree dependency:   none in Geo core
network dependency:     none in Geo semantics
```

G0 provides:

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

Acceptance evidence:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
G0 focused:                       PASS — 209 assertions
world/core regression:            PASS
201 / 201 discovered tests:       PASS
204 / 204 steps:                  PASS
Breakpoint :9081 collision noise: 0
```

---

## G1 — implementation record

```text
stage:                  G1 — Geodesy + Body Shape
branch:                 feature/g1-geodesy-body-shape
base:                   feature/g0-geo-contracts
base commit:            7632ed576a3c0d9007c0ff1296d1d89cd43756d7
decision:               IMPLEMENTED CANDIDATE
production worlds:      unchanged
production terrain:     unchanged
renderer dependency:    none
SceneTree dependency:   none in production G1 code
network dependency:     none in geodesy semantics
nominal lab radius:     6_000_000 m
body shape:             body-shape/sphere-v1
```

Implemented contracts/services:

```text
BodyFixedPosition
GeodeticPosition
LocalTangentFrame
BodyShapeProvider
SphereBodyShapeProvider
GeodesyService
```

Operations:

```text
body_to_geodetic()
geodetic_to_body()
surface_normal()
altitude()
local_tangent_frame()
```

Coordinate convention:

```text
+Y              north pole
longitude 0°    +X
longitude +90°  +Z
latitude         [-90°, +90°]
longitude        [-180°, +180°)
exact poles      longitude canonicalized to 0°
```

Local tangent semantics:

```text
Up      = body-shape surface normal
East    = increasing longitude tangent
North   = East × Up
```

`LocalTangentFrame` validates unit axes, orthogonality and `E × U = N` handedness.

---

## G1 architectural decisions

`GeodesyService` is provider-neutral. It does not own sphere radius math and does not know renderer, LOD, network or SceneTree state.

`SphereBodyShapeProvider` is the first concrete shape provider. Binding is explicit through:

```text
PlanetDefinition.body_shape_id
provider shape_id
provider contract_version
provider generator_version
PlanetDefinition.checksum
```

These values form `body_shape_manifest_hash`, so changing shape implementation/version or planet definition cannot silently reuse the same provenance.

Canonical serialized DTOs remain JSON-safe arrays/numbers. Internal math uses double-precision `Vector3` from the custom Godot double build.

G1 intentionally does not modify `GeoKernel`; body shape/geodesy is a lower coordinate foundation that future G2 surface addressing consumes.

---

## G1 isolated validation evidence

A minimal headless harness was assembled from the production G1 scripts plus the accepted G0 contract dependencies and run on the exact engine binary:

```text
Godot Engine v4.7.1.stable.double.custom_build.a13da4feb
cold editor import:       PASS
G1 deep geodesy smoke:    PASS — 76 assertions
```

Verified in the isolated run:

```text
equator roundtrip
north/south pole roundtrip
arbitrary lat/lon/alt roundtrips
negative and positive altitude
sub-meter double precision
unit surface normal
stable tangent basis
orthogonality
E × U = N handedness
NaN/INF rejection
center-of-body rejection
```

The first isolated compile found and fixed one real GDScript issue before handoff: duplicate inherited `GeoUtilsScript` declaration in `SphereBodyShapeProvider`.

This evidence validates the new production code in isolation, but does not replace the full project regression.

---

## G1 full acceptance gate

Focused runners:

```text
RUN_G1_GEODESY_TESTS.ps1
RUN_G1_GEODESY_TESTS.sh
```

Full Windows gate:

```text
RUN_G1_FULL_ACCEPTANCE.ps1
```

Required final evidence:

```text
headless editor import:                 PASS
G1 focused acceptance:                 PASS
existing world/core regression:        PASS
Breakpoint runtime :9081 collision:    0
git diff --check vs G0:                PASS
```

Until this full-checkout run completes, G1 remains `IMPLEMENTED CANDIDATE`.

---

## Expected existing regression noise

As established during G0, some existing logs intentionally exercise error paths:

```text
World manifest identity mismatch (...)
CONFLICTING_REMOTE_SNAPSHOT_TICK
STALE_REMOTE_AUTHORITY_EPOCH
```

Those messages are not G1 failures when their suites finish PASS. MW7 ObjectDB/ResourceCache exit warnings also remain separate cleanup debt.

---

## Канонический порядок программы

```text
G0  Contracts freeze v0                     ACCEPTED
G1  Geodesy + Body Shape                     IMPLEMENTED CANDIDATE
G2  Planetary Surface Cells + LOD            BLOCKED BY G1 ACCEPTANCE
G3  Mega Casual Macro Surface                BLOCKED BY G2
G4  Provider Composition / Replacement       BLOCKED BY G3
G5  WorldFeature + FeatureGraph              BLOCKED BY G4
G6  Mega Casual River                        BLOCKED BY G5
G7  Semantic Geo Fields                      BLOCKED BY G6
G8  Casual Geomorphology                     BLOCKED BY G7
G9  Geology Lite                             BLOCKED BY G8
G10 GeoVolume Contract                       BLOCKED BY G9
G11 Mega Casual Cave                         BLOCKED BY G10
G12 Cache + Generation Scheduler             BLOCKED BY G11
G13 Progressive Detail Contract Freeze       BLOCKED BY G12
G14 Simple Detail Generator                  BLOCKED BY G13
G15 Multiple PlanetRecipe Acceptance         BLOCKED BY G14
G16 Generator Substitution Acceptance        BLOCKED BY G15
```

After `G13 ACCEPTED` the parallel high-resolution track opens:

```text
GH0 Contract + Fixture Harness
→ GH1 Structural 100 m Patch
→ GH2 Decimeter Physical Detail
→ GH3 Material Micro Detail
→ GH4 Volumetric Refinement Adapter
→ GH5 Performance Budgets
→ GH6 Main Geo Composition
```

Future integration:

```text
G17 Matter Bridge
G18 Representation LOD Integration
G19 Network Manifest Integration
```

---

## Следующее действие

On a full Windows checkout of `feature/g1-geodesy-body-shape`:

```powershell
.\RUN_G1_FULL_ACCEPTANCE.ps1
```

If it passes, record `G1 ACCEPTED` and create:

```text
feature/g2-planetary-cells-lod
```

G2 must add addressing/quadtree/LOD lifecycle without changing the canonical geodesy semantics frozen in G1.

---

## Архитектурные инварианты

Without a separate ADR it is forbidden to violate:

```text
Generator != Renderer
LOD != World State
Feature != Chunk
GeoKernel != planet-specific monolith
High-resolution detail != canonical topology
procedural baseline != persistent delta
renderer/cache artifact != canonical world state
network transport != generation semantics
provider parameters must be part of provenance
providers may consume only declared semantic dependencies
body-shape identity/version must participate in geodesy provenance
```

---

## Документы программы

```text
docs/procedural/README_RU.md
docs/procedural/STATUS_RU.md

docs/architecture/PROCEDURAL_PLANETARY_GENERATION_FABRIC_RU.md
docs/architecture/HIGH_RESOLUTION_DETAIL_GENERATOR_RU.md
docs/architecture/adr/ADR-019-procedural-planetary-generation-fabric.md

docs/plans/PROCEDURAL_PLANETARY_GENERATION_ROADMAP_RU.md
docs/plans/PROCEDURAL_PLANETARY_GENERATION_EXECUTION_PLAN_RU.md

docs/validation/PROCEDURAL_PLANET_LAB_ACCEPTANCE_RU.md

docs/checkpoints/G0_GEO_CONTRACTS_CANDIDATE_RU.md
docs/checkpoints/G0_GEO_CONTRACTS_CLEANUP1_RU.md
docs/checkpoints/G1_GEODESY_BODY_SHAPE_CANDIDATE_RU.md
```
