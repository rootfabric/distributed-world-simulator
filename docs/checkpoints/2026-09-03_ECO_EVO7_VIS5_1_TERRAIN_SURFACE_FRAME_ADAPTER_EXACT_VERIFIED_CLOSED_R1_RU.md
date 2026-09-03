# ECO.EVO7 VIS5.1 — Terrain Surface Frame Adapter Exact Verified Closed R1

Дата: 2026-09-03  
Статус: ACCEPTED / EXACT DOUBLE-GODOT GREEN / CLOSED  
Branch: feature/eco-evo7-vis5-terrain-ecosystem-composition-r1

## Exact executable subject

~~~text
HEAD:
25ead34b89453a3e61a0b9b0ef48928bc73c6ea3

TREE:
e6f42c6fbc351a9fbf30f53b8a5336445a74ae59
~~~

The exact source was exported through a validation-only GitHub-hosted source-export carrier:

~~~text
branch:
validation/eco-vis5-1-source-export-r1

workflow:
VIS5.1 Exact Source Export R1

run:
33726361101

result:
SUCCESS
~~~

The workflow asserted the exact target HEAD/TREE before creating the immutable archive.

Local reconstruction reproduced the canonical tree exactly:

~~~text
reconstructed TREE:
e6f42c6fbc351a9fbf30f53b8a5336445a74ae59

TREE match:
YES
~~~

## Canonical Godot

Project-attached Linux double-Godot:

~~~text
4.7.1.stable.double.custom_build.a13da4feb

SHA-256:
bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7
~~~

## Full canonical regression

Executed:

~~~text
RUN_ECO_EVO7_VIS5_1_TESTS.sh
~~~

Final result:

~~~text
RC=0
~~~

Key predecessor evidence:

~~~text
FFF2 Morphology Evolution:
PASS / 56 assertions

PH2 Environment-Coupled Development:
PASS / 107 assertions

VIS4.0 Truth / Contract Audit:
PASS / 176 assertions

LS3.4 Local Competition:
PASS / 45 assertions

LS3.6 Rule Workbench:
PASS / 114 assertions

VIS4.1 Source-Bound Morphology Evidence R2:
PASS / 598 assertions

VIS1:
PASS / 41 assertions

VIS2:
PASS / 69 assertions

VIS3:
PASS / 107 assertions

VIS4.2 Honest Diagnostic Morphology:
PASS / 1265 assertions

PH5 core:
PASS / 720 assertions

PH5-S2:
PASS / 387 assertions

PH5-S3:
PASS / 49 assertions

PH5-S3 materialization:
PASS / 61 assertions

PH5-S4 robustness:
PASS / 5026 assertions

PH5-S4 phenotype x tier matrix:
PASS / 430 assertions

VIS4.3 Exact PH5 Bridge:
PASS / 752 assertions

PLAY0:
PASS / 103 assertions

VIS4.4 PLAY0.MORPH:
PASS / 74 assertions

VIS4.5 Deterministic Individuality:
PASS / 491 assertions

VIS4.6 Grid Appearance Boundary:
PASS / 796 assertions

VIS4.7 Morphology Inspector:
PASS / 106 assertions

VIS4.8 Diversity Evidence:
PASS / 106 assertions

VIS4.8 renderer fidelity:
PASS

VIS4.8 live diversity:
LIVE_DIVERSITY_SUFFICIENT

VIS4.9 Performance / LOD:
PASS / 116 assertions

VIS5.0 Terrain / Ecosystem Composition Contract:
PASS / 87 assertions

VIS5.1 Terrain Surface Frame Adapter:
PASS / 70 assertions
~~~

Observed VIS4.9 diagnostics during this exact run:

~~~text
cache hit rate:
0.282

cost units:
12280

observational frame ms:
7.484
~~~

These remain observational diagnostics and are not portable acceptance thresholds.

Final marker:

~~~text
ECO.EVO7 VIS5.1 Terrain Surface Frame Adapter candidate: PASS
~~~

## Post-run integrity

The extracted exact source was indexed locally before runtime.

After the complete runner:

~~~text
tracked content diff:
CLEAN

reconstructed TREE:
e6f42c6fbc351a9fbf30f53b8a5336445a74ae59

TREE unchanged:
YES
~~~

Runtime log SHA-256:

~~~text
2da85205e76cdfcc496c9521e2439fbe0c42f982729d69c08904668a2d7daed1
~~~

## VIS5.1 accepted boundary

VIS5.1 now provides a read-only separation between:

~~~text
radial_basis
= gravity / planet-radial orientation
= accepted macro-plant semantics

terrain_basis
= derived geometric surface-normal frame
= future ground-cover / rock presentation
~~~

The adapter consumes only:

~~~text
ProceduralEarthWorld.get_planet_radius()
ProceduralEarthWorld.get_surface_point()
ProceduralEarthWorld.get_surface_state()
~~~

and does not change:

~~~text
canonical ecology position
Descriptor V2
GrowthGraph
biology
population
mutation
generation authority
PERF2.4
~~~

## Project Control note

Project Control run:

~~~text
33725450042
conclusion:
FAILURE
~~~

The failure is in the global architecture/ownership compatibility regression, not in VIS5 runtime or source validation.

Reported global findings include:

~~~text
G:
CRITICAL_DEPENDENCY_DRIFT

ECO:
CRITICAL_DEPENDENCY_DRIFT

affected dependency examples:
scripts/simulation/matter/generation/moon_geology_sampler.gd
scripts/simulation/matter/generation/moon_surface_feature_catalog.gd
scripts/simulation/matter/mutation/matter_excavation_service.gd
scripts/simulation/matter/query/matter_continuous_query_service.gd
scripts/simulation/matter/storage/matter_brick_materializer.gd
config/control/project-program-registry.v1.json
network ownership dependencies
~~~

The complete VIS5 branch delta from the closed VIS4 base contains only VIS5 workflow/runners/config/docs/adapter/tests and does not modify any of the reported critical-drift files.

Therefore this Project Control result is recorded as:

~~~text
INHERITED GLOBAL OWNERSHIP/PASSPORT DRIFT
NOT A VIS5.1 RUNTIME OR SOURCE FINDING
~~~

It should be repaired in the control-plane ownership/passport line, but it does not invalidate the exact VIS5.1 runtime evidence.

## Formal verdict

~~~text
VIS5.1
ACCEPTED
EXACT DOUBLE-GODOT GREEN
CLOSED

VIS5 runtime required_fixes:
[]
~~~

Next visual checkpoint:

~~~text
VIS5.2 — Noncanonical Ground-Cover Presentation Bridge
~~~
