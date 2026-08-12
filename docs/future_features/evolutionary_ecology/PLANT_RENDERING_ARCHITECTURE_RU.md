# ECO.PH — Extensible Plant Rendering Architecture

Статус: `DESIGN CONTRACT / PH5-S1..S4 ACCEPTED / ECO.PH RESEARCH COMPLETE / RESEARCH_ONLY`.

Центральный маршрут:

`docs/future_features/evolutionary_ecology/ECO_CENTRAL_ROUTE_RU.md`.

Post-PH5 global alignment:

`docs/future_features/evolutionary_ecology/ECO_CONV0_GLOBAL_ALIGNMENT_RU.md`.

Цель PH renderer track: line-skeleton, 3D geometry, canopy, impostor и LOD являются derived presentation. Рост визуальной сложности не должен менять genome, ecology, population identity, lifecycle или GrowthGraph semantics.

## Accepted pipeline

`Genome + Development + Environment + IndividualSeed -> GrowthGraph -> PlantRenderDescription -> RendererProfile -> Multi-Scale Representation`.

`PlantRenderDescription` — deterministic derived presentation metadata, не world truth.

## Renderer profiles

1. `DEBUG_SKELETON` — line/debug representation;
2. `BRANCH_TUBES` — tapered branch geometry;
3. `BRANCH_LEAF_INSTANCED` — branches + instanced foliage;
4. `CANOPY_APPROXIMATION` — crown volume/cluster approximation;
5. `FULL_PROCEDURAL` — detailed hero/promoted representation;
6. `IMPOSTOR_BILLBOARD` — far billboard representation.

## PH5-S1 — ACCEPTED

PlantRenderDescription + RendererProfile foundation.

Exact Windows evidence:

- focused `720`;
- visual smoke `15`;
- restart `4`;
- reference description `72196b2711322160e95dca32c0e4729dcf009f7c817a1448e53bd7de02ce97a3`;
- profile matrix `2121aaf7f0e725bcf9a8216784ad835bb488c0e6b5a3a1e24604220779c302e0`;
- graphical `PASS_BY_USER_OBSERVATION`.

## PH5-S2 — ACCEPTED

Real tapered branch `ArrayMesh` + foliage `MultiMesh`.

Exact Windows evidence:

- focused `387`;
- visual smoke `12`;
- restart `5`;
- reference branch+leaf geometry `2e66860bff80fbf56274e211fcefe0ba4f895a39e76e153e835021a814305f0f`;
- full geometry `5b869596e4c341f1f43aa457828016ec8af657a1c0e771b22a7348f1e8ae743e`;
- graphical `PASS_BY_USER_OBSERVATION_REAL_3D_TREE_FORMATION`.

## PH5-S3 — ACCEPTED

Multi-scale tiers:

- `TIER_0_FULL`;
- `TIER_1_REDUCED`;
- `TIER_2_CANOPY`;
- `TIER_3_IMPOSTOR`;
- `TIER_4_POPULATION_ONLY`.

Accepted properties:

- deterministic tier selection + hysteresis;
- strict truth-hash validation;
- real reduced ArrayMesh/MultiMesh counts match declared representation cost;
- real canopy mesh;
- real Godot billboard material for impostor;
- population-only requires no individual plant geometry/GrowthGraph materialization;
- tier change cannot mutate ecology truth.

Exact Windows evidence:

- tier policy `49`;
- far materialization `16`;
- real multiscale materialization `61`;
- matrix `f0a2b391c2c1ded19f8d44e0fb46b66256ad98e09366eab40b094ea4903e3b20`.

## PH5-S4 — ACCEPTED

Robustness/handoff:

- nonfinite/invalid input fail-closed;
- hysteresis and threshold churn stable;
- dematerialization/rematerialization deterministic;
- contrasting PH2 phenotype × five-tier matrix;
- graphical near/mid/far/population-only lab.

Exact Windows evidence:

- robustness `5026`, digest `dea866454f7655067fe739803c00663a0bb08c6f1649ce899044c5a4ea04fb51`;
- canonical PH2 × tier matrix `430`, hash `e0522bb289060d064134a3955a3979a9b5fc0066500d5ca082f3eaf99666a68d`;
- visual lab smoke `40`;
- graphical `PASS_BY_USER_CONFIRMATION_AFTER_ACCEPTANCE_LAB_EXECUTION`.

Accepted checkpoint:

`docs/checkpoints/ECO_PH5_S3_S4_MULTISCALE_REPRESENTATION_ACCEPTED_RU.md`.

## LOD invariant

`LOD / mesh tessellation / leaf asset / shader / renderer profile != genome, species, population or ecology identity`.

Смена representation tier не имеет права менять GrowthGraph hash, PH3 resource result, PH3C selection inputs или PH4 lifecycle state.

## Closure boundary

`ECO.PH RESEARCH COMPLETE` означает, что renderer research закрыт как самостоятельная линия. Новые идеи о aggregate population projection, bounded synthetic samples, interest/network projection и promoted individual lifecycle не должны снова расширять PH5 core.

Они переходят в следующие контексты:

- `CONV0` — world-integration consumer contracts and aggregate projection requirements;
- `CAL1/P2` — ecology research semantics;
- `P3/PH6` — только после canonical production foundations.

## GrowthGraph / promoted detail

Для будущих promoted individuals можно сохранять derived/delta annotations: radius/taper, age, health, vigor, buds/growth tips, leaf/flower/fruit sites, structural load, exposure, damage/pruning deltas.

Но:

`planet-wide individual GrowthGraph truth` запрещён.

## Roadmap convergence

- PH1 debug skeleton — ACCEPTED;
- PH2 environment-coupled phenotype — ACCEPTED;
- PH3 morphology resource coupling — ACCEPTED;
- PH3C pairwise morphology-aware selection — ACCEPTED causal scope;
- PH4 seed development lifecycle — ACCEPTED;
- PH5-S1 render description/profile foundation — ACCEPTED;
- PH5-S2 real 3D branch/foliage — ACCEPTED;
- PH5-S3 multi-scale representation — ACCEPTED;
- PH5-S4 robustness/handoff — ACCEPTED;
- ECO.PH — RESEARCH COMPLETE;
- CONV0-A — NEXT design-contract alignment;
- CAL1 — next research stage after CONV0-A;
- CONV0-B — wait canonical R3 foundation contracts;
- P3/PH6 — only after canonical production foundations and Harness-controlled promotion.

Renderer-specific `TREE/BUSH/GRASS` canonical classes remain forbidden; those labels may exist only as post-hoc observations of continuous morphology space.
