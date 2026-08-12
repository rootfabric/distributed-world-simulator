# ECO.PH — Extensible Plant Rendering Architecture

Статус: `DESIGN CONTRACT / PH5-S1 ACCEPTED / PH5-S2 ACCEPTED / PH5-S3 NEXT / RESEARCH_ONLY`.

Центральный маршрут ветки: `docs/future_features/evolutionary_ecology/ECO_CENTRAL_ROUTE_RU.md`.

Цель: line-skeleton PH1 является только debug renderer. Рост визуальной сложности не должен менять genome, ecology, population identity, lifecycle или GrowthGraph semantics.

## Pipeline

`Genome + Development + Environment + IndividualSeed -> GrowthGraph -> PlantRenderDescription -> RendererProfile -> LOD representation`

`PlantRenderDescription` — derived representation description. Он может содержать branch primitives/splines/radius profiles, leaf/bud/flower anchors, canopy hints, material slots, wind weights, collision hints и LOD clusters, но не становится новой world truth.

## Renderer profiles

1. `DEBUG_SKELETON` — line projections/debug representation.
2. `BRANCH_TUBES` — tapered trunk/branch geometry.
3. `BRANCH_LEAF_INSTANCED` — branches + instanced leaves/buds/flowers.
4. `CANOPY_APPROXIMATION` — дешёвый crown volume/cluster renderer для массы растений.
5. `FULL_PROCEDURAL` — high-detail hero/promoted plant representation.
6. `IMPOSTOR_BILLBOARD` — дальний LOD.

Один и тот же GrowthGraph и один derived `PlantRenderDescription` должны быть допустимым входом для любого renderer profile.

## PH5 staged implementation

### PH5-S1 — PlantRenderDescription + RendererProfile Foundation

Статус: `ACCEPTED`.

Exact Windows evidence: focused `720`, visual smoke `15`, restart `4`; exact hashes:

- description `72196b2711322160e95dca32c0e4729dcf009f7c817a1448e53bd7de02ce97a3`;
- profile matrix `2121aaf7f0e725bcf9a8216784ad835bb488c0e6b5a3a1e24604220779c302e0`;
- full materialization `374eade14f40d3d42491ca24dfaae69adc511dea47e76bc629a5d3abf5a2028c`.

Graphical profile switching confirmed by user. S1 proves renderer/profile truth separation, not production 3D quality.

### PH5-S2 — 3D Tapered Branch Tubes + Instanced Foliage

Статус: `ACCEPTED`.

Реализовано:

- реальная triangle mesh materialization через `SurfaceTool -> ArrayMesh`;
- taper из `radius_start_m/radius_end_m` accepted PlantRenderDescription;
- profile-controlled radial tessellation (`branch_sides`);
- foliage `MultiMesh` с deterministic anchor transforms;
- leaf mesh/material остаётся replaceable presentation asset;
- отдельный Node3D graphical lab для `BRANCH_TUBES`, `BRANCH_LEAF_INSTANCED`, `FULL_PROCEDURAL`.

Exact Windows evidence:

- focused `387`;
- visual smoke `12`;
- fresh-process restart `5`;
- reference branch+leaf geometry `2e66860bff80fbf56274e211fcefe0ba4f895a39e76e153e835021a814305f0f`;
- full geometry `5b869596e4c341f1f43aa457828016ec8af657a1c0e771b22a7348f1e8ae743e`;
- graphical `PASS_BY_USER_OBSERVATION_REAL_3D_TREE_FORMATION`.

S2 invariant:

`mesh vertices / branch sides / leaf asset / MultiMesh instances != GrowthGraph / genome / species / population / ecology truth`.

### PH5-S3 — Multi-Scale Plant Representation / Canopy Approximation + Impostor/LOD

Статус: `NEXT`.

Цель S3 — не дальнейшая ботаническая косметика, а доказательство scale separation.

Representation tiers:

- `TIER_0_FULL` — detailed promoted/hero plant;
- `TIER_1_REDUCED` — reduced individual representation;
- `TIER_2_CANOPY` — canopy/cluster approximation;
- `TIER_3_IMPOSTOR` — billboard/impostor;
- `TIER_4_POPULATION_ONLY` — population truth without individual GrowthGraph materialization.

Необходимо доказать:

- near/mid/far renderer selection;
- profile/LOD switching without GrowthGraph/resource/selection/lifecycle hash change;
- возможность dematerialize/rematerialize individual representation;
- возможность вообще не materialize individual GrowthGraph для далёких population patches до observation/interaction promotion;
- `distance/screen size/LOD != ecology identity`.

### PH5-S4 — Visual Robustness / Handoff

Статус: `BLOCKED_BY_PH5_S3_ACCEPTANCE`.

- graphical acceptance across contrasting PH2 phenotypes;
- scale/profile/tier transitions;
- deterministic presentation descriptors;
- rematerialization/dematerialization robustness;
- bounded representation resources;
- explicit handoff and closure `ECO.PH RESEARCH COMPLETE`.

После S4 renderer research не должен автоматически продолжаться в PH6. Центральный маршрут требует разделить дальнейшую работу на `ECO.CONV0` world-integration contracts и `ECO.CAL1` morphology economics calibration; затем `CAL1 -> ECO.P2`, а production `ECO.P3 -> PH6` остаётся за canonical foundation gates.

## LOD invariant

`LOD / mesh tessellation / leaf asset / shader / renderer profile != genome, species, population or ecology identity`.

Смена LOD не имеет права менять GrowthGraph hash, PH3 resource result, PH3C selection inputs или PH4 lifecycle state.

## GrowthGraph evolution

Сегменты/узлы можно расширять derived annotations без превращения их в planet-wide truth: radius/taper, age, health, vigor, bud/growth-tip state, leaf/flower/fruit attachment sites, structural load, light exposure, resource-flow diagnostics, damage/pruning deltas для promoted individuals.

Следует различать:

- **development truth/input** — inherited traits + environment + history;
- **derived morphology** — GrowthGraph;
- **render description** — presentation-ready deterministic metadata;
- **renderer profile/LOD** — текущая стоимость и fidelity materialization.

## Roadmap convergence

- PH1: debug skeleton — ACCEPTED foundation.
- PH2: environment changes realized morphology, renderer remains passive — ACCEPTED.
- PH3: morphology pays resource costs/benefits — ACCEPTED.
- PH3C: morphology consequences affect pairwise selection — ACCEPTED causal scope.
- PH4: heredity/lifecycle transports program, not prebuilt phenotype/mesh — ACCEPTED.
- PH5-S1: renderer contract/diagnostic foundation — ACCEPTED.
- PH5-S2: real 3D branch/foliage materialization — ACCEPTED.
- PH5-S3: multi-scale LOD/population-only truth invariance — NEXT.
- PH5-S4: robustness and PH handoff — BLOCKED by S3.
- ECO.CONV0 + ECO.CAL1: planned after PH5-S4 as separate non-runtime lanes.
- ECO.P2: after CAL1 acceptance.
- ECO.P3/PH6: only after canonical production foundations and Harness-controlled promotion.

Запрещено вводить renderer-specific `TREE/BUSH/GRASS` canonical classes. Такие слова могут быть только post-hoc visual/ecological observations of continuous morphology space.
