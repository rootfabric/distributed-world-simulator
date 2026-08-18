# ECO EVO2 — Portable SpeciesCatalog / Unseen World Roadmap

Статус: `COMPLETE / RESEARCH_ONLY / E2.1..E2.8 + E2.FINAL ACCEPTED`.

Ветка: `feature/eco-evolutionary-ecology`.

## 0. Итог EVO2

EVO2 завершил research-only route от evolved lineage hypotheses до persisted portable SpeciesCatalog, способного пройти заранее зафиксированный unseen-world challenge без biome-species shortcut:

```text
environment / evolution
        ↓
deterministic research SpeciesCatalog
        ↓
frozen-catalog transfer
        ↓
environment generalization
        ↓
sorting vs continued adaptation
        ↓
replicated causal experiments
        ↓
cross-seed robustness
        ↓
canonical research persistence / restore
        ↓
precommitted hidden unseen world
        ↓
causal colonization + sorting + adaptation
```

Запрещённый shortcut не использовался:

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

E2.FINAL aggregate
6daab256af3d1e7693c66a8afaad4d04fd1564c4376b9f3cd747a268a10c2250

E2.FINAL evidence
989e5ae02e66052ca7d2e46f5f452446300ba625dd4efd5cd6b5ffd9db2f2cd1
```

P4 production-integration evidence остаётся отдельной governance-линией и не даёт EVO2 production authority.

## 2. Accepted route

```text
E2.1 SpeciesCatalog Contract                         ACCEPTED
E2.2 Deterministic Evolution Bake Export             ACCEPTED
E2.3 Frozen-Catalog Transfer                         ACCEPTED
E2.4 Environment Generalization Matrix               ACCEPTED
E2.5 Ecological Sorting vs Continued Adaptation      ACCEPTED
E2.6 Replicated Causal Experiments                   ACCEPTED
E2.7 Cross-Seed Robustness                           ACCEPTED
E2.8 Catalog Persistence & Provenance                ACCEPTED
E2.FINAL Unseen World Challenge                      ACCEPTED
```

Ключевые ступени:

- E2.3 доказал hidden-target transfer и causal reachability;
- E2.4 прогнал один frozen catalog через multiple environment/geography classes;
- E2.5 отделил ecological sorting от continued inherited adaptation;
- E2.6 повторил paired causal effect на predeclared replicate set;
- E2.7 доказал bounded cross-seed robustness без cherry-picking;
- E2.8 доказал exact typed persistence/restore полного SpeciesCatalog и provenance;
- E2.FINAL связал persisted artifact с precommitted unseen world end-to-end.

## 3. Species concept policy

`research_species_id` — стабильная identity portable lineage hypothesis внутри research pipeline.

Ни adaptation, ни replication, ни robustness, ни persistence, ни FINAL challenge не превращают research descendants автоматически в canonical biological species.

```text
research species identity != canonical taxonomy
```

## 4. E2.8 persistence boundary

E2.8 сохраняет и восстанавливает полный accepted E2.2 SpeciesCatalog и accepted EVO2 provenance:

```text
schema    distributed_world_simulator.ecology.evo2_catalog_persistence.v1
version   1.0.0
encoding  GODOT_VARIANT_BINARY_CANONICAL_V1
artifact  10383 bytes
SHA-256   b31c863f8e1943e5778d56631f8c8ad75b95f3b9d3930a699f80fd07595d45d1
```

Exact semantic identity после restore:

- ordered catalog entries;
- `research_species_id`;
- lineage + ancestry;
- frozen genome payload/checksum;
- recruitment traits/checksum;
- source observation hashes;
- entry hashes;
- catalog hash;
- bake/source identity;
- E2.1..E2.7 provenance;
- explicit synthetic-fixture boundary E2.2.

E2.8 acceptance: 74/74 assertions, fresh writer/restore A/B byte-identical, semantic tamper fail-closed.

## 5. E2.FINAL — Unseen World Challenge — ACCEPTED

Validation:

`validation/ecology/eco-evo2-final-unseen-world-validation.json`

Checkpoint:

`docs/checkpoints/2026-08-18_ECO_EVO2_FINAL_UNSEEN_WORLD_CHALLENGE_ACCEPTED_RU.md`

Exact code-under-test:

`376796ab8c8370b7370fcd220ed207d07955cb42`

### 5.1 Protocol frozen before result

Hidden-world protocol был committed отдельно до первого behavioral result:

```text
protocol precommit  d936efac36d2664ec2f24f26306fa3ba95409117
protocol blob       372591ee3bee1c19538729259373e97fd9838461
protocol hash       d3dc2b0c2a251cf645d03430eb14ad2215166a5be03f5ec13b8eafb4d56678e1
```

После первого результата не менялись:

- target geometry;
- environment values;
- transport;
- emission multiplier;
- population/adaptation protocol;
- acceptance thresholds.

Это исключает подгонку world definition после наблюдения результата.

### 5.2 Frozen experiment

```text
source port          eco-evo2-final/source-port
reachable            dry-ridge / wet-basin
isolated control     isolated-control
transport            Vector2(1, 0)
turbulence           0.25
emission             seed_count × 32
population           8
adaptation           10 generations
children/parent      4
```

Precommitted minimum gates:

```text
reachable colonized patches >= 2
unique recruited species    >= 2
sorting observed cells      >= 1
adaptation-positive cells   >= 1
isolated control colonized  false
```

No censoring:

```text
ADAPTATION_NULL       valid evidence
ADAPTATION_REVERSAL   valid evidence
VALID_NO_COLONIZATION valid evidence
```

### 5.3 No-bypass causal path

FINAL catalog source — только restored persisted E2.8 bytes:

```text
fresh E2.8 writer process
        ↓
