# ECO — Центральный маршрут развития ветки

Статус: `RESEARCH_ONLY / EVO2 COMPLETE / XFER0 ACCEPTED / EVO3 RESEARCH PLANNING CURRENT`.

Canonical North Star: `docs/future_features/evolutionary_ecology/ECO_EVOLUTIONARY_ECOSYSTEM_VISION_RU.md`.  
Machine roadmap: `config/ecology/eco-evolutionary-ecology-roadmap.v1.json`.  
EVO2 historical plan: `docs/plans/ECO_EVO2_PORTABLE_SPECIES_CATALOG_ROADMAP_RU.md`.  
XFER0 contract: `docs/plans/ECO_XFER0_RESEARCH_SIMULATOR_CONTRACT_RU.md`.

## 1. Accepted research frontier

```text
ECO.P1                    ACCEPTED
ECO.PH0..PH5-S4           ACCEPTED
ECO.CONV0-A               ACCEPTED
ECO.CAL1-A..F             ACCEPTED
CAL1-F                    ROBUST_UNITY_CALIBRATION
ECO.EVO1 / P2.1..P2.8     ACCEPTED / EVO1 COMPLETE
ECO.P3 / P3.1..P3.8       ACCEPTED / RESEARCH ROUTE COMPLETE
ECO.EVO2 / E2.1..E2.8     ACCEPTED
ECO.EVO2 / E2.FINAL       ACCEPTED / EVO2 COMPLETE_RESEARCH_ONLY
ECO.XFER0                  ACCEPTED_BOUNDED_DESIGN
ECO.EVO3                   AUTHORIZED_RESEARCH_PLANNING_NOT_STARTED
ECO.XFER1                  BLOCKED_WAIT_CANONICAL_G_ENV_MAT_WQ_SD_TF
```

Последние durable checkpoints:

- `docs/checkpoints/2026-08-18_ECO_EVO2_FINAL_UNSEEN_WORLD_CHALLENGE_ACCEPTED_RU.md`;
- `docs/checkpoints/2026-08-18_ECO_XFER0_BOUNDED_RESEARCH_SIMULATOR_CONTRACT_ACCEPTED_RU.md`.

## 2. Frozen EVO2 identities

```text
E2.2 bake       45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b
E2.2 catalog    5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219
E2.3            82d76f858568d5bd53af4d299abd2155f2fde7e845de828cf4555e601ee1efa8
E2.4            ae2952de10ac721c8052694963b690d9f72af05d9c92e2fa4cd70e00f72fb2b5
E2.5            942ad54e7672c4f57874e1802b320c1b2a4aa74e43b05f7e285793ea4ec8b2a6
E2.6            1a4bcf1cffe65450a27037e9307bb5c7ac3cb8a98899918207107e367d9d5fbd
E2.7            eb3b30919114cb9971b7413f416a3ae07eb50aebe81801454aaa310d6e879c7d
E2.8 aggregate  4182176c1cc8b6d609fefc7057b5ff5307c92f839682e76f6168841d60275061
E2.8 content    3d7ca34560483e2a4d1eb1955c008eb1f05ab3603e3d358abbf4823b33554e2e
E2.8 transport  b31c863f8e1943e5778d56631f8c8ad75b95f3b9d3930a699f80fd07595d45d1
E2.FINAL        6daab256af3d1e7693c66a8afaad4d04fd1564c4376b9f3cd747a268a10c2250
FINAL evidence  989e5ae02e66052ca7d2e46f5f452446300ba625dd4efd5cd6b5ffd9db2f2cd1
```

EVO2 доказал сквозной research route:

```text
causal evolution
    ↓
portable SpeciesCatalog
    ↓
hidden-target transfer
    ↓
environment generalization
    ↓
sorting vs continued adaptation
    ↓
replication + cross-seed robustness
    ↓
exact persistence / provenance restore
    ↓
precommitted unseen-world challenge
    ↓
EVO2 COMPLETE_RESEARCH_ONLY
```

Это research proof, а не production owner promotion.

## 3. XFER0 — Bounded Research-to-Simulator Contract — ACCEPTED

Exact code-under-test:

`bb80beac95d838b56cccbe5d98f7e1bcbfd80376`

Contract hash:

`06024c88fba045ba98e74594e55dce717d2c8dcd26f3d6a559a789bb5e39d309`

Aggregate:

`1adf3d0fa733ed74e3a28bfe1d0632f5d45c62ca5df932bce3e55693a18e9044`

Machine files:

```text
contract   1987dd67ae0755b4a00bc22f48a019837fb2066a
schema     8759a3e0832ae514df69ade5d6235b524bea84de
validator  1244d6dac0149957857a294b662738076ccc6e2d
tests      6afe9af777a976775fc3be4f68b5a91720e30474
runner     789bc1c17b2964bc1f71166e2a7a3725911566d6
```

