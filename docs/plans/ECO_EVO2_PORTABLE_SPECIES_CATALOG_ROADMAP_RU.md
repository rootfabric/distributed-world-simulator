# ECO EVO2 — Portable SpeciesCatalog / Unseen World Roadmap

Статус: `ACTIVE / RESEARCH_ONLY / E2.1..E2.8 ACCEPTED / E2.FINAL AUTHORIZED_NOT_STARTED`.

Ветка: `feature/eco-evolutionary-ecology`.

## 0. Назначение

EVO2 превращает результат эволюционного исследования в переносимый ecological artifact и доказывает, что его можно применить к unseen world без biome-species shortcut:

```text
environment
    ↓
evolution / bake
    ↓
SpeciesCatalog
    ↓
causal population ecology
    ↓
unseen environments
    ↓
sorting + adaptation + robustness
    ↓
canonical research persistence / restore
    ↓
FINAL hidden unseen-world proof
```

Запрещён shortcut:

```text
biome -> hand-written species list -> scatter
```

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
```

P4 production-integration evidence остаётся отдельной governance-линией и не даёт EVO2 production authority.

## 2. Species concept policy

`research_species_id` — стабильная identity portable lineage hypothesis внутри research pipeline.

Ни adaptation, ни replication, ни robustness, ни persistence не превращают descendants автоматически в canonical biological species.

## 3. Accepted route E2.1–E2.7

```text
E2.1 SpeciesCatalog Contract                         ACCEPTED
E2.2 Deterministic Evolution Bake Export             ACCEPTED
E2.3 Frozen-Catalog Transfer                         ACCEPTED
E2.4 Environment Generalization Matrix               ACCEPTED
E2.5 Ecological Sorting vs Continued Adaptation      ACCEPTED
E2.6 Replicated Causal Experiments                   ACCEPTED
E2.7 Cross-Seed Robustness                           ACCEPTED
```

Ключевые доказательства:

- E2.3: hidden-target transfer и causal reachability;
- E2.4: один frozen catalog через six environment/geography classes;
- E2.5: pure ecological sorting отделён от continued inherited adaptation;
- E2.6: paired causal effect повторён на заранее объявленных `R01..R05`, null/reversal outcomes сохраняются;
- E2.7: отдельный predeclared `S01..S10` ensemble показал bounded robustness без cherry-picking.

## 4. E2.8 — Catalog Persistence & Provenance — ACCEPTED

Exact code-under-test:

`5790de059aaafbfc10434bb2d40124e3c1ceb361`

Validation:

`validation/ecology/eco-evo2-e2-8-catalog-persistence-validation.json`

Accepted checkpoint:

`docs/checkpoints/2026-08-18_ECO_EVO2_E2_8_CATALOG_PERSISTENCE_PROVENANCE_ACCEPTED_RU.md`

### 4.1 Research contract

E2.8 сохраняет и восстанавливает **полный accepted E2.2 SpeciesCatalog**, а не проекцию:

```text
full accepted SpeciesCatalog
+ accepted EVO2 provenance E2.1..E2.7
        ↓
canonical typed Variant serialization
        ↓
content hash + transport hash + schema/version
        ↓
persist to bytes
        ↓
fresh-process restore
        ↓