exact accepted artifact
        ↓
Persistence.restore
        ↓
full frozen SpeciesCatalog + provenance
        ↓
every restored entry enters source port
        ↓
P2.1 dispersal
        ↓
establishment / seed bank / ResourceModel viability
        ↓
P2.4 patch migration
        ↓
actual recruited counts
        ↓
founder population
        ↓
CONTROL vs TREATMENT continued adaptation
```

Forbidden shortcuts are structurally checked:

```text
NO Catalog.build bypass
NO direct accepted-catalog reconstruction preload
NO bake-export preload
NO direct SpeciesCatalog builder preload
NO rebake
NO target-aware species filtering
NO biome species table
```

### 5.4 Exact artifacts

```text
protocol   372591ee3bee1c19538729259373e97fd9838461
challenge  4d353e774887c45f8a0487cb17b782e44d563951
acceptance 82850fb850c35bcffb937707e4a8d29fb2827caa
runner     4385861b62ae10df07cb0f71295f50bf9a2097ee
```

Exact GDScript execution set: `17 / 17 PASS`.

Acceptance transitive preload closure contains 16 exact blobs; the accepted E2.8 writer is the additional executed fresh-input producer.

### 5.5 Fresh post-freeze verification

```text
Godot                               4.7.1.stable.double.custom_build.a13da4feb
parser/preload                      PASS
parser ERROR lines                  0
fresh E2.8 writer A/B               PASS / PASS
writer logs                         byte-identical
fresh artifacts                     byte-identical
artifact bytes                      10383
artifact SHA-256                    b31c863f8e1943e5778d56631f8c8ad75b95f3b9d3930a699f80fd07595d45d1
FINAL process A/B                   PASS / PASS
assertions                          68 / 68 PASS
FINAL ERROR lines                   0 / 0
FINAL logs                          byte-identical
FINAL log SHA-256                   4fdeaa581cd889c94f1bb5e1391466cad3deea308d631f4e3a3c056b532f69c2
```

### 5.6 Observed result

```text
reachable_colonized_patches  2
unique_recruited_species     2
isolated_no_colonization     true
sorting_observed_cells       2
adaptation_positive_cells    2

