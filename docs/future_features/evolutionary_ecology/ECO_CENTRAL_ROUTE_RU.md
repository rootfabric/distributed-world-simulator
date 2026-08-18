# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO2 E2.5 AUTHORIZED_NOT_STARTED`.

Canonical North Star: `docs/future_features/evolutionary_ecology/ECO_EVOLUTIONARY_ECOSYSTEM_VISION_RU.md`.  
Machine roadmap: `config/ecology/eco-evolutionary-ecology-roadmap.v1.json`.  
EVO2 plan: `docs/plans/ECO_EVO2_PORTABLE_SPECIES_CATALOG_ROADMAP_RU.md`.

Последние accepted checkpoints:

- E2.1: `docs/checkpoints/2026-08-18_ECO_EVO2_E2_1_SPECIES_CATALOG_ACCEPTED_RU.md`;
- E2.2: `docs/checkpoints/2026-08-18_ECO_EVO2_E2_2_EVOLUTION_BAKE_EXPORT_ACCEPTED_RU.md`;
- E2.3: `docs/checkpoints/2026-08-18_ECO_EVO2_E2_3_FROZEN_CATALOG_TRANSFER_ACCEPTED_RU.md`;
- E2.4: `docs/checkpoints/2026-08-18_ECO_EVO2_E2_4_ENVIRONMENT_GENERALIZATION_MATRIX_ACCEPTED_RU.md`.

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
```

Frozen identities relevant to current route:

```text
P2.6  3ea48d77dd44640e14ddf064e8b6b028e27a1c0fabfd36ff57461ceed054671c
P2.8  ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6
P3.8  6132820a5c6597765b4f3abeeb8cf9fc9e6aaffb90ba83a1263997b17fc6f3a0
E2.1  aa23bc269738ace132fb1386ec01b339cc7fd82e1238223c1075b60dac5896ad
E2.2  56d4b8bfd3064ad37b720d5bff2bc98bb72b0ab7ad871877fc268d5e6df703ce
E2.3  82d76f858568d5bd53af4d299abd2155f2fde7e845de828cf4555e601ee1efa8
E2.4  ae2952de10ac721c8052694963b690d9f72af05d9c92e2fa4cd70e00f72fb2b5
```

E2.2 exact frozen artifact:

```text
bake     45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b
catalog  5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219
```

## 2. E2.3 — Frozen-Catalog Transfer — ACCEPTED

Exact code-under-test: `c7ee41371807ed7dbb75e7e1eae1587105873a26`.

E2.3 proved the causal transfer boundary: the same suitable environment colonizes when reachable and remains `VALID_NO_COLONIZATION` when isolated. It also established the Harness rule that canonical behavioral verification needs exact transitive executable closure, not merely exact top-level files.

Acceptance authority: human-directed exact-attached-Godot equivalent fresh behavioral execution. Independent Reviewer/Verifier PASS is not claimed.

## 3. E2.4 — Environment Generalization Matrix — ACCEPTED

Exact code-under-test:

`0135aee461a107375cdb3e52e07e8c799145998b`

Implementation blob:

`823ef6445d7f71aee79b7c0bb0932b321f90ce8d`

Accepted evidence:

```text
exact transitive executable closure   18 / 18 PASS
Godot                                4.7.1.stable.double.custom_build.a13da4feb
parser/preload                       PASS
fresh process A                      PASS
fresh process B                      PASS
assertions                           82 / 82 PASS
logs                                 byte-identical
aggregate                            ae2952de10ac721c8052694963b690d9f72af05d9c92e2fa4cd70e00f72fb2b5
plan                                 f688eb014245d63483562376c3f5db8c08a85bdc35feb52428f5ff17753f82e0
```

Один exact frozen E2.2 catalog прошёл через шесть environment/geography classes без rebake и target-aware species list:

```text
NEAR_SOURCE       COLONIZED year 1
DRY               COLONIZED year 1
WET               COLONIZED year 1
NUTRIENT_POOR     COLONIZED year 1
HIGH_SEASONALITY  four deterministic envelope phases; all execute validly
PATCH_ISOLATED    VALID_NO_COLONIZATION
```

Главный causal control сохраняется: `PATCH_ISOLATED` использует exact тот же environment checksum, что `NEAR_SOURCE`, но отличается только географической достижимостью. Это не позволяет suitability сама по себе создавать population truth.

`HIGH_SEASONALITY` намеренно ограничен режимом `SEASONAL_ENVELOPE`:

```text
COOL_WET
MILD
HOT_DRY
COOL_DARK
```

Все четыре phase используют один стабильный unseen target patch, но разные deterministic EnvironmentSample. Это доказывает portability across seasonal extremes, **но не заявляет непрерывную seasonal population dynamics**.

Environment challenge меняет population state/history даже при одном frozen catalog. Evolution/mutation остаётся disabled. No biome-to-species mapping.

Canonical PowerShell runner не запускался в текущем Linux carrier из-за отсутствия `pwsh`/`powershell`; явно классифицированный equivalent gate воспроизвёл parent pins, exact closure, parser, behavioral assertions, fresh-process determinism и frozen output predicates. Independent Reviewer/Verifier PASS не заявляется.

## 4. Current research route

```text
E2.1 SpeciesCatalog Contract                         ACCEPTED
    ↓
E2.2 Deterministic Evolution Bake Export             ACCEPTED
    ↓
E2.3 Frozen-Catalog Transfer                         ACCEPTED
    ↓
E2.4 Environment Generalization Matrix               ACCEPTED
    ↓
E2.5 Ecological Sorting vs Continued Adaptation      ← AUTHORIZED / NEXT
    ↓
E2.6 Replicated Causal Experiments
    ↓
E2.7 Cross-Seed Robustness
    ↓
E2.8 Catalog Persistence & Provenance
    ↓
EVO2 FINAL — Unseen World Challenge
```

## 5. E2.5 — Ecological Sorting vs Continued Adaptation

Следующий вопрос EVO2: какую часть ответа новой среды объясняет сортировка уже существующих frozen strategies, а какую — новая adaptation после transfer?

Causal paired design:

```text
CONTROL
exact E2.4 parent artifact
+ frozen catalog
+ evolution disabled
+ unseen environment exposure
        ↓
ecological sorting only

TREATMENT
same exact parent catalog/root
+ same environment exposure
+ bounded continued adaptation enabled
        ↓
ecological sorting + new adaptation
```

E2.5 должен отличать:

- изменение abundance/composition уже существующих research species;
- появление нового adapted descendant/strategy state;
- improvement, вызванный mutation/selection после transfer;
- простой demographic/ecological sorting без genetic change.

Не разрешается:

- менять исходный catalog между Control/Treatment;
- использовать разные target environments;
- скрытый target-aware rebake;
- biome→species lookup;
- считать mutation автоматически новым canonical biological species;
- смешивать production authority с research lineage evidence.

E2.6 остаётся заблокирован до formal E2.5 acceptance.

## 6. Production P4 — отдельная governance-линия

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

## 7. Неподвижные архитектурные ограничения

```text
research ecology != production world authority
SpeciesCatalog != canonical species taxonomy
population truth != planet-wide individual entity truth
representation != ecology truth
EVO2 != permission to own G/WQ/MAT/LIFE/WB/NX foundations
```

Главный runtime принцип:

> population is truth; individual is a representation unless interaction promotes it to durable world state.

## 8. Current resolver

```text
OPEN / IMPLEMENT ECO.EVO2 / E2.5 ECOLOGICAL SORTING VS CONTINUED ADAPTATION
```
