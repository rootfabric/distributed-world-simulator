# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO2 E2.6 AUTHORIZED_NOT_STARTED`.

Canonical North Star: `docs/future_features/evolutionary_ecology/ECO_EVOLUTIONARY_ECOSYSTEM_VISION_RU.md`.  
Machine roadmap: `config/ecology/eco-evolutionary-ecology-roadmap.v1.json`.  
EVO2 plan: `docs/plans/ECO_EVO2_PORTABLE_SPECIES_CATALOG_ROADMAP_RU.md`.

Последние accepted checkpoints:

- E2.1: `docs/checkpoints/2026-08-18_ECO_EVO2_E2_1_SPECIES_CATALOG_ACCEPTED_RU.md`;
- E2.2: `docs/checkpoints/2026-08-18_ECO_EVO2_E2_2_EVOLUTION_BAKE_EXPORT_ACCEPTED_RU.md`;
- E2.3: `docs/checkpoints/2026-08-18_ECO_EVO2_E2_3_FROZEN_CATALOG_TRANSFER_ACCEPTED_RU.md`;
- E2.4: `docs/checkpoints/2026-08-18_ECO_EVO2_E2_4_ENVIRONMENT_GENERALIZATION_MATRIX_ACCEPTED_RU.md`;
- E2.5: `docs/checkpoints/2026-08-18_ECO_EVO2_E2_5_SORTING_VS_ADAPTATION_ACCEPTED_RU.md`.

## 1. Принятый research фундамент

```text
ECO.P1                    ACCEPTED
ECO.PH0..PH5-S4           ACCEPTED
ECO.CONV0-A               ACCEPTED
ECO.CAL1-A..F             ACCEPTED
CAL1-F                    ROBUST_UNITY_CALIBRATION
ECO.EVO1 / P2.1..P2.8     ACCEPTED / EVO1 COMPLETE
ECO.P3 / P3.1..P3.8       ACCEPTED / RESEARCH ROUTE COMPLETE
ECO.EVO2 / E2.1           ACCEPTED
ECO.EVO2 / E2.2           ACCEPTED
ECO.EVO2 / E2.3           ACCEPTED
ECO.EVO2 / E2.4           ACCEPTED
ECO.EVO2 / E2.5           ACCEPTED
```

Frozen identities relevant to current route:

```text
P2.8  ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6
P3.8  6132820a5c6597765b4f3abeeb8cf9fc9e6aaffb90ba83a1263997b17fc6f3a0
E2.1  aa23bc269738ace132fb1386ec01b339cc7fd82e1238223c1075b60dac5896ad
E2.2  56d4b8bfd3064ad37b720d5bff2bc98bb72b0ab7ad871877fc268d5e6df703ce
E2.3  82d76f858568d5bd53af4d299abd2155f2fde7e845de828cf4555e601ee1efa8
E2.4  ae2952de10ac721c8052694963b690d9f72af05d9c92e2fa4cd70e00f72fb2b5
E2.5  942ad54e7672c4f57874e1802b320c1b2a4aa74e43b05f7e285793ea4ec8b2a6
```

E2.2 exact frozen artifact:

```text
bake     45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b
catalog  5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219
```

## 2. Что уже доказано EVO2

### E2.3 — transfer

Одинаково подходящая unseen environment колонизируется, если causal dispersal делает её reachable, и остаётся `VALID_NO_COLONIZATION`, если она географически изолирована.

### E2.4 — generalization

Один frozen catalog без rebake проходит через `NEAR_SOURCE / DRY / WET / NUTRIENT_POOR / HIGH_SEASONALITY / PATCH_ISOLATED`. `HIGH_SEASONALITY` остаётся four-phase deterministic envelope, а не claim непрерывной seasonal population dynamics.

### E2.5 — sorting vs adaptation

Exact code-under-test:

`4c17a91957e392eabc04e136f9590773dbe54dd1`

Implementation blob:

`74443f7b0c1b5e2234b1949761abc6cfab4bdd9c`

Accepted evidence:

```text
exact transitive executable closure  21 / 21 PASS
Godot                               4.7.1.stable.double.custom_build.a13da4feb
parser/preload                      PASS
fresh process A                     PASS
fresh process B                     PASS
assertions                          93 / 93 PASS
logs                                byte-identical
aggregate                           942ad54e7672c4f57874e1802b320c1b2a4aa74e43b05f7e285793ea4ec8b2a6
```

