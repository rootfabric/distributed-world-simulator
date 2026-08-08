# Universal World Generation Fabric — status ledger

**Program foundation:** G0–G3 Procedural Planetary Generation  
**Post-G3 roadmap:** `docs/universal-world-generation-roadmap-post-g3`  
**Current implementation branch:** `feature/g6-hydrology-fluid-surface`

## Current state

```text
G0 Contracts Freeze                    ACCEPTED
G1 Geodesy + Body Shape                BASELINE
G2 Planetary Surface Cells + LOD       ACCEPTED
G3 Mega Casual Macro Surface           ACCEPTED
G4 Provider Composition / Replacement  ACCEPTED
G5 World Feature Graph                 ACCEPTED
G6 Hydrology / Fluid Surface v0        IMPLEMENTED CANDIDATE
G7 Semantic Field Fabric               BLOCKED BY G6 ACCEPTANCE
```

G6 base:

```text
feature/g5-world-feature-graph
e7b10c09a6be879b25cd5c7ec8407832fd758ac2
```

G6 implementation candidate:

```text
68dc5158347989c6d16564993144106d2a294516
```

Canonical records:

```text
docs/checkpoints/G4_PROVIDER_COMPOSITION_REPLACEMENT_ACCEPTED_RU.md
docs/checkpoints/G5_WORLD_FEATURE_GRAPH_ACCEPTED_RU.md
docs/checkpoints/G6_HYDROLOGY_FLUID_SURFACE_CANDIDATE_RU.md
```

## Universal architecture

```text
new world
  != new engine special-case

new world
  = recipe + providers + features + fluids/environment + detail backends
```

Canonical post-G3 documents:

```text
docs/plans/UNIVERSAL_WORLD_GENERATION_EXECUTION_PLAN_RU.md
docs/plans/UNIVERSAL_WORLD_GENERATION_ROADMAP_RU.md
docs/procedural/NEXT_AFTER_G3_UNIVERSAL_WORLD_GENERATION_RU.md
```

## Accepted foundation through G5

G4 established recipe-driven provider composition:

```text
PlanetRecipe
  -> GeoRecipeComposer
  -> GeoProviderRegistry
  -> GeoKernel
```

Replacement remains recipe-driven and G4 Architecture Review A is `PASS`.

G5 established canonical spatial feature identity:

```text
WorldFeature
FeatureId
FeatureType
FeatureBounds
FeatureAnchor
FeatureRelation
FeatureQuery
FeatureGraph
```

Identity deliberately excludes:

```text
SurfaceCellKey
LOD
face/x/y
camera
renderer
query order
```

The accepted G5 seam gate proves one feature can cross multiple cube-sphere cells/faces at LOD 2/4/8/12 while retaining one canonical identity and graph manifest.

## G6 implemented hydrology / fluid geography

G6 adds:

```text
FluidRegionId
FluidSurfaceDescriptor
RiverSpline
RiverChannelProfile
WaterSurfaceQuery
WaterSurfaceSample
RiverFeature
CasualRiverProviderV1
```

Core invariant:

```text
River != Cell
River != LOD
FluidRegion != renderer artifact
```

`FluidRegionId` derives from:

```text
body_id
fluid_type_id
seed
generator_version
stable_key
```

Generic fluid descriptor already supports non-water identity and surface modes, so future worlds do not require hardcoded `OCEAN_PLANET`, `LAVA_PLANET`, etc.

v0 surface modes:

```text
fluid-surface-mode/local-spline
fluid-surface-mode/constant-level
fluid-surface-mode/free-surface
```

`CasualRiverProviderV1` creates a G5 `WorldFeature` of type river and answers canonical water-surface queries. Query inputs contain body/frame/position/range/optional region filter — no representation cell or LOD.

Returned sample includes:

```text
feature_id
fluid_region_id
surface_position
surface_normal
flow_vector
channel width/depth
distance to centerline
normalized source-to-mouth distance
inside_channel
```

G6 remains deliberately below G7 Semantic Field Fabric: it does not yet publish `hydro/*` fields into a generic semantic field namespace.

## Critical G6 seam / LOD gate

Mega Casual River fixture:

```text
body radius                6,000,000 m
control points             9
longitude                  34° -> 58°
length                     > 1,000 km
cube-sphere seam           PX/PZ
channel width              60 -> 180 m
channel depth              3 -> 9 m
flow                       1.2 -> 2.4 m/s
```

At LOD 2/4/8/12:

```text
multiple representation cells      PASS
PX/PZ seam crossing                PASS
representation cell set changes    PASS
River FeatureId unchanged          PASS
FluidRegionId unchanged            PASS
provider manifest unchanged        PASS
canonical query excludes cell/LOD  PASS
```

Therefore:

```text
representation address changes
canonical hydrology does not
```

## Numerical query decision

Nearest-point search for spherical river arcs uses a deterministic fixed search:

```text
SPHERICAL_COARSE_STEPS      24
SPHERICAL_REFINEMENT_STEPS  24
```

The refinement was increased during acceptance because 8 iterations were insufficient for a 10 m query tolerance on mega-scale arcs. This affects query precision only, not identity.

## Architecture boundary

Canonical G6 hydrology source is tested to exclude:

```text
SurfaceCellKey
SurfaceLodSelector
MeshInstance3D
ImmediateMesh
Camera3D
RenderingServer
RandomNumberGenerator
randf / randi
EARTH / MOON / OCEAN_PLANET special cases
```

Renderer code exists only in the G6 visual lab.

`RUN_G6_FULL_ACCEPTANCE.ps1` also freezes G0–G5 procedural architecture and rejects G6 changes under production world/runtime/network/Matter paths.

## Exact-engine candidate evidence

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
cold editor import                         PASS
G6 hydrology/fluid surface                PASS — 161 assertions
G6 river/cell LOD identity                PASS — 72 assertions
G6 visual lab headless                    PASS
G5 World Feature Graph regression         PASS — 249 assertions
G5 feature/cell identity regression       PASS — 94 assertions
G5 visual lab regression                  PASS — 4 features
G6 focused Linux wrapper                  PASS
```

Implementation publication was byte-checked against the tested local harness for core/query/LOD/runner/lab files.

Full Windows acceptance is still pending:

```powershell
.\RUN_G6_FULL_ACCEPTANCE.ps1
```

Until that passes, status remains `IMPLEMENTED CANDIDATE`.

Lab:

```text
res://scenes/labs/procedural/g6_hydrology_fluid_surface_lab.tscn
```

## Next

After G6 acceptance:

```text
G7 — Semantic Field Fabric
```

G7 is where consumers should begin requesting generic causal fields such as:

```text
hydro/river-distance-m
hydro/water-level-m
hydro/moisture
hydro/drainage
```

without knowing the concrete hydrology provider.

Parallel tracks remain available under the post-G3 roadmap:

```text
GR0 — Surface Representation Lab
GE0 — Environment Field Contracts
```

## Invariants

```text
Generator != Renderer
LOD != World State
Feature != Chunk
Feature != SurfaceCell
River != Cell
FluidRegion != Renderer
recipe != planet class
provider graph != world-type switch
canonical truth != representation
procedural baseline + sparse authoritative mutations = current world truth
```
