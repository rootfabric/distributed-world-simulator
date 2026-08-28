# ECO — Центральный маршрут развития ветки

Статус (исторический документ): `RESEARCH_ONLY / EVO2 COMPLETE / XFER0 ACCEPTED / EVO3 E3.0..E3.3 ACCEPTED / E3.4 CURRENT` — срез на момент написания.

**Статус на 2026-08-28 (ECO EVO7 live continuation):** `LS3.0–LS3.FINAL CLOSED / ECO-VIS1 CLOSED / ECO-VIS2 R2.1 IMPLEMENTATION CANDIDATE`.

Текущий live-simulation маршрут вынесен в `config/ecology/eco-evo7-live-simulation-roadmap.v1.json`. Он фиксирует новый визуальный checkpoint: `LS3.FINAL → ECO-VIS1 → ECO-VIS2 → ECO-VIS3 → LS4`. Исторические EVO2/EVO3 разделы ниже не переписываются задним числом.

Historical machine roadmap: `config/ecology/eco-evolutionary-ecology-roadmap.v1.json`.  
Live EVO7 roadmap: `config/ecology/eco-evo7-live-simulation-roadmap.v1.json`.  
EVO3 architecture: `docs/architecture/ECO_EVO3_PLANETARY_ECOLOGY_COMPILER_ARCHITECTURE_RU.md`.  
EVO3 roadmap: `docs/plans/ECO_EVO3_PLANETARY_ECOLOGY_COMPILER_ROADMAP_RU.md`.  
E3.1 snapshot contract: `docs/plans/ECO_EVO3_E3_1_PLANET_FIELD_SNAPSHOT_CONTRACT_RU.md`.  
E3.2 acceptance: `docs/checkpoints/2026-08-19_ECO_EVO3_E3_2_ACCEPTED_E3_3_AUTHORIZED_RU.md`.  
E3.3 acceptance: `docs/checkpoints/2026-08-19_ECO_EVO3_E3_3_ACCEPTED_E3_4_AUTHORIZED_RU.md`.  
XFER0 boundary: `docs/plans/ECO_XFER0_RESEARCH_SIMULATOR_CONTRACT_RU.md`.

## Accepted research route

```text
EVO0 / CAL1                         COMPLETE
EVO1 / P2.1..P2.8                  COMPLETE
P3 / P3.1..P3.8                    COMPLETE_RESEARCH_ONLY
EVO2 / E2.1..E2.FINAL              COMPLETE_RESEARCH_ONLY
XFER0                               ACCEPTED_BOUNDED_DESIGN
EVO3 / E3.0                        ACCEPTED
EVO3 / E3.1                        ACCEPTED
EVO3 / E3.2                        ACCEPTED
EVO3 / E3.3                        ACCEPTED
EVO3 / E3.4                        AUTHORIZED_NOT_STARTED  ← CURRENT
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

Exact freeze: `7a1f5f0dc29b0564c6d4b684826250fca6a9b711`.

```text
contract hash       b3e96b432008ea93692c5cbde9cf7c74cceca4e4c4196ef261a5fbd0ff405170
fixture hash        3e22d87666b13a4bafcdd5dd3184097b53b221103fd2f9e9f2be452c8ab79978
field provenance    3827c1da7d94227fb04b5fbfbd93fd5262c826cd86503af9f540a120431a82c3
snapshot hash       2ceb042d905b06ae76acc699b60ed6c115d3e0ac7943ce7cbe0c94f962447b00
artifact SHA-256    5123ebd58e6eade5d3dab2325af49a43234bc8834182ddd7db7d6c463896b790
aggregate           0a412c5c6cb12264c93c92d502321b578ebb3d166ae90d80ab450e03478e8036
runner log          f0c8169b1c36edb68505e19951db493324fac637b989383d2f3234304a3763e2
```

E3.1 фиксирует deterministic research snapshot входа planet compiler и не создаёт biome/species/population truth, canonical SD или production binding.

## E3.2 — Ecological Opportunity Field — ACCEPTED

```text
reviewed HEAD       578981af36c2fe101925db024e6b7747c99806ab
executable freeze   f276a5b29a39a00ae15c866a310b20f3ad9fe9c8
merge commit        83f35d7abe2ebdea3e5afe175833817ad631c5e6
Project Control     32214348326 / #997 — SUCCESS
aggregate           ef0ed137bf8d2862f4c9cfacee0792dba8079e539daa4bfb7322d7d5da8afc9c
contract hash       bbb2e4f29ac88da42102ee6c08d239f8e0a72760ab8d1371fdea2cda258ed47d
opportunity field   acba61638f8128b667880f2bd391ab73f6175d0899656bba92657d578d48203c
artifact SHA-256    59a0af5e40cae5c8a91e487da158edadfd4e127a0390ebe856f78f2365a066ff
tests               47/47
```

Fresh independent verdict: `PASS — SAFE FOR E3.2 MERGE/ACCEPTANCE AND SUBSEQUENT E3.3 AUTHORIZATION`.

## E3.3 — Research Ecology Decomposition — ACCEPTED

Принят после exact-head Project Control и fresh independent critical review.

```text
reviewed HEAD       7ae4c17d0cca0d37369b620481d000fdbc8545fc
executable freeze   527e2dbef1ae4462e5b9e682b002408057930970
merge commit        ac47904147edaa7dc46c63c20e91fd4f3a580c13
Project Control     32247214418 / #1003 — SUCCESS
candidate aggregate 148b627b094bc71574a21043627bea859e05716e6cd3d09d57f94111a51cb837
contract hash       593b1889198021e2fcdae0c3746bdbe771d606427f07a7ccfc7c8a530cebec9f
decomposition       9736ec70f844c930f8e160a4f08ae8e0aae1cce6f73fbf106499bea15b15a51a
artifact SHA-256    cab0ec65d66f68f097c07b686e5e87ba998dfe39a9b587a3f945b10d0ac2029a
tests               60/60
```

Fresh independent verdict: `PASS — SAFE FOR E3.3 MERGE/ACCEPTANCE AND SUBSEQUENT E3.4 AUTHORIZATION`.

E3.3 фиксирует deterministic research-only patch/edge/region decomposition. Research identities не являются canonical SD domains; species identity и biome labels не являются partition keys.

## Current — E3.4 Causal Colonization Program Compiler

E3.4 обязан потреблять одновременно:

```text
accepted E3.3 research decomposition
+
FULL persisted EVO2 SpeciesCatalog
        ↓
causal dispersal / establishment compiler
        ↓
causal colonization_program
```

Обязательные границы:

- все записи полного SpeciesCatalog входят в input manifest и остаются eligible на входной границе;
- causal dispersal/establishment может отсеивать отдельные виды;
- `NO_COLONIZATION` является допустимым полноценным результатом;
- запрещены biome→species tables, target-aware species injection, catalog rebake/retuning и direct scatter как ecology truth;
- output остаётся `RESEARCH_DERIVED_NON_AUTHORITATIVE`;
- canonical SD, production persistence/network/transaction/authority не создаются;
- E3.5 остаётся заблокированным до отдельного принятия E3.4.

Architecture source of truth: stage `COLONIZATION_PROGRAM` в `config/ecology/eco-evo3-planetary-ecology-compiler.v1.json`.

## Дальнейший EVO3 route

```text
E3.4 Causal Colonization Program Compiler        CURRENT
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
