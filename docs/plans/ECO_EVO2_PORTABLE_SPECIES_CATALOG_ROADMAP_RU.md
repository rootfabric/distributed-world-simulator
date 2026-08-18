# ECO EVO2 — Portable SpeciesCatalog / Unseen World Roadmap

Статус: `ACTIVE / RESEARCH_ONLY / E2.1 ACCEPTED / E2.2 ACCEPTED / E2.3 ACCEPTED / E2.4 ACCEPTED / E2.5 AUTHORIZED_NOT_STARTED`.

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
EVO1/P2.8 aggregate
ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6

P3.8 aggregate
6132820a5c6597765b4f3abeeb8cf9fc9e6aaffb90ba83a1263997b17fc6f3a0

E2.1 SpeciesCatalog aggregate
aa23bc269738ace132fb1386ec01b339cc7fd82e1238223c1075b60dac5896ad

E2.2 Deterministic Evolution Bake Export aggregate
56d4b8bfd3064ad37b720d5bff2bc98bb72b0ab7ad871877fc268d5e6df703ce

E2.2 frozen bake
45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b

E2.2 frozen catalog
5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219

E2.3 Frozen-Catalog Transfer aggregate
82d76f858568d5bd53af4d299abd2155f2fde7e845de828cf4555e601ee1efa8

E2.4 Environment Generalization Matrix aggregate
ae2952de10ac721c8052694963b690d9f72af05d9c92e2fa4cd70e00f72fb2b5
```

P4 production-integration evidence остаётся отдельной governance-линией и не даёт EVO2 production authority.

## 2. Species concept policy

`research_species_id` — стабильная идентичность portable lineage hypothesis внутри research pipeline.

Это не canonical biological taxonomy и не production species registry.

## 3. E2.1 — SpeciesCatalog Contract — ACCEPTED

Exact code-under-test: `bf468942718df6b84ebd4c61a294987e8e63c607`.  
Accepted aggregate: `aa23bc269738ace132fb1386ec01b339cc7fd82e1238223c1075b60dac5896ad`.

## 4. E2.2 — Deterministic Evolution Bake Export — ACCEPTED

Exact code-under-test: `7cf98d67a4658644a6f2dde3e93e28a184638ec3`.  
Accepted aggregate: `56d4b8bfd3064ad37b720d5bff2bc98bb72b0ab7ad871877fc268d5e6df703ce`.

Frozen export policy остаётся typed, deterministic, fail-closed и без taxonomy promotion.

## 5. E2.3 — Frozen-Catalog Transfer — ACCEPTED

Exact code-under-test: `c7ee41371807ed7dbb75e7e1eae1587105873a26`.  
Accepted aggregate: `82d76f858568d5bd53af4d299abd2155f2fde7e845de828cf4555e601ee1efa8`.

Frozen transfer contract сохраняет exact E2.2 catalog, starts target empty, hard-disables evolution, reuses causal dispersal/establishment/competition/turnover, permits `VALID_NO_COLONIZATION`, and rejects target-aware shortcuts.

Accepted verification: 17/17 exact executable closure, 59/59 assertions, two byte-identical fresh processes. Independent role PASS not claimed.

## 6. E2.4 — Environment Generalization Matrix — ACCEPTED

Exact code-under-test:

`0135aee461a107375cdb3e52e07e8c799145998b`

Implementation:

```text
scripts/research/ecology/plant_environment_generalization_matrix_v1.gd
823ef6445d7f71aee79b7c0bb0932b321f90ce8d
```

Validation:

`validation/ecology/eco-evo2-e2-4-environment-generalization-matrix-validation.json`

Accepted checkpoint:

`docs/checkpoints/2026-08-18_ECO_EVO2_E2_4_ENVIRONMENT_GENERALIZATION_MATRIX_ACCEPTED_RU.md`

### Frozen E2.4 contract

Один exact frozen catalog предлагается каждой environment cell без rebake, target-aware species filtering или mutation:

```text
NEAR_SOURCE
DRY
WET
NUTRIENT_POOR
HIGH_SEASONALITY
PATCH_ISOLATED
```

Matrix plan имеет canonical order/hash, per-cell typed hashes и deterministic replay validation.

### HIGH_SEASONALITY boundary

`HIGH_SEASONALITY` — это bounded `SEASONAL_ENVELOPE`, не fake static average и не claim непрерывной seasonal dynamics:

```text
same unseen patch identity
  ├─ COOL_WET
  ├─ MILD
  ├─ HOT_DRY
  └─ COOL_DARK
