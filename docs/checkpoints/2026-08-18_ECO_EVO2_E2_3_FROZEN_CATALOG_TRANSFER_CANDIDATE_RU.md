# ECO EVO2 / E2.3 — Frozen-Catalog Transfer — Candidate

Дата: `2026-08-18`

Статус: `CANDIDATE / RESEARCH_ONLY / EXACT PARSER PASS / BEHAVIORAL VERIFICATION REQUIRED`.

Ветка: `feature/eco-evolutionary-ecology`.

## 1. Exact identity

Accepted E2.2 base HEAD:

`6e5207bcdf9bce096726a4fe9d72f14e635c437f`

E2.3 exact code-under-test HEAD:

`6eb9c75ec3da82a9792b36a8e6c203a50a488883`

Executable blobs:

```text
implementation
1077b1892c4a537d95d6e50fbfa3b9a251c85369

test
80e0d6ee5b6626af961f54f4d34678680126041e

runner
6a906d5a553e58388d43190f646594e94f69edfa
```

Machine validation:

`validation/ecology/eco-evo2-e2-3-frozen-catalog-transfer-validation.json`

## 2. Frozen parent

E2.3 принимает только exact frozen E2.2 identity:

```text
E2.2 aggregate
56d4b8bfd3064ad37b720d5bff2bc98bb72b0ab7ad871877fc268d5e6df703ce

E2.2 bake
45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b

E2.2 catalog
5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219
```

Любой изменённый bake/catalog fail-closed.

## 3. Реализованный transfer boundary

Pipeline:

```text
accepted E2.2 bake export
        ↓
exact frozen SpeciesCatalog
        ↓
all catalog entries → neutral source-port inoculum
        ↓
TARGET revealed only after freeze
        ↓
accepted P2.6 biogeography solver
        ↓
dispersal / establishment / resource competition
population turnover / succession
        ↓
Population history + causal events + final state hash
```

Никакая target species list в API не передаётся.

Executable API:

`transfer(bake_export, target)`

## 4. Hard freeze

В transfer truth жёстко зафиксировано:

```text
evolution_enabled = false
canonical_species_declared = false
production_authority_claimed = false
```

В executable source отсутствуют mutation/evolution kernel references, `biome` lookup и `species_table`.

E2.3 не создаёт новый ecology solver. Он напрямую вызывает accepted `plant_long_horizon_biogeography_v1.gd`, то есть наследует доказанные P2.3–P2.6 механизмы вместо параллельной модели.

## 5. Hidden-target gate

Target считается действительно unseen только если для каждого target patch одновременно выполняется:

1. `patch_id` отсутствует во всей E2.2 bake geography provenance;
2. exact `EnvironmentSample.checksum` отсутствует во всей E2.2 bake ecology provenance.

Это блокирует два shortcut:

```text
старый patch под новым experiment name
старый environment под новым patch name
```

Target descriptor canonicalized и bounded:

```text
max years          60
max target patches 8
```

Malformed Variant types, overlapping patches, source-port overlap, duplicate patches, invalid schedule и hash tamper fail-closed.

## 6. Neutral source port

Все frozen catalog entries без target-aware filtering превращаются в research strategies, keyed by `research_species_id`.

Все они одинаково доступны только через neutral source port:

`eco-evo2-transfer/source-port`

Target patches в year 0 имеют:

```text
adult population = 0
seed bank        = 0
```

Следовательно target population не может появиться через скрытый scatter.

## 7. Causal paired fixture

Acceptance suite определяет два target controls с **одинаковым exact environment checksum**:

```text
TARGET_REACHABLE
bounds = Rect2(1.01, -80, 100, 160)

TARGET_UNREACHABLE
bounds = Rect2(500, -80, 100, 160)
```

Они различаются географической достижимостью, а не suitability.

Expected semantics:

```text
reachable   -> causal dispersal + recruitment may colonize
unreachable -> VALID_NO_COLONIZATION
```

Это напрямую проверяет принцип:

> suitability сама по себе не является population truth.

## 8. Acceptance suite

Определено `59` assertions.

Проверяются:

- exact accepted E2.2 aggregate/bake/catalog;
- hidden-target provenance gate;
- frozen bake/catalog immutability;
- target input immutability;
- all catalog entries participate without target-specific filtering;
- empty initial target;
- reachable recruitment/colonization;
- isolated valid no-colonization;
- equal suitability + different reachability → different causal result;
- population events carry only frozen research species IDs;
- resource competition can change composition after co-establishment;
- same-process determinism;
- no global RNG consumption;
- schedule input-order canonicalization;
- target/bake/catalog/result tamper rejection;
- no mutation/biome/species-table path;
- direct P2.6 reuse.

Canonical runner:

`RUN_ECO_EVO2_E2_3_TESTS.ps1`

## 9. Exact attached Godot parser evidence

Использован exact attached Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
SHA-256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Exact implementation blob parser/preload:

`PASS / exit 0`

Exact acceptance-test blob parser/preload:

`PASS / exit 0`

Оба parser log SHA-256:

`7e13b74061328cb38002de86c89b160a49fe4d3df65f763fc0d8c691893803c2`

## 10. Что НЕ доказано этим checkpoint

Этот checkpoint **не заявляет behavioral PASS**.

В текущем execution container отсутствуют полный exact downstream dependency carrier и PowerShell runtime, поэтому `RUN_ECO_EVO2_E2_3_TESTS.ps1` здесь не был исполнен.

Следовательно пока НЕ зафиксированы:

- 59/59 behavioral PASS;
- reachable/isolated canonical output hashes;
- two-fresh-process behavioral equality;
- E2.3 formal acceptance.

Это сознательно fail-closed состояние, а не интерпретация parser PASS как behavioral PASS.

Также E2.3 пока работает на accepted E2.2 **synthetic contract fixture**. Это не выдаётся за уже подключённый real evolution bake producer.

## 11. Findings, закрытые до freeze

`E2_3_VALIDATION_001_RECURSIVE_TARGET_VALIDATOR`

Ранняя версия имела рекурсивный `create_target ↔ validate_target` путь. Исправлено до candidate freeze: builder теперь one-way, validator independently rebuilds один раз.

`E2_3_VALIDATION_002_MALFORMED_TARGET_TYPE_BOUNDARY`

Добавлены explicit Variant-type checks и bounded `MAX_TARGET_PATCHES = 8` до любых conversions/rebuild.

## 12. Governance boundary

```text
E2.3 != production authority
E2.3 != canonical species taxonomy
E2.3 != permission to modify accepted E2.2
E2.3 != permission to open E2.4 before verification
```

Independent Reviewer PASS не заявляется.

## 13. Следующий formal gate

```text
Fresh/canonical behavioral verification E2.3
        ↓ GREEN only
freeze E2.3
        ↓
open E2.4 Environment Generalization Matrix
```

До этого E2.3 остаётся `CANDIDATE`, а E2.4 — `BLOCKED_UNTIL_E2_3_ACCEPTED`.
