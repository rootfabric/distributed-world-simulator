# ECO.P1A-S4 — Determinism, Sensitivity and Failure Classification — ACCEPTED

## Решение

`ACCEPTED`.

Exact Windows runner на Godot `4.7.1.stable.double.custom_build.a13da4feb` подтвердил весь S4 gate без расхождения с локальным baseline.

## Parent regression

- P1A-S1: `109/109`;
- P1A-S2: `235/235`;
- P1A-S3: `208/208`.

## S4 automated evidence

- determinism/sensitivity/failure matrix: `165/165`;
- fresh-process restart replay: `5/5`;
- failures: `0`.

Принятые hashes:

- baseline summary: `327d211d24f8f74251e02f0ced22323b4120c18d9b42a9cfcf99974cf9accc5a`;
- full result: `cb1641a6b49dfa2be3f64c94f2ebc3240327eaca559d025d34e72ba74c0aa11e`;
- biomass series: `7c621f1a8c302fdd10f60fd4e576b7688a3bd1065f84c84b7c391e5031f05e0c`.

## Sensitivity conclusion

Малые perturbations moisture/sunlight/cost coefficients дают плавные и причинно ожидаемые изменения aggregate net. Root depth не является free trait: умеренное увеличение помогает, дальнейшее увеличение снова ухудшает глобальный результат; локально глубокие корни помогают dry ridge и одновременно вредят wet floodplain.

## Failure matrix

Пройдены проверки:

- global extinction;
- unbounded biomass;
- one-field domination;
- free trait escalation;
- boundary seams;
- hidden biome conditionals;
- presentation-resolution dependency;
- floating-point/restart replay divergence.

## Truth boundary

S4 не изменяет accepted S1 EnvironmentSample, S2 resource equations или S2 PatchSimulator. Все perturbations существуют только внутри research sensitivity harness.

## Следующий шаг

`P1A-S5 — P1A Acceptance + Evolution Decision`.

S5 не добавляет новую экологическую математику. Он сводит evidence S1–S4 по десяти критериям P1A и принимает либо отклоняет весь `ECO.P1A Environmental Causality Baseline`.
