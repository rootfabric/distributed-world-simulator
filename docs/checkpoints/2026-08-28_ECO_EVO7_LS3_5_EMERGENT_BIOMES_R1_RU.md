# ECO.EVO7 LS3.5 — Emergent Biomes R1

## Статус кандидата

LS3.5 — строго read-only observatory/classifier поверх принятой spatial ecology LS3.4.

Принятый predecessor: `78ba78a19ed77eb7a1678b01e6e001edb5284104`.

Нормативная причинная граница:

```text
physical EnvironmentField + evolved LS3.4 community
                         |
                         v
              emergent classifier

NO EDGE BACK TO ECOLOGY
```

Classifier не шагает симуляцию, не владеет reproduction/mutation/dispersal/recruitment/competition и не пишет production/persistence/network/renderer state.

## Архитектура

R1 реализован как pure read-only classifier, а не wrapper вокруг LS3.4.

Входы:

- exact LS3.1 `EnvironmentField`;
- exact post-competition LS3.4 snapshot.

Выход:

- 1024 post-hoc cell classification records;
- patch summary;
- deterministic `classification_hash`;
- source environment/ecology/population hashes;
- research-only labels.

LS3.4 не импортирует LS3.5. Обратного call edge нет по конструкции.

## Измеряемые cell observables

Physical:

- soil moisture;
- surface water fraction;
- temperature;
- elevation;
- incident light;
- drainage;
- local relief.

Community:

- occupied records / occupancy fraction;
- cover proxy из post-competition survivor LAI;
- lineage richness;
- mean LAI;
- canopy height;
- mean root depth;
- mean root-shoot ratio;
- mean water satisfaction;
- realized post-allocation water state.

Spatial:

- occupied-neighbor fraction;
- neighbor cover;
- continuity;
- fragmentation.

## Base-class scoring

Classifier не читает `recipe_id`, biome labels, x/y segmentation или заранее заданную class map.

Base labels:

- `desert-like`;
- `wetland-like`;
- `forest-like`;
- `grass/shrub-like`;
- `alpine-like`.

Scores строятся только из measured observables.

### desert-like

Высокий вес:

- dryness;
- low cover;
- drainage;
- fragmentation.

### wetland-like

Высокий вес:

- soil/surface wetness;
- low drainage;
- cover;
- realized water satisfaction.

### forest-like

Только для occupied community:

- cover;
- canopy height;
- LAI;
- continuity;
- moisture.

### grass/shrub-like

Только для occupied community:

- low/moderate height;
- low/moderate LAI;
- open cover;
- intermediate moisture;
- continuity.

### alpine-like

Высокий вес:

- cold;
- elevation;
- low canopy;
- low cover;
- local relief.

Tie-breaking deterministic по score, затем label string.

## Ecotone pass

`ecotone` назначается только после base classification.

Для Moore-neighborhood измеряются:

- neighbor base-class disagreement;
- moisture gradient;
- cover gradient;
- canopy-height gradient.

Cell становится `ecotone`, только если:

- рядом >= 2 base classes;
- disagreement >= 0.25;
- и либо class-score margin <= 0.18, либо measured boundary strength >= 0.24.

Таким образом ecotone — результат локальной measured boundary, а не segmentation map.

## Identity / validation

Classification artifact привязан к:

- source EnvironmentField hash;
- source LS3.4 state hash;
- source post-competition population hash;
- generation;
- all canonical cell classification hashes;
- summary hash;
- classifier authority hash.

Validator повторно строит expected classification из exact physical/community sources. Поэтому label/metric tamper не принимается даже после полного rehash output artifact.

Physical source cell/field hashes и LS3.4 competition field также повторно валидируются до классификации.

## Authority boundary

```text
ecology_write              = false
classifier_to_ecology_edge = false
production_biome_truth     = false
persistence_write          = false
network_replication_write  = false
renderer_write             = false
```

`*-like` обязательно остаётся research terminology. LS3.5 output не является production biome truth.

## Acceptance R1

Обязательные доказательства:

1. Classifier ON/OFF не меняет ecology/community identity hashes на одинаковых LS3.4 runs.
2. Classifier call не мутирует source ecology snapshot.
3. Search/call-site audit: fitness, dispersal/recruitment и competition не читают LS3.5/labels.
4. Один настоящий 32x32 patch после spatial evolution содержит >=3 base classes и ecotones.
5. Все 1024 cells классифицированы ровно один раз.
6. Controlled measured cases дают все пять base labels без coordinate/recipe input.
7. Class boundaries подтверждаются measured physical/community deltas.
8. Ecotones требуют local base-class disagreement.
9. Same physical/community state deterministically replay-ит exact classification hash.
10. Output label tamper после полного rehash — REJECT.
11. Classifier-to-ecology authority escalation — REJECT.
12. Stale/tampered physical source — REJECT.
13. Continuity/fragmentation bounded и complementary.
14. Occupied cells публикуют lineage richness.

Pre-publication focused exact-double result:

```text
ECO.EVO7 LS3.5 Emergent Biomes: PASS (64 assertions)
rc=0
Godot=4.7.1.stable.double.custom_build.a13da4feb
```

На real `WATER_GRADIENT_STRONG` patch уже на generation 5 observed result содержит 5 distinct base classes до ecotone pass и >0 ecotone cells.

## Следующая граница

LS3.6 Rule Workbench может визуализировать/сравнивать LS3.5 output, но не получает право превращать labels обратно в ecological inputs.

LS3.FINAL должен доказать multi-environment divergence одной и той же исходной flora при сохранённой physical-first causality.
