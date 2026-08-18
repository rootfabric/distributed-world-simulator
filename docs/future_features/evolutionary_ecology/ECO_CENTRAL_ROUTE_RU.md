# ECO — Центральный маршрут развития ветки

Статус: `RESEARCH_ONLY / EVO2 COMPLETE / XFER0 BOUNDED DESIGN NEXT`.

Canonical North Star: `docs/future_features/evolutionary_ecology/ECO_EVOLUTIONARY_ECOSYSTEM_VISION_RU.md`.  
Machine roadmap: `config/ecology/eco-evolutionary-ecology-roadmap.v1.json`.  
EVO2 plan: `docs/plans/ECO_EVO2_PORTABLE_SPECIES_CATALOG_ROADMAP_RU.md`.

## 1. Accepted research frontier

```text
ECO.P1                    ACCEPTED
ECO.PH0..PH5-S4           ACCEPTED
ECO.CONV0-A               ACCEPTED
ECO.CAL1-A..F             ACCEPTED
CAL1-F                    ROBUST_UNITY_CALIBRATION
ECO.EVO1 / P2.1..P2.8     ACCEPTED / EVO1 COMPLETE
ECO.P3 / P3.1..P3.8       ACCEPTED / RESEARCH ROUTE COMPLETE
ECO.EVO2 / E2.1..E2.8     ACCEPTED
ECO.EVO2 / E2.FINAL       ACCEPTED / EVO2 RESEARCH ROUTE COMPLETE
```

Последний checkpoint:

`docs/checkpoints/2026-08-18_ECO_EVO2_FINAL_UNSEEN_WORLD_CHALLENGE_ACCEPTED_RU.md`

Machine validation:

`validation/ecology/eco-evo2-final-unseen-world-validation.json`

Frozen FINAL identities:

```text
E2.8 aggregate        4182176c1cc8b6d609fefc7057b5ff5307c92f839682e76f6168841d60275061
E2.8 transport        b31c863f8e1943e5778d56631f8c8ad75b95f3b9d3930a699f80fd07595d45d1
E2.2 catalog          5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219
FINAL protocol commit d936efac36d2664ec2f24f26306fa3ba95409117
FINAL code-under-test  376796ab8c8370b7370fcd220ed207d07955cb42
FINAL protocol hash   d3dc2b0c2a251cf645d03430eb14ad2215166a5be03f5ec13b8eafb4d56678e1
FINAL evidence hash   989e5ae02e66052ca7d2e46f5f452446300ba625dd4efd5cd6b5ffd9db2f2cd1
FINAL aggregate       6daab256af3d1e7693c66a8afaad4d04fd1564c4376b9f3cd747a268a10c2250
```

## 2. Что доказал EVO2 целиком

```text
causal evolutionary ecology
        ↓
deterministic portable SpeciesCatalog         E2.1 / E2.2
        ↓
frozen-catalog hidden-target transfer         E2.3
        ↓
environment generalization                    E2.4
        ↓
sorting separated from continued adaptation   E2.5
        ↓
replicated causal experiments                 E2.6
        ↓
cross-seed bounded robustness                 E2.7
        ↓
exact catalog persistence + provenance        E2.8
        ↓
persisted-catalog unseen-world proof          E2.FINAL
```

Research North Star EVO2 выполнен: portable frozen research catalog можно сохранить, восстановить в новом процессе и применить к заранее зафиксированному unseen world без biome → species shortcut. Заселение возникает через causal dispersal/establishment/migration, после чего ecological sorting и continued adaptation остаются раздельно наблюдаемыми механизмами.

## 3. E2.FINAL — Unseen World Challenge — ACCEPTED

### 3.1 Precommit discipline

Hidden world и acceptance thresholds были записаны отдельным commit **до первого behavioral result**:

```text
protocol commit  d936efac36d2664ec2f24f26306fa3ba95409117
protocol blob    372591ee3bee1c19538729259373e97fd9838461
protocol hash    d3dc2b0c2a251cf645d03430eb14ad2215166a5be03f5ec13b8eafb4d56678e1
```

После первого результата geometry, environments, transport и thresholds не менялись.

Frozen world:

```text
reachable   dry-ridge / wet-basin
control     isolated-control
transport   Vector2(1, 0), turbulence 0.25
emission    frozen genome seed_count × 32
population  8
adaptation  10 generations × 4 offspring/parent
```

Frozen minimum gates:

```text
reachable colonized patches >= 2
unique recruited species    >= 2
sorting observed cells      >= 1
adaptation-positive cells   >= 1
isolated control colonized  false
```

`ADAPTATION_NULL`, `ADAPTATION_REVERSAL` и `VALID_NO_COLONIZATION` остаются допустимыми evidence classes; post-hoc censorship запрещён.

### 3.2 End-to-end route

