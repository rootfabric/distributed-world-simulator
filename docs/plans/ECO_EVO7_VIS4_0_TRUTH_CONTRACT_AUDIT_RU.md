# ECO.EVO7 VIS4.0 — Truth / Contract Audit

Статус: IMPLEMENTED AUDIT CANDIDATE / EXACT-WINDOWS VERIFICATION REQUIRED  
Дата: 2026-08-30  
Ветка: feature/eco-evo7-vis4-evolved-plant-morphology-r1  
Base: PAR3 R3.2 8ca0fcc65752c3b748c793deb3b4a9f9ca4f17bf

## 1. Вывод аудита

VIS4 можно продолжать без изменения biology, но исходный план требовал одной важной коррекции.

Правильная цепочка истины для формы растения:

~~~text
hereditary potential
      |
      v
PH2 environment-coupled development
      |
      +-> realized_development_traits
      +-> exact GrowthGraph
      |
      v
PlantFunctionalPhenotype
      |
      +-> realized crown/root/resource scalars
      |
      v
LS3.4 competition
      |
      v
published ecology snapshot
      |
      v
VIS4 presentation
~~~

Критическая граница: renderer не должен повторно вызывать biology для восстановления того, что уже было рассчитано внутри LS3.4.

## 2. Что уже публикуется честно

LS3.4 evaluation уже публикует source-bound:

~~~text
phenotype_hash
realized_height_m
leaf_area_index_proxy
realized_root_depth_m
realized_root_spread_m
root_shoot_ratio
water_satisfaction
effective_light
realized_resource_balance
~~~

Эти поля VIS2 может читать напрямую без recompute.

## 3. Что уже вычисляется, но теряется на publication boundary

PlantFunctionalPhenotype уже вычисляет:

~~~text
realized_crown_radius_m
realized_crown_density
leaf_size_proxy
leaf_conservative_strategy
structural_investment
growth_graph_hash
plasticity_phenotype_hash
~~~

Но текущий LS3.4 evaluation их не переносит.

Следствие:

~~~text
biology knows the value
renderer cannot see the value
~~~

VIS4.1 должен сделать additive source-bound pass-through. Renderer не имеет права восстанавливать эти значения собственной формулой.

## 4. Более глубокий gap: exact realized branch topology

PH2 не просто масштабирует высоту. Он реально меняет DevelopmentTraits по среде:

~~~text
max_height_m
internode_length_m
apical_dominance
branch_probability
branch_angle_deg
branch_length_ratio
branching_depth
crown_spread_m
~~~

В частности PH2 реагирует на:

~~~text
shade elongation
shade branch suppression
light branching
drought suppression
nutrient growth
flood suppression
~~~

После этого PH2 строит exact GrowthGraph от realized traits + individual_seed.

Однако LS3.4 наружу не публикует:

~~~text
realized_development_traits
exact GrowthGraph
growth_graph_hash
plasticity phenotype seal
~~~

Поэтому читать только hereditary dev_traits в VIS4 было бы недостаточно честно: под тенью, засухой или ярким светом видимая topology может отличаться от genetic potential.

### Решение для VIS4.1

Нужен additive read-only morphology evidence sidecar или эквивалентная source-bound поверхность, содержащая минимум:

~~~text
record_id
bundle_checksum
individual_seed
phenotype_hash
plasticity_phenotype_hash
growth_graph_hash
realized_development_traits
realized_crown_radius_m
realized_crown_density
leaf_size_proxy
leaf_conservative_strategy
structural_investment
~~~

Она должна формироваться в том же LS3.4 calculation pass, где PH2/FunctionalPhenotype уже рассчитаны.

Запрещён вариант:

~~~text
renderer
 -> reconstruct environment
 -> call phenotype biology again
~~~

## 5. Что реально эволюционирует сейчас

Аудит mutation authority уточнил важную деталь.

### Mutable morphology в EVO7 R1

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

Плюс через старый genome mutation kernel:

~~~text
root_depth_m
~~~

### Heritable, но НЕ mutable в EVO7 R1

~~~text
internode_length_m
branch_probability
branch_angle_deg
branch_length_ratio
branching_depth
~~~

Следовательно, эти пять параметров уже участвуют в PH topology и plasticity, но пока не создают самостоятельную генетическую дивергенцию внутри текущего FFF2 mutation policy.

Это подтверждает правильность отдельного будущего MORPH1.

## 6. Что это значит для ожидаемого разнообразия уже в VIS4

Без MORPH1 уже можно честно увидеть evolutionary variation по:

~~~text
height
crown spread
apical dominance
crown/foliage density
leaf economics
structural investment
root allocation/spread/depth
~~~

Плюс environmental plasticity изменяет internode/branch probability/angle/length/crown spread для конкретного растения.

Но нельзя заявлять, что branch_angle или branching_depth уже эволюционируют генетически в текущем EVO7 R1.

## 7. Текущий VIS2 gap

VIS2 descriptor сегодня уже честно переносит часть LS3.4 evidence, но не имеет:

~~~text
individual_seed
realized_crown_radius_m
realized_crown_density
structural_investment
growth_graph_hash
plasticity_phenotype_hash
realized PH2 topology
~~~

Поэтому VIS4.1 должен быть versioned/additive successor, а не renderer-side reconstruction.

## 8. Текущий PLAY0 bottleneck подтверждён

