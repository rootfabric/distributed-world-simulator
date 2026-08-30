# ECO.EVO7 VIS4.1 — Source-Bound Morphology Evidence / Descriptor V2

Дата: 2026-08-30  
Статус: IMPLEMENTED CANDIDATE / EXACT-HEAD VERIFICATION IN PROGRESS  
Ветка: feature/eco-evo7-vis4-evolved-plant-morphology-r1  
Predecessor: VIS4.0 Truth / Contract Audit  
Base lineage: PAR3 R3.2 8ca0fcc65752c3b748c793deb3b4a9f9ca4f17bf

## Цель

Закрыть publication gap, найденный VIS4.0, без переноса biology в renderer.

Новая цепочка:

~~~text
LS3.4 existing phenotype pass
  |
  +-> PH2 realized_development_traits
  +-> exact GrowthGraph
  +-> FunctionalPhenotype morphology
  |
  v
PlantMorphologyEvidence.v1
  |
  v
separate sealed presentation sidecar
  |
  v
Workbench.get_morphology_evidence()
  |
  v
VIS4 Morphology Descriptor V2
~~~

LS3.4 ecology snapshot schema и его state_hash не расширяются morphology sidecar-ом. Evidence имеет отдельный hash и source binding.

## Evidence contract

Файл:

~~~text
scripts/research/ecology/plant_morphology_evidence_v1.gd
~~~

Schema:

~~~text
distributed_world_simulator.ecology.plant_morphology_evidence.v1
ECO.EVO7-VIS4.1.R1
~~~

Contract явно объявляет:

~~~text
derived_representation = true
presentation_only = true
~~~

### Identity/source binding

~~~text
record_id
cell_index
bundle_checksum
lineage_id
individual_seed
source_phenotype_hash
source_plasticity_phenotype_hash
source_growth_graph_hash
source_inherited_traits_hash
source_realized_traits_hash
source_extension_traits_hash
~~~

### GENETIC POTENTIAL

~~~text
max_height_m
internode_length_m
apical_dominance
branch_probability
branch_angle_deg
branch_length_ratio
branching_depth
crown_spread_m
foliage_density
leaf_economics_proxy
structural_investment
root_depth_m
root_spread_m
root_shoot_ratio
~~~

### REALIZED PH2 TOPOLOGY

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

Это exact environment-plasticity result, а не raw hereditary potential.

### FUNCTIONAL MORPHOLOGY

~~~text
realized_height_m
realized_crown_radius_m
realized_crown_density
leaf_area_index_proxy
leaf_size_proxy
leaf_conservative_strategy
structural_investment
realized_root_depth_m
realized_root_spread_m
root_shoot_ratio
~~~

Каждый record имеет evidence_hash.

## Sidecar snapshot seal

Evidence snapshot связывается с:

~~~text
generation
source_precompetition_population_hash
source_competition_hash
source_postcompetition_population_hash
record_count
records[]
evidence_hash
~~~

Sidecar содержит только surviving current plants.

## LS3.4 single-pass integration

Файл:

~~~text
scripts/ecology/shadow/eco_evo7_ls34_local_competition_v1.gd
~~~

До VIS4.1:

~~~text
ph2 = CoupledDevelopment.realize(...)
fp  = FunctionalPhenotype.compile(...)
competition consumes fp
~~~

После VIS4.1:

~~~text
ph2 = CoupledDevelopment.realize(...)      # один call site
fp  = FunctionalPhenotype.compile(...)    # один call site

competition consumes fp
MorphologyEvidence.build_record(record, ph2, fp)
~~~

То есть presentation evidence создаётся из уже рассчитанных объектов. Повторного biology pass нет.

Добавлены public read-only API:

~~~text
get_morphology_evidence()
validate_morphology_evidence()
~~~

При изменении competition mode sidecar инвалидируется, чтобы stale evidence не мог попасть в presentation.

## Workbench facade

Файл:

~~~text
scripts/ecology/shadow/eco_evo7_ls36_rule_workbench_v1.gd
~~~

Добавлены:

~~~text
get_morphology_evidence()
validate_morphology_evidence()
~~~

Workbench не вычисляет morphology и не лезет в private internals.

## Descriptor V2

Файл:

