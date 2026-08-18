# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO2 E2.4 AUTHORIZED_NOT_STARTED`.

Canonical North Star: `docs/future_features/evolutionary_ecology/ECO_EVOLUTIONARY_ECOSYSTEM_VISION_RU.md`.  
Machine roadmap: `config/ecology/eco-evolutionary-ecology-roadmap.v1.json`.  
EVO2 plan: `docs/plans/ECO_EVO2_PORTABLE_SPECIES_CATALOG_ROADMAP_RU.md`.

Последние accepted checkpoints:

- E2.1: `docs/checkpoints/2026-08-18_ECO_EVO2_E2_1_SPECIES_CATALOG_ACCEPTED_RU.md`;
- E2.2: `docs/checkpoints/2026-08-18_ECO_EVO2_E2_2_EVOLUTION_BAKE_EXPORT_ACCEPTED_RU.md`;
- E2.3: `docs/checkpoints/2026-08-18_ECO_EVO2_E2_3_FROZEN_CATALOG_TRANSFER_ACCEPTED_RU.md`.

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
```

Frozen identities relevant to current route:

```text
P2.6  3ea48d77dd44640e14ddf064e8b6b028e27a1c0fabfd36ff57461ceed054671c
P2.8  ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6
P3.8  6132820a5c6597765b4f3abeeb8cf9fc9e6aaffb90ba83a1263997b17fc6f3a0
E2.1  aa23bc269738ace132fb1386ec01b339cc7fd82e1238223c1075b60dac5896ad
E2.2  56d4b8bfd3064ad37b720d5bff2bc98bb72b0ab7ad871877fc268d5e6df703ce
E2.3  82d76f858568d5bd53af4d299abd2155f2fde7e845de828cf4555e601ee1efa8
```

E2.2 exact frozen artifact:

```text
bake     45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b
catalog  5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219
```

## 2. E2.3 — Frozen-Catalog Transfer — ACCEPTED

Exact code-under-test:

`c7ee41371807ed7dbb75e7e1eae1587105873a26`

Final implementation blob:

`a886d179fe32a2bb531956923fd0cc59bbbb28c6`

Fresh canonical behavioral evidence:

```text
exact transitive executable closure  17 / 17 PASS
Godot                              4.7.1.stable.double.custom_build.a13da4feb
parser/preload                     PASS
fresh process A                    PASS
fresh process B                    PASS
assertions                         59 / 59 PASS
logs                               byte-identical
aggregate                          82d76f858568d5bd53af4d299abd2155f2fde7e845de828cf4555e601ee1efa8
```

Causal paired result:

```text
same hidden environment suitability
        ↓
reachable target   → COLONIZED, first year 1
isolated target    → VALID_NO_COLONIZATION
```

E2.3 acceptance также доказала, что exact top-level files недостаточны для canonical execution: полный transitive closure должен быть exact до запуска. Это discovery передано в отдельный Harness control candidate.

Во время first fresh execution был найден реальный defect source-port bias: moisture `0.58` не позволяла одной frozen strategy размножаться. Repair сделал source-port target-independent, но нейтральным для обеих strategies (`0.40`), после чего весь exact closure и 59 assertions были повторно прогнаны.

Acceptance authority: human-directed exact-attached-Godot equivalent fresh behavioral execution. Independent Reviewer/Verifier PASS **не заявляется**.

## 3. Current research route

```text
E2.1 SpeciesCatalog Contract                         ACCEPTED
    ↓
E2.2 Deterministic Evolution Bake Export             ACCEPTED
    ↓
E2.3 Frozen-Catalog Transfer                         ACCEPTED
    ↓
E2.4 Environment Generalization Matrix               ← AUTHORIZED / NEXT
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

## 4. E2.4 — Environment Generalization Matrix

Цель: перестать доказывать portability на одной hidden target и проверить один и тот же frozen catalog на контролируемом наборе сред без rebake и без biome->species mapping.

Минимальная matrix:

```text
NEAR_SOURCE
DRY
WET
NUTRIENT_POOR
HIGH_SEASONALITY
PATCH_ISOLATED
```

Hard invariants сохраняются:

- exact E2.2/E2.3 frozen lineage;
- evolution/mutation disabled;
- одинаковый catalog для всех matrix cells;
- target environment не участвует в bake;
- population starts empty;
- no hard-coded target species list;
- causal dispersal/establishment/competition/turnover;
- valid no-colonization допустим;
- deterministic same-input replay;
- canonical behavioral evidence требует exact transitive executable closure.

E2.5 не открывается до formal E2.4 acceptance.

## 5. Production P4 — отдельная governance-линия

P4.1..P4.8 branch-locally завершены, но это **не** global/main acceptance и **не** runtime merge.

```text
P4_BRANCH_LIFECYCLE_COMPLETE
    ↓
independent review / verifier freshness
    ↓
main-owned promotion decision
    ↓
human runtime merge gate
```

EVO2 не получает production authority из P4.

## 6. Неподвижные архитектурные ограничения

```text
research ecology != production world authority
SpeciesCatalog != canonical species taxonomy
population truth != planet-wide individual entity truth
representation != ecology truth
EVO2 != permission to own G/WQ/MAT/LIFE/WB/NX foundations
```

Главный runtime принцип:

> population is truth; individual is a representation unless interaction promotes it to durable world state.

## 7. Current resolver

```text
OPEN / IMPLEMENT ECO.EVO2 / E2.4 ENVIRONMENT GENERALIZATION MATRIX
```
