# ECO.P1B-S3 — Regional Population Field and Trait Distribution — CANDIDATE

## Статус

`LOCAL_FOCUSED_PASS / EXACT_WINDOWS_PENDING`.

S2 доказал local selection в четырёх независимых контрольных средах. S3 переносит тот же принцип на одну неоднородную карту: `7×7 = 49` population patches, каждый с шестью individuals одной ancestral lineage.

## Что важно архитектурно

- исходный genotype один;
- `lineage_id` один для всего эксперимента;
- individuals каждого patch уникальны;
- mutation stream не читает environment values;
- selection читает только принятый P1A `PlantResourceModelV1.net_resource_balance`;
- `DRY/WET/SHADED/SUNLIT` вычисляются после факта как diagnostic quartiles и не участвуют в simulation;
- species/biome classes отсутствуют;
- migration и inter-patch competition пока отсутствуют;
- `seed_dispersal_distance_m` по-прежнему заморожен на 15 m, потому что до ECO.P2 у него нет migration benefit.

## Neutral control

Для каждого patch сохраняются те же founder identities и те же deterministic mutation seeds, но selection проводится в одном uniform mean environment.

Это позволяет сравнить случайную пространственную структуру mutation с heterogeneous-environment selection.

В первом поколении real и neutral run имеют одинаковый candidate-pool hash patch-by-patch. Различие возникает только на этапе selection.

## Local evidence

Godot `4.7.1.stable.double.custom_build.a13da4feb`:

- focused: `388/388`;
- separate-process replay: `6/6`.

Hashes:

- real field: `cbd2f4a65f2a06f8ee9feeea0d9eae90d37cd0ede15df1bd808ef52773089b56`;
- neutral control: `b4d18ef35a2a77104fa18c8a3f3004a6f5898d572e57917429cc955cc7e2c5e6`;
- alternate seed: `ca81e0cfea0b05850470276fef10c880d3832613df9ff7f35d3c7395bd32589b`.

Средний accepted resource balance всей карты:

- generation 0: `-0.15744`;
- generation 8: `+0.18194`.

Trait/environment correlations:

- `water_preference ↔ soil_moisture = +0.84993`;
- `root_depth ↔ soil_moisture = -0.59843`;
- `shade_tolerance ↔ sunlight = -0.44674`.

Neutral control:

- water/moisture `+0.18268`;
- root/moisture `+0.09853`;
- shade/sunlight `+0.21177`.

То есть основной spatial signal не объясняется только случайным распределением mutation seeds.

## Региональная динамика

В generation 0 все diagnostic regions имеют один и тот же ancestor mean:

- water preference `0.58`;
- root depth `0.85 m`;
- shade tolerance `0.45`.

К generation 8:

- WET water preference `0.5761`, DRY `0.4913`;
- DRY root depth `0.9228 m`, WET `0.6754 m`;
- SHADED shade tolerance `0.4782`, SUNLIT `0.4380`.

То есть regional distributions возникают во времени, а не закладываются в initialization.

## Gate

После exact-Windows PASS S3 принимается. Следующий шаг — `ECO.P1B-S4 Local Adaptation Robustness Gate`: более широкий multi-seed/long-run aggregate check и решение о закрытии всего P1B. Migration намеренно остаётся за пределами P1B и относится к будущему ECO.P2 dispersal/biogeography.
