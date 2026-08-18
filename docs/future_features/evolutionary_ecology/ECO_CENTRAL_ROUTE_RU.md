# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO2 E2.7 AUTHORIZED_NOT_STARTED`.

Canonical North Star: `docs/future_features/evolutionary_ecology/ECO_EVOLUTIONARY_ECOSYSTEM_VISION_RU.md`.  
Machine roadmap: `config/ecology/eco-evolutionary-ecology-roadmap.v1.json`.  
EVO2 plan: `docs/plans/ECO_EVO2_PORTABLE_SPECIES_CATALOG_ROADMAP_RU.md`.

Последние accepted checkpoints:

- E2.1: `docs/checkpoints/2026-08-18_ECO_EVO2_E2_1_SPECIES_CATALOG_ACCEPTED_RU.md`;
- E2.2: `docs/checkpoints/2026-08-18_ECO_EVO2_E2_2_EVOLUTION_BAKE_EXPORT_ACCEPTED_RU.md`;
- E2.3: `docs/checkpoints/2026-08-18_ECO_EVO2_E2_3_FROZEN_CATALOG_TRANSFER_ACCEPTED_RU.md`;
- E2.4: `docs/checkpoints/2026-08-18_ECO_EVO2_E2_4_ENVIRONMENT_GENERALIZATION_MATRIX_ACCEPTED_RU.md`;
- E2.5: `docs/checkpoints/2026-08-18_ECO_EVO2_E2_5_SORTING_VS_ADAPTATION_ACCEPTED_RU.md`;
- E2.6: `docs/checkpoints/2026-08-18_ECO_EVO2_E2_6_REPLICATED_CAUSAL_EXPERIMENTS_ACCEPTED_RU.md`.

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
ECO.EVO2 / E2.6           ACCEPTED
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
E2.6  1a4bcf1cffe65450a27037e9307bb5c7ac3cb8a98899918207107e367d9d5fbd
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

Одинаковые frozen founders и environment сначала показывают ecological sorting в Control с mutation disabled, а затем environment-specific inherited adaptation в Treatment. DRY/WET reciprocal cross-environment test отвергает простой global fitness inflation.

Exact E2.5 aggregate:

`942ad54e7672c4f57874e1802b320c1b2a4aa74e43b05f7e285793ea4ec8b2a6`.

### E2.6 — replicated causal experiments — ACCEPTED

Exact code-under-test:

`8ac37bfea0f36731407e1252db1a7c2a2305420e`

Implementation blob:

`7fb18d91ba59493c608edafba610dc882152852a`

Replication protocol был frozen **до** acceptance execution:

```text
replicates = R01 / R02 / R03 / R04 / R05
all records retained
post-hoc censoring forbidden
positive adaptation threshold >= 4/5 per environment
reciprocal home-advantage threshold >= 4/5 per environment
```

Control/Treatment сохраняют E2.5 causal identity lock. Различается только permission for bounded inherited adaptation.

Fresh exact evidence:

```text
exact transitive executable closure   7 / 7 PASS
Godot                                4.7.1.stable.double.custom_build.a13da4feb
parser/preload                       PASS
fresh process A                      PASS
fresh process B                      PASS
assertions                           218 / 218 PASS
logs                                 byte-identical
aggregate                            1a4bcf1cffe65450a27037e9307bb5c7ac3cb8a98899918207107e367d9d5fbd
replicate set                        5e02d04d3d94f95f6e8e76f6387ee07c723d2e596046f6a65d65cd815abbc637
```

Observed retained replication result:

```text
DRY
mean adaptation gain       +0.235359270024
positive effects           5 / 5
reciprocal home advantage  5 / 5

WET
mean adaptation gain       +0.379178153879
positive effects           5 / 5
reciprocal home advantage  5 / 5
```

Важно: acceptance protocol требовал только 4/5 и не позволял удалять null/reversal runs. Получившийся 5/5 — наблюдаемый результат, а не заранее встроенное требование.

E2.6 намеренно **не** заявляет p-value/statistical significance и **не** заявляет broad cross-seed robustness. Пять deterministic replicate streams подтверждают replication causal effect; более широкий robustness claim оставлен E2.7.

Canonical PowerShell runner существует (`08a2ffbfbe1b3c28b020571256b6831d37d97fcb`), но в Linux carrier нет `pwsh/powershell`; acceptance основана на explicit equivalent fresh behavioral gate. Independent Reviewer/Verifier PASS не заявляется.

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
E2.6 Replicated Causal Experiments                   ACCEPTED
    ↓
E2.7 Cross-Seed Robustness                           ← AUTHORIZED / NEXT
    ↓
E2.8 Catalog Persistence & Provenance
    ↓
EVO2 FINAL — Unseen World Challenge
```

## 4. E2.7 — Cross-Seed Robustness

E2.7 должен перейти от малого replicated set к заранее объявленному более широкому seed ensemble и проверить, насколько causal adaptation conclusion устойчив к variation stream choice.

Минимальные правила E2.7:

- seed ensemble фиксируется до выполнения и хэшируется;
- E2.6 `R01..R05` не считается достаточным E2.7 proof автоматически;
- все seeds/runs сохраняются, включая null, reversal и failed-effect outcomes;
- никакой post-hoc seed selection;
- те же frozen catalog/environment/policy identities;
- effect distribution фиксирует median, quantiles/range и sign consistency, а не только mean;
- sensitivity к отдельному seed/leave-one-out должна быть явной;
- robustness threshold фиксируется до acceptance run;
- если вводится statistical confidence, метод и threshold фиксируются до просмотра результата;
- DRY/WET reciprocal local-adaptation contrast остаётся обязательной частью robustness evidence;
- E2.8 не открывается до formal E2.7 acceptance.

E2.7 не должен менять biological mechanism или подгонять mutation policy. Его задача — проверить устойчивость уже принятого E2.5/E2.6 механизма.

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
OPEN / IMPLEMENT ECO.EVO2 / E2.7 CROSS-SEED ROBUSTNESS
```
