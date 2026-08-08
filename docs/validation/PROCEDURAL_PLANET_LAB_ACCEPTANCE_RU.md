# Procedural Planet Lab — acceptance gates и наблюдаемость

**Ветка:** `feature/g0-procedural-planetary-generation-lab`.
**Roadmap:** `docs/plans/PROCEDURAL_PLANETARY_GENERATION_ROADMAP_RU.md`.
**Назначение:** сделать каждый ранний этап проверяемым независимо от визуального качества и не позволить красивому результату скрыть нарушение детерминизма, LOD или provider boundaries.

---

## 1. Главный acceptance principle

Ранний procedural prototype принимается не по красоте.

Приоритет:

```text
correct contracts
→ deterministic world
→ stable geodesy
→ stable feature identity
→ continuous cross-cell fields
→ LOD semantic stability
→ replaceability
→ visual quality
```

Если terrain выглядит красиво, но меняется при другом порядке загрузки cells, stage считается FAIL.

---

## 2. Обязательные debug modes

Lab должен предоставить наблюдаемость минимум для:

```text
NORMAL
SURFACE_CELLS
LOD_LEVEL
PROVIDER_OUTPUT
FEATURE_IDS
FEATURE_BOUNDS
RIVER_DISTANCE
FLOW
CURVATURE
EROSION
DEPOSITION
GEOLOGY
SURFACE_NORMAL
VOLUME/SDF
DETAIL_LEVEL
DETAIL_BUDGET
CACHE_STATE
```

Конкретные hotkeys не являются контрактом; список режимов — является.

---

## 3. Универсальные automated invariants

Эти тесты запускаются на каждом G-stage, где применимы.

### Determinism

```text
same body seed
same recipe manifest
same coordinate
same context
→ same canonical sample
```

### Order independence

Сравнить результаты:

```text
A → B → C
C → A → B
B → C → A
```

### Observer independence

Перемещение spectator/camera не меняет canonical sample/feature identity.

### Serialization stability

Versioned descriptors и fixtures имеют canonical JSON/hash representation.

### Invalid input rejection

Reject:

```text
NaN/INF
invalid ids
unknown provider version
missing dependency
invalid bounds
negative target resolution
impossible body identity
```

### Cross-cell continuity

Для shared border sampling соседние cells получают согласованные canonical positions/fields.

### LOD semantic compatibility

Coarse и fine representations могут иметь разную geometric error, но high-level feature classification/identity на общей точке не конфликтует.

### No presentation dependency

Headless query tests проходят без material/mesh/renderer setup.

---

## 4. G0 gate — Contracts

```text
[PASS] FlatSurfaceProvider registers
[PASS] provider graph validates
[PASS] missing `requires` rejected
[PASS] incompatible contract version rejected
[PASS] duplicate provider output ownership handled explicitly
[PASS] no SceneTree requirement for canonical sample
```

---

## 5. G1 gate — Geodesy

Test points:

```text
equator
north/south high latitude
near poles
several body-fixed directions
altitude 0
altitude positive
altitude below nominal surface where valid
```

Checks:

```text
roundtrip error bounded
surface normal normalized
local tangent frame orthogonal/right-handed
no discontinuity under small coordinate movement
```

Visual:

fly-in to a smooth sphere without visible transform jitter.

---

## 6. G2 gate — Cells/LOD

Stress route:

```text
50 km altitude
→ fast descent
→ ground pass
→ climb
→ lateral high-speed pass across cell boundaries
→ return to start
```

Checks:

```text
no missing cells in required set
no permanent duplicate active cells
stable cell ids
hysteresis prevents rapid thrash
unload eventually releases inactive representation
```

---

## 7. G3/G4 gate — Casual surface/provider swapping

Golden sampling fixture:

```text
128–1024 deterministic body-fixed sample points
```

Record semantic surface heights/normals for exact generator version.

Provider swap test:

```text
Recipe A → CasualMacroTerrainV1
Recipe B → AlternativeMacroTerrainV1
```

Both use identical GeoKernel caller and renderer adapter.

---

## 8. G5/G6 gate — Feature world and river

For one RiverFeature:

