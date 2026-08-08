# Universal World Generation Fabric — entrypoint

Current implementation:

```text
feature/g5-world-feature-graph
```

Current state:

```text
G3 ACCEPTED
G4 ACCEPTED — Architecture Review A PASS
G5 ACCEPTED
G6 NEXT — UNBLOCKED
```

Start here:

1. `docs/procedural/STATUS_RU.md`
2. `docs/checkpoints/G5_WORLD_FEATURE_GRAPH_ACCEPTED_RU.md`
3. `docs/checkpoints/G4_PROVIDER_COMPOSITION_REPLACEMENT_ACCEPTED_RU.md`
4. `docs/procedural/NEXT_AFTER_G3_UNIVERSAL_WORLD_GENERATION_RU.md`
5. `docs/plans/UNIVERSAL_WORLD_GENERATION_EXECUTION_PLAN_RU.md`
6. `docs/plans/UNIVERSAL_WORLD_GENERATION_ROADMAP_RU.md`

## Current architecture

```text
G0 contracts / GeoKernel
        ↓
G1 body-fixed geodesy
        ↓
G2 cube-sphere cells + LOD
        ↓
G3 canonical macro surface
        ↓
G4 recipe-driven provider composition
        ↓
G5 canonical World Feature Graph
        ↓
G6 hydrology / fluid geography
```

G4 established:

```text
world semantics = recipe-driven provider graph
```

G5 establishes spatial semantic identity above representation cells:

```text
WorldFeature
  feature_id
  feature_type
  bounds
  anchors
  parent
  relations
        ↓
FeatureGraph
        ↓
FeatureQuery
```

Canonical FeatureId depends on:

```text
body_id
feature_type
seed
generator_version
stable_key
```

and deliberately does not depend on:

```text
SurfaceCellKey
LOD
camera
renderer
streaming state
```

The accepted G5 seam gate proves that one fault crosses multiple cube-sphere cells and the PX/PZ face boundary at LOD 2/4/8/12 while keeping one FeatureId and one graph manifest.

G5 is not surface-only. Acceptance also covers a subsurface cave system and a free-space floating island.

Acceptance evidence:

```text
G5 World Feature Graph: PASS (249 assertions)
G5 feature/cell identity: PASS (94 assertions)
full world/core regression: PASS
Breakpoint :9081 collision noise: 0
G5 full acceptance gate: PASS
```

Visual lab:

```text
res://scenes/labs/procedural/g5_world_feature_graph_lab.tscn
```

Blocking GEO track is now `G6 — Hydrology / Fluid Surface v0`. G6 must build river/fluid geography on stable G5 feature identity rather than chunk-local identities.
