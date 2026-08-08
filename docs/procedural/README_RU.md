# Universal World Generation Fabric — entrypoint

Current implementation:

```text
feature/g6-hydrology-fluid-surface
```

Current state:

```text
G3 ACCEPTED
G4 ACCEPTED — Architecture Review A PASS
G5 ACCEPTED
G6 IMPLEMENTED CANDIDATE
G7 BLOCKED BY G6 ACCEPTANCE
```

Start here:

1. `docs/procedural/STATUS_RU.md`
2. `docs/checkpoints/G6_HYDROLOGY_FLUID_SURFACE_CANDIDATE_RU.md`
3. `docs/checkpoints/G5_WORLD_FEATURE_GRAPH_ACCEPTED_RU.md`
4. `docs/checkpoints/G4_PROVIDER_COMPOSITION_REPLACEMENT_ACCEPTED_RU.md`
5. `docs/procedural/NEXT_AFTER_G3_UNIVERSAL_WORLD_GENERATION_RU.md`
6. `docs/plans/UNIVERSAL_WORLD_GENERATION_EXECUTION_PLAN_RU.md`
7. `docs/plans/UNIVERSAL_WORLD_GENERATION_ROADMAP_RU.md`
8. `docs/procedural/SESSION_2026-08-08_GENERATION_ASSET_RESEARCH_RU.md`
9. `docs/plans/POST_BASELINE_WORLD_DETAIL_PLAN_RU.md`

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
G6 canonical hydrology / fluid geography
        ↓
G7 semantic field fabric
```

G4 established:

```text
world semantics = recipe-driven provider graph
```

G5 established stable spatial feature identity above representation cells:

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

Canonical `FeatureId` is independent of cell/LOD/camera/renderer/streaming state.

G6 builds fluid geography on that identity rather than inventing chunk-local rivers.

## G6 canonical hydrology

New vocabulary:

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

The core relationship is:

```text
G5 RiverFeature
     +
RiverSpline
     +
RiverChannelProfile
     +
FluidSurfaceDescriptor
     ↓
CasualRiverProviderV1
     ↓
WaterSurfaceQuery -> WaterSurfaceSample
```

Important boundaries:

```text
River != SurfaceCellKey
River != LOD
FluidRegion != renderer artifact
WaterSurfaceQuery does not receive cell/LOD
G6 != CFD
G6 != G7 Semantic Field Fabric
```

A generic fluid descriptor is already able to express non-water fluid identity and multiple surface modes. This is the foundation for future river/lake/ocean/lava-lake/methane-sea/subsurface-fluid implementations without adding world-type switches to core.

## G6 seam / LOD proof

The Mega Casual River fixture is planetary-scale and deliberately crosses the G2 cube-sphere `PX/PZ` seam.

It is addressed at:

```text
LOD 2
LOD 4
LOD 8
LOD 12
```

The representation cell set changes, while all of the following remain stable:

```text
River FeatureId
FluidRegionId
provider manifest
canonical water query result identity
```

Candidate evidence:

```text
G6 hydrology/fluid surface          PASS — 161 assertions
G6 river/cell LOD identity          PASS — 72 assertions
G6 visual lab headless              PASS
G5 graph regression                 PASS — 249 assertions
G5 cell identity regression         PASS — 94 assertions
G6 focused Linux wrapper            PASS
```

Implementation candidate:

```text
68dc5158347989c6d16564993144106d2a294516
```

Full Windows gate still required:

```powershell
.\RUN_G6_FULL_ACCEPTANCE.ps1
```

Visual lab:

```text
res://scenes/labs/procedural/g6_hydrology_fluid_surface_lab.tscn
```

The blue river ribbon is intentionally width-exaggerated for visibility. It is presentation-only; canonical channel width remains 60→180 m.

## What G7 will add

After G6 acceptance, G7 should expose provider-independent semantic fields such as:

```text
hydro/river-distance-m
hydro/water-level-m
hydro/moisture
hydro/drainage
```

Consumers then ask for a semantic field and do not know whether its source was a river provider, lake model, terrain analysis or another composition backend.

## Detail / asset research doctrine

The 2026-08-08 asset research remains intentionally **reference-only during the base generation program**.

```text
BASE FIRST
BEAUTY SECOND
```

Until the universal generation fabric, fields, volume queries, scheduler/streaming and detail contracts are stable, environments may use deliberately simple casual representations:

```text
simple river strip
simple ocean envelope
primitive trees/rocks
simple snow coverage
simple swamp water/reeds
simple dune forms
simple lava strip
simple cloud proxies
simple SDF caves
simple reef scatter
```

The important early acceptance targets are:

```text
canonical identity
provider composition
determinism
query contracts
causal fields
LOD independence
streaming lifecycle
network derivation
mutation compatibility
```

Only after that baseline is accepted should the project spend significant effort adapting high-quality ideas from the accumulated reference mosaic: Procedural Forest Demo, Waterways, ocean renderers, deformable snow/activity maps, procedural branching/path geometry, Terrain3D/Infinigen-style techniques and other environment references.

See:

```text
docs/procedural/SESSION_2026-08-08_GENERATION_ASSET_RESEARCH_RU.md
docs/plans/POST_BASELINE_WORLD_DETAIL_PLAN_RU.md
```
