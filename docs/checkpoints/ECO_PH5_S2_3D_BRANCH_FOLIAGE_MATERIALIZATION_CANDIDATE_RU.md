# ECO.PH5-S2 — 3D Tapered Branch Tubes + Instanced Foliage — CANDIDATE

Статус: `IMPLEMENTED / EXACT WINDOWS PENDING / RESEARCH_ONLY`.

PH5-S1 принят. S2 переводит presentation foundation из 2D diagnostic materialization в реальную Godot 3D geometry path, не меняя источник истины.

## Pipeline

`accepted GrowthGraph -> accepted PlantRenderDescription -> RendererProfile -> Plant3DMaterializer -> ArrayMesh + MultiMesh`

## Реализовано

- tapered branch tubes строятся как triangle geometry через `SurfaceTool`;
- радиальная плотность берётся из `RendererProfile.branch_sides`;
- start/end radius каждого сегмента берутся из accepted `PlantRenderDescription`;
- `BRANCH_LEAF_INSTANCED` и `FULL_PROCEDURAL` используют `MultiMesh` foliage;
- leaf mesh/material является заменяемым presentation asset;
- создан реальный `Node3D` graphical lab с camera/light/ground;
- environment и profile можно переключать независимо от GrowthGraph.

## Fail-closed boundary

Mesh vertex count, radial sides, leaf mesh, leaf material и MultiMesh instance count не являются genome/species/population/ecology identity.

Renderer не имеет обратного пути в GrowthGraph, PH3 resource ledger, PH3C selection или PH4 lifecycle.

## Acceptance gate

`RUN_ECO_PH5_S2_TESTS.ps1` должен подтвердить:

1. parent PH5-S1 regression/replay;
2. non-empty real ArrayMesh для трёх 3D profiles во всех семи accepted PH2 environments;
3. deterministic tapered topology and positive AABB;
4. MultiMesh foliage для foliage profiles;
5. полную GrowthGraph immutability;
6. exact focused/fresh-process geometry-hash equality;
7. 3D scene smoke.

После automated PASS открыть `OPEN_ECO_PH5_S2_LAB.ps1` и визуально проверить несколько контрастных environments в `BRANCH_TUBES`, `BRANCH_LEAF_INSTANCED`, `FULL_PROCEDURAL`.

S2 пока не заявляет production botanical assets, wind animation, bark/leaf shaders, canopy clustering или impostor baking — это дальнейшие representation stages.
