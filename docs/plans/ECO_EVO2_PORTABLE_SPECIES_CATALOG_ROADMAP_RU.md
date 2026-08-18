# ECO EVO2 — Portable SpeciesCatalog / Unseen World Roadmap

Статус: `ACTIVE / RESEARCH_ONLY / E2.1..E2.6 ACCEPTED / E2.7 AUTHORIZED_NOT_STARTED`.

Ветка: `feature/eco-evolutionary-ecology`.

## 0. Назначение

EVO2 превращает результат эволюционного исследования из состояния «успешный конкретный эксперимент» в переносимый ecological artifact.

North Star:

```text
SpeciesCatalog produced by evolution
        +
previously unseen environment
        ↓
self-organized persistent population ecology
```

Запрещён shortcut:

```text
biome -> hand-written species list -> scatter
```

Целевой путь:

```text
environment -> evolution/bake -> SpeciesCatalog -> population solver -> representation
```

## 1. Frozen parent evidence

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
```

P4 production-integration evidence остаётся отдельной governance-линией и не даёт EVO2 production authority.

## 2. Species concept policy

`research_species_id` — стабильная идентичность portable lineage hypothesis внутри research pipeline. Adapted descendants E2.5/E2.6 сохраняют эту research identity; genetic divergence не превращается автоматически в canonical biological taxonomy.

## 3. Accepted sequence E2.1–E2.4

```text
E2.1 SpeciesCatalog Contract              ACCEPTED
E2.2 Deterministic Evolution Bake Export  ACCEPTED
E2.3 Frozen-Catalog Transfer              ACCEPTED
E2.4 Environment Generalization Matrix    ACCEPTED
```

E2.3 закрепил hidden-target transfer с causal reachability control. E2.4 расширил это на шесть environment/geography classes с одним exact frozen catalog и сохранил `VALID_NO_COLONIZATION` как валидный результат. `HIGH_SEASONALITY` в E2.4 остаётся deterministic seasonal envelope, а не continuous seasonal dynamics claim.

## 4. E2.5 — Ecological Sorting vs Continued Adaptation — ACCEPTED

Exact code-under-test:

`4c17a91957e392eabc04e136f9590773dbe54dd1`

Implementation:

```text
scripts/research/ecology/plant_sorting_vs_adaptation_v1.gd
74443f7b0c1b5e2234b1949761abc6cfab4bdd9c
```

Validation:

`validation/ecology/eco-evo2-e2-5-sorting-vs-adaptation-validation.json`

Accepted checkpoint:

`docs/checkpoints/2026-08-18_ECO_EVO2_E2_5_SORTING_VS_ADAPTATION_ACCEPTED_RU.md`

### 4.1 Causal paired design

```text
CONTROL
same frozen catalog
same target environment
same founders
mutation_probability = 0
        ↓
ecological sorting only

TREATMENT
same frozen catalog
same target environment
same founders
one fixed bounded mutation policy
        ↓
MutationKernel.reproduce
        ↓
ResourceModel.evaluate
        ↓
selection
```

Единственная deliberate causal treatment — permission for bounded inherited adaptation. Policy steps не зависят от cell/environment.

`ADAPTATION_DETECTED` требует:

1. novel descendant genome;
2. positive measurable resource-balance advantage относительно frozen Control.

Mutation event сам по себе недостаточен.

### 4.2 Accepted outcome

```text
DRY Control sorting gain      +0.712602797217
DRY Treatment adaptation      +0.210067450172

WET Control sorting gain      +1.231209807202
WET Treatment adaptation      +0.387714189995
```

Reciprocal cross-environment result:

```text
DRY-adapted in DRY   +0.500903251638
WET-adapted in DRY   -1.600499312923

