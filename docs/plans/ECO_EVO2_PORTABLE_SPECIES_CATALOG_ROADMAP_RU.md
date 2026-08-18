# ECO EVO2 — Portable SpeciesCatalog / Unseen World Roadmap

Статус: `ACTIVE / RESEARCH_ONLY / E2.1 ACCEPTED / E2.2 ACCEPTED / E2.3 ACCEPTED / E2.4 AUTHORIZED_NOT_STARTED`.

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

E2.3 Frozen-Catalog Transfer aggregate
82d76f858568d5bd53af4d299abd2155f2fde7e845de828cf4555e601ee1efa8
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

## 4. E2.2 — Deterministic Evolution Bake Export — ACCEPTED

Exact code-under-test:

`7cf98d67a4658644a6f2dde3e93e28a184638ec3`

Accepted aggregate:

`56d4b8bfd3064ad37b720d5bff2bc98bb72b0ab7ad871877fc268d5e6df703ce`

Frozen export policy остаётся typed, deterministic, fail-closed и без taxonomy promotion.

## 5. E2.3 — Frozen-Catalog Transfer — ACCEPTED

Exact code-under-test:

`c7ee41371807ed7dbb75e7e1eae1587105873a26`

Final implementation blob:

`a886d179fe32a2bb531956923fd0cc59bbbb28c6`

Validation:

`validation/ecology/eco-evo2-e2-3-frozen-catalog-transfer-validation.json`

Accepted checkpoint:

`docs/checkpoints/2026-08-18_ECO_EVO2_E2_3_FROZEN_CATALOG_TRANSFER_ACCEPTED_RU.md`

### Frozen E2.3 contract

```text
exact accepted E2.2 bake/catalog
        ↓
all catalog entries → target-independent source port
        ↓
mutation/evolution disabled
        ↓
previously unseen target revealed
        ↓
accepted P2.6 dispersal / establishment / competition / turnover
        ↓
population history
```

Hard constraints:

- target patch IDs absent from bake evidence;
- target exact EnvironmentSample checksums absent from bake evidence;
- target starts with no adults and no seed bank;
- no target species list API;
- no biome->species lookup;
- frozen catalog not mutated;
- no global RNG consumption;
- valid no-colonization is a successful ecological outcome, not execution failure.

### Accepted verification

```text
exact transitive executable closure  17 / 17 PASS
Godot                              4.7.1.stable.double.custom_build.a13da4feb
parser/preload                     PASS
fresh processes                    2 / 2 PASS
assertions                         59 / 59 PASS
logs                               byte-identical
log SHA-256                        7b2f89965bac13dc1238b053ecfd7b3544948eb6fa9941f3ca56d66ca79cad7b
aggregate                          82d76f858568d5bd53af4d299abd2155f2fde7e845de828cf4555e601ee1efa8
```

Paired causal control:

```text
same target environment suitability
reachable → COLONIZED
isolated  → VALID_NO_COLONIZATION
```

Initial fresh run correctly failed because source-port moisture `0.58` suppressed reproduction of one frozen strategy. Repair made the source port target-independent but neutral enough for both (`0.40`), then full closure and all behavioral assertions were rerun.

Acceptance authority is fresh behavioral execution, **not** independent Reviewer/Verifier authority.

## 6. E2.4 — Environment Generalization Matrix — AUTHORIZED / CURRENT

Goal: проверить один frozen catalog на разных previously unseen environments без rebake и без target-aware species selection.

Minimum matrix:

```text
NEAR_SOURCE
DRY
WET
NUTRIENT_POOR
HIGH_SEASONALITY
PATCH_ISOLATED
```

### Required invariants

Для каждой matrix cell:

1. exact E2.2 catalog/bake identity;
2. exact E2.3 accepted transfer contract lineage;
3. evolution/mutation disabled;
4. target absent from bake provenance;
5. target starts empty;
6. same frozen catalog is offered to every cell;
7. no biome->species mapping;
8. colonization requires causal dispersal + establishment;
9. composition emerges from environment/competition/history;
10. `VALID_NO_COLONIZATION` remains legitimate;
11. deterministic same-input replay;
12. no global RNG consumption;
13. exact transitive executable closure before canonical behavioral execution;
14. fresh process does not impersonate independent role evidence.

### Expected E2.4 evidence

Matrix result must expose per-cell:

- target/environment identity;
- colonization status;
- first colonization timing when applicable;
- species occupancy/composition trajectory;
- final population state hash;
- result hash;
- causal contrast against relevant control;
- aggregate matrix hash.

E2.5 stays blocked until E2.4 acceptance.

## 7. E2.5 — Ecological Sorting vs Continued Adaptation

```text
Control   = frozen catalog, evolution disabled
Treatment = same catalog/root, continued adaptation enabled
```

Нужно разделить ecological sorting уже существующих strategies и новую evolutionary adaptation.

## 8. E2.6 — Replicated Causal Experiments

Использовать VIS2.2 evidence patterns без автоматического наследования formal PASS.

## 9. E2.7 — Cross-Seed Robustness

Acceptance не может зависеть от одного seed.

## 10. E2.8 — Catalog Persistence & Provenance

Typed deterministic persistence, canonical bytes/hash, schema/version policy, restore and tamper rejection.

## 11. EVO2 FINAL — Unseen World Challenge

Target скрыт от bake pipeline до freeze SpeciesCatalog. После reveal система должна построить причинно объяснимую spatial population truth без hard-coded biome species tables.

## 12. После EVO2

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
```

Animals остаются deferred до plant-only portability proof.

## 13. Current execution

```text
CURRENT = OPEN / IMPLEMENT ECO.EVO2 / E2.4 Environment Generalization Matrix
NEXT    = E2.5 Ecological Sorting vs Continued Adaptation after E2.4 acceptance
```
