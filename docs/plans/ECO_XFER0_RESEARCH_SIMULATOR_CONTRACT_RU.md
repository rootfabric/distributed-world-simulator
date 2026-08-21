# ECO.XFER0 — bounded research → simulator contract

Статус: `ACCEPTED_BOUNDED_DESIGN / RESEARCH_ONLY / NO_PRODUCTION_BINDING`.

Ветка: `feature/eco-evolutionary-ecology`.

Exact XFER0 code-under-test: `bb80beac95d838b56cccbe5d98f7e1bcbfd80376`.

Parent EVO2 durable head: `3367615b8ad5fed59ac13ac6fcc215e36155b27d`.

Machine contract: `config/ecology/eco-xfer0-contract.v1.json`.

## 1. Зачем XFER0

EVO2 доказал автономную portable plant ecology как research system. XFER0 не переносит этот код напрямую в production. Он фиксирует, **какие данные и намерения ECO может передавать симулятору**, и одновременно фиксирует, чем ECO не имеет права владеть.

Главное правило:

> ECO может публиковать типизированные research-derived payloads и requests. Только canonical simulator owners могут превратить их в authoritative world state.

Поэтому XFER0 — interface/authority contract, а не runtime integration.

## 2. Граница scope

XFER0 гарантированно не делает:

- production runtime implementation;
- activation/lease/Work Order mutation;
- canonical owner mutation;
- network protocol mutation;
- production persistence mutation;
- world transaction mutation;
- canonical taxonomy mutation;
- biome → species table;
- asset scatter как ecology truth.

Concrete production API binding в XFER0 запрещён. Все binding points остаются semantic-only.

## 3. Six interface surfaces

### 3.1 ENVIRONMENT_INPUT — simulator → ECO

ECO требует semantic sample/region input:

- stable spatial key;
- stable time key;
- reference-frame identity;
- temperature;
- soil moisture;
- light availability;
- nutrient availability;
- flood/disturbance pressure.

XFER0 связывает эти semantics с dependency set `G / ENV / MAT / WQ / SD / TF`, но **не изобретает их production API**.

Allowed: `READ_SAMPLE`, `READ_REGION_SUMMARY`.

Forbidden: terrain/environment/material/time/spatial writes.

### 3.2 ECOLOGY_STATE_OUTPUT — ECO → simulator

ECO может выдавать population/cohort state candidate:

- research species identity;
- lineage provenance;
- biomass/density;
- seed-bank/recruitment state;
- ecology revision.

Это payload/candidate, а не право создать planet-wide entity truth или выполнить world mutation.

### 3.3 QUERY_PROJECTION — ECO → WQ/presentation

Только read-only derived projection, обязательно с source ecology revision, spatial key и provenance hash.

Query/presentation не может мутировать ecology/world или authorise interaction.

### 3.4 PERSISTENCE_PAYLOAD — ECO → production persistence owner

ECO определяет typed payload schema/version/content hash и restore validation contract.

ECO **не** владеет:

- durability;
- commit point;
- distributed log;
- transaction commit semantics.

E2.8 persistence остаётся research proof и semantic donor, а не production persistence subsystem.

### 3.5 IDENTITY_PROVENANCE — reference-only

Portable identities:

- `research_species_id`;
- catalog hash;
- lineage id;
- genome checksum;
- source evidence hash.

Эти значения можно reference/compare/audit. Их нельзя автоматически повышать до canonical taxonomy или использовать для authority assignment.

### 3.6 REPRESENTATION_PROMOTION_REQUEST — ECO → canonical world owners

Если interaction требует перейти от aggregate population representation к durable entity/world state, ECO может выдать только `REQUEST_PROMOTION` с source population identity/revision/provenance.

ECO не может самостоятельно:

- создать durable entity;
- назначить authority;
- commit world transaction;
- удалить population truth.

## 4. Truth model

```text
ECO population/cohort state
        = ecology truth

representation / query / mesh
        = derived view

interaction needs durable world state
        ↓
REQUEST_PROMOTION
        ↓
canonical lifecycle / transaction / authority owners
        ↓
explicit committed promotion
```

Даже после promotion durable representation не становится второй ecology truth.

## 5. Canonical foundation barrier

XFER1 остаётся blocked до main-owned canonical contracts:

```text
G
ENV
MAT
WQ
SD
TF
```

XFER0 фиксирует только required semantics. Он не может:

- копировать research DTO в canonical owner;
- объявлять предполагаемый API canonical;
- обходить owner mapping/review;
- считать acceptance XFER0 production authorization.

Observed canonical main при acceptance: `2cff3e999a3beb82ffab207fc79b0629f2765007`.

Это observation, не production binding pin.

## 6. EVO3 gate

После acceptance XFER0 разрешено открыть **EVO3 research planning**:

`Planetary Ecology Compiler / broader planetary generalization`.

Но это не разрешает production runtime. Любой concrete simulator binding всё ещё требует XFER1 и canonical owner contracts.

## 7. Machine validation

Exact artifacts:

```text
contract   1987dd67ae0755b4a00bc22f48a019837fb2066a
schema     8759a3e0832ae514df69ade5d6235b524bea84de
validator  1244d6dac0149957857a294b662738076ccc6e2d
tests      6afe9af777a976775fc3be4f68b5a91720e30474
runner     789bc1c17b2964bc1f71166e2a7a3725911566d6
```

Contract hash:

`06024c88fba045ba98e74594e55dce717d2c8dcd26f3d6a559a789bb5e39d309`

Validation:

- Python compile PASS;
- contract validator PASS;
- 17/17 positive/negative semantic tests PASS;
- all negative tamper cases recalculate contract hash before validation;
- fresh canonical runner A/B exit 0;
- A/B logs byte-identical;
- log SHA-256 `9126f83e992e1d834e1e7e5317ec97cca174d1027a518310d70df6bd49ac47aa`.

## 8. What 17 tests guard

Fail-closed regression covers:

- EVO2 parent pin substitution;
- production activation;
- canonical owner mutation;
- removal of a required foundation;
- concrete production API binding;
- environment write surface;
- query/world write surface;
- persistence durability claim;
- canonical taxonomy promotion;
- durable-entity creation from promotion request;
- planet-wide individual truth creation;
- premature XFER1 readiness;
- treating XFER0 as production authorization;
- EVO3 runtime authority;
- biome species-table shortcut;
- asset-scatter-as-truth shortcut.

## 9. Accepted meaning

XFER0 acceptance means:

**the research→simulator semantic boundary and authority barriers are frozen and machine-checked.**

It does not mean:

- XFER1 ready;
- production integration accepted;
- P4 accepted/promoted because of ECO research;
- production persistence/network/transaction authority;
- canonical biological taxonomy.

## 10. Next

```text
EVO2                         COMPLETE_RESEARCH_ONLY
    ↓
XFER0 bounded contract       ACCEPTED
    ↓
EVO3 research planning       AUTHORIZED_NOT_STARTED

parallel blocker:
XFER1                        BLOCKED_WAIT_CANONICAL_G_ENV_MAT_WQ_SD_TF
```
