# ECO.PH — Extensible Plant Rendering Architecture

Статус: `DESIGN_CONTRACT / RESEARCH_ONLY`.

Цель: текущий line-skeleton PH1 является только debug renderer. Рост визуальной сложности не должен менять genome, ecology, population identity или GrowthGraph semantics.

## Pipeline

`Genome + Development + Environment + IndividualSeed -> GrowthGraph -> PlantRenderDescription -> RendererProfile -> LOD representation`

`PlantRenderDescription` в будущем может содержать branch splines/radius profiles, leaf/bud/flower anchors, canopy hints, material slots, wind weights, collision hints и LOD clusters. Это **derived representation description**, не новая world truth.

## Renderer profiles

1. `DEBUG_SKELETON` — нынешние line projections.
2. `BRANCH_TUBES` — spline/tube trunk and branches with taper.
3. `BRANCH_LEAF_INSTANCED` — tubes + instanced leaves/buds/flowers.
4. `CANOPY_APPROXIMATION` — дешёвый crown volume/cluster renderer для массы растений.
5. `FULL_PROCEDURAL` — high-detail hero/promoted plant representation.
6. `IMPOSTOR_BILLBOARD` — дальний LOD.

Один и тот же GrowthGraph должен быть допустимым входом для любого renderer profile.

## LOD invariant

`LOD / mesh tessellation / leaf asset / shader / renderer profile != genome, species, population or ecology identity`.

Смена LOD не имеет права менять GrowthGraph hash или resource result. Для далёких population patches допускается вообще не материализовать individual GrowthGraph до появления наблюдателя/interaction promotion.

## GrowthGraph evolution

Сегменты/узлы можно расширять derived annotations без превращения их в planet-wide truth: radius/taper, age, health, vigor, bud/growth-tip state, leaf/flower/fruit attachment sites, structural load, light exposure, resource-flow diagnostics, damage/pruning deltas для promoted individuals.

## Roadmap convergence

- PH1: debug skeleton — ACCEPTED foundation.
- PH2: environment changes realized morphology, renderer remains passive.
- PH3: morphology pays resource costs/benefits.
- PH5: implement `PlantRenderDescription` + renderer profile abstraction + branch tubes + instanced foliage + canopy/impostor LOD.
- PH6: only promoted interacted individuals may persist detailed development/damage deltas under future canonical persistence ownership.

Запрещено вводить renderer-specific `TREE/BUSH/GRASS` canonical classes. Такие слова могут быть только post-hoc visual/ecological observations of continuous morphology space.
