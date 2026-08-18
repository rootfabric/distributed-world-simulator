# ECO EVO2 — Portable SpeciesCatalog / Unseen World Roadmap

Статус: `ACTIVE / RESEARCH_ONLY / E2.1..E2.5 ACCEPTED / E2.6 AUTHORIZED_NOT_STARTED`.

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
```

P4 production-integration evidence остаётся отдельной governance-линией и не даёт EVO2 production authority.

## 2. Species concept policy

`research_species_id` — стабильная идентичность portable lineage hypothesis внутри research pipeline. Adapted descendants E2.5 сохраняют эту research identity; genetic divergence не превращается автоматически в canonical biological taxonomy.

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

### 4.2 Bounded challenge

```text
cells                  DRY / WET
generations            10
population             8
offspring per parent   4
```

Treatment policy:

```text
mutation_probability              0.30
water_preference_step             0.055
root_depth_m_step                 0.20
growth_rate_step                  0.045
shade_tolerance_step              0.045
seed_dispersal_distance_m_step    0.0
```

Control совпадает с Treatment policy по всем step values и меняет только `mutation_probability -> 0`.

### 4.3 Sorting result

Оба Control arm начинают с одинакового 50/50 frozen founder set и не создают novel genomes.

```text
DRY Control
→ frozen alpha strategy wins
→ sorting gain +0.712602797217

WET Control
→ frozen beta strategy wins
→ sorting gain +1.231209807202
```

Это pure ecological sorting существующих strategies без genetic change.

### 4.4 Adaptation result

```text
DRY Treatment
classification    ADAPTATION_DETECTED
adaptation gain   +0.210067450172
water preference  shifts below frozen DRY-sorted state

WET Treatment
classification    ADAPTATION_DETECTED
adaptation gain   +0.387714189995
water preference  shifts above frozen WET-sorted state
```

Adapted descendants сохраняют исходный `research_species_id/source_lineage_id`. E2.5 не объявляет новые canonical species.

### 4.5 Reciprocal local adaptation

Final Treatment populations cross-evaluated through the same accepted causal `ResourceModel`:

```text
DRY-adapted in DRY   +0.500903251638
WET-adapted in DRY   -1.600499312923

WET-adapted in WET   +1.157255352906
DRY-adapted in WET   -1.601811151164
```

Обе populations имеют home advantage. Это исключает простую интерпретацию «Treatment получил общий скрытый fitness bonus».

### 4.6 Accepted verification

```text
exact transitive executable closure   21 / 21 PASS
Godot                                4.7.1.stable.double.custom_build.a13da4feb
parser/preload                       PASS
fresh processes                      2 / 2 PASS
assertions                           93 / 93 PASS
logs                                 byte-identical
run log SHA-256                      9aa1e912a545cdb470dbada92ba8eac5024632e2ec7f58eaef6a4ffd977975a9
aggregate                            942ad54e7672c4f57874e1802b320c1b2a4aa74e43b05f7e285793ea4ec8b2a6
DRY paired hash                      1d8dd8f37ad0c83f439dce5493c59b38a3618f9201630a125a6197691eecab7c
WET paired hash                      9234fdfa74530c1f16b90960814e88e6417b2f3f9a92a8523e825471f2dd1292
```

Canonical runner:

```text
RUN_ECO_EVO2_E2_5_TESTS.ps1
aac648105002a3b9337c0b7fcedfdc501d01402e
```

Он не запускался в Linux carrier из-за отсутствия `pwsh/powershell`; exact equivalent gate воспроизвёл его parent, 21-file closure, parser, behavioral, fresh-process and frozen-output predicates.

Acceptance authority — fresh behavioral execution; independent Reviewer/Verifier PASS **не заявляется**.

### 4.7 Integrity

Validator перестраивает expected result deterministic replay-ом. Acceptance negative tests отвергают даже:

- cross-environment semantic tamper после пересчёта aggregate hash;
- selected mutation-event tamper после пересчёта arm/paired/aggregate hashes;
- parent/bake/catalog tamper;
- extra fields;
- canonical-taxonomy promotion.

## 5. E2.6 — Replicated Causal Experiments — AUTHORIZED / CURRENT

E2.5 показал causal split на одном frozen deterministic assay. E2.6 должен проверить устойчивость causal вывода на заранее объявленном bounded replication set.

### 5.1 Replication contract

До исполнения E2.6 должен freeze:

- replicate IDs;
- seed/stream derivation;
- exact Control/Treatment identity locks;
- target environments/challenge set;
- horizon/population protocol;
- aggregation rules;
- acceptance rule для null/reversal outcomes.

После freeze нельзя выбрасывать «неудобные» replicates.

### 5.2 Required per-replicate evidence

Для каждого replicate:

- exact starting parent hash;
- Control/Treatment initial equality;
- sorting result;
- adaptation classification;
- paired effect/gain;
- novel-genome evidence;
- cross-environment contrast, когда применимо;
- deterministic result hash;
- failure/null reason, если эффект отсутствует.

### 5.3 Aggregate evidence

E2.6 должен показывать не только mean:

- count/sign consistency;
- min/max effect;
- null/reversal count;
- classification distribution;
- exact replicate set hash;
- aggregate causal evidence hash.

Допустимые replicate classifications сохраняются:

```text
SORTING_ONLY_RESPONSE
ADAPTATION_DETECTED
ADAPTATION_NO_MEASURABLE_ADVANTAGE
NO_RESPONSE
```

### 5.4 Observability reuse

Можно использовать VIS2.2 evidence/causal observability patterns как техническую архитектуру записи evidence, но formal PASS VIS2.2 не наследуется автоматически.

E2.7 остаётся blocked до formal E2.6 acceptance.

## 6. E2.7 — Cross-Seed Robustness

После replicated causal design проверить, что acceptance не зависит от одного seed family / replication schedule.

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
CURRENT = OPEN / IMPLEMENT ECO.EVO2 / E2.6 Replicated Causal Experiments
NEXT    = E2.7 Cross-Seed Robustness after E2.6 acceptance
```