DRY classification           ADAPTATION_POSITIVE
DRY adaptation gain          0.222347111576

WET classification           ADAPTATION_POSITIVE
WET adaptation gain          0.218384189961
```

Observed result 2/2 не заменяет precommitted thresholds 2/2, 2 species, 1 sorting cell и 1 adaptation-positive cell.

Первый run после protocol precommit дал тот же evidence hash, поэтому scientific repair после результата не потребовался.

### 5.7 Harness repair history

Первый runner freeze:

`65864edced044e170374f95980fe1edd0cc1e682`

Он передал accepted E2.8 writer positional path вместо требуемого `--artifact-path=<path>`. Writer корректно fail-closed **до запуска ecology**.

Repair изменил только runner invocation:

```text
accepted freeze  376796ab8c8370b7370fcd220ed207d07955cb42
runner blob      4385861b62ae10df07cb0f71295f50bf9a2097ee
```

Scientific protocol, thresholds, challenge implementation и acceptance test не менялись.

### 5.8 Claim boundary

Accepted claim:

> persisted frozen research SpeciesCatalog с accepted EVO2 provenance восстанавливается в fresh process и проходит precommitted unseen-world causal ecology route без rebake, biome species tables и target-aware species injection.

Не accepted:

```text
production ecology authority
production save/persistence authority
distributed durability
canonical biological taxonomy
world transaction semantics
P4 global/main acceptance
```

Canonical `.ps1` runner существует, но `pwsh/powershell` отсутствует в Linux carrier. Acceptance authority — `EXPLICIT_EQUIVALENT_FRESH_BEHAVIORAL_EXECUTION`. Independent Reviewer/Verifier PASS не заявляется.

## 6. EVO2 completion decision

`ECO.EVO2` закрыт как **COMPLETE_RESEARCH_ONLY**.

Это означает, что research route portable plant ecology доказал:

1. deterministic research species identities;
2. portable frozen catalog;
3. hidden-world causal colonization;
4. environmental generalization;
5. separation sorting/adaptation;
6. replicated causal evidence;
7. bounded seed robustness;
8. exact persistence/provenance;
9. end-to-end persisted-artifact unseen-world execution.

Это **не** означает production integration.

## 7. Следующий этап — bounded XFER0

Следующий architectural checkpoint должен определить explicit research-to-simulator boundary:

```text
EVO2 COMPLETE
    ↓
XFER0 bounded contract design
    ↓
EVO3 Planetary Ecology Compiler
    ↓
plant runtime convergence
    ↓
herbivores
    ↓
predators / food web / coevolution
```

XFER0 должен ответить:

- какие SpeciesCatalog fields допустимы как simulator-facing input;
- какой provenance обязан переноситься вместе с catalog;
- как environment/query contracts подаются ecology без захвата environment authority;
- как population/cohort state представляется без planet-wide individual entity truth;
- где проходит boundary между research persistence и production durability;
- какие canonical foundations должны существовать до XFER1/LIVE;
- какие fail-closed guards запрещают research shortcut превращать в production truth.

EVO3 должен начинаться только после того, как XFER0 зафиксирует эти ownership/semantic boundaries.

## 8. Production P4 remains separate

P4 branch lifecycle evidence не является частью EVO2 acceptance и не меняется от FINAL proof.

```text
P4 global acceptance        false here
runtime merge authorized    false here
required                    independent review/verifier + main-owned promotion
```

## 9. Current execution

```text
ECO.EVO2   COMPLETE_RESEARCH_ONLY
CURRENT    OPEN / DESIGN ECO.XFER0 BOUNDED CONTRACTS
NEXT       PLAN ECO.EVO3 PLANETARY ECOLOGY COMPILER
ANIMALS    DEFERRED UNTIL PLANT FOUNDATION / PLANETARY GENERALIZATION
```
