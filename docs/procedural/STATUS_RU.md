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
G6.2 Cross-Cell / Cross-LOD Continuity ACCEPTED
G6.3 Runtime WaterSurfaceQuery         NEXT — UNBLOCKED
```

Accepted G6.1 tested head:

```text
b8f36d17dc8ba138e6b215968aa0e651eec9ccd1
```

Accepted G6.2 tested head:

```text
444811c0ac98a133844cd7ec0869a6cf0a261f11
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
docs/checkpoints/G6_2_CROSS_CELL_CROSS_LOD_CONTINUITY_ACCEPTED_RU.md
```

## Universal architecture

```text
new world
  != new engine special-case

new world
  = recipe + providers + features + environment + detail backends
```

## Accepted foundation through G6.2

G4 established recipe-driven provider composition. G5 established stable spatial feature identity above representation cells. G6.0 established canonical fluid contracts. G6.1 accepted `CasualRiverProviderV1` as a deterministic compiler from stable G5 river semantics into `FluidRegionId`, `RiverSpline`, `RiverChannelProfile`, and `FluidSurfaceDescriptor`.

G6.2 then proved that the resulting canonical river geography survives representation changes across cube-sphere faces and LOD without identity reroll.

Accepted Windows dependency chain:

```text
G5 World Feature Graph: PASS — 249 assertions
G5 feature/cell identity: PASS — 94 assertions
G6.0 fluid contracts: PASS — 169 assertions
G6.1 CasualRiverProviderV1: PASS — 74 assertions
G6.2 cross-cell/cross-LOD continuity: PASS — 86 assertions
git diff --check: PASS
working tree: clean
```

## G6.2 accepted continuity proof

Deterministic fixture:

```text
planet radius:      6,000,000 m
river source lon:   34°
river mouth lon:    58°
expected cube seam: PX / PZ
LOD matrix:         2 / 4 / 8 / 12
```

The G2 representation address set changes with LOD while these stay stable:

```text
FeatureId
FluidRegionId
RiverSpline.spline_id
RiverChannelProfile.profile_id
provider manifest hash
RiverSpline checksum
FluidSurfaceDescriptor checksum
```

Accepted architecture rule:

```text
canonical river geography
        ↓
CubeSphereAddressing / SurfaceCellKey
        ↓
LOD-specific representation cells

NOT:
SurfaceCellKey / LOD -> hydrology identity
```

Therefore:

```text
Feature != SurfaceCell
FluidRegion != SurfaceCell
LOD != river identity
CubeSphere face != river identity
RiverChunkId is not required
```

## Next — G6.3

Blocking GEO track is now:

```text
G6.3 runtime WaterSurfaceQuery resolver
  -> G6.4 casual visual river lab
  -> G6 full acceptance
  -> G7 Semantic Field Fabric
```

G6.3 must resolve canonical fluid geography from world-space/body-frame queries without requiring the caller to know representation cell, cube face, or LOD.

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
