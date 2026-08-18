# ECO EVO2 — Portable SpeciesCatalog / Unseen World Roadmap

Статус: `ACTIVE / RESEARCH_ONLY / E2.1 ACCEPTED / E2.2 CANDIDATE_VERIFICATION / E2.3 BLOCKED`.

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

На E2.1 одна validated lineage observation соответствует одной research species entry. Отбор устойчивых линий принадлежит E2.2; clustering/grouping в текущем E2.2 contract не разрешён.

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

Статус: `CANDIDATE_VERIFICATION / NOT_SELF_ACCEPTED`.

Exact code-under-test HEAD:

`7cf98d67a4658644a6f2dde3e93e28a184638ec3`

Executable blobs:

```text
implementation  6ed4abfa58c28a99fb1c28547d81e1a292756e10
acceptance test 87a980543239b71b6a7fb5d7e2ecfcd2e89df195
runner          b2d55213ac19714fe3f603e7266c539ac43ab104
```

Candidate checkpoint:

`docs/checkpoints/2026-08-18_ECO_EVO2_E2_2_EVOLUTION_BAKE_EXPORT_CANDIDATE_RU.md`

Machine validation:

`validation/ecology/eco-evo2-e2-2-evolution-bake-export-validation.json`

### Goal

Получать SpeciesCatalog из typed long-run lineage-history evidence автоматически, а не вручную перечислять retained lineages.

Текущий accepted upstream P2.8 доказывает long-run deterministic Plant World persistence, но не публикует canonical multi-lineage evolved-observation collection. Поэтому E2.2 фиксирует явный producer boundary вместо подмены реального evolution bake статической fixture.

### Implemented pipeline

```text
validated long-run lineage histories
    ↓
canonical typed source + source_hash
    ↓
deterministic retained-lineage policy
    ↓
latest unambiguous representative observation
    ↓
accepted E2.1 SpeciesCatalog.build(...)
    ↓
embedded source + selected/rejected evidence + bake_hash
```

### Frozen candidate policy

Research policy revision: `ECO.EVO2-E2.2.1`.

```text
WINDOW_YEARS                       = 8
MIN_OCCUPIED_YEARS_IN_WINDOW       = 6
MIN_LINEAGE_AGE_YEARS              = 8
MAX_REPRESENTATIVE_STALENESS_YEARS = 2
```

Retained lineage должна:

1. иметь age >= 8 years;
2. присутствовать в final year;
3. быть occupied минимум 6 из trailing 8 years;
4. иметь latest representative observation не старше 2 years.

Explicit rejection reasons:

- `RECENT_LINEAGE`;
- `EXTINCT_AT_FINAL`;
- `TRANSIENT_PERSISTENCE`;
- `STALE_REPRESENTATIVE`.

Это export policy, а не biological species definition.

### Determinism / fail-closed semantics

Candidate доказал:

- lineage input-order independence;
- observation canonicalization;
- duplicate lineage rejection;
- duplicate occupancy-year rejection;
- incomplete trailing-window rejection;
- ambiguous distinct observations at same representative year rejection;
- deterministic latest representative selection;
- source evidence is not mutated;
- no global RNG consumption;
- exact E2.1 and P2.8 parent pinning;
- exact source-run provenance propagation;
- output passes accepted E2.1 catalog validation;
- all-rejected source fails closed;
- no canonical taxonomy promotion.

### Integrity hardening

До candidate freeze был найден и закрыт implementer finding `E2_2_INTEGRITY_001_RECOMPUTED_SELECTION_TAMPER`.

Final validator не доверяет только stored selection/rejection hashes. Export embeds exact validated source evidence; validator повторно:

1. валидирует embedded source;
2. выводит selected/rejected decisions из source;
3. требует exact equality с export claims;
4. пересобирает expected E2.1 SpeciesCatalog;
5. требует exact equality expected/supplied catalog;
6. только затем принимает `bake_hash`.

Таким образом rehashed selection tamper не проходит.

### Exact attached Godot candidate evidence

```text
Godot       4.7.1.stable.double.custom_build.a13da4feb
parser      PASS
assertions  62 / 62 PASS
process A   PASS
process B   PASS
logs        byte-identical
aggregate   56d4b8bfd3064ad37b720d5bff2bc98bb72b0ab7ad871877fc268d5e6df703ce
source      c165964f710036287b9e8d310085a662d004b05eecc0c915ad1d3650a18dedb9
bake        45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b
catalog     5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219
log SHA-256 04a11281a398bf24a7880a95a01728a9a64bbac5c79e7a8aa6019ba918f329b2
```

Acceptance fixture использует synthetic source provenance и не impersonates accepted evolution result.

### Formal boundary

Полный canonical PowerShell runner ещё не исполнялся в execution container: там нет полного checkout/pwsh. Exact GitHub blobs были проверены в minimal `res://` project на exact attached Godot.

Поэтому E2.2 остаётся `CANDIDATE`, independent Reviewer PASS не заявляется и E2.3 не авторизован.

## 5. E2.3 — Frozen-Catalog Transfer

Статус: `BLOCKED_UNTIL_E2_2_ACCEPTED`.

После E2.2 acceptance SpeciesCatalog строится на source landscape, фиксируется, затем mutation/evolution выключаются.

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
CURRENT = VERIFY ECO.EVO2 / E2.2 Deterministic Evolution Bake Export
NEXT    = E2.3 Frozen-Catalog Transfer after E2.2 acceptance
```
