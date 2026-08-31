# ECO.EVO7 VIS4.2 — Honest Diagnostic Morphology R1

Дата: 2026-08-31  
Статус: WINDOWS VERIFIED RED / SUPERSEDED BY VIS4.2 R2 REPAIR  
Ветка: feature/eco-evo7-vis4-evolved-plant-morphology-r1

Predecessor accepted boundary:

~~~text
VIS4.1 R2 exact-tested implementation:
c499a39ee3fa4c7b5ab871df7f89f7cb4b6ec436
TREE 4427bada5367f9b06d4b642a6ab9e73670821c2e
~~~

VIS4.1 formal closure documentation HEAD preceded VIS4.2 implementation:

~~~text
2d239f8c70b5306613132fe6a0b1d25d336a5149
~~~

## Goal

VIS4.2 must make already-existing evolved morphology visibly honest before PH5/PLAY0 migration.

It does NOT:
- change biology;
- replace PLAY0;
- generate a second phenotype;
- introduce seed-driven individuality;
- introduce canonical TREE/BUSH/GRASS classes.

It adds a diagnostic-only read path:

~~~text
Workbench public read facade
        |
        v
VIS4.1 Descriptor V2
        |
        v
VIS4.2 DiagnosticMorphologyMapper
        |
        v
VIS4.2 DiagnosticMorphologyOverlay
        |
        v
diagnostic pixels only
~~~

## New durable surfaces

~~~text
scripts/labs/ecology/eco_evo7_vis4_2_diagnostic_morphology_mapper.gd
scripts/labs/ecology/eco_evo7_vis4_2_diagnostic_morphology_overlay.gd
scripts/labs/ecology/eco_evo7_vis4_2_diagnostic_morphology_viewer.gd

scenes/labs/ecology/eco_evo7_vis4_2_diagnostic_morphology_viewer.tscn

tests/ecology/eco_evo7_vis4_2_honest_diagnostic_morphology_acceptance.gd

RUN_ECO_EVO7_VIS4_2_TESTS.ps1
RUN_ECO_EVO7_VIS4_2_TESTS.sh

.github/workflows/evo7-vis4-2-honest-diagnostic-morphology.yml
~~~

## Source discipline

The mapper validates the complete sealed Descriptor V2 before mapping.

Generation zero remains potential/founder-only:

~~~text
Descriptor V2 founder source exists
VIS4.2 realized diagnostic snapshot = {}
~~~

VIS4.2 therefore never fabricates realized morphology before the LS3.4 phenotype pass.

Generation > 0 must be fully evidence-backed.

## Honest morphology mappings

### Height

~~~text
realized_height_m
    ->
diagnostic stem height
~~~

### Crown width

Critical VIS4.2 repair relative to old VIS2 presentation:

~~~text
realized_crown_radius_m
    ->
diagnostic crown radius
~~~

Forbidden:

~~~text
leaf_area_index_proxy
    ->
crown radius approximation
~~~

The VIS4.2 overlay contains no LAI-to-crown mapping.

### Crown density

~~~text
realized_crown_density
    ->
foliage cluster count
+
foliage alpha/density
~~~

### Branch silhouette

~~~text
realized apical_dominance
realized branch_probability
realized branch_angle_deg
realized branch_length_ratio
realized branching_depth
    ->
diagnostic branching silhouette
~~~

These values come only from Descriptor V2 realized_topology.

### Structural cue

~~~text
structural_investment
    ->
diagnostic stem width
~~~

### Leaf strategy cue

~~~text
leaf_conservative_strategy
    ->
diagnostic leaf-cluster size cue
~~~

This remains presentation-only and has no ecology feedback.

## Neutral color gate

VIS4.2 defaults to neutral color.

Purpose:

~~~text
same morphology differences
must remain visible
without lineage hue
~~~

Lineage color can be enabled as an optional diagnostic mode, but neutral/lineage color toggling cannot change:
- ecology state hash;
- Descriptor V2 source hash;
- diagnostic render/source hash;
- morphology shape signature.

## No individuality yet

VIS4.2 explicitly sets:

~~~text
seed_shape_jitter = false
~~~

The renderer does not read individual_seed fields.

Deterministic individuality remains VIS4.5 scope.

This preserves the distinction:

