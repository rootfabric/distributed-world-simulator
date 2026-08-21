# ECO.P1C-S2 — Dynamic Shared-Patch Abundance Competition — ACCEPTED

## Решение

`ACCEPTED` по exact-Windows evidence от 2026-08-11.

## Проверка

- P1A-S1 `109/109` PASS;
- P1A-S2 `235/235` PASS;
- P1A-S3 `208/208` PASS;
- P1A-S4 `165/165` PASS;
- P1B-S1 `5834/5834` PASS;
- P1B-S2 `364/364` PASS;
- P1B-S3 `388/388` PASS;
- P1B-S4 `86/86` PASS;
- P1C-S1 `116/116` PASS;
- P1C-S2 `101/101` PASS;
- fresh-process replay `5/5` PASS.

Exact hashes совпали с Linux baseline:

- result `3e52c4e93fcdefba64607dd2c935ccbddba78db3f400d6a6ea51b23db766982b`;
- uniform `47f0e9c7573bf002151718a57c930d400682c3d86dbd3a8b96b8ddf48c4a01a2`;
- alternate `4706d80289b1fc9918f1758ccabdbb62a76053739f3c7bccadcd282e797d572b`;
- founder pool `77acaada39a39c54224b73f2548ebc228343e869264e45780d08419ebb6bee38`.

## Что доказано

Статический top-rank pressure из S1 не превратился в глобальную biomass-монополию. В heterogeneous field founder №14 лидирует на 80% patches, но удерживает только ~24.1% общей biomass; `19/20` founders остаются выше 1% global biomass. Uniform control сохраняет только 11 founders выше 1% и выбирает одного лидера на всех patches.

Следовательно, heterogeneous environment поддерживает динамическое coexistence нескольких стратегий, а не только разные top-N snapshot rankings.

## Граница truth

S2 не вводит новые species/biome classes, новый fitness score, mutation, migration, authority, persistence, networking или presentation truth. Growth/mortality/recruitment остаются делегированы принятому P1A `SinglePlantPatchSimulatorV1`.

## Следующий шаг

`ECO.P1C-S3 — Niche/Cluster Diagnostics + Multi-seed Coexistence`.
