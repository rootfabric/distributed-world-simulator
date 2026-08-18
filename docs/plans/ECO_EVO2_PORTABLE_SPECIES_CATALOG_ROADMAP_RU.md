# ECO EVO2 — Portable SpeciesCatalog / Unseen World Roadmap

Статус: `COMPLETE / RESEARCH_ONLY / E2.1..E2.8 + E2.FINAL ACCEPTED / XFER0 HANDOFF ACCEPTED`.

Ветка: `feature/eco-evolutionary-ecology`.

Current central route: `docs/future_features/evolutionary_ecology/ECO_CENTRAL_ROUTE_RU.md`.  
Post-EVO2 contract: `docs/plans/ECO_XFER0_RESEARCH_SIMULATOR_CONTRACT_RU.md`.

## 0. Итог EVO2

EVO2 завершил plant-only portability proof:

```text
environment/history
        ↓
causal evolution / bake
        ↓
portable research SpeciesCatalog
        ↓
causal population ecology
        ↓
unseen environment transfer
        ↓
sorting + continued adaptation
        ↓
replication + cross-seed robustness
        ↓
exact persistence + provenance restore
        ↓
precommitted hidden unseen-world challenge
        ↓
EVO2 COMPLETE_RESEARCH_ONLY
```

Запрещённый shortcut на всём route оставался:

```text
biome -> hand-written species list -> scatter
```

EVO2 не стал production ecology owner и не создал canonical species taxonomy.

## 1. Frozen accepted lineage

```text
EVO1/P2.8
ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6

P3.8
6132820a5c6597765b4f3abeeb8cf9fc9e6aaffb90ba83a1263997b17fc6f3a0

E2.1
aa23bc269738ace132fb1386ec01b339cc7fd82e1238223c1075b60dac5896ad

E2.2
56d4b8bfd3064ad37b720d5bff2bc98bb72b0ab7ad871877fc268d5e6df703ce

E2.2 bake
45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b

E2.2 catalog
5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219

E2.3
82d76f858568d5bd53af4d299abd2155f2fde7e845de828cf4555e601ee1efa8

E2.4
ae2952de10ac721c8052694963b690d9f72af05d9c92e2fa4cd70e00f72fb2b5

E2.5
942ad54e7672c4f57874e1802b320c1b2a4aa74e43b05f7e285793ea4ec8b2a6

E2.6
1a4bcf1cffe65450a27037e9307bb5c7ac3cb8a98899918207107e367d9d5fbd

E2.7
eb3b30919114cb9971b7413f416a3ae07eb50aebe81801454aaa310d6e879c7d

E2.8 aggregate
4182176c1cc8b6d609fefc7057b5ff5307c92f839682e76f6168841d60275061

E2.8 content
3d7ca34560483e2a4d1eb1955c008eb1f05ab3603e3d358abbf4823b33554e2e

E2.8 provenance
a3a2f53107cefc5c96d835bd93327864d45f31e55b123fcd2fe4053fd5495a15

E2.8 transport
b31c863f8e1943e5778d56631f8c8ad75b95f3b9d3930a699f80fd07595d45d1

E2.FINAL aggregate
6daab256af3d1e7693c66a8afaad4d04fd1564c4376b9f3cd747a268a10c2250

E2.FINAL evidence
989e5ae02e66052ca7d2e46f5f452446300ba625dd4efd5cd6b5ffd9db2f2cd1
```

Production P4 remains a separate governance lineage.

## 2. Accepted checkpoint route

```text
E2.1  SpeciesCatalog Contract                         ACCEPTED
E2.2  Deterministic Evolution Bake Export             ACCEPTED
E2.3  Frozen-Catalog Transfer                         ACCEPTED
E2.4  Environment Generalization Matrix               ACCEPTED
E2.5  Ecological Sorting vs Continued Adaptation      ACCEPTED
E2.6  Replicated Causal Experiments                   ACCEPTED
E2.7  Cross-Seed Robustness                           ACCEPTED
E2.8  Catalog Persistence & Provenance                ACCEPTED
E2.FINAL Unseen World Challenge                       ACCEPTED
```

Per-checkpoint exact implementation/evidence history остаётся в `validation/ecology/**` и `docs/checkpoints/**`; этот документ теперь служит durable summary завершённого EVO2 route.

## 3. Species concept policy

`research_species_id` — portable research lineage/species hypothesis identity.

Он сохраняется через transfer, adaptation, replication и persistence, но не становится автоматически:

- canonical biological taxonomy;
- durable world entity identity;
- authority identity;
- production content/asset selector.

## 4. E2.FINAL — accepted closure

Exact code-under-test:

`376796ab8c8370b7370fcd220ed207d07955cb42`.

Hidden world/protocol был precommitted до первого result:

`d936efac36d2664ec2f24f26306fa3ba95409117`.

