# Procedural Planetary Generation — status ledger

**Program branch:** `feature/g0-procedural-planetary-generation-lab`
**Current implementation branch:** `feature/g0-geo-contracts`
**Purpose:** единая точка фиксации прогресса программы.

---

## Текущее состояние

```text
PROGRAM: Procedural Planetary Generation Fabric
G0 CORE: ACCEPTED
G0 CLEANUP1: ACCEPTED
PRODUCTION RUNTIME CHANGED: NO
PRODUCTION TERRAIN CHANGED: NO
NEXT GATE: G1 — Geodesy + Body Shape
```

G0 реализован как data-only/headless foundation. На этом этапе намеренно отсутствуют sphere mesh, geodesy, LOD, mountains, rivers, caves и production-world integration.

---

## G0 — implementation record

```text
stage:                  G0 — Contracts freeze v0
branch:                 feature/g0-geo-contracts
program base branch:    feature/g0-procedural-planetary-generation-lab
core candidate head:    6bc49940fa6d762690d0e5a4ea4261a72c24310b
clean-wrapper evidence: 388c680085d4cb30c75020906790c9c0d642fb0a
core decision:          ACCEPTED
cleanup1 decision:      ACCEPTED
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

`GeoProviderDescriptor` фиксирует provider/version/requires/provides и canonical JSON-safe `parameters`. Изменение параметров генератора меняет descriptor/provider-manifest hash и не может незаметно создать другой procedural baseline под той же provenance.

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
- передаёт provider только объявленные `requires[]`;
- проверяет exact provider output contract;
- сохраняет field provenance в GeoSample;
- разделяет Surface и Volume query kinds уже в G0.

---

## G0 validation evidence

Exact engine:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
```

Focused evidence:

```text
headless editor import:          PASS
focused G0:                     PASS — 209 assertions
source hygiene:                 PASS — 15 GDScript files
query order independence:       PASS
provider replacement:           PASS
provider parameter provenance:  PASS
surface/volume boundary:        enforced
```

Полный Windows regression на реальном checkout:

```text
world-regression-summary.json
passed:                 true
declared_test_count:    201
discovered_test_count:  201
steps:                  204
failed steps:           0
```

Clean-wrapper rerun подтвердил:

```text
world/core regression:                 PASS
Breakpoint runtime :9081 collision:    0
functional regression failures:        0
```

Первый `git diff --check` после clean-wrapper обнаружил только trailing whitespace в четырёх Markdown-файлах. Он исправлен documentation-only patch; runtime/code после успешного regression не менялся.

---

## G0 cleanup1 — acceptance output hygiene

Причина исходного шума:

```text
17 x
ERROR: [breakpoint_runtime] could not listen on 127.0.0.1:9081 (error 22)
```

Multi-process child Godot instances одновременно пытались поднять `BreakpointRuntimeBridge` на одном fixed loopback port.

Сам addon уже имеет штатный switch:

```text
BREAKPOINT_RUNTIME_DISABLED=1
```

Поэтому cleanup1 не меняет addon или production runtime.

Изменения:

```text
RUN_G0_GEO_CONTRACTS_TESTS.ps1
  + temporary BREAKPOINT_RUNTIME_DISABLED=1
  + automatic cold editor import
  + environment restore

RUN_G0_GEO_CONTRACTS_TESTS.sh
  + same behavior for Linux

RUN_G0_FULL_ACCEPTANCE.ps1
  + focused G0
  + full world/core regression in child PowerShell
  + inherited BREAKPOINT_RUNTIME_DISABLED=1
  + current-run log scan requiring zero :9081 collision errors
  + git diff --check
```

Cleanup checkpoint:

```text
docs/checkpoints/G0_GEO_CONTRACTS_CLEANUP1_RU.md
```

---

## Expected negative-path output

Некоторые ERROR/WARNING строки в полном output являются частью намеренно проверяемых failure paths. Например:

```text
World manifest identity mismatch (...)
CONFLICTING_REMOTE_SNAPSHOT_TICK
STALE_REMOTE_AUTHORITY_EPOCH
```

Соответствующие suites завершились `PASS`.

MW7 также печатает существующие ObjectDB/ResourceCache exit warnings. Это отдельный технический долг и не является G0 regression failure.

---

## Канонический порядок программы

```text
G0  Contracts freeze v0                     ACCEPTED
G1  Geodesy + Body Shape                     NEXT
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

## Следующая ветка

```text
feature/g1-geodesy-body-shape
```

G1 добавляет только:

```text
IBodyShapeProvider
SphereBodyShapeProvider
BodyFixedPosition
GeodeticPosition
LocalTangentFrame
GeodesyService
```

и доказывает body/geodetic roundtrip, altitude, surface normal и tangent frame на double-precision координатах.

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

docs/checkpoints/G0_GEO_CONTRACTS_CANDIDATE_RU.md
docs/checkpoints/G0_GEO_CONTRACTS_CLEANUP1_RU.md
```

При закрытии каждого следующего gate этот ledger обновляется первым.
