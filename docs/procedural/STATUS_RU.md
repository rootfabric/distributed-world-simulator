# Procedural Planetary Generation — status ledger

**Program branch:** `feature/g0-procedural-planetary-generation-lab`  
**Purpose:** единая точка фиксации прогресса, чтобы не потерять текущее состояние программы.

---

## Текущее состояние

```text
PROGRAM: Procedural Planetary Generation Fabric
STATE: ARCHITECTURE / PLANNING FIXED
PRODUCTION RUNTIME CHANGED: NO
IMPLEMENTATION STARTED: NO
CURRENT NEXT GATE: G0 — Contracts freeze v0
```

Архитектура, roadmap, execution plan, HR doctrine и acceptance зафиксированы. Следующее практическое действие — реализация G0 отдельной короткой веткой.

---

## Канонический порядок первой программы

```text
G0  Contracts freeze v0
G1  Geodesy + Body Shape
G2  Planetary Surface Cells + LOD
G3  Mega Casual Macro Surface
G4  Provider Composition / Replacement
G5  WorldFeature + FeatureGraph
G6  Mega Casual River
G7  Semantic Geo Fields
G8  Casual Geomorphology
G9  Geology Lite
G10 GeoVolume Contract
G11 Mega Casual Cave
G12 Cache + Generation Scheduler Boundaries
G13 Progressive Detail Contract Freeze
G14 Simple Detail Generator
G15 Multiple PlanetRecipe Acceptance
G16 Generator Substitution Acceptance
```

После G13 параллельно:

```text
GH0 Contract + Fixture Harness
GH1 Structural 100 m Patch
GH2 Decimeter Physical Detail
GH3 Material Micro Detail
GH4 Volumetric Refinement Adapter
GH5 Performance Budgets
GH6 Main Geo Composition
```

Future integration, не часть первого прототипа:

```text
G17 Matter Bridge
G18 Representation LOD Integration
G19 Network Manifest Integration
```

---

## Gate status

| Gate | Status | Meaning |
|---|---|---|
| G0 | PLANNED / NEXT | contracts, provider graph, FlatSurfaceProvider |
| G1 | BLOCKED BY G0 | sphere, geodesy, tangent frame |
| G2 | BLOCKED BY G1 | cube-sphere cells, LOD lifecycle |
| G3 | BLOCKED BY G2 | primitive macro hills |
| G4 | BLOCKED BY G3 | provider composition/replacement proof |
| G5 | BLOCKED BY G4 | FeatureGraph + ValleyFeature |
| G6 | BLOCKED BY G5 | ~40 km RiverFeature |
| G7 | BLOCKED BY G6 | semantic fields + debug overlays |
| G8 | BLOCKED BY G7 | cliffs/islands/shoals/banks |
| G9 | BLOCKED BY G8 | geology lite |
| G10 | BLOCKED BY G9 | GeoVolume independent of mesh |
| G11 | BLOCKED BY G10 | enterable casual cave |
| G12 | BLOCKED BY G11 | cache + scheduler boundaries |
| G13 | BLOCKED BY G12 | DetailPatch contracts + recorded fixtures |
| G14 | BLOCKED BY G13 | simple reference detail backend |
| G15 | BLOCKED BY G14 | multiple planet recipes |
| G16 | BLOCKED BY G15 | substitution acceptance |
| GH0 | BLOCKED BY G13 | standalone HR fixture harness |
| GH1 | BLOCKED BY GH0 | structural 100 m detail |
| GH2 | BLOCKED BY GH1 | decimeter physical detail |
| GH3 | BLOCKED BY GH1 | material micro detail; may overlap GH2 |
| GH4 | BLOCKED BY G10+GH1 | explicit derived-vs-canonical volume boundary |
| GH5 | BLOCKED BY GH1 | profiling/performance budgets |
| GH6 | BLOCKED BY G14+GH0 | integration through IDetailProvider |
| G17 | FUTURE | procedural baseline + persistent Matter delta |
| G18 | FUTURE | Representation LOD composition |
| G19 | FUTURE | network manifest/provenance integration |

---

## Следующая ветка

Рекомендуемая следующая реализационная ветка:

```text
feature/g0-geo-contracts
```

Она реализует только G0. Не добавлять terrain visuals, реки или пещеры в G0.

---

## Ближайшая серия работ

### SERIES A — FOUNDATION

```text
G0 → G1 → G2 → G3 → G4
```

После G4: architecture review. Проверить provider neutrality, renderer independence, LOD/world-state separation.

### SERIES B — RIVER WORLD

```text
G5 → G6 → G7 → G8 → G9
```

После G9: первый river-valley fly-in review.

### SERIES C — VOLUME + DETAIL CONTRACT

```text
G10 → G11 → G12 → G13
```

После G13: открыть `feature/gh0-high-resolution-detail-generator`.

### SERIES D — PARALLEL

```text
MAIN GEO                         HIGH RESOLUTION
G14 Simple Detail               GH0 Fixture Harness
G15 Planet Recipes              GH1 Structural Patch
G16 Substitution Acceptance     GH2 Physical Detail
                                 GH3 Material Micro Detail
                                 GH4 Volume Refinement Adapter
                                 GH5 Performance Budgets
                                 GH6 Main Composition
```

---

## Основные milestones

### Milestone A — G4

Архитектурный kernel доказан:

```text
sphere/geodesy
+ planetary cells/LOD
+ casual surface
+ provider replacement
```

### Milestone B — G9

Первый интересный procedural landscape:

```text
fly from altitude
→ recognize same valley
→ follow ~40 km river
→ see islands/shoals
→ see cliffs
→ see geology influence bank form
```

### Milestone C — G11

Мир перестаёт быть heightfield-only:

```text
land near cliff
→ approach cave entrance
→ enter procedural GeoVolume cave
```

### Milestone D — G13

Главный engineering fork:

```text
stable DetailPatchContext
+ fixtures
→ independent HR development becomes possible
```

### Milestone E — G16

Первая procedural generation program архитектурно завершена: несколько recipes и generators заменяются без ветвления core.

### Milestone HR — GH6

High-resolution backend подключён через тот же detail contract без изменения GeoKernel.

---

## Обязательная запись при закрытии каждого gate

После каждого G/GH этапа обновить этот файл и зафиксировать:

```text
stage
branch
base commit
implementation commit
checkpoint/tag when applicable
validation command(s)
assertion/test result
visual acceptance result
known debt
next gate
decision: CANDIDATE / ACCEPTED / REJECTED
```

Нельзя считать stage завершённым только потому, что визуально «работает».

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
```

---

## Текущие документы программы

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

---

## Правило продолжения работы

Если спустя время непонятно, что делать дальше:

1. открыть этот файл;
2. найти первый gate со статусом `PLANNED / NEXT`;
3. прочитать соответствующую секцию execution plan;
4. сверить архитектурные invariants и acceptance;
5. создать короткую implementation branch;
6. после проверки обновить этот ledger.