FINAL принимает именно bytes accepted E2.8 artifact:

```text
fresh E2.8 writer
        ↓
10,383-byte artifact / transport b31c863f...
        ↓
fresh Persistence.restore
        ↓
exact SpeciesCatalog + EVO2 provenance
        ↓
ALL restored catalog entries enter source port
        ↓
P2.1 dispersal
        ↓
establishment / seed bank / ResourceModel viability
        ↓
P2.4 patch migration
        ↓
actual recruited counts
        ↓
colonization-derived founders
        ↓
paired CONTROL / TREATMENT sorting + continued adaptation
```

FINAL implementation intentionally has no direct `Catalog.build`, no accepted-catalog reconstruction preload, no bake-export preload и no direct SpeciesCatalog builder preload. Rebake, target-aware species filtering и biome species table не используются.

### 3.3 Observed result

```text
reachable_colonized_patches  2
unique_recruited_species     2
isolated_no_colonization     true
sorting_observed_cells       2
adaptation_positive_cells    2

DRY  ADAPTATION_POSITIVE  gain 0.222347111576
WET  ADAPTATION_POSITIVE  gain 0.218384189961
```

Observed 2/2 не заменяет precommitted minimum 1/2 gates.

### 3.4 Fresh verification

```text
exact GDScript execution set        17 / 17 PASS
acceptance transitive closure       16 exact blobs
fresh E2.8 writer                   additional exact executed input
parser/preload                      PASS
parser ERROR lines                  0
fresh writer A/B                    PASS / PASS
writer artifacts                    byte-identical
artifact SHA-256                    b31c863f8e1943e5778d56631f8c8ad75b95f3b9d3930a699f80fd07595d45d1
FINAL A/B                           PASS / PASS
assertions                          68 / 68 PASS
FINAL ERROR lines                   0 / 0
FINAL logs                          byte-identical
FINAL log SHA-256                   4fdeaa581cd889c94f1bb5e1391466cad3deea308d631f4e3a3c056b532f69c2
```

Exact artifacts:

```text
protocol   372591ee3bee1c19538729259373e97fd9838461
challenge  4d353e774887c45f8a0487cb17b782e44d563951
test       82850fb850c35bcffb937707e4a8d29fb2827caa
runner     4385861b62ae10df07cb0f71295f50bf9a2097ee
```

Initial runner-only freeze `65864ed...` был superseded: E2.8 writer получил positional path вместо требуемого `--artifact-path=...` и fail-closed **до ecology execution**. Исправлен только Harness invocation; scientific protocol, thresholds, challenge implementation и acceptance test не менялись. Accepted code-under-test — `376796ab...`.

Canonical PowerShell runner существует, но `pwsh/powershell` отсутствует в Linux verification carrier. Authority: `EXPLICIT_EQUIVALENT_FRESH_BEHAVIORAL_EXECUTION`. Independent Reviewer/Verifier PASS не заявляется.

## 4. Claim boundary

EVO2 закрывает **research proof**, а не production integration.

Accepted:

> persisted frozen research SpeciesCatalog с accepted provenance восстанавливается в fresh process и проходит precommitted unseen-world causal ecology route без rebake, biome species tables и target-aware species injection.

Не accepted:

```text
production ecology authority
production persistence/save authority
distributed durability
canonical biological taxonomy
world transaction semantics
planet-wide individual entity truth
P4 global/main acceptance
```

P4 остаётся отдельной governance-линией: branch lifecycle evidence существует, но global/main acceptance и runtime merge требуют independent review/verifier freshness и main-owned promotion decision.

## 5. Следующий архитектурный шаг — XFER0

Теперь не нужно добавлять ещё один EVO2 experiment. Следующий этап — **bounded XFER0 contract design**: определить, какие accepted research artifacts и semantic guarantees можно передавать будущему simulator-facing ecology layer, не передавая ему чужую authority.

```text
EVO2 COMPLETE
    ↓
XFER0 bounded contracts
    ↓
EVO3 Planetary Ecology Compiler
    ↓
plant runtime convergence
    ↓
herbivores
    ↓
predators / food web / coevolution
```

XFER0 должен сохранить ограничения:

- research artifact != production authority;
- SpeciesCatalog != canonical taxonomy;
- population state meaning остаётся единым между execution modes;
- production persistence, spatial fabric, time fabric, environment truth и world lifecycle остаются у своих canonical owners;
- никакого прямого перехода от EVO2 proof к production runtime без explicit integration contracts.

## 6. Current resolver

```text
ECO.EVO2                 COMPLETE_RESEARCH_ONLY
NEXT                      OPEN / DESIGN ECO.XFER0 BOUNDED CONTRACTS
THEN                      PLAN ECO.EVO3 PLANETARY ECOLOGY COMPILER
P4                        SEPARATE / NOT GLOBALLY ACCEPTED HERE
```
