# ECO.EVO7 VIS4.0 — Truth / Contract Audit R1

Дата: 2026-08-30  
Статус: IMPLEMENTED AUDIT CANDIDATE / NOT ACCEPTED  
Ветка: feature/eco-evo7-vis4-evolved-plant-morphology-r1  
Exact predecessor: PAR3 R3.2 8ca0fcc65752c3b748c793deb3b4a9f9ca4f17bf

## Scope

VIS4.0 реализует только truth/contract audit для будущего evolved plant morphology presentation.

Этот checkpoint не меняет:

- biology formulas;
- mutation policy;
- LS3.4 competition semantics;
- VIS2/VIS3/PLAY0 runtime presentation;
- persistence;
- network authority;
- canonical ecology state.

Implementer не объявляет этот checkpoint ACCEPTED.

## Durable artifacts

~~~text
docs/plans/ECO_EVO7_VIS4_0_TRUTH_CONTRACT_AUDIT_RU.md
config/ecology/eco-evo7-vis4-truth-contract-audit.v1.json
tests/ecology/eco_evo7_vis4_0_truth_contract_audit_acceptance.gd
RUN_ECO_EVO7_VIS4_0_TESTS.ps1
RUN_ECO_EVO7_VIS4_0_TESTS.sh
~~~

Главный VIS4 roadmap также обновлён:

~~~text
docs/plans/ECO_EVO7_VIS4_EVOLVED_PLANT_MORPHOLOGY_IMPLEMENTATION_PLAN_RU.md
~~~

## Audited truth

### Уже опубликовано LS3.4

Exact evaluation block подтверждён:

~~~text
phenotype_hash
effective_light
water_satisfaction
realized_height_m
leaf_area_index_proxy
realized_root_depth_m
realized_root_spread_m
root_shoot_ratio
realized_resource_balance
~~~

Это допустимые direct presentation inputs.

### Уже вычисляется, но теряется до presentation

PlantFunctionalPhenotype вычисляет, но LS3.4 evaluation не публикует:

~~~text
realized_crown_radius_m
realized_crown_density
leaf_size_proxy
leaf_conservative_strategy
structural_investment
growth_graph_hash
plasticity_phenotype_hash
~~~

VIS4.1 обязан переносить их source-bound из уже выполненного biology pass. Renderer-side recomputation запрещён.

### Exact realized topology

PH2 формирует:

~~~text
realized_development_traits
growth_graph
~~~

после environment plasticity.

Поэтому exact live topology должна происходить из PH2 realized evidence, а не из raw hereditary dev_traits.

VIS4.1 должен добавить additive evidence/sidecar или эквивалентный read-only publication path.

## Mutability audit

Текущие EVO7 R1 morphology mutation axes:

~~~text
max_height_m
crown_spread_m
apical_dominance
foliage_density
leaf_economics_proxy
structural_investment
root_spread_m
root_shoot_ratio
~~~

root_depth_m продолжает эволюционировать через существующий genome mutation kernel.

Следующие PH0 поля наследуются и участвуют в realized topology, но не входят в текущий EVO7 R1 morphology mutation AXES:

~~~text
internode_length_m
branch_probability
branch_angle_deg
branch_length_ratio
branching_depth
~~~

Их свободное evolutionary expansion остаётся будущим MORPH1.

## PH5 audit

Accepted PH5 capability donor подтверждён:

~~~text
GrowthGraph
PlantRenderDescription
RendererProfile
ArrayMesh branch materialization
MultiMesh foliage
CANOPY
IMPOSTOR
multiscale LOD
~~~

Но current PH5 presentation имеет зафиксированные ограничения:

- branch base radii сейчас фиксированы renderer logic;
- foliage anchor count сейчас фиксирован по типу segment;
- structural_investment не участвует в branch radius;
- realized_crown_density не управляет foliage density;
- leaf strategy не участвует в render description.

Следовательно VIS4.3/4.4 должен использовать тонкий source-bound presentation adaptation вокруг accepted PH5, а не создавать второй procedural renderer.

## PLAY0 audit

Current PLAY0 primary plant representation подтверждён:

~~~text
BoxMesh stem
SphereMesh crown
~~~

Current crown width использует LAI heuristic и не использует realized_crown_radius_m.

Это подтверждает, что первая большая проблема разнообразия является presentation bottleneck.

## Machine gate

Acceptance source-gate:

~~~text
tests/ecology/eco_evo7_vis4_0_truth_contract_audit_acceptance.gd
~~~

проверяет audit manifest против фактических source contracts и fail-closed фиксирует:

- published/hidden field boundary;
- PH2 realized topology ownership;
- hereditary sources;
- current mutation axes;
- VIS2 descriptor gap;
- PLAY0 bottleneck;
- PH5 reuse surface;
- PH5 presentation gaps;
- forbidden renderer recomputation;
- отсутствие canonical TREE/BUSH/GRASS classes.

## Validation evidence available in this implementation session

Exact Linux double Godot binary:

~~~text
4.7.1.stable.double.custom_build.a13da4feb
~~~

GDScript parse/syntax gate для exact current VIS4.0 acceptance script:

~~~text
godot --headless --check-only
res://tests/ecology/eco_evo7_vis4_0_truth_contract_audit_acceptance.gd

RC=0
~~~

Полный project runner на complete repository checkout в этой implementation environment не выполнялся, поэтому статус остаётся IMPLEMENTED AUDIT CANDIDATE.

Fresh exact-repository/exact-Windows verification должна выполняться через:

~~~text
RUN_ECO_EVO7_VIS4_0_TESTS.ps1
~~~

до любой формальной acceptance claim.

## Exit state

~~~text
TRUTH OWNER INVENTORY              COMPLETE
PUBLISHED FIELD INVENTORY          COMPLETE
HIDDEN MORPHOLOGY GAP              COMPLETE
REALIZED TOPOLOGY GAP              COMPLETE
MUTABILITY AUDIT                   COMPLETE
PH5 REUSE AUDIT                    COMPLETE
PH5 PRESENTATION GAP AUDIT         COMPLETE
PLAY0 BOTTLENECK AUDIT             COMPLETE
MACHINE-READABLE MANIFEST          PRESENT
SOURCE-GATE TEST                   PRESENT
EXACT DOUBLE GDSCRIPT PARSE        PASS
FULL REPOSITORY VERIFICATION       PENDING
FORMAL ACCEPTANCE                  NOT CLAIMED
~~~

## Next route

Следующий implementation checkpoint:

~~~text
VIS4.1 — Source-Bound Morphology Evidence / Descriptor V2
~~~

Его цель — открыть presentation layer уже рассчитанные realized morphology/topology facts без повторного вызова biology и без изменения ecology authority.
