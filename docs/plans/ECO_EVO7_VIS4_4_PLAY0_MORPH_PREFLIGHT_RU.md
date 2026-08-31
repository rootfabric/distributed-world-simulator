# ECO.EVO7 VIS4.4 — PLAY0.MORPH Preflight

Дата: 2026-08-31
Статус: PREFLIGHT COMPLETE / VIS4.3 CLOSED / RUNTIME UNBLOCKED

## Current PLAY0 seam

Current completed-generation publication is:

~~~text
Workbench completed snapshot
 -> VIS2 adapter
 -> _published_descriptors
 -> Play0PlanetPresentation.apply_snapshot()
 -> BoxMesh stem MultiMesh
 -> SphereMesh crown MultiMesh
~~~

The correct VIS4.4 migration seam is the publication/presentation boundary, not the player, ecology worker, terrain, streaming or render-origin authority.

## Required VIS4.4 publication path

After VIS4.3 GREEN:

~~~text
completed Workbench snapshot
 + morphology evidence
 + graph reconstruction evidence
     |
     v
VIS4.1 Descriptor V2
     |
     v
VIS4.3 exact PH5 bridge
     |
     v
publish complete bridge snapshot atomically
     |
     v
PLAY0 presentation only
~~~

Partial generation data must never reach presentation.

Generation zero may keep the existing founder/sprout fallback because no realized PH2 morphology exists yet.

Generation > 0 must use PH5 geometry when the exact bridge is valid. Box/Sphere may not remain the primary live-plant path.

## Physical placement reuse

Current PLAY0 already has the correct world-placement source:

~~~text
cell direction
 -> ProceduralEarthWorld.get_surface_point(direction)
~~~

VIS4.4 must reuse it exactly.

Each PH5 plant local +Y axis is aligned to the physical surface up direction with the same _up_basis(up) semantics.

Presentation offset remains noncanonical; ecology cell position remains truth.

## Render-origin rule

Current PLAY0 caches world-space plant positions and reprojects them when render origin changes.

VIS4.4 must preserve this:

~~~text
GrowthGraph / RenderDescription / PH5 materialization
    cached by source hash + tier

render-origin change
    -> transform update only
    -> NO GrowthGraph rebuild
    -> NO phenotype rebuild
~~~

## PH5 node mapping

Near tiers:

~~~text
TIER_0_FULL / TIER_1_REDUCED
 -> MeshInstance3D(branch_mesh)
 -> MultiMeshInstance3D(foliage_multimesh)
~~~

Far tiers:

~~~text
TIER_2_CANOPY / TIER_3_IMPOSTOR
 -> accepted PH5 far_mesh/materialization
~~~

Population tier:

~~~text
TIER_4_POPULATION_ONLY
 -> no individual plant node
~~~

Do not generate a second branch mesh or foliage placement algorithm in PLAY0.

## LOD

VIS4.4 should use accepted PlantMultiscaleRepresentation tier semantics.

Initial integration may use a deterministic projected-height estimate plus select_tier/select_tier_hysteretic.

Cache key must include at least:

~~~text
record_id
source_growth_graph_hash
render_description_hash
tier
representation_hash
~~~

Camera movement may switch tier but must not change ecology/source identity.

## Materials and color

Geometry is source morphology. Color remains presentation-only.

Neutral-color mode from VIS4.2 should remain available so morphology differences are visible without lineage hue.

Lineage color can be optional.

Color/material changes must not change GrowthGraph, RenderDescription or geometry source hashes.

## Atomic fallback

For generation > 0:

~~~text
complete VIS4.3 bridge
 -> PH5 presentation

missing/incomplete/tampered bridge
 -> fail closed
 -> keep last completed presentation
 -> never silently fall back to heuristic live morphology
~~~

This preserves the existing PLAY0 completed-snapshot philosophy.

## Proposed acceptance gates

