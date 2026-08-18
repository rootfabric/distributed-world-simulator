# ECO EVO2 — Portable SpeciesCatalog / Unseen World Roadmap

Статус: `ACTIVE / RESEARCH_ONLY / E2.1 ACCEPTED / E2.2 IN_DEVELOPMENT`.

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

EVO2 наследует только уже принятую research evidence:

```text
EVO1/P2.8 aggregate
ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6

P3.8 aggregate
6132820a5c6597765b4f3abeeb8cf9fc9e6aaffb90ba83a1263997b17fc6f3a0

P3.8 checkpoint SHA-256
1722f3ce96a8244bfaf2f8295c162b51552c6c5cc4cfd1126b40691a37bab367

P3.8 final state hash
1395e6cdfc6dc5ea963b0d077fc00c618645c8866a7e47e822bcbdd98e429cf9

E2.1 SpeciesCatalog aggregate
aa23bc269738ace132fb1386ec01b339cc7fd82e1238223c1075b60dac5896ad
```

P4.1..P4.8 production-integration work существует как branch-local lifecycle evidence, но EVO2 не наследует из него production authority. P4 promotion остаётся отдельным control-plane процессом.

## 2. Species concept policy

P2.7 deliberately produced `SPECIATION_CANDIDATE`, а не canonical taxonomy.

Поэтому EVO2 вводит термин:

`research_species_id`

Он означает стабильную идентичность portable lineage hypothesis внутри research pipeline.

Он **не** означает:

- официальную биологическую таксономию;
- production-owned species registry;
- доказанную reproductive isolation;
- право объединять/разделять виды без отдельной evidence policy.

На E2.1 одна validated lineage observation соответствует одной research species entry. Отбор устойчивых линий и возможная grouping policy принадлежат E2.2.

## 3. E2.1 — SpeciesCatalog Contract

Статус: `ACCEPTED`.

Exact code-under-test:

`bf468942718df6b84ebd4c61a294987e8e63c607`

Acceptance source HEAD:

`c79e2d61e665689fe39621442f72171de5d2790f`

Accepted exact attached Godot evidence:

```text
4.7.1.stable.double.custom_build.a13da4feb
53 / 53 assertions PASS
fresh-process logs byte-identical
aggregate aa23bc269738ace132fb1386ec01b339cc7fd82e1238223c1075b60dac5896ad
```

Acceptance authority: human-directed exact-attached-Godot equivalent fresh verification. Independent Reviewer PASS не заявляется.

### Frozen contract

Каждая entry содержит:

- `research_species_id`;
- `lineage_id`;
- `ancestry_path`;
- `parent_lineage_id`;
- `split_year`;
- validated ecological genome + checksum;
- validated recruitment traits + checksum;
- observed patch range prior;
- source P2.7 observation hash;
- entry hash;
- `canonical_species_declared = false`.

Stable identity rule:

`research_species_id` выводится из schema/version/species-concept и `lineage_id`.

Следствия:

- изменение порядка входа не меняет ID;
- повторный export той же lineage не меняет ID;
- изменение snapshot traits не меняет lineage identity, но меняет `entry_hash` и `catalog_hash`;
- разные lineage IDs не collision-collapse в одну entry.

Catalog содержит schema/version/species concept, frozen parent P2.7 evidence identity, explicit `bake_id`, `source_run_hash`, entries в canonical order и deterministic `catalog_hash`.

Frozen acceptance gates включают strict exact source observation field shape, strict `split_year` Variant type, tamper rejection, input-order independence, no global RNG consumption и no source mutation.

Persistence/JSON round-trip остаётся E2.8.

## 4. E2.2 — Deterministic Evolution Bake Export

Статус: `IN_DEVELOPMENT / CURRENT`.

### Goal

Получать SpeciesCatalog из long-run evolution result автоматически, а не вручную перечислять lineages.

### Required pipeline

```text
long-run lineage evidence
    ↓
deterministic candidate selection
    ↓
deterministic representative observation per retained lineage
    ↓
accepted E2.1 SpeciesCatalog.build(...)
```

### Required policy

Bake должен доказать:

- deterministic candidate selection;
- explicit survival/persistence threshold;
- deterministic representative snapshot;
- no iteration-order dependence;
- no global RNG dependence;
- provenance до exact evolution result;
- source long-run result is not mutated;
- clear policy для extinct/recent/transient lineages;
- fail-closed handling duplicate/ambiguous lineage evidence;
- accepted E2.1 catalog validation on every successful export;
- no biome lookup;
- no canonical species declaration.

