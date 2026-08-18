# ECO EVO2 — Portable SpeciesCatalog / Unseen World Roadmap

Статус: `ACTIVE / RESEARCH_ONLY / E2.1..E2.7 ACCEPTED / E2.8 AUTHORIZED_NOT_STARTED`.

Ветка: `feature/eco-evolutionary-ecology`.

## 0. Назначение

EVO2 превращает результат эволюционного исследования в переносимый ecological artifact:

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
```

P4 production-integration evidence остаётся отдельной governance-линией и не даёт EVO2 production authority.

## 2. Species concept policy

`research_species_id` — стабильная identity portable lineage hypothesis внутри research pipeline.

Ни E2.5 adaptation, ни E2.6 replication, ни E2.7 robustness не превращают adapted descendants автоматически в canonical biological species.

## 3. Accepted route E2.1–E2.6

```text
E2.1 SpeciesCatalog Contract                         ACCEPTED
E2.2 Deterministic Evolution Bake Export             ACCEPTED
E2.3 Frozen-Catalog Transfer                         ACCEPTED
E2.4 Environment Generalization Matrix               ACCEPTED
E2.5 Ecological Sorting vs Continued Adaptation      ACCEPTED
E2.6 Replicated Causal Experiments                   ACCEPTED
```

Ключевые доказательства:

- E2.3: hidden-target transfer и causal reachability;
- E2.4: один frozen catalog через six environment/geography classes;
- E2.5: pure ecological sorting отделён от continued inherited adaptation;
- E2.6: paired causal effect повторён на заранее объявленных `R01..R05`, включая обязательное сохранение null/reversal outcomes.

## 4. E2.7 — Cross-Seed Robustness — ACCEPTED

Exact code-under-test:

`52f31ca58a77296d63b1642954659edcbd12b8fe`

Validation:

`validation/ecology/eco-evo2-e2-7-cross-seed-robustness-validation.json`

Accepted checkpoint:

`docs/checkpoints/2026-08-18_ECO_EVO2_E2_7_CROSS_SEED_ROBUSTNESS_ACCEPTED_RU.md`

### 4.1 Research contract

E2.7 сохранил exact causal mechanism E2.5/E2.6 и изменил только seed-family namespace:

```text
same frozen E2.2 catalog/genomes
same DRY/WET environments
same Control/Treatment policy
same MutationKernel
same ResourceModel
same generations/population/offspring
        +
new predeclared S01..S10 seed ensemble
```

Predeclared thresholds:

```text
positive effect             >= 8 / 10 per cell
reciprocal home advantage   >= 8 / 10 per cell
full seed pass              >= 7 / 10
q25 effect                  > 0
median effect               > 0
leave-one-out minimum mean  > 0
```

После freeze нельзя удалять или переставлять seeds.

### 4.2 Architecture

E2.7 разделён на три research modules:

```text
plant_cross_seed_robustness_v1.gd
    orchestration / parent pins / bounded verdict

plant_cross_seed_protocol_v1.gd
    causal Control/Treatment execution

plant_cross_seed_evidence_v1.gd
    semantic replay validation / robust aggregates
```

Exact blobs:

```text
orchestrator  f980a6132835cd2c483d5210615579ddccf7e618
protocol      8d28fb09ac6e3f8b46594b39f76db69c2b6f9b17
evidence      940ed657b7aa85758ac33088634d1ce5fdc4e673
test          334a833acd1d0bc32ee03f0977d764ff5e517196
runner        6da8290ec1944d704a778e3b1ce8910260e5b5cb
```

### 4.3 Accepted behavioral evidence

```text
exact transitive GDScript closure   9 / 9 PASS
Godot                               4.7.1.stable.double.custom_build.a13da4feb
parser/preload                      PASS
fresh processes                     2 / 2 PASS
assertions                          290 / 290 PASS
ERROR lines                         0 / 0
logs                                byte-identical
log SHA-256                         51c421e5e3f909cc265bd8180fa1bd9a56f1f5e3a1e727a5010a5667d40156a9
aggregate                           eb3b30919114cb9971b7413f416a3ae07eb50aebe81801454aaa310d6e879c7d
seed ensemble                       a49ce9d6856e08e1e0a61f060a8019de61685cdc63b25229b3761c9e7c9d792f
```

Published GitHub bytes были заново восстановлены и сверены по exact Git blob SHA перед behavioral verification; локальный pre-publication probe не использовался как acceptance authority.

### 4.4 Distribution result

```text
DRY
mean                 0.229458431680
median               0.227109019511
q25                  0.218691252321
q75                  0.230928849977
min                  0.186805390360
max                  0.279412047042
positive/null/rev    10 / 0 / 0
home advantage       10 / 10
LOO minimum mean     0.223908029973
aggregate            f3b65f8c890c75243f9a089f6f3036ef937c7251d675c0fd6919f06b00522c3f

