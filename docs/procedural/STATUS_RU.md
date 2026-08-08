# Procedural Planetary Generation — status ledger

**Program branch:** `feature/g0-procedural-planetary-generation-lab`  
**Current implementation branch:** `feature/g0-geo-contracts`  
**Purpose:** единая точка фиксации прогресса программы.

---

## Текущее состояние

```text
PROGRAM: Procedural Planetary Generation Fabric
STATE: G0 IMPLEMENTED CANDIDATE
PRODUCTION RUNTIME CHANGED: NO
PRODUCTION TERRAIN CHANGED: NO
CURRENT GATE: G0 — Contracts freeze v0
NEXT GATE AFTER ACCEPTANCE: G1 — Geodesy + Body Shape
```

G0 реализован как data-only/headless foundation. На этом этапе намеренно отсутствуют sphere mesh, geodesy, LOD, mountains, rivers, caves и production-world integration.

---

## G0 — implementation record

```text
stage:                  G0 — Contracts freeze v0
branch:                 feature/g0-geo-contracts
program base branch:    feature/g0-procedural-planetary-generation-lab
candidate state:        IMPLEMENTED CANDIDATE
production worlds:      unchanged
production terrain:     unchanged
renderer dependency:    none
SceneTree dependency:   none in Geo core
network dependency:     none in Geo semantics
```

Реализованы:

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
GeoProvider base contract
FlatSurfaceProvider
GeoKernel
```

`GeoProviderDescriptor` фиксирует не только provider/version/requires/provides, но и canonical JSON-safe `parameters`. Поэтому изменение параметров генератора меняет descriptor hash/provider manifest и не может незаметно создать другой procedural baseline под той же provenance.

`GeoKernel`:

- валидирует PlanetDefinition и PlanetRecipe до generation;
- требует точного соответствия runtime provider descriptor recipe descriptor;
- отклоняет missing/undeclared/duplicate provider implementations;
- отклоняет missing dependencies;
- отклоняет duplicate semantic outputs;
- отклоняет dependency cycles;
- отклоняет nondeterministic providers;
- строит deterministic lexical topological order;
- вычисляет provider manifest hash;
- запускает только providers, необходимые для requested fields;
- передаёт provider только объявленные `requires[]`, исключая hidden dependencies;
- проверяет exact provider output contract;
- сохраняет field provenance в GeoSample;
- разделяет Surface и Volume query kinds уже в G0.

---

## G0 validation evidence

Проверено на exact engine:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
```

Локальный изолированный harness содержал G0 source tree и необходимые существующие contract dependencies.

Результат:

```text
headless editor import: PASS
focused G0:            PASS — 209 assertions
source hygiene:        PASS — 15 GDScript files
NaN/INF rejection:     PASS
checksum mutation:     PASS
query order independence: PASS
provider replacement:  PASS
provider parameter provenance: PASS
missing dependency:    rejected
output collision:      rejected
dependency cycle:      rejected
nondeterministic provider: rejected
surface/volume boundary: enforced
renderer/Node/RNG source markers in Geo core: absent
```

Focused runners:

```text
RUN_G0_GEO_CONTRACTS_TESTS.ps1
RUN_G0_GEO_CONTRACTS_TESTS.sh
```

Standalone acceptance script intentionally называется:

```text
tests/procedural/contracts/g0_geo_contracts_acceptance.gd
```

а не `test_*.gd`, чтобы implementation candidate не ломал strict coverage manifest существующего `RUN_WORLD_REGRESSION_TESTS.ps1` до формальной регистрации G0 в общей regression suite.

### Что ещё требуется для `G0 ACCEPTED`

На полном рабочем checkout проекта:

```text
1. editor import/parse
2. RUN_G0_GEO_CONTRACTS_TESTS.ps1
3. существующие world/core regression suites
4. git diff --check
5. проверить отсутствие production-world changes
6. после PASS зарегистрировать G0 acceptance evidence
```

До этой внешней проверки решение остаётся `IMPLEMENTED CANDIDATE`, а не `ACCEPTED`.

---

## Канонический порядок программы

```text
G0  Contracts freeze v0                     IMPLEMENTED CANDIDATE
G1  Geodesy + Body Shape                     BLOCKED BY G0 ACCEPTANCE
G2  Planetary Surface Cells + LOD            BLOCKED BY G1
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

После `G13 ACCEPTED` параллельно:

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

## Следующая ветка после G0 acceptance

```text
feature/g1-geodesy-body-shape
```

G1 должен добавить только:

```text
IBodyShapeProvider
SphereBodyShapeProvider
BodyFixedPosition
GeodeticPosition
LocalTangentFrame
GeodesyService
```

и доказать body/geodetic roundtrip, altitude, surface normal и tangent frame на double-precision координатах.

G1 не должен добавлять mountains, river generation или planetary LOD.

---

## Архитектурные инварианты

Без отдельного ADR запрещено нарушать:

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
```

При закрытии каждого следующего gate этот ledger обновляется первым.