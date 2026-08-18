# ECO EVO2 — Portable SpeciesCatalog / Unseen World Roadmap

Статус: `ACTIVE / RESEARCH_ONLY / E2.1 ACCEPTED / E2.2 ACCEPTED / E2.3 CANDIDATE_VERIFICATION / E2.4 BLOCKED`.

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

E2.1 SpeciesCatalog aggregate
aa23bc269738ace132fb1386ec01b339cc7fd82e1238223c1075b60dac5896ad

E2.2 Deterministic Evolution Bake Export aggregate
56d4b8bfd3064ad37b720d5bff2bc98bb72b0ab7ad871877fc268d5e6df703ce

E2.2 frozen bake
45496eb67aac5cc0a65babfeb0c49fa99616df17c2f7e8b9e8b95d04cb2b4e5b

E2.2 frozen catalog
5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219
```

P4 production-integration evidence остаётся отдельной governance-линией и не даёт EVO2 production authority.

## 2. Species concept policy

`research_species_id` — стабильная идентичность portable lineage hypothesis внутри research pipeline.

Это не canonical biological taxonomy и не production species registry.

## 3. E2.1 — SpeciesCatalog Contract — ACCEPTED

Exact code-under-test:

`bf468942718df6b84ebd4c61a294987e8e63c607`

Accepted aggregate:

`aa23bc269738ace132fb1386ec01b339cc7fd82e1238223c1075b60dac5896ad`

Frozen contract сохраняет stable research identity, exact lineage/ancestry provenance, validated ecological genome/recruitment traits, canonical ordering/hash, strict source types, no taxonomy promotion, no global RNG consumption и no source mutation.

## 4. E2.2 — Deterministic Evolution Bake Export — ACCEPTED

Exact code-under-test:

`7cf98d67a4658644a6f2dde3e93e28a184638ec3`

Acceptance source HEAD:

`4ddf7d275d10a6a84a3e414bfb0e76447cb2a890`

Accepted aggregate:

`56d4b8bfd3064ad37b720d5bff2bc98bb72b0ab7ad871877fc268d5e6df703ce`

E2.2 deterministically selects retained lineage hypotheses from typed long-run evidence, chooses an unambiguous representative observation, and builds the accepted E2.1 SpeciesCatalog. Selection is re-derived during validation and recomputed-hash tamper fails closed.

Known boundary: E2.2 uses a synthetic contract fixture because accepted P2.8 does not yet publish a canonical multi-lineage evolved-observation collection. Это не объявляется real accepted evolution producer.

## 5. E2.3 — Frozen-Catalog Transfer — IMPLEMENTED CANDIDATE

### Exact candidate identity

Accepted E2.2 base HEAD:

`6e5207bcdf9bce096726a4fe9d72f14e635c437f`

Exact E2.3 code-under-test HEAD:

`6eb9c75ec3da82a9792b36a8e6c203a50a488883`

Executable blobs:

```text
implementation  1077b1892c4a537d95d6e50fbfa3b9a251c85369
acceptance test 80e0d6ee5b6626af961f54f4d34678680126041e
runner          6a906d5a553e58388d43190f646594e94f69edfa
```

Machine validation:

`validation/ecology/eco-evo2-e2-3-frozen-catalog-transfer-validation.json`

Candidate checkpoint:

`docs/checkpoints/2026-08-18_ECO_EVO2_E2_3_FROZEN_CATALOG_TRANSFER_CANDIDATE_RU.md`

### Goal

Доказать, что exact frozen E2.2 catalog способен причинно заселять environment, который не участвовал в bake, при полностью отключённой evolution/mutation.

### Implemented boundary

```text
accepted E2.2 bake
        ↓
frozen SpeciesCatalog
        ↓
ALL catalog entries -> neutral source port
        ↓
TARGET revealed after freeze
        ↓
accepted P2.6 Biogeography.simulate(...)
        ↓
dispersal / recruitment / resource competition
population turnover / succession
        ↓
population history + causal events + final hash
```

E2.3 не создаёт parallel ecology solver.

Используется accepted P2.6 `plant_long_horizon_biogeography_v1.gd`, который наследует P2.3–P2.5 mechanics.

### Hard freeze

Executable truth:

```text
evolution_enabled = false
canonical_species_declared = false
production_authority_claimed = false
```

Transfer API:

`transfer(bake_export, target)`

Нет target species list, mutation callback, biome lookup или species table.

### Hidden target

Target fail-closed отвергается, если target уже присутствовал в bake как:

1. тот же `patch_id`;
2. тот же exact `EnvironmentSample.checksum`.

Таким образом rename patch не может превратить уже виденную среду в unseen environment.

Target contract bounded:

```text
MAX_YEARS          = 60
MAX_TARGET_PATCHES = 8
```

Типы target descriptor проверяются до conversions; duplicate/overlapping patches, source-port overlap, invalid schedule и hash tamper fail closed.

### Neutral inoculum

Все frozen catalog entries без target-aware filtering становятся strategies keyed by `research_species_id` и инокулируются только в нейтральный source port.

Target patches начинают с:

```text
adults    = 0
seed bank = 0
```

Никакого target scatter нет.

### Paired causal proof

Acceptance suite использует два target cases с **одинаковым exact suitability/environment checksum**:

```text
TARGET_REACHABLE
Rect2(1.01, -80, 100, 160)

