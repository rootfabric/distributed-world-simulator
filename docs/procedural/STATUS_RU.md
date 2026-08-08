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
G6.0 Fluid Contracts                   ACCEPTED
G6.1 CasualRiverProviderV1             ACCEPTED
G6.2 Cross-Cell / Cross-LOD Continuity NEXT
```

Current accepted G6.1 tested head:

```text
b8f36d17dc8ba138e6b215968aa0e651eec9ccd1
```

Current global revision:

```text
GLOBAL-P0-2026-08-08-R1
```

Canonical records:

```text
docs/checkpoints/G4_PROVIDER_COMPOSITION_REPLACEMENT_ACCEPTED_RU.md
docs/checkpoints/G5_WORLD_FEATURE_GRAPH_ACCEPTED_RU.md
docs/checkpoints/G6_0_FLUID_CONTRACTS_CANDIDATE_RU.md
docs/checkpoints/G6_1_CASUAL_RIVER_PROVIDER_ACCEPTED_RU.md
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

## Accepted foundation through G5

G4 established recipe-driven provider composition:

```text
PlanetRecipe
  -> GeoRecipeComposer
  -> GeoProviderRegistry
  -> GeoKernel
```

G5 established stable spatial feature identity above representation cells:

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

Canonical `FeatureId` excludes:

```text
SurfaceCellKey
LOD
face/x/y
camera
renderer
query order
```

The accepted G5 seam gate proves one feature can cross multiple cube-sphere cells/faces at LOD 2/4/8/12 while retaining one canonical identity and graph manifest.

## G6.0 Fluid Contracts — ACCEPTED

Canonical fluid vocabulary:

```text
FluidType
FluidRegionId
FluidSurfaceDescriptor
RiverSpline
RiverChannelProfile
WaterSurfaceQuery
```

`FluidRegionId` derives from stable semantic inputs and deliberately excludes representation state. G6.0 post-P0 dependency gate was reconfirmed during G6.1 acceptance:

```text
G5 World Feature Graph: PASS — 249 assertions
G5 feature/cell identity: PASS — 94 assertions
G6.0 fluid contracts: PASS — 169 assertions
```

## G6.1 CasualRiverProviderV1 — ACCEPTED

Accepted architecture:

```text
G5 WorldFeature(feature-type/river)
        + optional linked valley
        ↓
CasualRiverProviderV1
        ↓
FluidRegionId
RiverSpline
RiverChannelProfile
FluidSurfaceDescriptor
```

G5 `River FeatureId` remains semantic owner. The provider is a deterministic compiler and does not create a second WorldFeature, own authority/persistence/network transport, depend on renderer/SceneTree, or use runtime randomness.

Exact Windows evidence on Godot `4.7.1.stable.double.custom_build.a13da4feb`:

```text
G6.1 CasualRiverProviderV1: PASS — 74 assertions
git diff --check from post-P0 G6.0 baseline: PASS
working tree: clean
```

Acceptance record:

```text
docs/checkpoints/G6_1_CASUAL_RIVER_PROVIDER_ACCEPTED_RU.md
```

## Next — G6.2

Blocking GEO track:

```text
G6.2 cross-cell / cross-LOD continuity
  -> G6.3 runtime WaterSurfaceQuery resolver
  -> G6.4 casual visual river lab
  -> G6 full acceptance
  -> G7 Semantic Field Fabric
```

G6.2 must prove that one canonical river may cross changing cube-sphere faces/cells and LOD 2/4/8/12 while retaining stable:

```text
FeatureId
FluidRegionId
RiverSpline.spline_id
RiverChannelProfile.profile_id
canonical provider result identity
```

`SurfaceCellKey` is representation addressing only and must not enter canonical hydrology identity.

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
FluidRegion != AuthorityRegion
FluidRegion != InterestRegion
FluidRegion != renderer object
recipe != planet class
provider graph != world-type switch
canonical truth != representation
procedural baseline + sparse authoritative mutations = current world truth
```
