# Universal World Generation Fabric — status ledger

**Program foundation:** G0–G3 Procedural Planetary Generation
**Post-G3 roadmap:** `docs/universal-world-generation-roadmap-post-g3`
**Current implementation branch:** `feature/g5-world-feature-graph`

## Current state

```text
G0 Contracts Freeze                    ACCEPTED
G1 Geodesy + Body Shape                BASELINE
G2 Planetary Surface Cells + LOD       ACCEPTED
G3 Mega Casual Macro Surface           ACCEPTED
G4 Provider Composition / Replacement  ACCEPTED
G5 World Feature Graph                 IMPLEMENTED CANDIDATE — FULL GATE PENDING
G6 Hydrology / Fluid Surface v0        NEXT AFTER G5 ACCEPTED
```

G5 base:

```text
feature/g4-provider-composition-replacement
4d1fed8e4367e6c4ea276fcf6b9b57159de72014
```

Canonical G4 acceptance record:

```text
docs/checkpoints/G4_PROVIDER_COMPOSITION_REPLACEMENT_ACCEPTED_RU.md
```

G5 candidate record:

```text
docs/checkpoints/G5_WORLD_FEATURE_GRAPH_CANDIDATE_RU.md
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

## G5 implemented candidate

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

Feature graph supports surface, subsurface and free-space semantics. Current acceptance fixtures include:

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

## Exact-engine focused evidence

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
cold editor import                 PASS
G5 World Feature Graph             PASS — 249 assertions
G5 feature/cell identity           PASS — 94 assertions
G5 visual lab headless             PASS — 4 features
```

Lab:

```text
res://scenes/labs/procedural/g5_world_feature_graph_lab.tscn
```

Focused runner:

```powershell
.\RUN_G5_WORLD_FEATURE_GRAPH_TESTS.ps1
```

Full checkout gate:

```powershell
.\RUN_G5_FULL_ACCEPTANCE.ps1
```

Required before acceptance:

```text
G4 dependency focused PASS
G5 focused PASS
full world/core regression PASS
Breakpoint :9081 collision noise 0
git diff --check vs accepted G4 PASS
frozen G0-G4 architecture paths unchanged
production/runtime/network/Matter/world paths unchanged
```

Until the real Windows full-checkout wrapper is green, G5 remains `IMPLEMENTED CANDIDATE`.

## Next

Blocking main track after G5 acceptance:

```text
G6 — Hydrology / Fluid Surface v0
```

G6 must express rivers/fluid geography through G5 feature identity instead of chunk-local identities.

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
recipe != planet class
provider graph != world-type switch
canonical truth != representation
procedural baseline + sparse authoritative mutations = current world truth
```
