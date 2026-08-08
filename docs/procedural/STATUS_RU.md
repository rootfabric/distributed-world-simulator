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
G6.2 Cross-Cell / Cross-LOD Continuity IMPLEMENTED CANDIDATE
G6.3 Runtime WaterSurfaceQuery         NEXT AFTER G6.2 ACCEPTANCE
```

Current accepted G6.1 tested head:

```text
b8f36d17dc8ba138e6b215968aa0e651eec9ccd1
```

G6.2 implementation candidate:

```text
322265247bb0a01bf7bdd814adca2ead30b124c9
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
docs/checkpoints/G6_2_CROSS_CELL_CROSS_LOD_CONTINUITY_CANDIDATE_RU.md
```

## Universal architecture

```text
new world
  != new engine special-case

new world
  = recipe + providers + features + environment + detail backends
```

## Accepted foundation through G6.1

G4 established recipe-driven provider composition. G5 established stable spatial feature identity above representation cells. G6.0 established canonical fluid contracts. G6.1 accepted `CasualRiverProviderV1` as a deterministic compiler from stable G5 river semantics into `FluidRegionId`, `RiverSpline`, `RiverChannelProfile`, and `FluidSurfaceDescriptor`.

Exact accepted G6.1 Windows evidence:

```text
G5 World Feature Graph: PASS — 249 assertions
G5 feature/cell identity: PASS — 94 assertions
G6.0 fluid contracts: PASS — 169 assertions
G6.1 CasualRiverProviderV1: PASS — 74 assertions
git diff --check: PASS
working tree: clean
```

## G6.2 Cross-Cell / Cross-LOD Continuity — candidate

G6.2 is a proof-only checkpoint. Accepted G6.0 contracts and G6.1 provider are unchanged.

Deterministic fixture:

```text
planet radius:      6,000,000 m
river source lon:   34°
river mouth lon:    58°
expected cube seam: PX / PZ
LOD matrix:          2 / 4 / 8 / 12
```

The G2 representation address set must change with LOD, while these canonical values remain unchanged:

```text
FeatureId
FluidRegionId
RiverSpline.spline_id
RiverChannelProfile.profile_id
provider manifest hash
RiverSpline checksum
FluidSurfaceDescriptor checksum
```

Architecture rule under test:

```text
canonical river geography
        ↓
CubeSphereAddressing / SurfaceCellKey
        ↓
LOD-specific representation cells

NOT:
SurfaceCellKey / LOD -> hydrology identity
```

G6.2 does not introduce `RiverChunkId`, renderer, runtime water resolver, authority, persistence, or network transport.

Focused validation:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_2_CROSS_CELL_CONTINUITY_TESTS.ps1
```

Expected chain:

```text
G5 World Feature Graph       PASS — 249
G5 feature/cell identity     PASS — 94
G6.0 fluid contracts         PASS — 169
G6.1 CasualRiverProviderV1   PASS — 74
G6.2 continuity              PASS REQUIRED
```

## Next

After focused G6.2 acceptance:

```text
G6.3 runtime WaterSurfaceQuery resolver
  -> G6.4 casual visual river lab
  -> G6 full acceptance
  -> G7 Semantic Field Fabric
```

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
