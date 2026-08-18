# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO2 E2.1 CANDIDATE_VERIFICATION`.

Canonical North Star: `docs/future_features/evolutionary_ecology/ECO_EVOLUTIONARY_ECOSYSTEM_VISION_RU.md`.
Machine roadmap: `config/ecology/eco-evolutionary-ecology-roadmap.v1.json`.
EVO2 plan: `docs/plans/ECO_EVO2_PORTABLE_SPECIES_CATALOG_ROADMAP_RU.md`.
E2.1 checkpoint: `docs/checkpoints/2026-08-18_ECO_EVO2_E2_1_SPECIES_CATALOG_CANDIDATE_RU.md`.

## 1. Что уже закрыто

```text
ECO.P1                    ACCEPTED
ECO.PH0..PH5-S4           ACCEPTED
ECO.CONV0-A               ACCEPTED
ECO.CAL1-A..F             ACCEPTED
CAL1-F                    ROBUST_UNITY_CALIBRATION
ECO.EVO1 / P2.1..P2.8     ACCEPTED / EVO1 COMPLETE
ECO.P3 / P3.1..P3.8       ACCEPTED / RESEARCH ROUTE COMPLETE
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
```

P2.8 exact acceptance доказал deterministic save/restart Plant World и закрыл EVO1. P3 затем доказал resource competition, carrying capacity, spatial dispersal, environmental gradients, seasonal forcing, disturbance/succession, multi-niche coexistence и deterministic ecosystem persistence.

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

## 3. Новый North Star после EVO1/P3

Следующий исследовательский вопрос:

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

`SpeciesCatalog` здесь — research artifact. Он не является canonical species taxonomy проекта и не получает production ownership.

## 4. EVO2 — Portable Evolutionary Ecology

```text
E2.1 SpeciesCatalog Contract                         ← CANDIDATE_VERIFICATION
    ↓ exact canonical branch gate required
E2.2 Deterministic Evolution Bake Export             ← BLOCKED UNTIL E2.1 ACCEPTED
    ↓
E2.3 Frozen-Catalog Transfer
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

### E2.1 — SpeciesCatalog Contract

Реализован research-only portable contract:

- stable `research_species_id`;
- source lineage identity и ancestry;
- ecological genome/traits;
- recruitment/dispersal strategy;
- observed range prior как evidence, а не biome assignment;
- source observation/evidence hashes;
- deterministic catalog ordering/hash;
- explicit provenance;
- fail-closed validation;
- `canonical_species_declared = false`.

E2.1 не решает clustering/species concept целиком. Один validated lineage hypothesis образует одну portable entry; E2.2 отвечает за deterministic bake selection/grouping policy.

Current exact candidate evidence:

```text
code-under-test HEAD
bf468942718df6b84ebd4c61a294987e8e63c607

Godot
4.7.1.stable.double.custom_build.a13da4feb

acceptance assertions
53 / 53 PASS

fresh-process replay
byte-identical

aggregate_hash
aa23bc269738ace132fb1386ec01b339cc7fd82e1238223c1075b60dac5896ad
```

Exact Git blobs для нового contract, acceptance test и его ECO dependencies были сверены с GitHub перед запуском. Дополнительно найден и закрыт fail-closed gap: E2.1 запрещает legacy extra fields и `float`-Variant `split_year`, которые старый P2.7 validator способен семантически принять.

Однако полный `RUN_ECO_EVO2_E2_1_TESTS.ps1` в canonical Git worktree здесь не выполнялся. Поэтому:

```text
E2.1 = STRONG CANDIDATE
E2.1 != SELF_ACCEPTED
E2.2 = BLOCKED
```

### E2.2 — Deterministic Evolution Bake Export

После E2.1 acceptance из frozen evolution result нужно получить воспроизводимый каталог устойчивых lineage hypotheses. Acceptance требует одинакового каталога при повторе exact inputs и отсутствия зависимости от iteration order/global RNG.

### E2.3 — Frozen-Catalog Transfer

Запретить mutation/evolution и проверить, может ли один каталог сформировать разумное сообщество в новой карте только через ecology: establishment, competition, dispersal, succession и disturbance.

### E2.4 — Environment Generalization Matrix

Проверить минимум близкую, сухую, влажную, nutrient-poor, seasonal и patch-isolated среды. Acceptance — не одинаковый species list, а причинно объяснимая смена occupancy/biomass/extinction/colonization.

### E2.5 — Sorting vs Adaptation

Control использует frozen catalog; Treatment разрешает дальнейшую evolution. Измерять отдельно ecological sorting и новую evolutionary adaptation.

### E2.6 — Replicated Causal Experiments

Использовать проверенные идеи VIS2.2: независимые stochastic roots, Control/Treatment CRN внутри пары, aggregate effect и reproducible rewind/rebranch evidence. VIS2.2 остаётся отдельной research/evidence lineage; его формальная closure не подменяется этим документом.

### E2.7 — Cross-Seed Robustness

Запретить acceptance по одному «красивому seed». Разные seeds могут давать разные истории, но ключевые закономерности должны сохраняться статистически.

### E2.8 — Catalog Persistence & Provenance

Доказать typed deterministic save/load, stable hashes, schema/version migration boundary, engine/model provenance и fresh-process restore.

### EVO2 FINAL — Unseen World Challenge

Каталог, сформированный без знания target map, получает новую EnvironmentProfile/landscape. Система должна без hardcoded biome species tables получить устойчивую spatial population truth с причинно объяснимой структурой.

## 5. Что после EVO2

При PASS EVO2 открывается bounded XFER0 и следующий исследовательский слой:

```text
EVO2 portable ecology proof
    ↓
bounded XFER0 contracts
    ↓
EVO3 Planetary Ecology Compiler / broader planetary generalization
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
VERIFY ECO.EVO2 / E2.1 SPECIES CATALOG CONTRACT ON CANONICAL BRANCH RUNNER
THEN OPEN E2.2 DETERMINISTIC EVOLUTION BAKE EXPORT
```
