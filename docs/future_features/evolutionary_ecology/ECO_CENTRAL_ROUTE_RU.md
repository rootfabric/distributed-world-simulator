# ECO — Центральный маршрут развития ветки

Статус: `RESEARCH_ONLY / EVO2 COMPLETE / XFER0 ACCEPTED / EVO3 E3.0 + E3.1 ACCEPTED / E3.2 CURRENT`.

Machine roadmap: `config/ecology/eco-evolutionary-ecology-roadmap.v1.json`.  
EVO3 architecture: `docs/architecture/ECO_EVO3_PLANETARY_ECOLOGY_COMPILER_ARCHITECTURE_RU.md`.  
EVO3 roadmap: `docs/plans/ECO_EVO3_PLANETARY_ECOLOGY_COMPILER_ROADMAP_RU.md`.  
E3.1 snapshot contract: `docs/plans/ECO_EVO3_E3_1_PLANET_FIELD_SNAPSHOT_CONTRACT_RU.md`.  
XFER0 boundary: `docs/plans/ECO_XFER0_RESEARCH_SIMULATOR_CONTRACT_RU.md`.

## Accepted research route

```text
EVO0 / CAL1                         COMPLETE
EVO1 / P2.1..P2.8                  COMPLETE
P3 / P3.1..P3.8                    COMPLETE_RESEARCH_ONLY
EVO2 / E2.1..E2.FINAL              COMPLETE_RESEARCH_ONLY
XFER0                               ACCEPTED_BOUNDED_DESIGN
EVO3 / E3.0                         ACCEPTED
EVO3 / E3.1                         ACCEPTED
EVO3 / E3.2                         AUTHORIZED_NOT_STARTED  ← CURRENT
```

## E3.0 — Planetary Ecology Compiler Architecture — ACCEPTED

Exact static freeze:

`250cf503c72440972bc8cdfaf4cea95398686ae0`.

```text
architecture hash  cbf50695b6db79d543c26168bcfa1bb9ac2e29b052f0eabeafb028ab618a3ac6
roadmap hash       1b153d5974ab2f922dfe557ce5a9d3eed5a83f904b5c50265d7a28fb6faba178
aggregate          a78bb0cd9fa782c929cd938f5553950ec75debf37d0fd854d1f3f3f8e7dc0f91
```

Compiler IR остаётся `PlanetEcologyProgram / RESEARCH_DERIVED_NON_AUTHORITATIVE`.

```text
FIELD_INGEST
→ OPPORTUNITY_FIELD
→ ECOLOGY_DECOMPOSITION
→ COLONIZATION_PROGRAM
→ POPULATION_WORKSET
→ TEMPORAL_PROGRAM
→ EVIDENCE_PACKAGE
```

## E3.1 — Planet Field Snapshot Contract — ACCEPTED

Exact freeze:

`7a1f5f0dc29b0564c6d4b684826250fca6a9b711`.

Frozen identities:

```text
contract hash       b3e96b432008ea93692c5cbde9cf7c74cceca4e4c4196ef261a5fbd0ff405170
fixture hash        3e22d87666b13a4bafcdd5dd3184097b53b221103fd2f9e9f2be452c8ab79978
field provenance    3827c1da7d94227fb04b5fbfbd93fd5262c826cd86503af9f540a120431a82c3
snapshot hash       2ceb042d905b06ae76acc699b60ed6c115d3e0ac7943ce7cbe0c94f962447b00
artifact SHA-256    5123ebd58e6eade5d3dab2325af49a43234bc8834182ddd7db7d6c463896b790
aggregate           0a412c5c6cb12264c93c92d502321b578ebb3d166ae90d80ab450e03478e8036
runner log          f0c8169b1c36edb68505e19951db493324fac637b989383d2f3234304a3763e2
```

E3.1 фиксирует deterministic research snapshot входа planet compiler:

```text
stable planet identity
stable time key
reference frame identity
stable spatial keys
opaque G / ENV / MAT / WQ / SD / TF references
temperature
soil moisture
light
nutrients
disturbance
provenance hashes
```

Continuous values сериализуются как integer fixed units (`microdeg / milli-C / ppm`), поэтому input canonicalization не зависит от float formatting.

Принципиально отсутствуют:

```text
NO biome labels
NO species assignment
NO population truth
NO canonical SD creation
NO production API binding
NO owner-state mutation
```

Exact published six-blob carrier прошёл canonical Python verification: `32/32`, fresh runner A/B `0/0`, два snapshot-build процесса создали byte-identical artifact.

## Current — E3.2 Ecological Opportunity Field

E3.2 должен потреблять **только accepted E3.1 PlanetFieldSnapshot**.

```text
PlanetFieldSnapshot
        ↓
continuous causal opportunity field
```

Прямой обход через raw E3.1 fixture запрещён. Opportunity field должен оставаться derived research field и не имеет права:

- выдавать species assignment;
- становиться population truth;
- создавать biome→species mapping;
- менять `G/ENV/MAT/WQ/SD/TF` ownership;
- объявлять production binding.

## Дальнейший EVO3 route

```text
E3.2 Ecological Opportunity Field               CURRENT
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

## Production boundary

`XFER1` остаётся `BLOCKED_WAIT_CANONICAL_G_ENV_MAT_WQ_SD_TF`.

ECO research не получает production persistence, world transaction, network, authority, canonical environment/time/spatial или canonical species-taxonomy ownership. Production integration остаётся отдельной main-owned governance линией.
