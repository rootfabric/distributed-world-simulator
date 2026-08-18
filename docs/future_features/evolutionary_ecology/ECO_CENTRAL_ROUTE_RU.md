# ECO — Центральный маршрут развития ветки

Статус: `RESEARCH_ONLY / EVO2 COMPLETE / XFER0 ACCEPTED / EVO3 E3.0 ACCEPTED / E3.1 CURRENT`.

Machine roadmap: `config/ecology/eco-evolutionary-ecology-roadmap.v1.json`.
EVO3 architecture: `docs/architecture/ECO_EVO3_PLANETARY_ECOLOGY_COMPILER_ARCHITECTURE_RU.md`.
EVO3 roadmap: `docs/plans/ECO_EVO3_PLANETARY_ECOLOGY_COMPILER_ROADMAP_RU.md`.
XFER0 boundary: `docs/plans/ECO_XFER0_RESEARCH_SIMULATOR_CONTRACT_RU.md`.

## Accepted research route

```text
EVO0 / CAL1                         COMPLETE
EVO1 / P2.1..P2.8                  COMPLETE
P3 / P3.1..P3.8                    COMPLETE_RESEARCH_ONLY
EVO2 / E2.1..E2.FINAL              COMPLETE_RESEARCH_ONLY
XFER0                               ACCEPTED_BOUNDED_DESIGN
EVO3 / E3.0                         ACCEPTED
EVO3 / E3.1                         AUTHORIZED_NOT_STARTED  ← CURRENT
```

## E3.0 — accepted architecture

Exact static freeze: `250cf503c72440972bc8cdfaf4cea95398686ae0`.

```text
architecture hash  cbf50695b6db79d543c26168bcfa1bb9ac2e29b052f0eabeafb028ab618a3ac6
roadmap hash       1b153d5974ab2f922dfe557ce5a9d3eed5a83f904b5c50265d7a28fb6faba178
aggregate          a78bb0cd9fa782c929cd938f5553950ec75debf37d0fd854d1f3f3f8e7dc0f91
runner log         70076e8f2eaaacc9372ae0659e4264a6e512f3b552be36badf931e200afb7165
```

E3.0 определяет `PlanetEcologyProgram` как deterministic research-derived non-authoritative IR. Он компилируется из owner-provided snapshot-bound `G/ENV/MAT/WQ/SD/TF` semantics и persisted EVO2 SpeciesCatalog/provenance.

Compiler stages:

```text
FIELD_INGEST
→ OPPORTUNITY_FIELD
→ ECOLOGY_DECOMPOSITION
→ COLONIZATION_PROGRAM
→ POPULATION_WORKSET
→ TEMPORAL_PROGRAM
→ EVIDENCE_PACKAGE
```

Критические границы:

- compiler не является вторым world generator;
- `biome -> species` mapping запрещён;
- compiled suitability не является population truth;
- research ecology regions не являются canonical `SD`;
- ECO не получает `G/ENV/MAT/WQ/SD/TF`, persistence, transaction, network или authority ownership;
- research species identity не становится canonical taxonomy;
- XFER1 остаётся blocked до owner-approved canonical contracts.

Static validation: canonical Python runner, 25/25 tests, fresh A/B exit 0/0, zero stderr, byte-identical stdout.

## Current — E3.1 Planet Field Snapshot Contract

Следующий checkpoint должен создать **research-only** snapshot contract/fixture для planet input semantics:

```text
stable planet identity
stable spatial key
stable time key
reference frame identity
G / ENV / MAT / WQ / SD / TF references
continuous environmental values
field provenance hash
```

E3.1 не имеет права изобретать production API. Concrete production binding остаётся XFER1 work.

## Дальнейший EVO3 route

```text
E3.1 Planet Field Snapshot Contract
  ↓
E3.2 Ecological Opportunity Field
  ↓
E3.3 Research Ecology Decomposition
  ↓
E3.4 Causal Colonization Program Compiler
  ↓
E3.5 Multi-scale Population Workset Compiler
  ↓
E3.6 Seasonal & Disturbance Temporal Program
  ↓
E3.7 Deterministic Planet Compilation
  ↓
E3.8 Cross-Planet Generalization Matrix
  ↓
E3.FINAL Planetary Ecology Compiler Challenge
```

После plant planetary compiler proof можно планировать plant runtime convergence и EVO4 multi-trophic ecology. Production integration remains a separate main-owned governance line.
