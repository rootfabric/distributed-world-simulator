# ECO.PH5-S2 — 3D Tapered Branch Tubes + Instanced Foliage — ACCEPTED

Статус: `ACCEPTED / RESEARCH_ONLY`.

PH5-S2 принят по exact Windows evidence и ручной graphical observation.

## Evidence

Engine: `Godot 4.7.1.stable.double.custom_build.a13da4feb`.

- PH5-S1 parent focused/restart: PASS;
- PH5-S2 focused real 3D materialization: `PASS (387 assertions)`;
- PH5-S2 3D visual lab smoke: `PASS (12 assertions)`;
- PH5-S2 fresh-process restart replay: `PASS (5 assertions)`;
- `reference_branch_leaf_geometry_hash=2e66860bff80fbf56274e211fcefe0ba4f895a39e76e153e835021a814305f0f`;
- `full_geometry_hash=5b869596e4c341f1f43aa457828016ec8af657a1c0e771b22a7348f1e8ae743e`;
- graphical: `PASS_BY_USER_OBSERVATION_REAL_3D_TREE_FORMATION`.

В graphical lab подтверждено, что `BRANCH_TUBES`, `BRANCH_LEAF_INSTANCED` и `FULL_PROCEDURAL` формируют реальную 3D geometry path с tapered branch mesh и foliage instances.

## Accepted truth boundary

`accepted GrowthGraph -> PlantRenderDescription -> RendererProfile -> derived ArrayMesh/MultiMesh`.

Mesh tessellation, branch sides, leaf asset/material и foliage instance count остаются presentation-only. Они не являются genome/species/population/ecology identity и не имеют обратного пути в resource/selection/lifecycle truth.

## Следующий этап

`ECO.PH5-S3 — Multi-Scale Plant Representation / Canopy Approximation + Impostor/LOD Truth-Invariance`.

Главная задача S3 — доказать переходы `FULL -> REDUCED -> CANOPY -> IMPOSTOR -> POPULATION_ONLY` без изменения ecology identity/truth и без обязательной materialization individual GrowthGraph на дальней дистанции.