```text
length ~40 km
crosses many cells
```

Checks:

```text
stable feature_id
same centerline independent of queried cell order
same width/depth function at shared coordinates
no cell-local reroll
bounds cover all represented segments
water presentation follows same semantic feature
```

Visual route must follow the river across several cell boundaries.

---

## 9. G7/G8 gate — Fields and geomorphology

At selected bend fixtures record:

```text
curvature
erosion
deposition
cliff candidate
shoal candidate
island candidate
```

Debug view must allow answering:

> Почему здесь появилась скала/отмель/остров?

Если feature нельзя объяснить входными fields и stable rule, система считается слишком непрозрачной.

---

## 10. G9 gate — Geology Lite

Run the same RiverFeature against:

```text
soft geology profile
hard geology profile
```

Expected:

```text
river feature identity unchanged
bank/geomorphology response changes
```

This proves provider decoupling.

---

## 11. G10/G11 gate — Volume and cave

Sample matrix around cave entrance/interior:

```text
outside air
solid cliff
entrance boundary
inside cavity
below floor
above roof
```

Checks:

```text
stable signed-distance/material semantics
surface and volume do not contradict at entrance beyond allowed epsilon
cave is present after reload
cave exists without mesh generation
```

Visual acceptance:

```text
approach cliff
→ enter cave
→ leave cave
```

without world/scene teleport.

---

## 12. G12 gate — Cache

For one route:

```text
first visit
leave beyond active range
return
```

Record:

```text
generation calls
cache hits
cache misses
artifact rebuilds
peak cached bytes
```

Cache hit may change latency but not output hash.

Change provider version and verify stale cache is not reused.

---

## 13. G13/G14 gate — Detail

Recorded `DetailPatchContext` must be runnable standalone.

Checks:

```text
same fixture → same artifact semantic hash
higher detail adds detail without moving stable coarse anchors
neighbor patches agree on border ownership
turning detail backend off does not change macro feature/sample identity
```

---

## 14. G15/G16 gate — Planet recipes and substitution

Run a minimal matrix:

```text
CasualEarthlikeRecipe
DryRockyRecipe
```

Then swap at least one provider in each semantic category implemented so far.

Core source should contain no planet-name special cases.

Recommended static/source-contract test searches forbidden direct references from GeoKernel core to recipe-specific classes.

---

## 15. Performance telemetry from day one

Even before optimization record:

```text
canonical query count/frame
canonical query time
cell generation time
feature query time
volume query time
detail generation time
cache hit/miss
mesh build time
main-thread commit time
active cell count
artifact bytes
```

Initial stages have no hard FPS target, but catastrophic scaling must be visible.

---

## 16. Golden fixtures and versioning

Golden fixtures are allowed only for exact generator versions.

Changing intended algorithm output requires:

```text
new generator_version
new golden fixture
migration/provenance note if persistent deltas already exist
```

Нельзя silently менять output под старым generator version.

---

## 17. Первый сквозной acceptance scenario

### River Valley Fly-In

1. Launch `procedural_planet_lab` with fixed seed.
2. Start spectator around 30–50 km altitude.
3. Confirm macro valley/river alignment.
4. Descend through several LOD levels.
5. Follow river across multiple surface cells.
6. Observe at least one generated island/shoal and cliff.
7. Land/approach the cliff.
8. Confirm near detail refinement.
9. Enter generated cave.
10. Exit and climb back to regional view.
11. Return to same location and compare feature ids/hashes.

Acceptance:

```text
[PASS] no semantic feature swap
[PASS] no cross-cell river break
[PASS] no coordinate instability
[PASS] no cave teleport
[PASS] same fixed-seed feature identity after revisit
[PASS] detail can be disabled independently
```

---

## 18. Red flags that block progression

Stop next-stage work if detected:

```text
feature generation depends on chunk load order
camera position changes canonical terrain
LOD changes semantic geography
provider replacement requires renderer rewrite
core knows concrete planet types
cave exists only as scene decoration, not volume query
high-resolution backend changes gameplay topology only on some quality tiers
cache omits generator/dependency version from key
neighbor cells independently roll boundary features
```

These are architecture bugs, not polish debt.