WET
mean                 0.386587470375
median               0.388500039215
q25                  0.368469916498
q75                  0.391244612251
min                  0.345047365361
max                  0.425056726888
positive/null/rev    10 / 0 / 0
home advantage       10 / 10
LOO minimum mean     0.382313108540
aggregate            98020ab8f6bb8fb52775ac4796bc2f45ea16530e468c5324b5716f598af4989b
```

Observed 10/10 не заменяет frozen acceptance thresholds.

### 4.5 Integrity

Acceptance rejects even after rehash:

- seed deletion;
- seed reordering;
- adaptation-effect semantic tamper;
- formal-significance promotion;
- cross-catalog robustness promotion;
- production-authority promotion.

Final-population semantics пересчитываются через exact ResourceModel, поэтому наружной hash-цепочки недостаточно для подделки causal result.

### 4.6 Claim boundary

Accepted claim:

`BOUNDED_CROSS_SEED_ROBUSTNESS_FOR_ONE_FROZEN_CATALOG_AND_PROTOCOL`.

Не accepted:

```text
formal statistical significance
cross-catalog / cross-bake robustness
production persistence/runtime authority
canonical species taxonomy
```

Canonical `.ps1` runner не исполнялся из-за отсутствия PowerShell в Linux carrier. Authority: `EXPLICIT_EQUIVALENT_FRESH_BEHAVIORAL_EXECUTION`. Independent Reviewer/Verifier PASS не заявляется.

## 5. E2.8 — Catalog Persistence & Provenance — AUTHORIZED / CURRENT

### 5.1 Research question

Portable ecology доказана в памяти процесса. Теперь нужно доказать, что сам portable research artifact можно детерминированно сохранить, передать и восстановить без потери identity/provenance.

```text
accepted SpeciesCatalog + accepted EVO2 lineage
        ↓
canonical serializer
        ↓
typed persistent artifact
        ↓
bytes/hash/schema/version
        ↓
fresh-process restore
        ↓
exact semantic identity
```

### 5.2 Required persisted content

Минимум:

- catalog schema/version/hash;
- ordered species entries;
- exact `research_species_id`;
- source lineage IDs;
- frozen genome payload/checksum;
- E2.2 bake/catalog parent hashes;
- accepted E2.3/E2.4/E2.5/E2.6/E2.7 evidence identities;
- persistence schema/version;
- canonical content hash.

### 5.3 Determinism requirements

Одинаковый input должен давать:

```text
identical semantic object
identical canonical bytes
identical content hash
identical restore result
```

Это должно подтверждаться fresh processes.

### 5.4 Version policy

E2.8 обязан fail-closed различать минимум:

```text
CURRENT_VERSION       accepted
KNOWN_COMPATIBLE      only if explicitly declared
UNKNOWN_NEWER         reject
MALFORMED             reject
WRONG_SCHEMA          reject
```

Нельзя молча принимать незнакомую будущую schema.

### 5.5 Tamper gates

Нужны как минимум:

- byte corruption;
- outer hash corruption;
- genome mutation с пересчётом outer hash;
- species/lineage identity substitution;
- provenance parent substitution;
- field insertion/removal;
- version/schema substitution;
- reordered entries, если order canonical.

Semantic tamper должен отвергаться даже при корректно пересчитанном transport/content hash.

### 5.6 Scope boundary

Это **research artifact persistence proof**, а не ownership production persistence subsystem.

E2.8 не может заявлять:

- production save authority;
- distributed durability;
- canonical taxonomy;
- world transaction semantics.

EVO2 FINAL остаётся blocked до E2.8 acceptance.

## 6. EVO2 FINAL — Unseen World Challenge

После E2.8 можно открыть финальное сквозное доказательство:

```text
hidden unseen world
        +
restored persisted frozen SpeciesCatalog/provenance
        ↓
no rebake / no biome species table
        ↓
causal colonization / ecology / adaptation
        ↓
reproducible evidence package
```

## 7. После EVO2

```text
EVO2 portable ecology proof
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

## 8. Current execution

```text
CURRENT = OPEN / IMPLEMENT ECO.EVO2 / E2.8 Catalog Persistence & Provenance
NEXT    = EVO2 FINAL Unseen World Challenge after E2.8 acceptance
```