WET-adapted in WET   +1.157255352906
DRY-adapted in WET   -1.601811151164
```

Adapted descendants сохраняют исходный `research_species_id/source_lineage_id`. E2.5 не объявляет новые canonical species.

### 4.3 Accepted verification

```text
exact transitive executable closure   21 / 21 PASS
Godot                                4.7.1.stable.double.custom_build.a13da4feb
parser/preload                       PASS
fresh processes                      2 / 2 PASS
assertions                           93 / 93 PASS
logs                                 byte-identical
run log SHA-256                      9aa1e912a545cdb470dbada92ba8eac5024632e2ec7f58eaef6a4ffd977975a9
aggregate                            942ad54e7672c4f57874e1802b320c1b2a4aa74e43b05f7e285793ea4ec8b2a6
```

Acceptance authority — fresh behavioral execution; independent Reviewer/Verifier PASS не заявляется.

## 5. E2.6 — Replicated Causal Experiments — ACCEPTED

Exact code-under-test:

`8ac37bfea0f36731407e1252db1a7c2a2305420e`

Implementation:

```text
scripts/research/ecology/plant_replicated_causal_experiments_v1.gd
7fb18d91ba59493c608edafba610dc882152852a
```

Acceptance test:

```text
tests/research/ecology/eco_evo2_e2_6_replicated_causal_experiments_acceptance.gd
55b9af8b1969b033606fab112accd616eee8122a
```

Canonical runner:

```text
RUN_ECO_EVO2_E2_6_TESTS.ps1
08a2ffbfbe1b3c28b020571256b6831d37d97fcb
```

Validation:

`validation/ecology/eco-evo2-e2-6-replicated-causal-experiments-validation.json`

Accepted checkpoint:

`docs/checkpoints/2026-08-18_ECO_EVO2_E2_6_REPLICATED_CAUSAL_EXPERIMENTS_ACCEPTED_RU.md`

### 5.1 Frozen replication protocol

Replicate identities были объявлены до acceptance run:

```text
R01
R02
R03
R04
R05
```

Acceptance thresholds были также frozen заранее:

```text
positive adaptation effect    >= 4 / 5 per environment
reciprocal home advantage     >= 4 / 5 per environment
```

Hard evidence rule:

```text
all 5 replicate records retained
null/reversal outcomes retained
post-hoc replicate censoring forbidden
```

E2.6 не требует 5/5. Если один replicate оказался бы null/reversal, он должен был остаться в artifact и учитываться в aggregate.

### 5.2 Replicate causal identity

В каждом replicate:

```text
CONTROL
same frozen founders
same DRY/WET environment
same replicate stream
mutation_probability = 0

TREATMENT
same frozen founders
same DRY/WET environment
same replicate stream
exact E2.5 mutation policy
```

Control/Treatment отличаются только permission for inherited adaptation.

Selection consequence вычисляется accepted `ResourceModel`; variation — accepted deterministic `MutationKernel`. No global RNG.

### 5.3 Small closure by design

E2.6 не запускает заново весь transfer/matrix graph. E2.5 accepted contract закреплён как immutable parent; для replication mechanism используется минимальный causal closure:

```text
EnvironmentSample
PlantGenome
LineageRecord
MutationKernel
ResourceModel
E2.6 implementation
E2.6 acceptance test
```

Exact closure:

`7 / 7 PASS`.

Это уменьшает скрытую coupling surface и делает replicated evidence легче для independent audit.

### 5.4 Observed replication result

```text
replicate set hash
5e02d04d3d94f95f6e8e76f6387ee07c723d2e596046f6a65d65cd815abbc637

DRY
mean adaptation gain       +0.235359270024
positive effects           5 / 5
reciprocal home advantage  5 / 5
aggregate                  10ca9de3ca7989494507bcb081a410bd1e8e625faa10843f62201c258e9bdd52

