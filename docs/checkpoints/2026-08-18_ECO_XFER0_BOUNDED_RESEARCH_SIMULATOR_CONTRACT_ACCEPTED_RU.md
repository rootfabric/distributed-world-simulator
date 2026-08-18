# ECO.XFER0 — Bounded Research-to-Simulator Contract — ACCEPTED

Дата: 2026-08-18  
Ветка: `feature/eco-evolutionary-ecology`  
Статус: `ACCEPTED_BOUNDED_DESIGN / RESEARCH_ONLY / NO_PRODUCTION_BINDING`

## Exact boundary

```text
Parent EVO2 durable HEAD
3367615b8ad5fed59ac13ac6fcc215e36155b27d

XFER0 exact code-under-test
bb80beac95d838b56cccbe5d98f7e1bcbfd80376

XFER0 contract hash
06024c88fba045ba98e74594e55dce717d2c8dcd26f3d6a559a789bb5e39d309

XFER0 aggregate
1adf3d0fa733ed74e3a28bfe1d0632f5d45c62ca5df932bce3e55693a18e9044
```

Parent EVO2 FINAL remains exact:

```text
FINAL code-under-test
376796ab8c8370b7370fcd220ed207d07955cb42

FINAL aggregate
6daab256af3d1e7693c66a8afaad4d04fd1564c4376b9f3cd747a268a10c2250

FINAL evidence
989e5ae02e66052ca7d2e46f5f452446300ba625dd4efd5cd6b5ffd9db2f2cd1

E2.8 catalog
5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219
```

## Что принято

XFER0 фиксирует research→simulator semantic boundary. Он не реализует production integration.

Главное правило:

> ECO может публиковать типизированные research-derived payloads и requests. Только canonical simulator owners могут превратить их в authoritative world state.

Accepted machine contract содержит ровно шесть interface surfaces:

```text
ENVIRONMENT_INPUT
ECOLOGY_STATE_OUTPUT
QUERY_PROJECTION
PERSISTENCE_PAYLOAD
IDENTITY_PROVENANCE
REPRESENTATION_PROMOTION_REQUEST
```

## Canonical foundation barrier

До XFER1 обязательны main-owned canonical contracts:

```text
G / ENV / MAT / WQ / SD / TF
```

XFER0 не связывает ECO с предполагаемыми production API этих foundation. Binding state остаётся:

`UNRESOLVED_CANONICAL_CONTRACTS`

а binding mode:

`SEMANTIC_ONLY_NO_PRODUCTION_API_BINDING`.

Поэтому XFER1 остаётся:

`BLOCKED_WAIT_CANONICAL_FOUNDATIONS`.

## Authority boundaries

### Environment

ECO получает read-only semantic environment input. Terrain, environment, material, time и spatial-domain writes запрещены.

### Ecology state

ECO может публиковать population/cohort-derived state и delta candidates, но не получает право создавать planet-wide entity truth, выполнять authoritative world mutation или обходить lifecycle owner.

### Query / presentation

Проекция read-only и обязана нести source ecology revision/spatial/provenance identity. Query/presentation не может мутировать world или ecology.

### Persistence

ECO может определить typed payload и restore validation contract. Durability, commit point, distributed log и transaction commit принадлежат внешнему canonical persistence/transaction owner.

### Identity

`research_species_id`, catalog/lineage/genome/evidence hashes остаются research provenance. Они не повышаются автоматически до canonical taxonomy и не дают authority.

### Representation promotion

ECO может только `REQUEST_PROMOTION`. Создание durable entity, authority assignment и transaction commit остаются у canonical world owners. После promotion representation не становится второй ecology truth.

## Exact machine artifacts

```text
contract
config/ecology/eco-xfer0-contract.v1.json
1987dd67ae0755b4a00bc22f48a019837fb2066a

schema
config/ecology/eco-xfer0-contract.schema.v1.json
8759a3e0832ae514df69ade5d6235b524bea84de

validator
scripts/research/ecology/validate_xfer0_contract.py
1244d6dac0149957857a294b662738076ccc6e2d

tests
tests/research/ecology/test_eco_xfer0_contract.py
6afe9af777a976775fc3be4f68b5a91720e30474

canonical runner
RUN_ECO_XFER0_CONTRACT_TESTS.py
789bc1c17b2964bc1f71166e2a7a3725911566d6
```

Design document:

`docs/plans/ECO_XFER0_RESEARCH_SIMULATOR_CONTRACT_RU.md`

## Verification

Canonical Python runner executed directly on the exact published artifacts.

```text
Python                         3.13.5
py_compile                     PASS
validator                      PASS
semantic tests                 17 / 17 PASS
fresh runner process A         PASS
fresh runner process B         PASS
exit codes                     0 / 0
A/B logs                       byte-identical
log SHA-256                    9126f83e992e1d834e1e7e5317ec97cca174d1027a518310d70df6bd49ac47aa
```

Negative tests deliberately recompute `contract_hash` after semantic tamper. Поэтому они доказывают authority/semantic rejection, а не только checksum mismatch.

Fail-closed cases включают production activation, owner mutation, removal foundation dependency, concrete production binding, environment/query writes, persistence durability ownership, taxonomy promotion, durable-entity creation, premature XFER1 readiness, XFER0-as-production-authorization, EVO3 runtime authority и biome/asset-scatter shortcuts.

## Candidate shape

От accepted EVO2 durable carrier до XFER0 freeze:

```text
3367615b8ad5fed59ac13ac6fcc215e36155b27d
        ↓
6 commits
5 distinct files
        ↓
bb80beac95d838b56cccbe5d98f7e1bcbfd80376
```

Шестой commit — только deterministic-output repair canonical runner. Production/runtime paths не менялись.

## Current main observation

На момент acceptance canonical `main` наблюдался как:

`2cff3e999a3beb82ffab207fc79b0629f2765007`

Это observation для architecture context, а не production-binding pin XFER0.

## Claim boundary

XFER0 acceptance означает:

`BOUNDED_RESEARCH_TO_SIMULATOR_SEMANTIC_AND_AUTHORITY_CONTRACT_FROZEN_AND_MACHINE_CHECKED`.

Он не означает:

```text
XFER1 READY
production integration accepted
production runtime authorized
production persistence/network/transaction authority
canonical biological taxonomy
P4 promotion/global acceptance
```

Independent Reviewer PASS не заявляется. Independent Verifier PASS не заявляется. Project Control/CI GREEN не приписывается этому checkpoint без отдельного exact-head evidence.

## Decision / next

Decision:

`ACCEPT_XFER0_AND_AUTHORIZE_EVO3_RESEARCH_PLANNING`.

```text
EVO2                         COMPLETE_RESEARCH_ONLY
    ↓
XFER0                        ACCEPTED_BOUNDED_DESIGN
    ↓
EVO3                         AUTHORIZED_RESEARCH_PLANNING_NOT_STARTED

parallel gate:
XFER1                        BLOCKED_WAIT_CANONICAL_G_ENV_MAT_WQ_SD_TF
```
