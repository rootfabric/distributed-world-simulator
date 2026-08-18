# ECO.EVO3 / E3.0 — Planetary Ecology Compiler Architecture & Roadmap — ACCEPTED

Дата: 2026-08-19.

Статус: `ACCEPTED / RESEARCH_ONLY / STATIC ARCHITECTURE / NO PRODUCTION BINDING`.

## Exact boundary

Ветка:

`feature/eco-evolutionary-ecology`

Parent XFER0 durable HEAD:

`66bb9fdb2a5efa0bd7d3cf7f216d042639a60b34`

E3.0 exact code-under-test / static freeze:

`250cf503c72440972bc8cdfaf4cea95398686ae0`

Freeze shape относительно XFER0: один commit, ровно 9 новых research/static files, production/runtime paths не затронуты.

## Frozen identities

```text
architecture revision  ECO-EVO3-ARCH-2026-08-19-R1
architecture hash      cbf50695b6db79d543c26168bcfa1bb9ac2e29b052f0eabeafb028ab618a3ac6
roadmap revision       ECO-EVO3-ROADMAP-2026-08-19-R1
roadmap hash           1b153d5974ab2f922dfe557ce5a9d3eed5a83f904b5c50265d7a28fb6faba178
E3.0 aggregate         a78bb0cd9fa782c929cd938f5553950ec75debf37d0fd854d1f3f3f8e7dc0f91
XFER0 contract         06024c88fba045ba98e74594e55dce717d2c8dcd26f3d6a559a789bb5e39d309
XFER0 aggregate        1adf3d0fa733ed74e3a28bfe1d0632f5d45c62ca5df932bce3e55693a18e9044
```

## Architecture decision

EVO3 определяет `Planetary Ecology Compiler` как research compiler, который принимает:

- owner-provided snapshot-bound semantics `G / ENV / MAT / WQ / SD / TF`;
- persisted EVO2 SpeciesCatalog/provenance;

и выдаёт детерминированный derived `PlanetEcologyProgram`.

Compiler **не** является вторым world generator и **не** создаёт `biome -> species` table. Compile-time suitability не является population truth; species distribution/population state должна возникать через causal ecology execution.

`PlanetEcologyProgram` имеет authority:

`RESEARCH_DERIVED_NON_AUTHORITATIVE`.

Его девять обязательных sections:

```text
input_snapshot_manifest
research_ecology_regions
ecological_opportunity_fields
colonization_program
population_work_units
temporal_disturbance_program
execution_budget_hints
projection_manifest
provenance_manifest
```

Research ecology region identity не является canonical `SD`, а population work unit не является authority domain.

## Compiler stages

```text
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
```

## Truth and scale model

Одна ecology state semantics сохраняется на:

`PLANET / REGION / PATCH / LOCAL_ACTIVE`

и в execution modes:

`INCUBATE_FAST / BACKGROUND_COARSE / LOCAL_ACTIVE`.

Меняются resolution/work budget/representation, но не meaning.

Canonical `G/ENV/MAT/SD/TF` truth остаётся у simulator owners. `PlanetEcologyProgram` — derived candidate. Population/cohort state — ecology semantic truth. Individual — representation, пока canonical lifecycle/transaction owner явно не выполнит promotion. Query/presentation остаются read-only derived surfaces.

## Authority barriers

E3.0 fail-closed запрещает:

- ownership `G/ENV/MAT/WQ/SD/TF`;
- production persistence/world transaction authority;
- network/authority assignment;
- canonical species taxonomy promotion;
- biome-to-species mapping;
- asset scatter as ecology truth;
- research region as canonical SD domain;
- compiled suitability as population truth;
- EVO2 evidence as production authorization.

Production API binding остаётся deferred к XFER1. XFER1 всё ещё `BLOCKED_WAIT_CANONICAL_FOUNDATIONS` для exact set `G/ENV/MAT/WQ/SD/TF`.

## Static verification

Canonical cross-platform runner:

`RUN_ECO_EVO3_ARCHITECTURE_TESTS.py`

Exact runner blob:

`4cb58a930c6a2f95207bf7ccff0d2e4be51a255b`

Post-freeze verification на published bytes:

```text
python compile               PASS
architecture validator       PASS
semantic tests               25 / 25 PASS
fresh runner A               PASS / exit 0
fresh runner B               PASS / exit 0
stderr                       0 / 0 lines
stdout A/B                   byte-identical
stdout SHA-256               70076e8f2eaaacc9372ae0659e4264a6e512f3b552be36badf931e200afb7165
candidate files              9
compiler stages              7
roadmap checkpoints          10
```

Negative suite меняет machine semantics и пересчитывает architecture/roadmap hash перед validation, поэтому проверяет именно fail-closed contract, а не только checksum mismatch.

## Roadmap accepted

```text
E3.0      ACCEPTED
E3.1      AUTHORIZED_NOT_STARTED   ← NEXT
E3.2      BLOCKED
E3.3      BLOCKED
E3.4      BLOCKED
E3.5      BLOCKED
E3.6      BLOCKED
E3.7      BLOCKED
E3.8      BLOCKED
E3.FINAL  BLOCKED
```

Следующий checkpoint:

**E3.1 Planet Field Snapshot Contract**.

Он должен создать research-only snapshot adapter/fixture для семантики `G/ENV/MAT/WQ/SD/TF`, не изобретая production API и не открывая XFER1.

## Evidence classification

Execution class:

`DIRECT_CANONICAL_PYTHON_STATIC_ARCHITECTURE_VALIDATION`.

Canonical runner реально исполнен. Independent Reviewer PASS и independent Verifier PASS **не заявляются**. Project Control / GitHub CI GREEN также не заявляются без отдельного exact-head evidence.

Machine validation:

`validation/ecology/eco-evo3-e3-0-architecture-roadmap-validation.json`.