FINAL использовал именно fresh-restored E2.8 persisted artifact, а не direct catalog reconstruction.

Observed result:

```text
reachable hidden patches colonized   2 / 2
restored species recruited            2
isolated control                      VALID_NO_COLONIZATION
sorting observed                      2 / 2 cells
continued adaptation positive         2 / 2 cells
assertions                            68 / 68 PASS
fresh logs                            byte-identical
```

No rebake, target-aware species filter или biome species table использовались.

Accepted checkpoint:

`docs/checkpoints/2026-08-18_ECO_EVO2_FINAL_UNSEEN_WORLD_CHALLENGE_ACCEPTED_RU.md`.

Validation:

`validation/ecology/eco-evo2-final-unseen-world-validation.json`.

## 5. Post-EVO2 handoff — XFER0 — ACCEPTED

EVO2 не был сразу связан с production API. Вместо этого следующий bounded checkpoint заморозил semantic/authority boundary.

Exact XFER0 code-under-test:

`bb80beac95d838b56cccbe5d98f7e1bcbfd80376`.

Contract hash:

`06024c88fba045ba98e74594e55dce717d2c8dcd26f3d6a559a789bb5e39d309`.

Aggregate:

`1adf3d0fa733ed74e3a28bfe1d0632f5d45c62ca5df932bce3e55693a18e9044`.

XFER0 фиксирует шесть surfaces:

```text
ENVIRONMENT_INPUT
ECOLOGY_STATE_OUTPUT
QUERY_PROJECTION
PERSISTENCE_PAYLOAD
IDENTITY_PROVENANCE
REPRESENTATION_PROMOTION_REQUEST
```

Все production bindings имеют режим:

`SEMANTIC_ONLY_NO_PRODUCTION_API_BINDING`.

Canonical foundation dependencies перед XFER1:

`G / ENV / MAT / WQ / SD / TF`.

Validation:

```text
Python compile                 PASS
contract validator             PASS
semantic tests                 17 / 17 PASS
fresh canonical runner A/B     PASS / PASS
logs                           byte-identical
SHA-256                        9126f83e992e1d834e1e7e5317ec97cca174d1027a518310d70df6bd49ac47aa
```

Accepted XFER0 checkpoint:

`docs/checkpoints/2026-08-18_ECO_XFER0_BOUNDED_RESEARCH_SIMULATOR_CONTRACT_ACCEPTED_RU.md`.

Machine validation:

`validation/ecology/eco-xfer0-bounded-contract-validation.json`.

## 6. Authority boundary after EVO2

ECO research retains ecology semantics, research SpeciesCatalog semantics, population/cohort meaning and lineage/adaptation provenance.

ECO does **not** own canonical:

```text
terrain/geology truth
environment truth
material ontology
world query fabric
spatial-domain fabric
time fabric
generic population runtime
world lifecycle/work budget
authority/network policy
production persistence durability
world transaction model
canonical taxonomy
presentation as truth
planet-wide individual entity truth
```

Population state remains ecology truth. Durable representation can appear only through explicit canonical lifecycle/transaction/authority promotion, and cannot become a second ecology truth.

## 7. Current next route

После accepted XFER0 можно открыть только research planning следующего направления:

```text
EVO3 — Planetary Ecology Compiler / broader planetary generalization
STATUS: AUTHORIZED_RESEARCH_PLANNING_NOT_STARTED
```

EVO3 должен спроектировать compilation pipeline от canonical environment/world-query semantics к ecology population/cohort semantics на планетарном масштабе, сохраняя bounded authority model XFER0.

Это не production runtime authorization.

## 8. XFER1 остаётся blocked

Concrete simulator binding не открыт:

```text
XFER1
BLOCKED_WAIT_CANONICAL_G_ENV_MAT_WQ_SD_TF
```

До XFER1 нужны:

- main-owned canonical foundation contracts;
- explicit owner mapping;
- authority review;
- отдельное решение о concrete production binding.

XFER0 нельзя трактовать как production authorization.

## 9. Production P4 остаётся отдельным

EVO2 completion и XFER0 acceptance не принимают и не promote P4. Production integration использует собственный Harness / review / verifier / main-owned promotion route.

## 10. Historical closure / current execution

```text
EVO2              COMPLETE_RESEARCH_ONLY
XFER0              ACCEPTED_BOUNDED_DESIGN
EVO3               AUTHORIZED_RESEARCH_PLANNING_NOT_STARTED
XFER1              BLOCKED_WAIT_CANONICAL_G_ENV_MAT_WQ_SD_TF
```

Current execution moved out of EVO2 implementation. Дальнейшая research работа должна идти через EVO3 planning; этот EVO2 документ остаётся summary принятой portable-ecology lineage и её bounded XFER0 handoff.