Первый E2.2 contract не вводит clustering. Одна retained validated lineage hypothesis остаётся одной research species entry. Любая более сложная grouping/species concept policy требует отдельного evidence gate.

### Initial E2.2 acceptance direction

Минимум нужно проверить:

1. stable retained-lineage selection under shuffled input ordering;
2. explicit minimum observation count / persistence window;
3. deterministic latest-or-policy-selected representative observation;
4. transient lineage exclusion;
5. extinct lineage handling by explicit policy, not implicit disappearance;
6. duplicate same-year / ambiguous representative evidence rejection;
7. exact source-run provenance hash propagation;
8. unchanged source evidence after bake;
9. repeated/fresh-process catalog hash equality;
10. global RNG untouched;
11. output passes frozen E2.1 `SpeciesCatalog.validate_catalog()`;
12. no taxonomy promotion.

## 5. E2.3 — Frozen-Catalog Transfer

Catalog строится на source landscape. Затем mutation/evolution выключаются.

Target landscape не использовался при bake.

Разрешены только:

- dispersal;
- establishment;
- competition;
- population turnover;
- succession;
- disturbance/recovery.

PASS требует причинно объяснимого self-organization без biome species table.

## 6. E2.4 — Environment Generalization Matrix

Минимальные target families:

```text
NEAR_SOURCE
DRY
WET
NUTRIENT_POOR
HIGH_SEASONALITY
PATCH_ISOLATED
```

Проверяются не одинаковые species lists, а:

- occupancy;
- biomass;
- recruitment;
- extinction;
- recolonization;
- trait/niche composition;
- stability bounds.

## 7. E2.5 — Ecological Sorting vs Continued Adaptation

Paired experiment:

```text
Control   = frozen catalog, evolution disabled
Treatment = same catalog/root, continued adaptation enabled
```

Нужно разделить ecological sorting уже существующих стратегий и новую evolutionary adaptation.

## 8. E2.6 — Replicated Causal Experiments

Использовать patterns доказанные VIS2.2:

- independent stochastic roots между replicates;
- common random numbers внутри Control/Treatment пары;
- aggregate causal effect;
- bounded evidence cache;
- deterministic rewind/rebranch semantics.

VIS2.2 не получает автоматический formal PASS от EVO2; это reuse архитектурных patterns/evidence machinery.

## 9. E2.7 — Cross-Seed Robustness

Acceptance не может зависеть от одного seed.

Нужно различать:

```text
exact history reproducibility for same seed
```

и

```text
robust ecological regularity across different seeds
```

Разные histories допустимы; runaway collapse/explosion или reversal основных causal expectations — finding.

## 10. E2.8 — Catalog Persistence & Provenance

Требуется:

- typed deterministic persistence;
- schema/version boundary;
- canonical bytes/hash;
- fresh-process restore;
- tamper rejection;
- source evolution identity;
- model/engine provenance;
- migration policy или explicit fail-closed version mismatch.

## 11. EVO2 FINAL — Unseen World Challenge

Target map/environment скрыт от bake pipeline до фиксации SpeciesCatalog.

После freeze каталога target открывается population solver.

PASS требует:

1. никаких hardcoded biome->species tables;
2. deterministic same-seed replay;
3. multiple target environments дают различимые, причинно объяснимые communities;
4. spatial history имеет значение — suitability alone недостаточна;
5. disturbance меняет trajectory, а не просто presentation;
6. population state остаётся truth;
7. individual materialization не становится planetary canonical truth.

## 12. XFER boundary

После EVO2 допускается bounded XFER0 contract work:

```text
WorldEnvironmentProvider -> EnvironmentSample
SpeciesCatalog            -> research ecology input
population solver         -> PopulationPatchState candidate
PopulationPatchState      -> representation materialization
```

Но XFER0 не может сам присвоить ECO ownership над G/WQ/MAT/LIFE/WB/NX/authority/persistence foundations.

## 13. После EVO2

Предлагаемый следующий research node:

`EVO3 — Planetary Ecology Compiler / broader planetary generalization`.

Животные открываются только после plant-only portable ecology proof.

## 14. Current execution

```text
CURRENT = DEVELOP ECO.EVO2 / E2.2 Deterministic Evolution Bake Export
NEXT    = E2.3 Frozen-Catalog Transfer after E2.2 acceptance
```
