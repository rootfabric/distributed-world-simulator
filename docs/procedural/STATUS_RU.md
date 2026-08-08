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

Архитектура и roadmap зафиксированы. Следующее практическое действие — реализация G0 отдельной короткой веткой.

---

## Канонический порядок

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
G12 Progressive Detail Hierarchy
G13 DetailPatchContext Freeze
    ├─ MAIN PLANET TRACK continues
    └─ HIGH-RESOLUTION DETAIL TRACK starts
G14 Detail Budget + Cache
G15 PlanetRecipe Profiles
G16 Generator Substitution Acceptance
```

High-resolution track after G13:

```text
GH0 Fixture Harness
GH1 Structural Detail
GH2 Physical Near Detail
GH3 Micro Visual Detail
GH4 Promotion Boundary
GH5 Determinism / Nested Refinement
GH6 Performance Budgets
GH7 Mainline Integration
```

---

## Gate status

| Gate | Status | Meaning |
|---|---|---|
| G0 | PLANNED / NEXT | contracts, provider graph, FlatSurfaceProvider |
| G1 | BLOCKED BY G0 | sphere, geodesy, tangent frame |
| G2 | BLOCKED BY G1 | cube-sphere cells, LOD lifecycle |
| G3 | BLOCKED BY G2 | primitive macro hills |
| G4 | BLOCKED BY G3 | replaceable provider proof |
| G5 | BLOCKED BY G4 | FeatureGraph + ValleyFeature |
| G6 | BLOCKED BY G5 | ~40 km RiverFeature |
| G7 | BLOCKED BY G6 | semantic fields |
| G8 | BLOCKED BY G7 | cliffs/islands/shoals |
| G9 | BLOCKED BY G8 | geology lite |
| G10 | BLOCKED BY G9 | GeoVolume |
| G11 | BLOCKED BY G10 | enterable casual cave |
| G12 | BLOCKED BY G11 | progressive detail tiers |
| G13 | BLOCKED BY G12 | DetailPatchContext + fixtures |
| G14 | BLOCKED BY G13 | budgets/cache |
| G15 | BLOCKED BY G14 | multiple planet recipes |
| G16 | BLOCKED BY G15 | generator substitution acceptance |
| GH0 | BLOCKED BY G13 | standalone HR fixture harness |
| GH1 | BLOCKED BY GH0 | structural detail |
| GH2 | BLOCKED BY GH1 | physical near detail |
| GH3 | BLOCKED BY GH1 | micro visual detail; may overlap GH2 |
| GH4 | BLOCKED BY G10+GH1 | topology promotion boundary |
| GH5 | BLOCKED BY GH1 | nested deterministic refinement |
| GH6 | BLOCKED BY GH1 | profiling and budgets |
| GH7 | BLOCKED BY G14+GH5 | integration as DetailProvider backend |

---

## Следующая ветка

Рекомендуемая следующая реализационная ветка:

```text
feature/g0-geo-contracts
```

Она должна реализовать только G0 и не начинать terrain visuals.

---

## Обязательный checkpoint для каждого gate

При закрытии любого G/GH этапа обновить этот файл и зафиксировать:

```text
stage
branch
base commit
checkpoint/tag when applicable
implementation commit
validation command(s)
assertion/test result
known debt
next gate
decision: CANDIDATE / ACCEPTED / REJECTED
```

Нельзя считать этап завершённым только потому, что визуально «работает».

---

## Архитектурные инварианты

Ни один будущий этап не должен без отдельного ADR нарушить следующие правила:

```text
Generator != Renderer
LOD != World State
Feature != Chunk
GeoKernel != planet-specific monolith
High-resolution detail != canonical topology
procedural baseline != persistent delta
renderer artifact != canonical world state
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

## Ближайшая серия работ

```text
SERIES A — FOUNDATION
G0 → G1 → G2 → G3 → G4
```

После G4 выполнить architecture review перед началом FeatureGraph.

```text
SERIES B — RIVER WORLD
G5 → G6 → G7 → G8 → G9
```

После G9 выполнить первый полноценный river-valley fly-in review.

```text
SERIES C — VOLUME + DETAIL CONTRACT
G10 → G11 → G12 → G13
```

После G13 открыть `feature/gh0-high-resolution-detail-generator`.

```text
SERIES D — PARALLELIZATION
MAIN: G14 → G15 → G16
HR:   GH0 → GH1 → GH2/GH3 → GH4/GH5/GH6 → GH7
```

---

## Первый пользовательски заметный milestone

Не ждать полного G16.

Первый сильный visual milestone:

```text
G9 accepted
```

Должно быть возможно:

```text
fly from altitude
→ recognize the same valley
→ follow ~40 km river
→ see different bank forms
→ see islands/shoals
→ see cliff behavior affected by geology
```

Следующий сильный milestone:

```text
G11 accepted
```

Дополнительно:

```text
land near cliff
→ approach cave entrance
→ enter procedural volume cave
```

Ключевой engineering milestone:

```text
G13 accepted
```

После него detailed terrain R&D может идти параллельно основной планетарной системе.
