# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO2 E2.2 CANDIDATE_VERIFICATION`.

Canonical North Star: `docs/future_features/evolutionary_ecology/ECO_EVOLUTIONARY_ECOSYSTEM_VISION_RU.md`.
Machine roadmap: `config/ecology/eco-evolutionary-ecology-roadmap.v1.json`.
EVO2 plan: `docs/plans/ECO_EVO2_PORTABLE_SPECIES_CATALOG_ROADMAP_RU.md`.
E2.1 accepted checkpoint: `docs/checkpoints/2026-08-18_ECO_EVO2_E2_1_SPECIES_CATALOG_ACCEPTED_RU.md`.
E2.2 candidate checkpoint: `docs/checkpoints/2026-08-18_ECO_EVO2_E2_2_EVOLUTION_BAKE_EXPORT_CANDIDATE_RU.md`.

## 1. Что уже закрыто

```text
ECO.P1                    ACCEPTED
ECO.PH0..PH5-S4           ACCEPTED
ECO.CONV0-A               ACCEPTED
ECO.CAL1-A..F             ACCEPTED
CAL1-F                    ROBUST_UNITY_CALIBRATION
ECO.EVO1 / P2.1..P2.8     ACCEPTED / EVO1 COMPLETE
ECO.P3 / P3.1..P3.8       ACCEPTED / RESEARCH ROUTE COMPLETE
ECO.EVO2 / E2.1           ACCEPTED
```

Ключевые frozen identities:

```text
CAL1-F  f531fe844ceaa77094f6d259601f0df2f4b8b421328a221a1bab14196ccad1ed
P2.1    cf620f1d7896502a29a67d52f3700a570a4c585ff21a002b750e9440aee717e6
P2.2    633c797526347aa65470ad3d20490f4fe042efa9d20d5e0e68c1ff4c01182f86
P2.3    15752b545460541f5e4257c94fa5b75973274cfecc707106c24f574269f7df3e
P2.4    78273550a6a5dcb3597aa7c176683ed6b58f7238c7e51418a27f72c52f3c6c97
P2.5    292f3aba448a38e5802cfef4fc95ecbcb84fc2b89416ffc34a034cfa5705b696
P2.6    3ea48d77dd44640e14ddf064e8b6b028e27a1c0fabfd36ff57461ceed054671c
P2.7    7e814c0d8bdff952f9b86579b95fe305212ec02017c2298437e2ba3e46d2babe
P2.8    ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6
P3.1    f3e5ff9efbdee004cde58bc7de4a971cc9a17b51a13060cfc98df548c7cc425a
P3.2    172ff809b1442fc43c2534c46f1fe59363efda7d04a3f128832d61e39e144639
P3.3    37342327500b79f71ff2f5adbab51b659015311039ae5105eb00bb1705ac6c41
P3.4    a4464e5d42fb4a9e29c4a6ddfcb4c338ecbb4547bcd8bd80f430a7565df90813
P3.5    255912c4da9f1296d11f9e64bf91812ae3d32dff2726b4866c4ba761be8b8c83
P3.6    a7abcc49c2b9e7d473ceefb147996cb2febf6248bafe7004e3d5da01827cc5cc
P3.7    ef05ffb15d33819d3a6c4a1d534670e570ecb2ec674ad4a232e151e680a0e53a
P3.8    6132820a5c6597765b4f3abeeb8cf9fc9e6aaffb90ba83a1263997b17fc6f3a0
E2.1    aa23bc269738ace132fb1386ec01b339cc7fd82e1238223c1075b60dac5896ad
```

E2.1 acceptance source HEAD:

`c79e2d61e665689fe39621442f72171de5d2790f`

E2.1 code-under-test:

`bf468942718df6b84ebd4c61a294987e8e63c607`

Acceptance был выполнен как human-directed exact-attached-Godot equivalent fresh verification. Independent Reviewer PASS этим не заявлялся.

## 2. Production P4 — отдельная governance-линия

P4.1..P4.8 branch-locally завершены и собраны в lifecycle evidence. Это **не** означает global/main acceptance и **не** означает runtime merge.

Текущая граница P4:

```text
P4_BRANCH_LIFECYCLE_COMPLETE
    ↓
independent review / verifier freshness
    ↓
main-owned promotion decision
    ↓
human runtime merge gate
```

EVO2 не получает production authority из P4 и не блокируется ожиданием его promotion. Любой будущий XFER обязан повторно сверяться с canonical `main` и Project Control.

## 3. North Star EVO2

> Может ли результат эволюции стать переносимым каталогом жизненных стратегий, который без biome->asset таблиц заселяет новую, ранее не использованную среду через экологическую сортировку, конкуренцию, распространение и историю?

Целевой pipeline:

```text
environment family
    ↓
Evolution Incubator
    ↓
portable SpeciesCatalog
    ↓
unseen environment
    ↓
population ecology
    ↓
self-organized community
```

`SpeciesCatalog` — research artifact, а не canonical species taxonomy и не production owner.

## 4. EVO2 — Portable Evolutionary Ecology

```text
E2.1 SpeciesCatalog Contract                         ACCEPTED
    ↓
E2.2 Deterministic Evolution Bake Export             CANDIDATE_VERIFICATION ← CURRENT
    ↓
E2.3 Frozen-Catalog Transfer                         BLOCKED_UNTIL_E2_2_ACCEPTED
    ↓
E2.4 Environment Generalization Matrix
    ↓
E2.5 Ecological Sorting vs Continued Adaptation
    ↓
E2.6 Replicated Causal Experiments
    ↓
E2.7 Cross-Seed Robustness
    ↓
E2.8 Catalog Persistence & Provenance
    ↓
EVO2 FINAL — Unseen World Challenge
```

