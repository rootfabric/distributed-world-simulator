# ECO EVO2 — Portable SpeciesCatalog / Unseen World Roadmap

Статус: `ACTIVE / RESEARCH_ONLY / E2.1 ACCEPTED / E2.2 ACCEPTED / E2.3 AUTHORIZED_NOT_STARTED`.

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

P3.8 checkpoint SHA-256
1722f3ce96a8244bfaf2f8295c162b51552c6c5cc4cfd1126b40691a37bab367

P3.8 final state hash
1395e6cdfc6dc5ea963b0d077fc00c618645c8866a7e47e822bcbdd98e429cf9

E2.1 SpeciesCatalog aggregate
aa23bc269738ace132fb1386ec01b339cc7fd82e1238223c1075b60dac5896ad

E2.2 Deterministic Evolution Bake Export aggregate
56d4b8bfd3064ad37b720d5bff2bc98bb72b0ab7ad871877fc268d5e6df703ce
```

P4.1..P4.8 production-integration work существует как branch-local lifecycle evidence, но EVO2 не наследует из него production authority. P4 promotion остаётся отдельным control-plane процессом.

## 2. Species concept policy

P2.7 deliberately produced `SPECIATION_CANDIDATE`, а не canonical taxonomy.

EVO2 использует термин `research_species_id`: стабильная идентичность portable lineage hypothesis внутри research pipeline.

Это **не** означает:

- официальную биологическую таксономию;
- production-owned species registry;
- доказанную reproductive isolation;
- право объединять/разделять виды без отдельной evidence policy.

## 3. E2.1 — SpeciesCatalog Contract — ACCEPTED

Exact code-under-test:

`bf468942718df6b84ebd4c61a294987e8e63c607`

Accepted aggregate:

`aa23bc269738ace132fb1386ec01b339cc7fd82e1238223c1075b60dac5896ad`

Frozen contract сохраняет stable `research_species_id`, exact lineage/ancestry provenance, validated ecological genome/recruitment traits, canonical ordering/hash, strict source observation types, no taxonomy promotion, no global RNG consumption и no source mutation.

## 4. E2.2 — Deterministic Evolution Bake Export — ACCEPTED

Exact code-under-test:

`7cf98d67a4658644a6f2dde3e93e28a184638ec3`

Acceptance source HEAD:

`4ddf7d275d10a6a84a3e414bfb0e76447cb2a890`

Final implementation blob:

`6ed4abfa58c28a99fb1c28547d81e1a292756e10`

Accepted exact attached Godot evidence:

```text
4.7.1.stable.double.custom_build.a13da4feb
62 / 62 assertions PASS
fresh-process logs byte-identical
aggregate 56d4b8bfd3064ad37b720d5bff2bc98bb72b0ab7ad871877fc268d5e6df703ce
source    c165964f710036287b9e8d310085a662d004b05eecc0c915ad1d3650a18dedb9
bake      45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b
catalog   5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219
```

Acceptance authority: human-directed exact-attached-Godot equivalent fresh verification. Independent Reviewer PASS не заявляется.

### Frozen pipeline

```text
long-run lineage evidence
    ↓
typed canonical bake source
    ↓
deterministic retention policy
    ↓
deterministic representative observation
    ↓
accepted E2.1 SpeciesCatalog.build(...)
```

### Frozen policy

```text
trailing window                  8 years
minimum occupied years           6 / 8
minimum lineage age              8 years
max representative staleness     2 years
```

Explicit rejection reasons:

- `RECENT_LINEAGE`;
- `EXTINCT_AT_FINAL`;
- `TRANSIENT_PERSISTENCE`;
- `STALE_REPRESENTATIVE`.

Validator обязан re-derive policy decisions из embedded source evidence и независимо rebuild expected E2.1 SpeciesCatalog. Rehashed-policy tamper отвергается.

Known boundary: accepted P2.8 не предоставляет canonical multi-lineage evolved-observation collection, поэтому E2.2 acceptance использует synthetic contract fixture, который **не** impersonates accepted real evolution result. Реальный producer этой boundary остаётся будущей research integration задачей.

## 5. E2.3 — Frozen-Catalog Transfer — AUTHORIZED / CURRENT NEXT

### Goal

Доказать, что frozen catalog способен причинно заселять environment, который **не участвовал** в bake.

Ключевой экспериментальный barrier:

```text
SOURCE ENVIRONMENT FAMILY
        ↓
E2.2 bake + freeze
        X  target hidden here
        ↓
FROZEN SpeciesCatalog
        ↓