Canonical Python evidence:

```text
Python compile                 PASS
contract validator             PASS
semantic regression            17 / 17 PASS
fresh runner A/B               PASS / PASS
exit codes                     0 / 0
logs                           byte-identical
log SHA-256                    9126f83e992e1d834e1e7e5317ec97cca174d1027a518310d70df6bd49ac47aa
```

Negative tests пересчитывают contract hash после semantic tamper, поэтому authority barriers проверяются независимо от простой checksum-защиты.

## 4. Six XFER0 interface surfaces

```text
SIMULATOR → ECO
ENVIRONMENT_INPUT

ECO → SIMULATOR
ECOLOGY_STATE_OUTPUT

ECO → WQ / presentation
QUERY_PROJECTION

ECO → persistence owner
PERSISTENCE_PAYLOAD

reference-only
IDENTITY_PROVENANCE

ECO → canonical lifecycle / transaction / authority owners
REPRESENTATION_PROMOTION_REQUEST
```

### ENVIRONMENT_INPUT

Read-only semantics: spatial/time keys, reference frame, temperature, moisture, light, nutrients, disturbance/flood pressure. ECO не пишет terrain/environment/material/time/spatial truth.

### ECOLOGY_STATE_OUTPUT

Population/cohort state остаётся ecology truth. Output — derived state/delta candidate, не право создавать planet-wide entity truth или выполнять world mutation.

### QUERY_PROJECTION

Только read-only derived view с source ecology revision/spatial/provenance identity. Presentation никогда не становится ecology truth.

### PERSISTENCE_PAYLOAD

ECO определяет typed payload/schema/provenance/restore validation. Canonical persistence owner сохраняет durability, commit point, distributed log и transaction semantics.

### IDENTITY_PROVENANCE

`research_species_id`, catalog/lineage/genome/evidence hashes можно reference/compare/audit, но нельзя автоматически повышать до canonical taxonomy или authority identity.

### REPRESENTATION_PROMOTION_REQUEST

ECO может только запросить promotion. Durable entity creation, authority assignment и transaction commit выполняют canonical world owners. Promoted representation не становится второй ecology truth.

## 5. Canonical foundation barrier

Concrete production API binding остаётся запрещённым в XFER0.

XFER1 ждёт main-owned canonical contracts:

```text
G
ENV
MAT
WQ
SD
TF
```

Binding state:

`UNRESOLVED_CANONICAL_CONTRACTS`.

Binding mode:

`SEMANTIC_ONLY_NO_PRODUCTION_API_BINDING`.

XFER0 не может копировать research DTO внутрь canonical owner, объявлять предполагаемый API canonical или использовать EVO2/XFER0 evidence как production authorization.

## 6. Current route — EVO3 research planning

```text
EVO2 portable ecology proof
        COMPLETE_RESEARCH_ONLY
        ↓
XFER0 bounded semantic/authority contract
        ACCEPTED
        ↓
EVO3 Planetary Ecology Compiler
        AUTHORIZED_RESEARCH_PLANNING_NOT_STARTED
```

EVO3 теперь может проектировать broader planetary generalization: какие ecology compilation stages нужны между canonical environment/world queries и population/cohort state. Но production runtime implementation пока не разрешён.

Параллельный production-binding gate:

```text
XFER1
BLOCKED_WAIT_CANONICAL_G_ENV_MAT_WQ_SD_TF
```

XFER1 должен получить explicit owner mapping, main-owned contracts и authority review до concrete binding.

## 7. Production P4 — отдельная governance-линия

EVO2 и XFER0 не меняют P4 production acceptance. P4 branch lifecycle evidence остаётся отдельной линией и не получает global/main acceptance из ECO research route.

Никакой XFER0 contract не может служить заменой independent Reviewer/Verifier или main-owned promotion decision.

## 8. Неподвижные ограничения

```text
research ecology != production world authority
SpeciesCatalog != canonical species taxonomy
population truth != planet-wide individual entity truth
representation != ecology truth
query/presentation != mutation authority
research persistence != production durability owner
XFER0 semantic contract != production API binding
EVO3 research planning != production runtime authorization
```

Главный принцип сохраняется:

> population is truth; individual is a representation unless canonical lifecycle/transaction authority explicitly promotes it to durable world state.

## 9. Current resolver

```text
OPEN / PLAN ECO.EVO3 PLANETARY ECOLOGY COMPILER — RESEARCH ONLY

DO NOT OPEN XFER1 PRODUCTION BINDING
UNTIL CANONICAL G / ENV / MAT / WQ / SD / TF OWNER CONTRACTS EXIST
```
