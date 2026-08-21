# ECO.P1B-S3 — Regional Population Field and Trait Distribution — ACCEPTED

## Статус

`ACCEPTED / EXACT WINDOWS PASS`.

S2 доказал local selection в четырёх независимых контрольных средах. S3 переносит тот же принцип на одну неоднородную карту: `7×7 = 49` population patches, каждый с шестью individuals одной ancestral lineage.

## Архитектурная граница

- исходный genotype один;
- `lineage_id` один для всего эксперимента;
- individuals каждого patch уникальны;
- mutation stream не читает environment values;
- selection читает только принятый P1A `PlantResourceModelV1.net_resource_balance`;
- `DRY/WET/SHADED/SUNLIT` вычисляются постфактум как diagnostic quartiles и не участвуют в simulation;
- species/biome classes отсутствуют;
- migration и inter-patch competition отсутствуют;
- `seed_dispersal_distance_m` заморожен на `15 m` до отдельного dispersal/biogeography этапа.

## Exact Windows evidence

Godot `4.7.1.stable.double.custom_build.a13da4feb`:

- P1A-S1 `109/109`;
- P1A-S2 `235/235`;
- P1A-S3 `208/208`;
- P1A-S4 `165/165`;
- P1B-S1 `5834/5834`;
- P1B-S2 `364/364`;
- P1B-S3 focused `388/388`;
- P1B-S3 fresh-process replay `6/6`.

Hashes:

- real field: `cbd2f4a65f2a06f8ee9feeea0d9eae90d37cd0ede15df1bd808ef52773089b56`;
- neutral control: `b4d18ef35a2a77104fa18c8a3f3004a6f5898d572e57917429cc955cc7e2c5e6`;
- alternate seed: `ca81e0cfea0b05850470276fef10c880d3832613df9ff7f35d3c7395bd32589b`.

## Принятый causal result

Средний accepted resource balance всей карты изменился от `-0.15744` в generation 0 до `+0.18194` в generation 8.

Trait/environment correlations:

- `water_preference ↔ soil_moisture = +0.84993`;
- `root_depth ↔ soil_moisture = -0.59843`;
- `shade_tolerance ↔ sunlight = -0.44674`.

Neutral control:

- water/moisture `+0.18268`;
- root/moisture `+0.09853`;
- shade/sunlight `+0.21177`.

В generation 0 все diagnostic regions имеют один ancestor mean. К generation 8 WET/DRY и SHADED/SUNLIT trait distributions расходятся в ожидаемых причинных направлениях. Real и neutral run получают одинаковые first-generation candidate pools patch-by-patch, поэтому divergence создаёт selection environment, а не скрытая site-specific mutation.

## Решение

`ECO.P1B-S3 ACCEPTED`.

Открыт `ECO.P1B-S4 Local Adaptation Robustness Gate`: multi-seed + longer-run aggregate проверка перед принятием всего `ECO.P1B Local Adaptation Proof`. Migration остаётся за пределами P1B.
