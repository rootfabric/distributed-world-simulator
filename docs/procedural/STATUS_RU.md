# Universal World Generation Fabric — status ledger

**Program foundation:** G0–G3 Procedural Planetary Generation
**Post-G3 roadmap:** `docs/universal-world-generation-roadmap-post-g3`
**Current implementation branch:** `feature/g6-hydrology-fluid-surface-v0`

## Current state

```text
G0 Contracts Freeze                    ACCEPTED
G1 Geodesy + Body Shape                BASELINE
G2 Planetary Surface Cells + LOD       ACCEPTED
G3 Mega Casual Macro Surface           ACCEPTED
G4 Provider Composition / Replacement  ACCEPTED
G5 World Feature Graph                 ACCEPTED
G6.0 Fluid Contracts                   IMPLEMENTED CANDIDATE
G6.1 Casual River Provider             NEXT — BLOCKED ON G6.0 FOCUSED ACCEPTANCE
```

G6.0 base:

```text
feature/g5-world-feature-graph
e7b10c09a6be879b25cd5c7ec8407832fd758ac2
```

Accepted G5 candidate head:

```text
34be9d35e7f0a0e6c7a7c7c8bdd58b70c95413b4
```

Canonical acceptance / candidate records:

```text
docs/checkpoints/G4_PROVIDER_COMPOSITION_REPLACEMENT_ACCEPTED_RU.md
docs/checkpoints/G5_WORLD_FEATURE_GRAPH_ACCEPTED_RU.md
docs/checkpoints/G6_0_FLUID_CONTRACTS_CANDIDATE_RU.md
```

## Universal architecture

```text
new world
  != new engine special-case

new world
  = recipe + providers + features + environment + detail backends
```

Canonical post-G3 documents:

```text
docs/plans/UNIVERSAL_WORLD_GENERATION_EXECUTION_PLAN_RU.md
docs/plans/UNIVERSAL_WORLD_GENERATION_ROADMAP_RU.md
docs/procedural/NEXT_AFTER_G3_UNIVERSAL_WORLD_GENERATION_RU.md
```

## G4 accepted composition foundation

```text
PlanetRecipe
  -> GeoRecipeComposer
  -> GeoProviderRegistry
  -> GeoKernel
```

Replacement remains recipe-driven and the final semantic surface caller remains:

```text
geo/surface-height-m
```

G4 Architecture Review A: `PASS`.

## G5 accepted World Feature Graph

Canonical feature vocabulary:

```text
FeatureType
FeatureId
FeatureBounds
FeatureAnchor
FeatureRelation
FeatureQuery
WorldFeature
FeatureGraph
```

Identity:

```text
FeatureId = hash(
  body_id,
  feature_type,
  seed,
  generator_version,
  stable_key
)
```

Representation state is deliberately excluded:

```text
NO SurfaceCellKey
NO LOD
NO face/x/y
NO camera
NO renderer
NO query-order dependency
```

Feature graph supports surface, subsurface and free-space semantics. Acceptance fixtures include:

```text
fault
valley
river
cave system
floating island
```

Spatial query v0 uses correctness-first broad phase:

```text
SPHERE
AABB
```

The current graph scan is O(N). A future BVH/octree/spatial index may optimize lookup without changing canonical feature identity or query semantics.

## Critical G5 gate

The seam fault crosses the G2 cube-sphere `PX/PZ` boundary and is addressed at:

```text
LOD 2
LOD 4
LOD 8
LOD 12
```

At every LOD:

```text
multiple SurfaceCellKey addresses  PASS
both PX and PZ faces               PASS
representation cell set changes    PASS
canonical FeatureId unchanged      PASS
graph manifest unchanged           PASS
```

Therefore:

```text
Feature != Cell
LOD != Feature Identity
```

## G5 acceptance evidence

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
cold editor import                 PASS
G5 World Feature Graph             PASS — 249 assertions
G5 feature/cell identity           PASS — 94 assertions
G5 visual lab headless             PASS — 4 features
full world/core regression         PASS
Breakpoint :9081 collision noise   0
git diff hygiene/freeze            PASS
G5 full acceptance gate            PASS
```

Expected/known regression output did not block acceptance:

```text
manifest identity mismatch negative paths   suites PASS
NX5 rejection warnings                      suite PASS
MW7 ObjectDB/ResourceCache exit warnings    existing debt
```

Lab:

```text
res://scenes/labs/procedural/g5_world_feature_graph_lab.tscn
```

## G6.0 Fluid Contracts candidate

Canonical fluid vocabulary now exists as contracts:

```text
FluidType
FluidRegionId
FluidSurfaceDescriptor
RiverSpline
RiverChannelProfile
WaterSurfaceQuery
```

`FluidRegionId` is derived from:

```text
body_id
fluid_type_id
seed
generator_version
stable_key
```

and deliberately excludes representation state.

The contracts are generic enough to represent water, lava, methane, ammonia and future fluids. River-specific geometry is expressed as stable `RiverSpline` and `RiverChannelProfile` descriptors while runtime provider generation remains deferred.

Focused validation command:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_FLUID_CONTRACT_TESTS.ps1
```

Runtime evidence is pending because the connector environment has no Godot binary.

## Next

Blocking main track:

```text
G6.0 focused acceptance
  -> G6.1 CasualRiverProviderV1
  -> G6.2 cross-cell/cross-LOD continuity
  -> G6.3 runtime WaterSurfaceQuery
  -> G6.4 casual visual river lab
  -> G6 full acceptance
  -> G7 Semantic Field Fabric
```

G6.1 must produce canonical fluid descriptors from stable G5 feature semantics rather than chunk-local identities.

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
FluidRegion != SurfaceCell
FluidRegion != renderer object
recipe != planet class
provider graph != world-type switch
canonical truth != representation
procedural baseline + sparse authoritative mutations = current world truth
```
