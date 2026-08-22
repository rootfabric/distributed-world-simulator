# ECO.EVO6 — продолжение Rule Language → эволюционный отбор, R1

Статус: `IMPLEMENTED_CANDIDATE / LOCAL_SMOKE_PASS / FRESH_REPO_EXECUTION_REQUIRED`.

База реализации: `main@1cb7e45daf520c8f094849b2e0d70fb157ace5c0` (`Merge EVO6 R4 rule generator`). Ветка: `feature/eco-evo6-rule-selection-continuation`.

## Что закрывает R1

### R3.1 — generated rules → наблюдаемый визуал

`evo6_generated_outcomes_v1.py` компилирует один seeded R4 rule set и строит из того же набора правил:

1. fate для каждой из 196 клеток A0 terrain (`survived`, `pigment`, `thorns`, `fitness_weight`);
2. четыре phenotype-класса на каждой клетке: `terrestrial/low`, `terrestrial/tall`, `amphibious/low`, `amphibious/tall`;
3. четыре детерминированных selection site только с ненулевым fitness spread.

Adapter также закрывает два контекстных пробела, не меняя замороженный R1 compiler/R4 generator:

- для generated `neighbours` rules строится детерминированный агрегат `count/taller_than_self` в заявленном `within_r=6` по A0 grid spacing `0.5 m`; mixed neighbour radii fail-close до появления отдельного versioned aggregate contract;
- terrain `snow_cover_frac` переносится из `features` в rule-visible `effective_conditions`, потому что существующий compiler читает этот predicate оттуда.

Для default seed materialized `196/196` neighbour aggregates; snow predicate доступен на 12 snow cells; generated set действительно содержит neighbour predicates.

Отдельный `eco_evo6_generated_rule_fly_lab.gd` наследует существующий R3 flyover и только подменяет источник `_fates`. Старый R3 lab не изменён. Если generated artifact отсутствует или невалиден, EVO6 lab fail-closes вместо молчаливого возврата к R2.

Default seed: `20260823`.

- exact artifact digest: `e2b4de200e919546e00ce7606af0402019409f75435d739bbc963afded7953f1`;
- selection surface digest: `5e3469504d8fbfb38a0c13bb4ad6ceb300c29164a4b465d743f10b3bdd5fad34`;
- max phenotype fitness spread: `1.20`;
- winner classes с ненулевым spread на полном terrain: `amphibious/tall`, `terrestrial/low`, `terrestrial/tall`.

Generated artifact не хранится как новый mutable truth: runner создаёт его во временный файл, передаёт путь через `EVO6_GENERATED_OUTCOMES_PATH` и удаляет после прогона.

### H1 — связь с существующим наследованием

Нового inheritance/mutation kernel нет. `evo6_rule_selection_bridge_v1.gd` импортирует существующий `plant_mutation_lineage_kernel_v1.gd` и вызывает `MutationKernel.reproduce(...)`.

EVO6 phenotype projection намеренно минимальна и обратима:

- `water_preference >= 0.58` → `amphibious`, иначе `terrestrial`;
- `growth_rate >= 0.65` → `tall`, иначе `low`.

То есть мутации уже существующих P1B traits способны менять phenotype class, а generated EVO6 rules — fitness этого класса.

### H2 — multi-generation selection

Для каждого выбранного terrain site запускается 12 поколений, population size 12, offspring per parent 3. Все sites получают одинаковый first-generation mutation pool. Разница появляется только после применения локального EVO6 phenotype fitness surface.

Reproduction, lineage IDs, genome checksums и mutation events принадлежат существующему P1B kernel. EVO6 bridge владеет только ранжированием кандидатов.

### H3 — diversity / anti-collapse

Bridge считает:

- unique final genomes;
- largest genome share;
- phenotype entropy;
- variance `water_preference`, `growth_rate`, `root_depth_m`, `shade_tolerance`;
- mutation event count;
- maximum selected fitness gain;
- population conservation;
- common first candidate-pool predicate.

Focused acceptance также строит counterfactual surface: меняется только EVO6 fitness, mutation seed остаётся тем же. Selected descendants обязаны изменить `result_hash`. Это отделяет причинность rule selection от случайного mutation drift.

## Границы

- `plant_mutation_lineage_kernel_v1.gd` не изменён;
- `plant_spatial_selection_baseline_v1.gd` не изменён;
- accepted P1A/P1B/PH contracts не изменены;
- старый EVO6 R1–R4 код не переписан;
- старый R3 flyover не переписан;
- population truth не объявляется canonical;
- результат остаётся research-layer candidate до отдельного review/acceptance.

## Проверка

Focused runner: `RUN_ECO_EVO6_RULE_SELECTION_CONTINUATION.ps1`.

Он выполняет:

1. Python R3.1 determinism/exact-digest + neighbour/snow context tests;
2. generation временного exact artifact;
3. существующий `ECO.P1B-S2` parent regression;
4. R3.1 visual adapter acceptance;
5. H1–H3 selection bridge acceptance.

PR-only exact-head workflow: `.github/workflows/evo6-rule-selection-continuation.yml`.

Интерактивный визуал: `OPEN_ECO_EVO6_GENERATED_RULE_LAB.ps1`.
