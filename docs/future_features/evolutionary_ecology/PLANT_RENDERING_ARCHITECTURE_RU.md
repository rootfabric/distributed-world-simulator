# ECO.PH — Extensible Plant Rendering Architecture

Статус: `DESIGN_CONTRACT / PH5 ACTIVE RESEARCH / RESEARCH_ONLY`.

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

Статус: `ACTIVE CANDIDATE`.

Реализуются и проверяются:

- deterministic `PlantRenderDescription`;
- tapered branch metadata;
- foliage/bud anchors;
- canopy/bounds metadata;
- six renderer profiles;
- profile-specific materialization hashes/counts;
- diagnostic 2D lab, показывающий различия profiles без изменения source GrowthGraph hash.

S1 **не** заявляет production 3D rendering.

### PH5-S2 — 3D Tapered Branch Tubes + Instanced Foliage

После S1 acceptance:

- реальная 3D mesh/tube materialization из branch primitives;
- taper и branch radius profiles;
- foliage MultiMesh/instancing или эквивалентный representation layer;
- leaves/buds как replaceable assets/material slots;
- никакого влияния mesh density/leaf asset на ecology truth.

### PH5-S3 — Canopy Approximation + Impostor/LOD

- near/mid/far renderer selection;
- canopy cluster representation;
- impostor/billboard representation;
- profile/LOD switching without GrowthGraph/resource/lifecycle hash change;
- возможность вообще не materialize individual GrowthGraph для далёких population patches до observation/interaction promotion.

### PH5-S4 — Visual Robustness / Handoff

- graphical acceptance across contrasting PH2 phenotypes;
- scale and profile transitions;
- deterministic presentation descriptors;
- explicit handoff toward later P3 SpeciesCatalog/phenotype projection work without making renderer identity canonical.

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
- PH5: staged extensible visual materialization — ACTIVE.
- PH6: only promoted interacted individuals may persist detailed development/damage deltas under future canonical persistence ownership.

Запрещено вводить renderer-specific `TREE/BUSH/GRASS` canonical classes. Такие слова могут быть только post-hoc visual/ecological observations of continuous morphology space.
