# ECO.EVO3 — Planetary Ecology Compiler — Research Architecture R1

Статус: `RESEARCH_ONLY / E3.0 ARCHITECTURE CANDIDATE / NO PRODUCTION BINDING`.

Родитель: accepted `ECO.XFER0` contract `06024c88fba045ba98e74594e55dce717d2c8dcd26f3d6a559a789bb5e39d309`.

## Назначение

EVO3 превращает owner-provided snapshot-bound planetary fields и persisted EVO2 SpeciesCatalog/provenance в детерминированный research artifact `PlanetEcologyProgram`.

```text
G / ENV / MAT / WQ / SD / TF owner snapshots
                  +
persisted EVO2 research SpeciesCatalog
                  ↓
FIELD_INGEST
                  ↓
OPPORTUNITY_FIELD
                  ↓
ECOLOGY_DECOMPOSITION
                  ↓
COLONIZATION_PROGRAM
                  ↓
POPULATION_WORKSET
                  ↓
TEMPORAL_PROGRAM
                  ↓
EVIDENCE_PACKAGE
                  ↓
PlanetEcologyProgram
```

Compiler не является вторым world generator и не создаёт `biome -> species` mapping. Compile-time suitability не является population truth; species/population state возникает только через causal ecology execution.

## PlanetEcologyProgram IR

IR имеет authority `RESEARCH_DERIVED_NON_AUTHORITATIVE` и содержит:

1. `input_snapshot_manifest`;
2. `research_ecology_regions`;
3. `ecological_opportunity_fields`;
4. `colonization_program`;
5. `population_work_units`;
6. `temporal_disturbance_program`;
7. `execution_budget_hints`;
8. `projection_manifest`;
9. `provenance_manifest`.

`research_ecology_region_id` — derived research identity, не canonical `SD` domain. `population_work_unit_id` — scheduling identity, не authority domain.

## Canonical input boundary

EVO3 читает только owner-provided snapshots/semantic adapters. Требуемые canonical foundations остаются внешними:

```text
G    geology / terrain context
ENV  environment fields
MAT  material context
WQ   world-query capability
SD   spatial identity/domain reference
TF   time identity/snapshots
```

Binding mode остаётся `XFER0_SEMANTIC_ONLY_NO_PRODUCTION_API_BINDING`. Concrete production API binding принадлежит XFER1 и остаётся заблокирован до owner-approved contracts.

## Catalog boundary

Source — persisted EVO2 research SpeciesCatalog + provenance. Все entries остаются eligible до causal elimination. Запрещены rebake, target-tuning, biome species filtering и автоматическое повышение `research_species_id` до canonical taxonomy.

## Truth model

```text
canonical G/ENV/MAT/SD/TF truth     simulator owners
PlanetEcologyProgram                derived research candidate
population/cohort ecology state     ECO semantic truth
individual representation           projection until canonical promotion
query/presentation                   derived read-only view
compiled suitability                 NOT population truth
```

## Scale model

Одна ecology state semantics сохраняется на уровнях `PLANET / REGION / PATCH / LOCAL_ACTIVE` и во всех режимах `INCUBATE_FAST / BACKGROUND_COARSE / LOCAL_ACTIVE`. Меняются resolution/work budget/representation, но не meaning.

## Determinism

Все внешние nondeterministic inputs snapshot-bound. Canonicalization использует stable ordering/sorted keys и explicit float policy. Global RNG consumption запрещён. Одинаковые snapshots + catalog должны давать одинаковый `PlanetEcologyProgram` и program hash.

## Authority barriers

EVO3 не получает:

- ownership `G/ENV/MAT/WQ/SD/TF`;
- production persistence или world-transaction authority;
- network/authority assignment;
- canonical species taxonomy;
- право превращать research region в canonical `SD`;
- право превращать compiled suitability в population truth;
- право использовать biome species table или asset scatter как ecology truth;
- право трактовать EVO2 evidence как production authorization.

## E3.0 result

E3.0 замораживает только architecture, machine roadmap и fail-closed validation. Runtime compiler implementation начинается не раньше E3.1 `Planet Field Snapshot Contract` и остаётся research-only. XFER1 остаётся отдельным production-binding gate.