### E2.1 — SpeciesCatalog Contract — ACCEPTED

Frozen contract:

- stable `research_species_id`;
- source lineage identity и ancestry;
- ecological genome/traits;
- recruitment/dispersal strategy;
- observed range prior как evidence, не biome assignment;
- deterministic catalog ordering/hash;
- strict source observation shape/types;
- explicit provenance;
- `canonical_species_declared = false`;
- no global RNG consumption;
- no source-state mutation.

Canonical E2.1 aggregate:

`aa23bc269738ace132fb1386ec01b339cc7fd82e1238223c1075b60dac5896ad`

### E2.2 — Deterministic Evolution Bake Export — CANDIDATE

E2.2 реализован как typed fail-closed boundary от long-run lineage-history evidence к accepted E2.1 SpeciesCatalog.

Exact code-under-test HEAD:

`7cf98d67a4658644a6f2dde3e93e28a184638ec3`

Final implementation blob:

`6ed4abfa58c28a99fb1c28547d81e1a292756e10`

Exact attached Godot evidence:

```text
Godot      4.7.1.stable.double.custom_build.a13da4feb
parser     PASS
assertions 62 / 62 PASS
process A  PASS
process B  PASS
logs       byte-identical
aggregate  56d4b8bfd3064ad37b720d5bff2bc98bb72b0ab7ad871877fc268d5e6df703ce
source     c165964f710036287b9e8d310085a662d004b05eecc0c915ad1d3650a18dedb9
bake       45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b
catalog    5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219
```

Implemented pipeline:

```text
long-run lineage evidence
    ↓
canonical typed source + source_hash
    ↓
retention policy
    ↓
latest unambiguous representative observation
    ↓
accepted E2.1 SpeciesCatalog.build(...)
    ↓
embedded source + deterministic bake evidence
```

Retention policy:

- trailing window = 8 years;
- occupied >= 6 years in trailing window;
- lineage age >= 8 years;
- lineage must exist in final year;
- representative observation staleness <= 2 years.

Explicit rejections:

- `RECENT_LINEAGE`;
- `EXTINCT_AT_FINAL`;
- `TRANSIENT_PERSISTENCE`;
- `STALE_REPRESENTATIVE`.

Integrity boundary усилен до candidate freeze: validator embeds and revalidates exact source evidence, заново выводит selected/rejected decisions и независимо пересобирает ожидаемый E2.1 SpeciesCatalog. Поэтому изменение selection claims с пересчитанными selection/bake hashes не проходит validation.

Mutation event не считается новым species. Clustering/grouping не вводится. Одна retained lineage hypothesis остаётся одной research species entry.

Acceptance fixture имеет synthetic source provenance и **не** выдаётся за accepted evolution result. Это важно: текущий accepted P2.8 доказывает deterministic long-run Plant World persistence, но не публикует canonical multi-lineage evolved-observation collection. E2.2 фиксирует typed producer boundary для такой будущей evidence.

Текущий formal state: `CANDIDATE / NOT_SELF_ACCEPTED`. Full canonical branch runner или equivalent fresh verification ещё нужен перед acceptance.

### E2.3 — Frozen-Catalog Transfer — BLOCKED

E2.3 не открывается по implementer evidence E2.2.

После E2.2 acceptance catalog freeze mutation/evolution выключаются. Новый landscape не использовался при bake. Разрешены только dispersal, establishment, competition, population turnover, succession и disturbance/recovery.

### E2.4 — Environment Generalization Matrix

Проверяются минимум NEAR_SOURCE, DRY, WET, NUTRIENT_POOR, HIGH_SEASONALITY и PATCH_ISOLATED.

### E2.5 — Sorting vs Adaptation

Control = frozen catalog; Treatment = тот же root/catalog с продолженной evolution.

### E2.6 — Replicated Causal Experiments

Использовать доказанные patterns VIS2.2 без автоматического присвоения VIS2.2 formal PASS.

### E2.7 — Cross-Seed Robustness

Acceptance не может зависеть от одного seed.

### E2.8 — Catalog Persistence & Provenance

Typed deterministic save/load, canonical bytes/hash, schema/version boundary и fresh-process restore.

### EVO2 FINAL — Unseen World Challenge

Target environment скрыт от bake pipeline до freeze SpeciesCatalog. После открытия target система должна без hardcoded biome species tables построить причинно объяснимую spatial population truth.

## 5. После EVO2

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
    ↓
player disturbance / terraforming / invasive species
```

Животные не открываются до plant-only portable ecology proof.

## 6. Неподвижные архитектурные ограничения

```text
research ecology != production world authority
SpeciesCatalog != canonical species taxonomy
population truth != planet-wide individual entity truth
representation != ecology truth
EVO2 != permission to own G/WQ/MAT/LIFE/WB/NX foundations
```

Главный runtime принцип сохраняется:

> population is truth; individual is a representation unless interaction promotes it to durable world state.

## 7. Current resolver

```text
VERIFY ECO.EVO2 / E2.2 DETERMINISTIC EVOLUTION BAKE EXPORT
NEXT = E2.3 FROZEN-CATALOG TRANSFER AFTER E2.2 ACCEPTANCE
```
