# ECO — Центральный маршрут развития ветки

Статус: `ACTIVE / RESEARCH_ONLY / EVO2 E2.3 CANDIDATE_VERIFICATION`.

Canonical North Star: `docs/future_features/evolutionary_ecology/ECO_EVOLUTIONARY_ECOSYSTEM_VISION_RU.md`.
Machine roadmap: `config/ecology/eco-evolutionary-ecology-roadmap.v1.json`.
EVO2 plan: `docs/plans/ECO_EVO2_PORTABLE_SPECIES_CATALOG_ROADMAP_RU.md`.

Последние accepted checkpoints:

- E2.1: `docs/checkpoints/2026-08-18_ECO_EVO2_E2_1_SPECIES_CATALOG_ACCEPTED_RU.md`;
- E2.2: `docs/checkpoints/2026-08-18_ECO_EVO2_E2_2_EVOLUTION_BAKE_EXPORT_ACCEPTED_RU.md`.

Текущий candidate checkpoint:

- E2.3: `docs/checkpoints/2026-08-18_ECO_EVO2_E2_3_FROZEN_CATALOG_TRANSFER_CANDIDATE_RU.md`.

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
```

Ключевые frozen identities:

```text
P2.6  3ea48d77dd44640e14ddf064e8b6b028e27a1c0fabfd36ff57461ceed054671c
P2.8  ba4e4bcef779764c86b20f1a76b452e0a2edcc88d351a1f9b4d2d41e10c420d6
P3.8  6132820a5c6597765b4f3abeeb8cf9fc9e6aaffb90ba83a1263997b17fc6f3a0
E2.1  aa23bc269738ace132fb1386ec01b339cc7fd82e1238223c1075b60dac5896ad
E2.2  56d4b8bfd3064ad37b720d5bff2bc98bb72b0ab7ad871877fc268d5e6df703ce
```

E2.2 exact accepted bake/catalog:

```text
bake
45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b

catalog
5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219
```

## 2. Production P4 — отдельная governance-линия

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

## 3. North Star EVO2

> Может ли результат эволюции стать переносимым каталогом жизненных стратегий, который без biome->asset таблиц заселяет новую, ранее не использованную среду через экологическую сортировку, конкуренцию, распространение и историю?

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

## 4. EVO2

```text
E2.1 SpeciesCatalog Contract                         ACCEPTED
    ↓
E2.2 Deterministic Evolution Bake Export             ACCEPTED
    ↓
E2.3 Frozen-Catalog Transfer                         ← CANDIDATE_VERIFICATION
    ↓ GREEN ONLY
E2.4 Environment Generalization Matrix               BLOCKED
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

## 5. E2.3 — Frozen-Catalog Transfer — IMPLEMENTED CANDIDATE

Exact code-under-test HEAD:

`6eb9c75ec3da82a9792b36a8e6c203a50a488883`

Executable blobs:

```text
implementation  1077b1892c4a537d95d6e50fbfa3b9a251c85369
acceptance test 80e0d6ee5b6626af961f54f4d34678680126041e
runner          6a906d5a553e58388d43190f646594e94f69edfa
```

### Implemented pipeline

```text
exact accepted E2.2 bake
        ↓
frozen SpeciesCatalog
        ↓
ALL entries → neutral source port
        ↓
hidden target revealed after freeze
        ↓
accepted P2.6 Biogeography.simulate(...)
        ↓
dispersal / establishment / resource competition
turnover / succession
        ↓
population history + events + final state hash
```

E2.3 не создаёт новый ecology solver. Он непосредственно переиспользует accepted P2.6 и через него существующие P2.3–P2.5 mechanics.

### Hard freeze

Executable truth:

```text
evolution_enabled = false
canonical_species_declared = false
production_authority_claimed = false
```

Transfer API:

`transfer(bake_export, target)`

В API нет target species list и mutation callback. В source отсутствуют `plant_mutation`, `mutation_kernel`, `biome` и `species_table` paths.

### Hidden-target proof

Target rejected, если хотя бы одно из следующего уже встречалось в E2.2 bake provenance:

- target `patch_id`;
- exact target `EnvironmentSample.checksum`.

Поэтому нельзя обойти unseen boundary простым rename patch или environment.

Target descriptor canonicalized и bounded:

```text
MAX_YEARS          = 60
MAX_TARGET_PATCHES = 8
```

### Initial truth

Все frozen catalog entries без target-aware filtering становятся source-port strategies keyed by `research_species_id`.

Target patches в year 0 имеют нулевые adults и seed bank. Population должна появиться только через причинный transport/establishment path.

### Paired causal fixture

Два control-target используют **одинаковый exact environment checksum**:

```text
TARGET_REACHABLE
Rect2(1.01, -80, 100, 160)

TARGET_UNREACHABLE
Rect2(500, -80, 100, 160)
```

Разница только в пространственной достижимости.

Acceptance требует:

```text
reachable   → causal recruitment/colonization
unreachable → VALID_NO_COLONIZATION
```

Это проверяет, что suitability сама по себе не создаёт population truth.

### Candidate test contract

Определено `59` assertions:

- exact E2.2 parent/bake/catalog pinning;
- target absent from bake geography/ecology provenance;
- frozen bake/catalog and target immutability;
- all frozen species available through one neutral source port;
- zero initial target population;
- reachable colonization and recruitment event;
- equal-suitability isolated no-colonization;
- research species identity preservation;
- shared-resource competition changes composition after co-establishment;
- same-process determinism;
- no global RNG consumption;
- input-order canonicalization;
- malformed/tampered target/bake/catalog/result fail-closed;
- no biome/species table or evolution kernel shortcut;
- direct P2.6 reuse.

## 6. Текущая verification boundary

Exact attached Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
SHA-256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Exact implementation parser/preload: `PASS / exit 0`.

Exact acceptance-test parser/preload: `PASS / exit 0`.

Behavioral runner **ещё не выполнен** в текущем execution container: отсутствуют полный exact downstream dependency carrier и `pwsh`.

Поэтому нельзя утверждать:

- `59/59 PASS`;
- reachable/isolated canonical result hashes;
- fresh-process behavioral determinism;
- E2.3 ACCEPTED.

E2.3 остаётся `CANDIDATE`. Independent Reviewer PASS не заявляется.

## 7. Known fixture boundary

E2.3 использует exact accepted E2.2 bake artifact, но E2.2 artifact сам построен на synthetic contract fixture, потому что accepted P2.8 пока не публикует canonical multi-lineage evolved-observation collection.

Это доказательство transfer **контракта**, а не утверждение, что real evolution producer уже подключён.

## 8. Следующие этапы

E2.4 открывается только после GREEN behavioral verification E2.3. Затем matrix минимум:

```text
NEAR_SOURCE
DRY
WET
NUTRIENT_POOR
HIGH_SEASONALITY
PATCH_ISOLATED
```

После E2.4 идут sorting-vs-adaptation, replicated causal experiments, cross-seed robustness, persistence/provenance и EVO2 FINAL unseen-world challenge.

## 9. Неподвижные архитектурные ограничения

```text
research ecology != production world authority
SpeciesCatalog != canonical species taxonomy
population truth != planet-wide individual entity truth
representation != ecology truth
EVO2 != permission to own G/WQ/MAT/LIFE/WB/NX foundations
```

Главный runtime принцип сохраняется:

> population is truth; individual is a representation unless interaction promotes it to durable world state.

## 10. Current resolver

```text
VERIFY ECO.EVO2 / E2.3 FROZEN-CATALOG TRANSFER
```
