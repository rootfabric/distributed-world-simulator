# ECO.P1B-S2 — Spatial Selection Baseline — ACCEPTED

## Решение

`ACCEPTED` по exact-Windows прогону на `Godot 4.7.1.stable.double.custom_build.a13da4feb`.

- P1A-S1: `109/109`;
- P1A-S2: `235/235`;
- P1A-S3: `208/208`;
- P1A-S4: `165/165`;
- P1B-S1: `5834/5834`;
- P1B-S2 focused: `364/364`;
- P1B-S2 fresh-process replay: `6/6`.

Fixed hashes:

- result: `a48df039415162a2e2b75fb9badc12ae35fd0cac9f459ae2ba9df88ab1280e80`;
- alternate seed: `507bcc108d458b685d97b96268d18e307f3cdc36ae0530a75801cddf2e6b8521`;
- first candidate pool: `9e4b8eba9d7d6bf915de209814e6edba823f30675c6f2aefa6a209fff135f2fd`.

## Что доказано

Четыре contrasting environments получают один и тот же generation-one mutation candidate pool. После применения accepted P1A `PlantResourceModelV1` выбранные populations расходятся. Значит первичное расхождение создаётся selection environment, а не site-specific mutation.

Selection не использует новый handwritten fitness score. Он ранжирует кандидатов по accepted `net_resource_balance`, а biomass/recruitment наблюдаются через accepted `SinglePlantPatchSimulatorV1`.

После 16 generations:

- floodplain уходит к мелким roots и более высокой water preference;
- dry ridge — к более глубоким roots и более низкой water preference;
- shaded slope — к большей shade tolerance;
- sunny slope — к меньшей shade tolerance.

Cross-environment matrix показывает, что каждая locally selected population имеет лучший accepted resource consequence в своей native environment среди четырёх evolved populations.

Второй mutation seed даёт другой exact result hash и другие genomes, но сохраняет феномен specialization.

## Граница

S2 не вводит migration, species formation, biome rules, inter-population competition, authority, persistence, networking или presentation coupling. `seed_dispersal_distance_m` остаётся frozen, потому что migration benefit ещё не моделируется.

## Следующий шаг

`ECO.P1B-S3 — Regional Population Field and Trait Distribution`: одна неоднородная 2D-карта с population patches и наблюдаемыми regional trait distributions во времени.
