# ECO.EVO7 VIS4.3 — Exact Live Phenotype -> PH5 Bridge R1

Дата: 2026-08-31
Статус: IMPLEMENTED CANDIDATE / EXACT WINDOWS VERIFICATION REQUIRED
Ветка: feature/eco-evo7-vis4-evolved-plant-morphology-r1

## Accepted predecessor

VIS4.2 R2 exact-tested boundary:

~~~text
HEAD: 3ecee0f0fe491a6f76145eb8f2da133c820ae793
TREE: 762806c32b43a1cc0740e7b5ab78be8e1cb108bd
VIS4.2 R2: ACCEPTED / WINDOWS VERIFIED / CLOSED
~~~

## Exact VIS4.3 runnable candidate

~~~text
HEAD: 67503a833822154e200c8113ab0e9f99a366aca0
TREE: f6fee460bf2239408809f35a931fd78326dc5f17
~~~

## Architecture

VIS4.3 adds a separate reconstruction-evidence sidecar produced from the SAME LS3.4 PH2 pass.

~~~text
PH2 already computed
  +-> VIS4.1 morphology evidence
  +-> VIS4.3 exact reconstruction evidence
          |
          v
exact realized DevelopmentTraits + development seed
          |
          v
accepted PlantGrowthGraphSkeleton.build()
          |
          +-> reconstructed graph_hash MUST equal source PH2 graph_hash
          |
          v
accepted PlantRenderDescription
          |
          v
accepted PH5 multiscale representation/materializer
~~~

New source contract:

~~~text
scripts/research/ecology/plant_growth_graph_reconstruction_evidence_v1.gd
~~~

It preserves exact realized traits including traits_id and checksum, plus development_individual_seed and source_growth_graph_hash.

New bridge:

~~~text
scripts/labs/ecology/eco_evo7_vis4_3_exact_ph5_bridge.gd
~~~

The bridge rejects every record unless reconstructed_graph_hash equals the source GrowthGraph seal.

## Non-causal integration

LS3.4 still contains one CoupledDevelopment.realize call and one FunctionalPhenotype.compile call.
Reconstruction evidence is packaged from the already-computed PH2 object and cannot abort ecology generation.
Neither ecology snapshot schema nor ecology state_hash is extended.

Workbench exposes only read-only get/validate methods for the new sidecar.

## PH5 reuse

VIS4.3 reuses:

~~~text
PlantDevelopmentTraits
PlantGrowthGraphSkeleton
PlantRenderDescription
PlantMultiscaleRepresentation
PlantMultiscaleMaterializer
~~~

No GrowthGraph algorithm is copied into the bridge.
No CoupledDevelopment / FunctionalPhenotype / ResourceModel call exists in the bridge.

## Acceptance

Focused acceptance requires generation-one 61/61 exact reconstruction and verifies:

~~~text
realized traits checksum exact
traits_id exact
development seed exact
source GrowthGraph seal exact
reconstructed GrowthGraph hash == source GrowthGraph hash
PH5 RenderDescription hash present
PH5 representation hash present
~~~

One live survivor is also materialized through all tiers:

~~~text
TIER_0_FULL
TIER_1_REDUCED
TIER_2_CANOPY
TIER_3_IMPOSTOR
TIER_4_POPULATION_ONLY
~~~

Each tier must preserve ecological_truth_hash == source_growth_graph_hash.

Tamper gates include:

~~~text
stale realized traits -> reject
rehashed traits_id -> evidence internally valid, bridge rejects by graph hash mismatch
rehashed development seed -> evidence internally valid, bridge rejects
~~~

Deterministic replay must keep ecology state hash, reconstruction evidence hash, Descriptor V2 hash and VIS4.3 bridge hash identical.

## Runner

RUN_ECO_EVO7_VIS4_3_TESTS.ps1 / .sh run:

~~~text
VIS4.2 R2 full predecessor chain
PH5 render/materialization regression
PH5-S2 3D materialization
PH5-S3 multiscale policy/materialization
PH5-S4 robustness and phenotype x tier matrix
VIS4.3 focused acceptance
~~~

Exact Godot:

~~~text
4.7.1.stable.double.custom_build.a13da4feb
~~~

## Formal status

VIS4.3 is NOT ACCEPTED until fresh exact Windows GREEN on:

~~~text
67503a833822154e200c8113ab0e9f99a366aca0
TREE f6fee460bf2239408809f35a931fd78326dc5f17
~~~

## Next after GREEN

VIS4.4 — PLAY0.MORPH