~~~text
VIS4.2 = source morphology fidelity
VIS4.5 = bounded deterministic individuality
~~~

## Diagnostic mapper identity

Mapper result binds:

~~~text
generation
source_adapter_hash
source_ecology_state_hash
source_morphology_evidence_hash
descriptor_count
render_hash
~~~

Each mapped descriptor preserves:

~~~text
record_id
cell_index
lineage_id

source_descriptor_hash
source_evidence_record_hash
source_growth_graph_hash

hereditary_individual_seed
development_individual_seed

realized morphology values
silhouette_hash
render_descriptor_hash
~~~

silhouette_hash is morphology-only and intentionally excludes lineage identity/color.

render_descriptor_hash binds silhouette to exact source descriptor/evidence/GrowthGraph seals.

## PLAY0 boundary

VIS4.2 does not modify primary PLAY0 morphology.

The acceptance source guard intentionally verifies that old PLAY0 still contains its current BoxMesh/SphereMesh path.

That is not a VIS4.2 defect.

Replacement happens later:

~~~text
VIS4.2 diagnostic truth
    ->
VIS4.3 PH5 bridge
    ->
VIS4.4 PLAY0.MORPH
~~~

## Focused acceptance

The focused test proves:

1. exact viewer identity and diagnostic-only contract;
2. generation-zero no-realized-evidence honesty;
3. generation-one exact Descriptor V2 binding;
4. expected 61 living plants remain 61 diagnostic descriptors;
5. all source morphology fields pass through exactly;
6. live generation exposes more than one morphology silhouette;
7. realized height monotonically changes visual height;
8. realized crown radius monotonically changes crown width;
9. realized crown density changes foliage density;
10. structural investment changes stem-width cue;
11. branch probability/depth changes branch count;
12. branch angle changes lateral silhouette;
13. branch length ratio changes branch reach;
14. apical dominance changes vertical crown silhouette;
15. leaf strategy changes leaf-size cue;
16. neutral color removes lineage hue without changing shape signature;
17. camera/selection/color presentation controls cannot mutate ecology;
18. tampered Descriptor V2 is rejected before mapping;
19. deterministic replay preserves ecology/evidence/Descriptor/render hashes;
20. no LAI-to-crown heuristic;
21. no biology implementation import/call;
22. no seed-driven shape randomness;
23. no mutation/persistence/network authority;
24. no canonical TREE/BUSH/GRASS classes.

## Regression runner

VIS4.2 runner includes:

~~~text
VIS4.1 R2 full predecessor runner
+
VIS3 presentation regression
+
VIS4.2 focused acceptance
~~~

Exact Godot requirement:

~~~text
4.7.1.stable.double.custom_build.a13da4feb
~~~

## Verification status

Implementation is not formally accepted until an exact-head Windows run proves:

~~~text
full VIS4.2 runner RC=0
VIS4.1 R2 regression GREEN
VIS3 regression GREEN
VIS4.2 focused GREEN
tracked worktree clean
exact double Godot
~~~

## Next after GREEN

~~~text
VIS4.3 — Live Phenotype -> PH5 Bridge
~~~

VIS4.3 may reconstruct presentation geometry through accepted PH5 surfaces, but still cannot create new ecology truth.


## Windows verification update

R1 exact subject:

~~~text
e74ffda554be177201542743f596b2c0bb272018
TREE a7090261af65b3f4a3313aa0c0275e18850f2435
~~~

received:

~~~text
VIS4.2 focused: FAIL (1263 assertions, 2 failures)
full runner: FAIL
RC=1
~~~

Finding:

~~~text
VIS4.2-WIN-001
generation-zero/fail-closed empty [] rejected by typed Array[Dictionary] renderer input
~~~

The morphology mappings, 61/61/61 source completeness, tamper checks and non-empty deterministic replay were otherwise GREEN.

This R1 candidate is not accepted.

Repair is tracked in:

~~~text
docs/checkpoints/2026-08-31_ECO_EVO7_VIS4_2_EMPTY_DESCRIPTOR_BOUNDARY_REPAIR_R2_RU.md
~~~

R2 exact runnable boundary:

~~~text
3ecee0f0fe491a6f76145eb8f2da133c820ae793
TREE 762806c32b43a1cc0740e7b5ab78be8e1cb108bd
~~~
