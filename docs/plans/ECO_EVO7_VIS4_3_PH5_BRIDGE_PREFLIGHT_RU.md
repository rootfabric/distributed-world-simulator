# ECO.EVO7 VIS4.3 — PH5 Bridge Preflight / Exact Reconstruction Gap

Дата: 2026-08-31  
Статус: PREFLIGHT COMPLETE / IMPLEMENTATION BLOCKED UNTIL VIS4.2 GREEN  
Ветка: feature/eco-evo7-vis4-evolved-plant-morphology-r1

## Purpose

До начала VIS4.3 проверено, можно ли построить exact PH5 bridge только из VIS4.1 Descriptor V2.

Ответ:

~~~text
NO — current Descriptor V2 is sufficient for honest diagnostic morphology,
but insufficient for byte-exact GrowthGraph reconstruction.
~~~

Это не дефект VIS4.2. VIS4.2 не обязан materialize PH5 geometry.

## Why Descriptor V2 is not enough

Descriptor V2 preserves:

~~~text
development_individual_seed
realized_topology numeric fields
source_growth_graph_hash
source_evidence_record_hash
~~~

Но exact PlantDevelopmentTraits v1 checksum вычисляется из:

~~~text
schema
version
traits_id
max_height_m
internode_length_m
apical_dominance
branch_probability
branch_angle_deg
branch_length_ratio
branching_depth
crown_spread_m
~~~

Current Descriptor V2 exposes numeric realized topology, but does NOT expose exact realized traits_id.

PlantGrowthGraphSkeleton.build(...) requires a validated PlantDevelopmentTraits dictionary.

Its graph hash includes:

~~~text
individual_seed
development_traits_checksum
all generated segments
~~~

Therefore:

~~~text
numeric traits
+
development seed
+
source graph hash
~~~

is NOT sufficient to reconstruct a validated traits dictionary with the same checksum, because traits_id participates in that checksum.

Inventing a new traits_id would create:

~~~text
different traits checksum
-> different GrowthGraph graph_hash
~~~

even if all visible numeric values were identical.

## Forbidden shortcuts

VIS4.3 must NOT:

1. invent a synthetic traits_id and ignore graph-hash mismatch;
2. copy the GrowthGraphSkeleton algorithm into a presentation bridge;
3. rerun EnvironmentCoupledDevelopment;
4. rerun FunctionalPhenotype;
5. accept approximate geometry while claiming source_growth_graph_hash fidelity;
6. create a second procedural tree renderer.

Any of these would violate the VIS4 source-truth contract.

## Recommended VIS4.3 source extension

Do NOT reopen accepted VIS4.1 MorphologyEvidence R2 unless required.

Preferred additive solution:

~~~text
VIS4.3 GrowthGraph Reconstruction Evidence
~~~

A separate derived/presentation-only sidecar produced from the SAME already-computed LS3.4 PH2 package.

Per living record it should preserve:

~~~text
record_id
cell_index
bundle_checksum

development_individual_seed

realized_development_traits
    schema
    version
    traits_id
    all realized topology fields
    checksum

source_realized_traits_hash
source_growth_graph_hash

reconstruction_evidence_hash
~~~

The sidecar must be:
- derived_representation=true;
- presentation_only=true;
- non-causal;
- absent from ecology state_hash/evaluation_hash;
- complete against postcompetition survivor count;
- source-bound to the same generation/population/competition seals as VIS4.1.

## Exact bridge algorithm

VIS4.3 can then do:

~~~text
validated Reconstruction Evidence
        |
        v
PlantDevelopmentTraits.validate(realized_traits)
        |
        +-- realized_traits.checksum
        |   == source_realized_traits_hash
        |
        v
PlantGrowthGraphSkeleton.build(
    realized_traits,
    development_individual_seed
)
        |
        +-- reconstructed graph_hash
        |   == source_growth_graph_hash
        |
        v
PlantRenderDescription.build(exact_graph)
        |
        v
PlantMultiscaleRepresentation / PH5
~~~

This reuses the accepted PH5 graph generator rather than copying it.

The GrowthGraph build here is deterministic geometry reconstruction, not biology recomputation, because all environment-plasticity decisions have already been frozen in exact realized_development_traits.

## Render-description gap after exact graph reconstruction

Accepted PlantRenderDescription v1 currently uses:
- fixed branch base radii;
- fixed foliage anchors/count per segment;
- foliage sizes derived from graph hash.

It does not consume:
- structural_investment;
- realized_crown_density;
- leaf_conservative_strategy.

Therefore VIS4.3 should first prove exact topology/PH5 reconstruction.

A later thin presentation envelope may carry these source-bound morphology scalars into PLAY0 materialization without changing ecology or the accepted GrowthGraph.

Do not silently mutate the meaning of the accepted PH5 graph.

## VIS4.3 proposed gates

Before VIS4.3 can close:

1. reconstruction evidence generated from already-computed PH2 only;
2. evidence failure cannot abort ecology;
3. exact survivor completeness;
4. exact realized traits checksum;
5. exact reconstructed GrowthGraph hash;
6. exact deterministic restart/replay graph hash;
7. PlantRenderDescription source_graph_hash equals VIS4.1 source_growth_graph_hash;
8. no copied GrowthGraph algorithm;
9. no CoupledDevelopment/FunctionalPhenotype call in bridge;
10. accepted PH5 RenderDescription/Multiscale stack reused;
11. renderer/materializer remains downstream-only;
12. VIS4.2 and VIS4.1 regressions GREEN.

## Execution gate

~~~text
VIS4.2 exact Windows GREEN
        |
        v
VIS4.3 reconstruction evidence + PH5 bridge implementation
~~~

Until VIS4.2 GREEN this document is design evidence only; VIS4.3 runtime code must not start.