WET
mean adaptation gain       +0.379178153879
positive effects           5 / 5
reciprocal home advantage  5 / 5
aggregate                  3fa2b4a96a141241e367d56b7fa69f6d8bc9f92f32cd5266128248c21a092755
```

Individual replicate evidence hashes:

```text
R01 36b5d458d037cafe6c1d72bb68040876a2a453637d68d89de75dae98f9e7fa84
R02 c3e2dbc3949c6d16edc646954b1a324b0e03215aae7a1759ec3d79bfd8a64177
R03 d808be565e5d1c39725b5212b72e85efb4113f3e11e27dc3f560da515d455477
R04 9785a696f335895b48dde1dc2813bde5f872bf887f9664c3ec122dba789c4ca4
R05 a815a398caf1845da32ea4fdc7e7462e42e36c4580393bac0b215cbbef71f4f9
```

Overall E2.6 aggregate:

`1a4bcf1cffe65450a27037e9307bb5c7ac3cb8a98899918207107e367d9d5fbd`.

### 5.5 Accepted verification

```text
exact transitive executable closure   7 / 7 PASS
Godot                                4.7.1.stable.double.custom_build.a13da4feb
Godot SHA-256                        bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
parser/preload                       PASS
fresh processes                      2 / 2 PASS
assertions                           218 / 218 PASS
ERROR lines                          0 / 0
logs                                 byte-identical
run log SHA-256                      a1dec9651244fb1ccf95a617469d56a4b7d674aceb6f73bf33e792a3c9a82307
```

Canonical PowerShell runner не запускался в Linux carrier из-за отсутствия `pwsh/powershell`; exact equivalent execution воспроизвёл его parent, closure, parser, fresh-process, PASS-marker and frozen-output predicates.

Independent Reviewer/Verifier PASS не заявляется.

### 5.6 Scientific boundary

E2.6 доказывает reproducibility causal effect across five predeclared deterministic streams.

E2.6 **не** доказывает:

- formal statistical significance;
- broad cross-seed robustness;
- robustness across alternative bake/catalog seeds;
- canonical speciation;
- production authority.

Поэтому observed 5/5 нельзя автоматически использовать как E2.7 PASS.

## 6. E2.7 — Cross-Seed Robustness — AUTHORIZED / CURRENT

E2.7 расширяет small replication proof до robustness study.

### 6.1 Research question

> Сохраняется ли принятый E2.5/E2.6 causal conclusion, если variation stream выбирается из существенно более широкого заранее объявленного seed ensemble?

E2.7 не должен менять biological mechanism, target environments или mutation policy. Это robustness test уже принятой модели, а не новый tuning stage.

### 6.2 Protocol freeze before execution

До первого acceptance run необходимо зафиксировать:

- полный seed ensemble и его hash;
- minimum ensemble size;
- derivation rule seed → replicate stream;
- exact frozen parent catalog/founders;
- exact DRY/WET environments;
- exact E2.5 treatment policy;
- effect observables;
- robustness thresholds;
- handling null/reversal/failed runs;
- uncertainty/statistical method, если он используется.

После просмотра результатов seed set нельзя менять без protocol revision/refreeze.

### 6.3 Required evidence

Для каждого seed:

- retained paired Control/Treatment record;
- adaptation effect sign/magnitude;
- reciprocal home/away contrast;
- classification;
- exact result hash.

Aggregate должен показывать минимум:

- N retained / N declared;
- positive/null/reversal counts;
- median effect;
- lower/upper quantiles или полный bounded range;
- sign consistency;
- reciprocal-home-advantage rate;
- leave-one-out sensitivity либо аналогичный single-seed influence diagnostic;
- seed-ensemble hash;
- aggregate robustness hash.

### 6.4 Fail-closed rules

Запрещено:

- post-hoc seed deletion;
- выбирать только «удачное» seed family;
- менять mutation policy после просмотра результатов;
- объявлять robustness только по mean;
- наследовать E2.6 5/5 как E2.7 acceptance;
- скрывать null/reversal outcomes;
- повышать adapted lineage до canonical species;
- приписывать production authority.

E2.8 остаётся blocked до formal E2.7 acceptance.

## 7. E2.8 — Catalog Persistence & Provenance

Typed deterministic persistence, canonical bytes/hash, schema/version policy, restore and tamper rejection.

## 8. EVO2 FINAL — Unseen World Challenge

Target скрыт от bake pipeline до freeze SpeciesCatalog. После reveal система должна построить причинно объяснимую spatial population truth без hard-coded biome species tables.

## 9. После EVO2

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

## 10. Current execution

```text
CURRENT = OPEN / IMPLEMENT ECO.EVO2 / E2.7 Cross-Seed Robustness
NEXT    = E2.8 Catalog Persistence & Provenance after E2.7 acceptance
```