E2.5 использует causal pair:

```text
CONTROL
same frozen catalog + same environment + mutation_probability=0
→ ecological sorting only

TREATMENT
same founders + same environment + one fixed bounded mutation policy
→ inherited variation + ResourceModel selection
```

DRY и WET Control arms меняют abundance при `novel_genome_count=0`, то есть демонстрируют pure ecological sorting. При этом DRY выбирает frozen alpha strategy, а WET — frozen beta strategy.

Treatment не получает target-aware bonus: candidate consequence считается только через accepted `ResourceModel`. Mutation считается adaptation только если одновременно есть novel inherited genome и положительный gain относительно frozen Control.

Observed paired result:

```text
DRY
sorting gain      +0.712602797217
adaptation gain   +0.210067450172
classification    ADAPTATION_DETECTED

WET
sorting gain      +1.231209807202
adaptation gain   +0.387714189995
classification    ADAPTATION_DETECTED
```

Reciprocal cross-environment check:

```text
DRY-adapted in DRY   +0.500903251638
WET-adapted in DRY   -1.600499312923

WET-adapted in WET   +1.157255352906
DRY-adapted in WET   -1.601811151164
```

То есть adaptive response environment-specific, а не просто общий fitness inflation.

Adapted descendant сохраняет исходный `research_species_id/source_lineage_id`; это не canonical speciation.

Canonical PowerShell runner существует, но в Linux carrier нет `pwsh/powershell`; acceptance основана на explicit equivalent fresh behavioral gate. Independent Reviewer/Verifier PASS не заявляется.

## 3. Current research route

```text
E2.1 SpeciesCatalog Contract                         ACCEPTED
    ↓
E2.2 Deterministic Evolution Bake Export             ACCEPTED
    ↓
E2.3 Frozen-Catalog Transfer                         ACCEPTED
    ↓
E2.4 Environment Generalization Matrix               ACCEPTED
    ↓
E2.5 Ecological Sorting vs Continued Adaptation      ACCEPTED
    ↓
E2.6 Replicated Causal Experiments                   ← AUTHORIZED / NEXT
    ↓
E2.7 Cross-Seed Robustness
    ↓
E2.8 Catalog Persistence & Provenance
    ↓
EVO2 FINAL — Unseen World Challenge
```

## 4. E2.6 — Replicated Causal Experiments

E2.5 сейчас является сильным deterministic paired assay, но всё ещё одной зафиксированной causal trajectory. E2.6 должен проверить, сохраняется ли вывод на bounded replication set.

Минимальная задача E2.6:

```text
same frozen starting catalog
same declared Control/Treatment protocol
multiple deterministic replicate identities
        ↓
per-replicate paired effects
        ↓
effect consistency / reversals / null outcomes
        ↓
replicated causal evidence package
```

E2.6 должен:

- повторять causal pairing, а не сравнивать несвязанные runs;
- заранее фиксировать replication set и seed/stream derivation;
- сохранять Control/Treatment identity locks;
- различать `ADAPTATION_DETECTED`, `ADAPTATION_NO_MEASURABLE_ADVANTAGE`, `SORTING_ONLY_RESPONSE`, `NO_RESPONSE`;
- показывать distribution/sign consistency, а не только среднее;
- сохранять отрицательные/null replicates, а не фильтровать их;
- использовать VIS2.2 observability/evidence patterns как технический шаблон без автоматического наследования PASS;
- не открывать E2.7 до formal E2.6 acceptance.

## 5. Production P4 — отдельная governance-линия

P4 branch lifecycle завершён, но это не global/main acceptance и не runtime merge. Нужны independent review/verifier freshness и main-owned promotion decision. EVO2 не получает production authority из P4.

## 6. Неподвижные архитектурные ограничения

```text
research ecology != production world authority
SpeciesCatalog != canonical species taxonomy
adapted descendant != automatic new canonical species
population truth != planet-wide individual entity truth
representation != ecology truth
EVO2 != permission to own G/WQ/MAT/LIFE/WB/NX foundations
```

Главный runtime принцип:

> population is truth; individual is a representation unless interaction promotes it to durable world state.

## 7. Current resolver

```text
OPEN / IMPLEMENT ECO.EVO2 / E2.6 REPLICATED CAUSAL EXPERIMENTS
```