1. VIS4.3 exact double-Godot GREEN predecessor.
2. PLAY0 ecology/generation worker unchanged in authority.
3. Generation zero founder fallback remains honest.
4. Generation > 0 primary plants are PH5, not Box/Sphere.
5. At least one live TIER0/1 plant has real branch mesh and foliage MultiMesh.
6. Far live plants exercise TIER2/3 when camera/distance warrants.
7. TIER4 creates no individual node.
8. Every rendered plant binds record_id and source GrowthGraph hash.
9. RenderDescription source_graph_hash equals VIS4.3 source graph hash.
10. Geometry/materialization hash deterministic across replay.
11. Neutral-color mode preserves geometry hashes.
12. Render-origin shift changes transforms only.
13. Camera/LOD changes cannot mutate ecology state_hash.
14. Missing/tampered bridge fails closed without heuristic substitution.
15. Existing player walk/jump/spectator/return flow remains GREEN.
16. Existing collision refresh/recenter flow remains GREEN.
17. PLAY0 soak retains ecology/presentation hash consistency.
18. No new ecology/persistence/network authority.

## Runtime gate

VIS4.3 is CLOSED on exact Ubuntu double-Godot verification. VIS4.4 runtime implementation is authorized.

## VIS4.3 exact closure carrier

The former Windows-only closure requirement is retired for VIS4.3. The Windows workflow remains optional cross-platform regression evidence.

Frozen executable predecessor:

~~~text
VIS4.3 SUBJECT:
b8e8c2ffea260eea40ae3a451ec0c63d81028f76

EXPECTED TREE:
920454da5bb41959680e3309c690f4ef399f3e6d
~~~

The durable Windows closure carrier is:

~~~text
1d0c8cf9de23349f2a5df410e11da7e5c32af318
ci(eco): pin VIS4.3 closure to frozen subject
~~~

Its workflow checks out the frozen executable subject rather than the moving durable branch HEAD, verifies both exact HEAD and exact TREE, verifies Godot identity
`4.7.1.stable.double.custom_build.a13da4feb`, and only then runs
`RUN_ECO_EVO7_VIS4_3_TESTS.ps1`.

A documentation/closure-carrier commit after the executable subject is not acceptance evidence by itself. Canonical acceptance is provided by an exact double-Godot run against the frozen subject and expected tree; the recorded Ubuntu run satisfies that requirement.


## VIS4.3 Ubuntu exact pre-verification evidence

Exact Ubuntu pre-verification completed GREEN against the frozen executable predecessor.

~~~text
SUBJECT:
b8e8c2ffea260eea40ae3a451ec0c63d81028f76

TREE:
920454da5bb41959680e3309c690f4ef399f3e6d

GODOT:
4.7.1.stable.double.custom_build.a13da4feb

LINUX BINARY SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7

FRESH IMPORT:
PASS / exit 0

TRACKED STATUS AFTER TESTS:
clean
~~~

Canonical chain evidence:

~~~text
VIS4.2 predecessor                         PASS / 1265 assertions
PH5 render description                    PASS / 720 assertions
PH5-S2 3D materialization                 PASS / 387 assertions
PH5-S3 multiscale policy                  PASS / 49 assertions
PH5-S3 multiscale materialization         PASS / 61 assertions
PH5-S4 representation robustness          PASS / 5026 assertions
PH5-S4 phenotype x tier matrix            PASS / 430 assertions
VIS4.3 exact Live Phenotype -> PH5 bridge PASS / 752 assertions
canonical VIS4.3 PASS marker              PRESENT
~~~

Fresh import also reproduced three legacy pre-existing ECO.EVO5 scene parse warnings
(`eco_evo5_probe2_tree_lab.tscn`, `eco_evo5_t51_creature_lab.tscn`,
`eco_evo5_terrain_fly_lab.tscn`: `Parse Error: Expected '['.`). Import still
returned exit 0 and no VIS4.3-related warning was reported. These warnings do not
promote or weaken VIS4.3 acceptance.

Qualification:

~~~text
EXACT UBUNTU DOUBLE-GODOT GREEN
EXACT SUBJECT VERIFIED
EXACT TREE VERIFIED
DOUBLE GODOT VERIFIED
CANONICAL VIS4.3 TEST CHAIN GREEN
TRACKED STATUS CLEAN
VIS4.3 CLOSED
VIS4.4 RUNTIME UNBLOCKED
~~~

VIS4.3 contains no platform-specific runtime branches, native extensions,
OS-specific APIs or path-dependent computation in its bridge/PH5 acceptance
scope. Windows execution is therefore optional cross-platform regression
coverage, not a required acceptance gate for this checkpoint.
