# ECO.EVO7 VIS4 — Evolved Plant Morphology Planning Checkpoint R1

Дата: 2026-08-30  
Статус: PLANNED / NO IMPLEMENTATION EVIDENCE / NO ACCEPTANCE CLAIM

## Identity

Branch:

~~~text
feature/eco-evo7-vis4-evolved-plant-morphology-r1
~~~

Exact predecessor:

~~~text
PAR3 R3.2
8ca0fcc65752c3b748c793deb3b4a9f9ca4f17bf
~~~

Parallel sibling at planning time:

~~~text
feature/eco-evo7-stream1-bounded-generation-stream-r1
HEAD e0d2cda22a431c69a1b3eb4c650d79627d8aea40
~~~

VIS4 intentionally branches from PAR3 R3.2 rather than STREAM1. STREAM1 and VIS4 may proceed independently and converge only after independent acceptance.

## Verified repository facts

### PLAY0 is the immediate visual bottleneck

The live planetary PLAY0 runtime is already Node3D over the real ProceduralEarthWorld and the accepted LS3.6 Workbench.

Its current ecology presentation is:

~~~text
scripts/labs/ecology/eco_evo7_play0_planet_presentation.gd
~~~

Near-plant geometry is currently:

~~~text
BoxMesh stem
SphereMesh crown
~~~

The stem height uses realized_height_m.

The current PLAY0 crown radius is an LAI-derived presentation heuristic, not the accepted realized_crown_radius_m.

Therefore the user-visible similarity of plants is primarily a presentation limitation, not proof that EVO7 lacks morphology.

### VIS2 adapter exposes only a subset

Current VIS2 phenotype descriptor includes height, LAI, roots, water/light/resource evidence and lineage information, but does not expose the full crown/branch/structural morphology required by PH5 presentation.

VIS4 requires a versioned/additive morphology read model rather than biology changes.

### PH5 already contains the renderer foundation

Accepted ECO.PH5 provides:

~~~text
GrowthGraph
PlantRenderDescription
RendererProfile
tapered branch ArrayMesh
foliage MultiMesh
canopy
impostor
five-tier representation
~~~

The accepted PH5 core is a capability donor and must be reused rather than reopened or duplicated.

### Individual deterministic geometry already has a valid basis

plant_growth_graph_skeleton_v1.gd derives branch arrangement from individual_seed while keeping morphology bounded by DevelopmentTraits.

This is the intended mechanism for same-phenotype individual variation.

### The grid issue is separate

VIS2 already applies deterministic presentation jitter in 2D.

The live ecology remains a 32x32 Spatial Cohort Lattice. Therefore:

~~~text
presentation scatter != ecological continuous position
~~~

VIS4 may improve only the presentation side. True individual continuous positions belong to a separate future ECO.SPATIAL1 checkpoint.

## Architectural decisions

1. No canonical TREE/BUSH/GRASS identity is introduced.
2. Continuous morphology space is preserved.
3. Renderer is a one-way consumer of accepted ecology evidence.
4. Renderer ON/OFF must preserve ecology_state_hash.
5. LOD is disposable representation, not plant identity.
6. PH5 is reused as the procedural branch/foliage materialization stack.
7. Realized crown dimensions replace PLAY0 LAI-only crown-width heuristics.
8. individual_seed controls bounded deterministic individuality only.
9. Neutral-color mode is required to prove geometry rather than lineage color.
10. Live diversity and renderer fidelity are separate acceptance dimensions.
11. If live diversity is weak, report LIVE_DIVERSITY_INSUFFICIENT; do not fake diversity.
12. STREAM1 partial work is never a presentation source; VIS4 consumes only fully published generation snapshots.

## Planned implementation sequence

~~~text
VIS4.0 Truth / Contract Audit
  ->
VIS4.1 Morphology Descriptor V2
  ->
VIS4.2 Honest diagnostic morphology
  ->
VIS4.3 Live phenotype -> PH5 bridge
  ->
VIS4.4 PLAY0.MORPH 3D materialization
  ->
VIS4.5 Deterministic individuality
  ->
VIS4.6 Spatial presentation boundary
  ->
VIS4.7 Morphology Inspector
  ->
VIS4.8 Diversity evidence
  ->
VIS4.9 Performance / LOD
  ->
exact double-Godot + graphical acceptance
~~~

## PLAY0.MORPH user milestone

The first strong visible milestone is reached when a user can:

- open the live planet;
- walk or fly to ecology plants;
- see materially different branch/crown silhouettes;
- disable lineage color and still distinguish forms;
- select an unusual plant;
- inspect the actual morphology traits that produced its appearance;
- advance evolution and observe source-bound morphology changes;
- move camera distance and see PH5 LOD transitions without ecology changes.

## Deferred checkpoints

### MORPH1 — Expanded Heritable Architecture

Only after VIS4 shows what current biology already contains.

Candidate future freely evolving axes:

~~~text
internode_length_m
branch_probability
branch_angle_deg
branch_length_ratio
branching_depth
~~~

MORPH1 requires explicit costs/trade-offs and the existing single mutation authority.

### ECO.SPATIAL1 — Continuous Individual Plant Position

Separate future ecology/spatial work. It may eventually make exact plant position continuous and ecologically meaningful. VIS4 presentation jitter must not pre-empt this contract.

## Documentation owner

Detailed branch-local implementation roadmap:

~~~text
docs/plans/ECO_EVO7_VIS4_EVOLVED_PLANT_MORPHOLOGY_IMPLEMENTATION_PLAN_RU.md
~~~

This checkpoint records the planning decision only. It does not claim implementation, tests, Windows verification, graphical acceptance or merge readiness.

## Next authorized work

~~~text
VIS4.0 — Truth / Contract Audit
~~~

No biology modification is authorized by this planning checkpoint.