TARGET_UNREACHABLE
Rect2(500, -80, 100, 160)
```

Они различаются только spatial reachability.

Required semantics:

```text
reachable   -> causal recruitment / colonization
unreachable -> VALID_NO_COLONIZATION
```

Это доказывает, что suitability сама по себе не создаёт population truth.

### Acceptance suite

Определено `59` assertions.

Покрываются:

1. exact E2.2 aggregate/bake/catalog pinning;
2. target identity absent from bake provenance;
3. catalog and target immutability;
4. mutation/evolution API absent;
5. all catalog entries available through neutral source port;
6. target starts empty;
7. deterministic transfer replay;
8. input order canonicalization;
9. global RNG untouched;
10. no biome/species tables;
11. reachable recruitment/colonization;
12. equal-suitability isolated no-colonization;
13. spatial reachability changes result;
14. target events preserve frozen research species IDs;
15. shared-resource competition may change composition;
16. malformed/tampered target/bake/catalog fail closed;
17. rehashed result tamper rejected by deterministic replay;
18. direct P2.6 reuse.

### Parser evidence

Exact attached Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
SHA-256 bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
```

Exact implementation parser/preload: `PASS / exit 0`.

Exact test parser/preload: `PASS / exit 0`.

Parser log SHA-256:

`7e13b74061328cb38002de86c89b160a49fe4d3df65f763fc0d8c691893803c2`

### Verification debt — fail closed

Behavioral runner пока **не исполнялся** в текущем container, потому что здесь отсутствуют полный exact downstream dependency carrier и `pwsh`.

Поэтому E2.3 сейчас НЕ имеет права заявлять:

- 59/59 PASS;
- canonical reachable/isolated result hashes;
- two fresh-process behavioral equality;
- formal E2.3 acceptance.

Independent Reviewer PASS также не заявляется.

E2.4 остаётся закрыт.

## 6. E2.4 — Environment Generalization Matrix — BLOCKED

Открывается только после E2.3 GREEN.

Минимальные target families:

```text
NEAR_SOURCE
DRY
WET
NUTRIENT_POOR
HIGH_SEASONALITY
PATCH_ISOLATED
```

E2.4 должен проверять не одинаковые species lists, а причинно объяснимую occupancy/biomass/recruitment/extinction/recolonization/trait composition across environment families.

## 7. E2.5 — Ecological Sorting vs Continued Adaptation

```text
Control   = frozen catalog, evolution disabled
Treatment = same catalog/root, continued adaptation enabled
```

Нужно отделить ecological sorting существующих strategies от новой evolutionary adaptation.

## 8. E2.6 — Replicated Causal Experiments

Использовать доказанные VIS2.2 patterns для replicate isolation / paired common random numbers / aggregate effects / deterministic rewind, без автоматического формального принятия VIS2.2.

## 9. E2.7 — Cross-Seed Robustness

Acceptance не может зависеть от одного seed. Нужно разделять exact same-seed reproducibility и robust regularity across independent seeds.

## 10. E2.8 — Catalog Persistence & Provenance

Typed deterministic persistence, schema/version boundary, canonical bytes/hash, fresh-process restore, tamper rejection и source evolution provenance.

## 11. EVO2 FINAL — Unseen World Challenge

Target скрыт до freeze SpeciesCatalog. После reveal система без hardcoded biome species tables должна построить причинно объяснимую spatial population truth.

## 12. XFER boundary

После EVO2 допускается только bounded XFER0 contract work:

```text
WorldEnvironmentProvider -> EnvironmentSample
SpeciesCatalog            -> research ecology input
population solver         -> PopulationPatchState candidate
PopulationPatchState      -> representation materialization
```

ECO не получает ownership над G/WQ/MAT/LIFE/WB/NX/authority/persistence foundations.

## 13. После EVO2

Следующий research node: `EVO3 — Planetary Ecology Compiler / broader planetary generalization`.

Животные открываются только после plant-only portable ecology proof.

## 14. Current execution

```text
CURRENT = FRESH/CANONICAL BEHAVIORAL VERIFICATION ECO.EVO2 / E2.3
NEXT    = E2.4 Environment Generalization Matrix only after E2.3 acceptance
```