exact semantic identity
```

### 4.2 Persistence format

```text
schema    distributed_world_simulator.ecology.evo2_catalog_persistence.v1
version   1.0.0
encoding  GODOT_VARIANT_BINARY_CANONICAL_V1
magic     DWS-ECO-EVO2-E2.8-CATALOG-PERSISTENCE-V1
```

Typed Variant binary используется сознательно, чтобы сохранить точную Variant semantics (`int`, `float`, `bool`) и не зависеть от JSON type coercion. Dictionary keys canonicalized before serialization. Outer envelope содержит binary SHA-256 и canonical Base64; restore выполняет transport validation до semantic decode.

Version policy fail-closed:

```text
CURRENT_VERSION       ACCEPT
KNOWN_COMPATIBLE      only if explicitly declared
UNKNOWN_NEWER         REJECT
UNDECLARED_OLDER      REJECT
MALFORMED             REJECT
WRONG_SCHEMA          REJECT
```

На E2.8 список `KNOWN_COMPATIBLE` пуст.

### 4.3 Exact artifacts

```text
accepted catalog carrier   b77c3421325fa1264f590b0bd75c1c59621f667f
provenance carrier         5602607fa3b63e79da28d8da52cb3ba5f61960c1
persistence codec          83f80afe9fd467f7718f487b70f6bf1a88521339
tamper support             227c57ff4f25c80dc3fa35e99f0e4fe791620eb7
acceptance                 8e0f0d2ba6eea03337f6559276da87cf5f689d4b
writer                     32f85fc1809af8c094227ecc702dbbc8e7e94608
restore                    5d7c698a8e30a6be9622ddd9c5c08f02feac351e
runner                     4e75eff15351ca3ba2c9229f8b7b39937c77834e
```

### 4.4 Accepted behavioral evidence

```text
exact transitive GDScript closure   9 / 9 PASS
Godot                               4.7.1.stable.double.custom_build.a13da4feb
parser/preload                      PASS
acceptance assertions               74 / 74 PASS
acceptance A/B                      byte-identical
acceptance log SHA-256              9c4e541105d1b6738231a6253ea522ebccc0846f552a30733744f0c34cd32505
writer A/B                          byte-identical
writer log SHA-256                  6ab0f1aef6a05d9e3e51fc8595d512df39b7d3aeb436d547b595ea1c6c2c912a
persisted artifacts A/B             byte-identical
artifact bytes                      10383
artifact SHA-256                    b31c863f8e1943e5778d56631f8c8ad75b95f3b9d3930a699f80fd07595d45d1
restore A/B                         byte-identical
restore log SHA-256                 fe46af6ff410cc335cdb6801cfad59fe6715857aeae7f97b7039204558e78d03
restored semantic identity          exact
ERROR lines                         0 in every verification process
```

Frozen semantic identities:

```text
aggregate     4182176c1cc8b6d609fefc7057b5ff5307c92f839682e76f6168841d60275061
content       3d7ca34560483e2a4d1eb1955c008eb1f05ab3603e3d358abbf4823b33554e2e
provenance    a3a2f53107cefc5c96d835bd93327864d45f31e55b123fcd2fe4053fd5495a15
catalog       5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219
bake id       eco-evo2-bake/ff406486cc83bb8217d66213
parent E2.7   eb3b30919114cb9971b7413f416a3ae07eb50aebe81801454aaa310d6e879c7d
```

### 4.5 Persisted semantic identity

Full catalog restore сохраняет:

- canonical entry order;
- both exact `research_species_id` values;
- source lineage + ancestry;
- frozen genome payload/checksum;
- recruitment traits/checksum;
- source observation hashes;
- entry hashes;
- exact catalog hash;
- exact E2.2 bake id/source identity.

Provenance сохраняет E2.1..E2.7 identities и явную границу: E2.2 source — synthetic contract fixture; он не impersonates real accepted evolution result.

### 4.6 Integrity

Acceptance reject even after rehash:

- byte corruption;
- transport hash corruption;
- content hash corruption;
- genome semantic mutation;
- species/lineage substitution;
- provenance parent substitution;
- extra/missing artifact fields;
- extra SpeciesCatalog entry field;
- wrong schema;
- future unknown version;
- reordered canonical entries;
- catalog identity substitution.

Build/serialize не потребляют global RNG.

### 4.7 Claim boundary

Accepted claim:

`RESEARCH_ARTIFACT_PERSISTENCE_WITH_EXACT_FULL_SPECIES_CATALOG_AND_EVO2_PROVENANCE_IDENTITY`.

Не accepted:

```text
production save authority
production persistence ownership
distributed durability
world transaction semantics
canonical species taxonomy
```

Canonical `.ps1` runner не исполнялся из-за отсутствия PowerShell в Linux carrier. Authority: `EXPLICIT_EQUIVALENT_FRESH_BEHAVIORAL_EXECUTION`. Independent Reviewer/Verifier PASS не заявляется.

## 5. EVO2 FINAL — Unseen World Challenge — AUTHORIZED / CURRENT

### 5.1 Research question

Может ли **именно восстановленный persisted frozen SpeciesCatalog** пройти полный unseen-world route без rebake, target-aware species injection и biome table shortcut?

### 5.2 Final experiment shape

```text
predeclared hidden unseen world
        +
E2.8 persisted artifact bytes
        ↓
fresh-process restore
        ↓
exact frozen SpeciesCatalog + provenance
        ↓
E2.3/E2.4-compatible causal transfer
        ↓
ecology + sorting + continued adaptation
        ↓
replicated deterministic final evidence
```

### 5.3 Hard gates

1. target/world definition frozen before result;
2. catalog input must originate from E2.8 restore, not direct reconstruction bypass;
3. restored `catalog_hash`, entries and provenance must match E2.8 accepted identity;
4. no evolution rebake before transfer;
5. no target-aware species list/filter/injection;
6. no biome → species table;
7. colonization must emerge through accepted causal dispersal/establishment/population mechanisms;
8. sorting and continued adaptation must remain separable according to E2.5 semantics;
9. null/reversal/no-colonization outcomes remain valid evidence and cannot be censored;
10. deterministic fresh-process result/evidence package;
11. semantic tamper of persisted input must fail closed;
12. FINAL does not grant production runtime/world/persistence authority.

### 5.4 Acceptance meaning

E2.FINAL acceptance may close **EVO2 research route**, but still does not merge any production integration or make P4 globally accepted.

## 6. После EVO2

```text
EVO2 portable persisted ecology proof
    ↓
bounded XFER0 contracts
    ↓
EVO3 Planetary Ecology Compiler
    ↓
plant runtime convergence
    ↓
herbivores
    ↓
predators / food web / coevolution
```

Animals остаются deferred до plant-only portability proof.

## 7. Current execution

```text
CURRENT = OPEN / IMPLEMENT ECO.EVO2 / E2.FINAL Unseen World Challenge
NEXT    = EVO2 completion decision only after E2.FINAL acceptance
```