TARGET ENVIRONMENT revealed
        ↓
transfer ecology with evolution disabled
```

### Hard freeze

После начала transfer запрещены:

- mutation;
- adaptive genome changes;
- lineage creation через evolutionary kernel;
- catalog entry mutation;
- target-aware rebake;
- biome->species lookup;
- hand-written target species lists.

Разрешены:

- dispersal;
- establishment/recruitment;
- resource competition;
- density/carrying capacity;
- population turnover;
- succession;
- disturbance/recovery.

### Minimum E2.3 contract

Новый transfer result должен содержать минимум:

- exact frozen E2.2 `catalog_hash`;
- exact target environment identity/provenance;
- explicit `evolution_enabled = false`;
- initial propagule/population state;
- deterministic yearly/step history;
- occupancy by research species;
- biomass/abundance summaries;
- recruitment/extinction/recolonization events;
- final population state hash;
- transfer result hash;
- explicit success-with-no-colonization semantics, отличимые от invalid execution.

### Required acceptance gates

1. exact accepted E2.2 parent pinned;
2. target identity absent from bake provenance;
3. catalog bytes/data unchanged before/after transfer;
4. mutation/evolution path cannot be invoked through transfer API;
5. same input/seed -> exact same history/result hash;
6. shuffled catalog/input ordering -> same canonical result;
7. global RNG state untouched;
8. no biome species tables or asset scatter decisions;
9. environmental suitability alone не создаёт population — нужен causal establishment path;
10. dispersal reachability имеет значение;
11. competition может изменить composition после establishment;
12. explicit no-colonization is valid ecological result, not empty/error result;
13. malformed target/catalog/provenance fails closed;
14. fresh-process determinism;
15. source/bake/catalog objects not mutated;
16. no production authority claim.

### Initial experiment shape

Для первого E2.3 proof достаточно одного строго hidden target, но он должен отличаться от source environments и не появляться ни в E2.2 source evidence, ни в bake selection policy.

Предпочтительно создать paired target cases внутри acceptance suite:

```text
TARGET_REACHABLE
TARGET_UNREACHABLE_OR_UNSUITABLE
```

Это позволит доказать, что transfer не является unconditional catalog scatter.

E2.3 не должен заранее превращаться в E2.4 matrix; здесь нужен один хорошо контролируемый causal transfer contract.

## 6. E2.4 — Environment Generalization Matrix

После E2.3 acceptance проверяются минимум:

```text
NEAR_SOURCE
DRY
WET
NUTRIENT_POOR
HIGH_SEASONALITY
PATCH_ISOLATED
```

## 7. E2.5 — Ecological Sorting vs Continued Adaptation

```text
Control   = frozen catalog, evolution disabled
Treatment = same catalog/root, continued adaptation enabled
```

Нужно разделить ecological sorting уже существующих стратегий и новую evolutionary adaptation.

## 8. E2.6 — Replicated Causal Experiments

Использовать patterns доказанные VIS2.2: independent stochastic roots между replicates, common random numbers внутри Control/Treatment пары, aggregate causal effect, bounded evidence cache, deterministic rewind/rebranch semantics.

VIS2.2 не получает автоматический formal PASS от EVO2.

## 9. E2.7 — Cross-Seed Robustness

Acceptance не может зависеть от одного seed. Нужно различать exact history reproducibility для same seed и robust ecological regularity across different seeds.

## 10. E2.8 — Catalog Persistence & Provenance

Требуются typed deterministic persistence, schema/version boundary, canonical bytes/hash, fresh-process restore, tamper rejection, source evolution identity и explicit migration/fail-closed version policy.

## 11. EVO2 FINAL — Unseen World Challenge

Target map/environment скрыт от bake pipeline до фиксации SpeciesCatalog. После freeze target открывается population solver.

PASS требует:

1. никаких hardcoded biome->species tables;
2. deterministic same-seed replay;
3. multiple target environments дают различимые, причинно объяснимые communities;
4. spatial history имеет значение;
5. disturbance меняет trajectory, а не presentation;
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

Но XFER0 не может присвоить ECO ownership над G/WQ/MAT/LIFE/WB/NX/authority/persistence foundations.

## 13. После EVO2

Следующий research node: `EVO3 — Planetary Ecology Compiler / broader planetary generalization`.

Животные открываются только после plant-only portable ecology proof.

## 14. Current execution

```text
CURRENT = OPEN / IMPLEMENT ECO.EVO2 / E2.3 Frozen-Catalog Transfer
NEXT    = E2.4 Environment Generalization Matrix after E2.3 acceptance
```