PLAY0 primary 3D plant renderer сейчас создаёт:

~~~text
BoxMesh stem
SphereMesh crown
~~~

и crown width выводится из LAI presentation heuristic.

В source нет direct use realized_crown_radius_m и нет PH5 multiscale materializer.

Следовательно, одинаковость текущих растений действительно presentation-driven.

## 9. PH5 reuse audit

PH5 обязателен к переиспользованию и уже даёт:

~~~text
deterministic GrowthGraph
tapered branch geometry
ArrayMesh branches
MultiMesh foliage
canopy
impostor
multiscale LOD
~~~

Но обнаружены три presentation gaps, которые нельзя скрыть словом reuse.

### PH5 gap A — structural investment

plant_render_description_v1 использует фиксированные branch base radii:

~~~text
main axis  -> 0.035
lateral   -> 0.014
~~~

structural_investment не участвует.

Значит VIS4 должен добавить derived presentation mapping structural investment -> branch radius/taper cue, не меняя biology.

### PH5 gap B — crown/foliage density

PH5 foliage anchors сегодня создаются фиксированно по segment class:

~~~text
first segment -> 0
main axis     -> 1
lateral      -> 2
~~~

realized_crown_density и LAI напрямую не управляют количеством foliage anchors.

Значит VIS4 adapter должен source-bound управлять visible foliage density поверх accepted PH5 geometry path.

### PH5 gap C — leaf economics

leaf_economics_proxy / leaf_conservative_strategy не используются PH5 render description.

Если VIS4 визуализирует leaf strategy, это должна быть отдельная derived presentation mapping, source-bound к published phenotype.

## 10. Правильная роль hereditary fields

Hereditary bundle остаётся важен для:

~~~text
genetic potential inspector
mutation/evolution explanation
identity/checksum binding
individual_seed
~~~

Но после этого аудита принято правило:

> raw hereditary topology нельзя выдавать за exact live realized topology, если PH2 уже применил environment plasticity.

В inspector следует различать:

~~~text
GENETIC POTENTIAL
REALIZED PHENOTYPE
~~~

## 11. Individual seed

individual_seed уже находится в hereditary bundle и используется GrowthGraph как deterministic keyed source.

Это правильный источник individual variation.

~~~text
same source + same seed
-> same graph
~~~

Никакой visual RNG в VIS4 не нужен.

## 12. Grid / position boundary

VIS2 stable jitter уже является presentation-only.

Но ecology truth остаётся Spatial Cohort Lattice.

VIS4.0 фиксирует:

~~~text
presentation offset
!= ecological position
~~~

Continuous plant position остаётся отдельным ECO.SPATIAL1.

## 13. Machine-readable audit

Добавлен:

~~~text
config/ecology/eco-evo7-vis4-truth-contract-audit.v1.json
~~~

Он фиксирует:

- authority boundary;
- live published fields;
- computed-but-not-published fields;
- realized topology publication gap;
- hereditary sources;
- mutable vs currently frozen architecture axes;
- preferred visual source per property;
- PH5 capability donors;
- PH5 presentation gaps;
- обязательные VIS4.1 actions;
- forbidden shortcuts.

## 14. Machine acceptance

Добавлен:

~~~text
tests/ecology/eco_evo7_vis4_0_truth_contract_audit_acceptance.gd
~~~

Тест проверяет source-level truth:

1. exact VIS4.0 identity/base;
2. no write authority;
3. exact LS3.4 published fields;
4. FunctionalPhenotype hidden fields действительно существуют;
5. hidden fields действительно отсутствуют в LS3.4 evaluation;
6. PH2 realized topology действительно существует;
7. PH2 realized topology не публикуется LS3.4;
8. hereditary source contracts;
9. mutable vs non-mutable EVO7 R1 axes;
10. VIS2 descriptor gap;
11. PLAY0 BoxMesh/SphereMesh bottleneck;
12. PH5 capability donors;
13. PH5 fixed radius/leaf-count gaps;
14. branch topology preferred source = PH2 realized traits;
15. renderer recomputation and canonical TREE/BUSH/GRASS classes forbidden.

Runners:

~~~text
RUN_ECO_EVO7_VIS4_0_TESTS.ps1
RUN_ECO_EVO7_VIS4_0_TESTS.sh
~~~

## 15. VIS4.0 exit verdict

Design exit выполнен на уровне implementation candidate:

~~~text
SOURCE INVENTORY          COMPLETE
TRUTH OWNERS              FROZEN
PUBLICATION GAPS          IDENTIFIED
MUTABILITY TRUTH          FROZEN
PH5 REUSE SURFACE         CONFIRMED
PH5 PRESENTATION GAPS     IDENTIFIED
FORBIDDEN SHORTCUTS       FROZEN
VIS4.1 INPUT CONTRACT     DEFINED
~~~

Но Implementer не объявляет собственный checkpoint ACCEPTED.

До acceptance ещё требуется exact-head test verification, а по проектной дисциплине независимая проверка при необходимости.

## 16. Следующий checkpoint

VIS4.1 теперь имеет более точную цель:

> не просто добавить несколько полей в VIS2 descriptor, а создать source-bound morphology evidence, которое переносит уже рассчитанную realized PH2 topology + скрытые FunctionalPhenotype morphology fields к presentation layer без повторного biology calculation.

Это устраняет главный риск второго источника истины до начала renderer work.
