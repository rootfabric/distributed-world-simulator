# ECO.PH5-S1 — PlantRenderDescription + RendererProfile Foundation — CANDIDATE

Статус: `LOCAL CORE FIXTURE PASS / REAL PH2 WINDOWS + GRAPHICAL PENDING`.

PH4 принят. PH5 начинается не с жёстко заданного TREE/BUSH/GRASS renderer, а с универсального derived pipeline:

`GrowthGraph -> PlantRenderDescription -> RendererProfile -> representation/LOD materialization`.

## Что реализовано

`PlantRenderDescription` детерминированно производит из GrowthGraph:

- tapered branch primitives;
- foliage/bud anchors;
- canopy bounds;
- representation bounds;
- собственный derived hash, всегда привязанный к source GrowthGraph hash.

Шесть renderer profiles:

1. `DEBUG_SKELETON`;
2. `BRANCH_TUBES`;
3. `BRANCH_LEAF_INSTANCED`;
4. `CANOPY_APPROXIMATION`;
5. `FULL_PROCEDURAL`;
6. `IMPOSTOR_BILLBOARD`.

Один и тот же `PlantRenderDescription` является входом для всех шести профилей. Смена профиля/LOD меняет только materialization hash/counts и не имеет права менять GrowthGraph.

## Fail-closed truth boundary

PH5-S1 не создаёт новую ecology truth. Renderer не участвует в genome, phenotype, resource ledger, morphology-aware selection, seed lifecycle, authority, networking или persistence.

`TREE/BUSH/GRASS` не вводятся как canonical classes.

## Local core preflight

На exact Godot 4.7.1 double Linux изолированно проверены опубликованные PH5-S1 core-файлы:

- focused contract fixture: `PASS (492 assertions)`;
- visual lab smoke: `PASS (15)`;
- fresh-process replay: `PASS (4)`.

Synthetic fixture hashes используются только как preflight evidence и **не** являются canonical PH5 hashes реальных PH2 растений:

- description: `3fb83c57e5bbffb34bf7396378f73fa02ff3c3d600c28570b41bcb147ebc9471`;
- profile matrix: `52adecb24e8f35f5fc97c59512670d660bf2901c8bf517842ad91b9ab10fb2a0`;
- full materialization: `e06be9cf131c1940640b6c745d64011bb65c0eda598b1d5f1591da9a371fd367`.

Все execution-critical Git blobs совпадают с локально прогнанными байтами.

## Почему PH5 разбит на подэтапы

PH5-S1 — contract + diagnostic visual materialization foundation. Это ещё не production 3D renderer.

После acceptance:

- `PH5-S2`: actual 3D tapered branch tubes + instanced foliage;
- `PH5-S3`: canopy approximation + impostor/LOD switching and truth-invariance proof;
- `PH5-S4`: visual robustness/acceptance and handoff toward later P3 representation work.

Так будущую сложность растений можно наращивать от debug skeleton до hero-quality procedural plant, не связывая fidelity с биологической идентичностью.

## Следующий gate

1. `RUN_ECO_PH5_TESTS.ps1` на exact Windows и реальных accepted PH2 GrowthGraphs.
2. Убедиться, что focused/restart hashes совпадают.
3. `OPEN_ECO_PH5_LAB.ps1` и вручную проверить 7 environments × 6 renderer profiles.
4. Только после graphical PASS принять PH5-S1.
