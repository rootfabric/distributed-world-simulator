# Universal World Generation Fabric — entrypoint

Current implementation:

```text
feature/g6-hydrology-fluid-surface-v0
```

Current state:

```text
G3 ACCEPTED
G4 ACCEPTED — Architecture Review A PASS
G5 ACCEPTED
G6.0 IMPLEMENTED CANDIDATE
G6.1 NEXT — after focused G6.0 acceptance
```

Start here:

1. `docs/procedural/STATUS_RU.md`
2. `docs/checkpoints/G6_0_FLUID_CONTRACTS_CANDIDATE_RU.md`
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
G6.0 canonical fluid contracts
        ↓
G6.1 river provider
        ↓
G6.2 cross-cell/cross-LOD continuity
        ↓
G6.3 runtime fluid surface query
        ↓
G6.4 casual visual river
```

G4 established:

```text
world semantics = recipe-driven provider graph
```

G5 established spatial semantic identity above representation cells. Its accepted seam gate proves that a canonical feature keeps one identity while its representation spans different cube-sphere cells and LODs.

G6.0 adds the canonical fluid vocabulary:

```text
FluidType
FluidRegionId
FluidSurfaceDescriptor
RiverSpline
RiverChannelProfile
WaterSurfaceQuery
```

`FluidRegionId` depends only on:

```text
body_id
fluid_type_id
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

`FluidSurfaceDescriptor` can optionally reference a G5 `FeatureId`, so rivers may be derived from stable feature semantics while lakes, oceans, lava seas or other fluid regions remain first-class generic fluid geography.

Focused validation:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_FLUID_CONTRACT_TESTS.ps1
```

The focused runner rechecks both accepted G5 contract suites before the new G6.0 contract suite.

Blocking GEO track after that focused acceptance is `G6.1 — CasualRiverProviderV1`.

## Detail / asset research doctrine

The 2026-08-08 asset research is intentionally **reference-only during the base generation program**.

```text
BASE FIRST
BEAUTY SECOND
```

Until the universal generation fabric, fields, volume queries, scheduler/streaming and detail contracts are stable, environments may use deliberately simple casual representations.

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

Only after that baseline is accepted should the project spend significant effort adapting high-quality ideas from the accumulated reference mosaic.

See:

```text
docs/procedural/SESSION_2026-08-08_GENERATION_ASSET_RESEARCH_RU.md
docs/plans/POST_BASELINE_WORLD_DETAIL_PLAN_RU.md
```