```

Каждая phase является отдельным deterministic transfer probe. Такой дизайн проверяет переносимость frozen strategies к сезонным экстремумам, но не подменяет будущую continuous seasonal population simulation.

### PATCH_ISOLATED causal control

`PATCH_ISOLATED` использует exact environment checksum `NEAR_SOURCE`, но удалённые bounds. Результат:

```text
NEAR_SOURCE      COLONIZED year 1
PATCH_ISOLATED   VALID_NO_COLONIZATION
```

То есть suitability не создаёт population truth без causal reachability.

### Accepted verification

```text
exact transitive executable closure   18 / 18 PASS
Godot                                4.7.1.stable.double.custom_build.a13da4feb
parser/preload                       PASS
fresh processes                      2 / 2 PASS
assertions                           82 / 82 PASS
logs                                 byte-identical
log SHA-256                          23ac2294dbe9b7ad0f78f7807e0bde67eb804b4e2f8640f711afdc71b5d0f40c
matrix aggregate                     ae2952de10ac721c8052694963b690d9f72af05d9c92e2fa4cd70e00f72fb2b5
plan hash                            f688eb014245d63483562376c3f5db8c08a85bdc35feb52428f5ff17753f82e0
```

Static reachable cells `NEAR_SOURCE`, `DRY`, `WET`, `NUTRIENT_POOR` colonize in the current controlled fixture, but do not produce identical population states/histories. Seasonal envelope phases also produce distinct deterministic ecological states.

Canonical PowerShell runner exists and includes an 18/18 exact closure gate, but was not executed in the Linux verification carrier because `pwsh`/`powershell` were unavailable. Equivalent execution was explicitly classified and reproduced the runner's parent, closure, parser, behavioral, fresh-process and frozen-output gates.

Acceptance authority is fresh behavioral execution, **not** independent Reviewer/Verifier authority.

## 7. E2.5 — Ecological Sorting vs Continued Adaptation — AUTHORIZED / CURRENT

### Research question

После переноса frozen SpeciesCatalog новая среда может изменить ecosystem двумя разными механизмами:

1. **Ecological sorting** — уже существующие стратегии меняют abundance, occupancy и persistence без genetic change.
2. **Continued adaptation** — после transfer mutation/selection создаёт новый adapted descendant state и дополнительное fitness response.

E2.5 обязан разделить эти механизмы причинно, а не просто показать, что Treatment «лучше».

### Paired causal design

```text
CONTROL
exact accepted E2.4/E2.3 parent lineage
+ exact same frozen SpeciesCatalog
+ exact same target environment exposure
+ evolution disabled
        ↓
ECOLOGICAL_SORTING_ONLY

TREATMENT
exact same parent catalog/root
+ exact same target environment exposure
+ bounded continued adaptation enabled
        ↓
ECOLOGICAL_SORTING_PLUS_ADAPTATION
```

### Required identity locks

Control и Treatment обязаны иметь одинаковые:

- initial SpeciesCatalog hash;
- initial research species IDs;
- initial genome/recruitment-trait checksums;
- target EnvironmentSample(s);
- geography/transport schedule;
- population initialization rules;
- simulation horizon;
- deterministic seed/stream policy.

Единственная причинная treatment variable — permission for bounded continued adaptation.

### Required observables

Минимально фиксировать:

- starting catalog/root hash;
- parent lineage/research species identity;
- mutation/adaptation event log;
- descendant genome/trait checksum;
- abundance/occupancy trajectories;
- final population state hash;
- fitness/resource or persistence delta against Control;
- treatment result hash;
- paired causal contrast hash.

### Required classification

E2.5 должен уметь различить:

```text
SORTING_ONLY_RESPONSE
ADAPTATION_DETECTED
ADAPTATION_NO_MEASURABLE_ADVANTAGE
NO_RESPONSE
```

Наличие mutation само по себе не считается adaptation advantage.

### Forbidden shortcuts

- разные starting catalogs между Control/Treatment;
- target-aware rebake;
- разные environments или transport controls;
- считать mutation автоматически новым canonical species;
- hand-written target fitness bonus;
- hidden biome/species lookup;
- использовать global RNG без deterministic stream contract;
- позволять Treatment переписывать accepted E2.4 evidence.

### Acceptance target

E2.5 GREEN требует как минимум одного controlled environment, где paired experiment причинно отделяет response frozen ecological sorting от response, возникшего только после bounded adaptation, при exact same starting parent state.

Если adaptation не создаёт measurable advantage в выбранном challenge, это не повод подгонять тест. Нужно либо зафиксировать `ADAPTATION_NO_MEASURABLE_ADVANTAGE`, либо изменить научно обоснованный challenge и заново freeze protocol до acceptance.

E2.6 остаётся blocked до formal E2.5 acceptance.

## 8. E2.6 — Replicated Causal Experiments

Использовать VIS2.2 evidence patterns без автоматического наследования formal PASS.

## 9. E2.7 — Cross-Seed Robustness

Acceptance не может зависеть от одного seed.

## 10. E2.8 — Catalog Persistence & Provenance

Typed deterministic persistence, canonical bytes/hash, schema/version policy, restore and tamper rejection.

## 11. EVO2 FINAL — Unseen World Challenge

Target скрыт от bake pipeline до freeze SpeciesCatalog. После reveal система должна построить причинно объяснимую spatial population truth без hard-coded biome species tables.

## 12. После EVO2

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

## 13. Current execution

```text
CURRENT = OPEN / IMPLEMENT ECO.EVO2 / E2.5 Ecological Sorting vs Continued Adaptation
NEXT    = E2.6 Replicated Causal Experiments after E2.5 acceptance
```
