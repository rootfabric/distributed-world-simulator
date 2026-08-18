# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO2 FINAL AUTHORIZED_NOT_STARTED`.

Canonical North Star: `docs/future_features/evolutionary_ecology/ECO_EVOLUTIONARY_ECOSYSTEM_VISION_RU.md`.  
Machine roadmap: `config/ecology/eco-evolutionary-ecology-roadmap.v1.json`.  
EVO2 plan: `docs/plans/ECO_EVO2_PORTABLE_SPECIES_CATALOG_ROADMAP_RU.md`.

Последние accepted checkpoints:

- E2.1 SpeciesCatalog Contract;
- E2.2 Deterministic Evolution Bake Export;
- E2.3 Frozen-Catalog Transfer;
- E2.4 Environment Generalization Matrix;
- E2.5 Ecological Sorting vs Continued Adaptation;
- E2.6 Replicated Causal Experiments;
- E2.7 Cross-Seed Robustness;
- E2.8 Catalog Persistence & Provenance — `docs/checkpoints/2026-08-18_ECO_EVO2_E2_8_CATALOG_PERSISTENCE_PROVENANCE_ACCEPTED_RU.md`.

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
ECO.EVO2 / E2.FINAL       AUTHORIZED_NOT_STARTED
```

Frozen identities:

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
```

## 2. Что теперь доказано EVO2

```text
frozen evolved catalog
        ↓
hidden target transfer                 E2.3
        ↓
environment generalization             E2.4
        ↓
sorting separated from adaptation      E2.5
        ↓
paired causal replication              E2.6
        ↓
cross-seed robustness                  E2.7
        ↓
exact catalog persistence/provenance   E2.8
```

Portable ecology теперь доказана не только внутри одного процесса: полный accepted E2.2 SpeciesCatalog и его accepted EVO2 provenance детерминированно сериализуются, записываются, передаются и восстанавливаются в fresh processes без изменения semantic identity.

## 3. E2.8 — Catalog Persistence & Provenance — ACCEPTED

Exact code-under-test:

`5790de059aaafbfc10434bb2d40124e3c1ceb361`

Validation:

`validation/ecology/eco-evo2-e2-8-catalog-persistence-validation.json`

Persistence contract:

```text
schema      distributed_world_simulator.ecology.evo2_catalog_persistence.v1
version     1.0.0
encoding    GODOT_VARIANT_BINARY_CANONICAL_V1
artifact    10383 bytes
```

Exact outputs:

```text
aggregate     4182176c1cc8b6d609fefc7057b5ff5307c92f839682e76f6168841d60275061
content       3d7ca34560483e2a4d1eb1955c008eb1f05ab3603e3d358abbf4823b33554e2e
provenance    a3a2f53107cefc5c96d835bd93327864d45f31e55b123fcd2fe4053fd5495a15
transport     b31c863f8e1943e5778d56631f8c8ad75b95f3b9d3930a699f80fd07595d45d1
catalog       5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219
bake id       eco-evo2-bake/ff406486cc83bb8217d66213
```

Verification:

```text
exact transitive GDScript closure   9 / 9 PASS
parser/preload                      PASS
acceptance                          74 / 74 PASS
fresh acceptance A/B                byte-identical
fresh writer A/B                    byte-identical
persisted artifacts A/B             byte-identical
fresh restore A/B                   byte-identical
restored semantic identity          exact
ERROR lines                         0 in every process
```

E2.8 сохраняет **полный accepted SpeciesCatalog**, включая ordered entries, research species IDs, source lineages/ancestry, frozen genomes, recruitment traits, source observation hashes, entry hashes, catalog hash и bake identity. Provenance фиксирует E2.1..E2.7 и явно сохраняет факт, что исходный E2.2 source является synthetic contract fixture, а не реальным accepted evolution result.

Tamper gates reject byte/hash corruption, genome mutation, species/lineage substitution, provenance substitution, field insertion/removal, wrong schema, unknown future version, canonical entry reordering и catalog identity substitution — в том числе после пересчёта nested/content/transport hashes.

### Claim boundary

E2.8 доказывает **research artifact persistence**.

Он не даёт:

- production save authority;
- ownership production persistence subsystem;
- distributed durability;
- world transaction semantics;
- canonical species taxonomy.

Canonical PowerShell runner существует, но в Linux carrier нет `pwsh/powershell`; acceptance authority — `EXPLICIT_EQUIVALENT_FRESH_BEHAVIORAL_EXECUTION`. Independent Reviewer/Verifier PASS не заявляется.

## 4. Current research route

```text
E2.1 SpeciesCatalog Contract                         ACCEPTED
    ↓
E2.2 Deterministic Evolution Bake Export             ACCEPTED
    ↓
E2.3 Frozen-Catalog Transfer                         ACCEPTED
    ↓
E2.4 Environment Generalization Matrix               ACCEPTED
    ↓
E2.5 Ecological Sorting vs Continued Adaptation      ACCEPTED
    ↓
E2.6 Replicated Causal Experiments                   ACCEPTED
    ↓
E2.7 Cross-Seed Robustness                           ACCEPTED
    ↓
E2.8 Catalog Persistence & Provenance                ACCEPTED
    ↓
EVO2 FINAL — Unseen World Challenge                  ← AUTHORIZED / NEXT
```

## 5. EVO2 FINAL — Unseen World Challenge

Финальный checkpoint должен собрать весь EVO2 route в одно end-to-end доказательство:

```text
hidden unseen world
        +
restored persisted frozen SpeciesCatalog/provenance
        ↓
NO rebake
NO biome species table
NO target-aware species injection
        ↓
causal colonization / sorting / adaptation
        ↓
replicated deterministic evidence package
```

Минимальные условия FINAL:

1. hidden target/world definition фиксируется до результата;
2. единственный catalog input — restored E2.8 artifact;
3. никакого rebake или изменения frozen catalog перед transfer;
4. colonization должна быть causal, через ранее accepted ecology mechanisms;
5. adaptation/sorting interpretation сохраняет E2.5 causal distinction;
6. null/reversal/no-colonization outcomes не цензурируются;
7. fresh-process deterministic evidence package;
8. final proof не захватывает production runtime/world authority.

EVO2 нельзя объявлять complete до acceptance этого checkpoint.

## 6. Production P4 — отдельная governance-линия

P4 branch lifecycle завершён, но это не global/main acceptance и не runtime merge. Нужны independent review/verifier freshness и main-owned promotion decision. EVO2 не получает production authority из P4.

## 7. Неподвижные ограничения

```text
research ecology != production world authority
SpeciesCatalog != canonical species taxonomy
adapted descendant != automatic canonical species
research persistence != production persistence authority
population truth != planet-wide individual entity truth
representation != ecology truth
```

Главный runtime principle остаётся:

> population is truth; individual is a representation unless interaction promotes it to durable world state.

## 8. Current resolver

```text
OPEN / IMPLEMENT ECO.EVO2 / E2.FINAL UNSEEN WORLD CHALLENGE
```