~~~text
scripts/labs/ecology/eco_evo7_vis4_morphology_render_adapter.gd
~~~

Schema:

~~~text
distributed_world_simulator.ecology.evo7_vis4_morphology_render_adapter.v2
~~~

Descriptor хранит раздельно:

~~~text
potential_morphology
realized_topology
functional_morphology
competition_context
~~~

Source seals:

~~~text
phenotype_hash
plasticity_phenotype_hash
growth_graph_hash
source_evidence_record_hash
source_evaluation_hash
~~~

### Generation 0

Только:

~~~text
FOUNDER_RECORD_ONLY
~~~

Разрешён genetic potential. Fabricated phenotype / realized topology / functional morphology запрещены.

### Generation > 0

Каждый living descriptor обязан иметь:

~~~text
LS3.4_SOURCE_BOUND_MORPHOLOGY
~~~

и exact binding к ecology state, competition, morphology evidence, evidence record и LS3.4 evaluation.

Fallback на founder data запрещён.

## Почему VIS2/PLAY0 ещё не переключены

VIS4.1 создаёт source surface, но не меняет renderer. Это намеренно:

~~~text
VIS4.1 evidence
   ->
VIS4.2 honest diagnostic morphology
   ->
VIS4.3 PH5 bridge
   ->
VIS4.4 PLAY0.MORPH
~~~

Так evidence publication отделена от renderer migration.

## Fail-closed cases

Отклоняются:

- morphology record с изменённым значением и старым hash;
- wrong postcompetition population binding;
- sidecar другой generation;
- evidence другого competition hash;
- record/bundle/cell mismatch;
- phenotype hash mismatch между evidence и LS3.4 evaluation;
- dead evaluation в live descriptor;
- generation > 0 без sidecar;
- generation 0 с fabricated realized evidence.

## Determinism

При одинаковых seeds:

~~~text
ecology state_hash A == B
morphology evidence_hash A == B
Descriptor V2 adapter_hash A == B
~~~

Evidence hash не входит в ecology state_hash.

## Automated acceptance

Focused test:

~~~text
tests/ecology/eco_evo7_vis4_1_source_bound_morphology_evidence_acceptance.gd
~~~

Он проверяет:

1. generation-zero founder honesty;
2. real generation step;
3. exact sidecar source binding;
4. one evidence record per surviving plant;
5. potential / realized / functional separation;
6. exact crown radius/density/structural exposure;
7. exact PH2 topology exposure;
8. exact competition context;
9. tamper rejection;
10. wrong-population rebind rejection;
11. deterministic replay;
12. no renderer-side phenotype recomputation;
13. one LS3.4 PH2 call site;
14. one LS3.4 FunctionalPhenotype call site;
15. no mutation/persistence/network authority.

Regression runners:

~~~text
RUN_ECO_EVO7_VIS4_1_TESTS.ps1
RUN_ECO_EVO7_VIS4_1_TESTS.sh
~~~

Они включают VIS4.0, FFF2/PH2 parent chain, LS3.4, LS3.6, VIS4.1 focused acceptance и VIS1/VIS2 regression.

## Exact Windows CI

Branch-local workflow:

~~~text
.github/workflows/evo7-vis4-1-source-bound-morphology.yml
~~~

Использует self-hosted Windows X64, exact github.sha и Godot:

~~~text
4.7.1.stable.double.custom_build.a13da4feb
~~~

Implementer не объявляет ACCEPTED до exact-head GREEN evidence.

## Authority

VIS4.1 не создаёт new mutation, fitness, competition, population, persistence, network или taxonomy authority.

Evidence и Descriptor V2 являются derived/reconstructable read models.

## Exit criteria

Technical completion требует:

~~~text
evidence contract present
single-pass packaging present
Workbench read-only API present
Descriptor V2 present
founder honesty present
source binding present
tamper rejection present
deterministic replay present
LS3.4 regression green
LS3.6 regression green
VIS2 regression green
exact double-Godot green
~~~

Formal acceptance остаётся отдельным reviewer/verifier action.

## Next

Следующий пункт:

~~~text
VIS4.2 — Honest Diagnostic Morphology
~~~

Он обязан читать только Descriptor V2 и не вызывать biology напрямую.
