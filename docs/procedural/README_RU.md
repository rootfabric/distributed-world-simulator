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
G6.0 ACCEPTED
G6.1 ACCEPTED
G6.2 IMPLEMENTED CANDIDATE — cross-cell / cross-LOD continuity
G6.3 NEXT — after G6.2 acceptance
```

Start here:

1. `docs/procedural/STATUS_RU.md`
2. `docs/checkpoints/G6_2_CROSS_CELL_CROSS_LOD_CONTINUITY_CANDIDATE_RU.md`
3. `docs/checkpoints/G6_1_CASUAL_RIVER_PROVIDER_ACCEPTED_RU.md`
4. `docs/checkpoints/G6_0_FLUID_CONTRACTS_CANDIDATE_RU.md`
5. `docs/checkpoints/G5_WORLD_FEATURE_GRAPH_ACCEPTED_RU.md`
6. `docs/checkpoints/G4_PROVIDER_COMPOSITION_REPLACEMENT_ACCEPTED_RU.md`
7. `docs/procedural/G6_P0_ALIGNMENT_RU.md`
8. `docs/procedural/NEXT_AFTER_G3_UNIVERSAL_WORLD_GENERATION_RU.md`
9. `docs/plans/UNIVERSAL_WORLD_GENERATION_EXECUTION_PLAN_RU.md`
10. `docs/plans/UNIVERSAL_WORLD_GENERATION_ROADMAP_RU.md`

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
G6.1 deterministic river provider
        ↓
G6.2 cross-cell/cross-LOD continuity proof
        ↓
G6.3 runtime fluid surface query
        ↓
G6.4 casual visual river
```

G4 established recipe-driven world semantics. G5 established spatial semantic identity above representation cells. G6.0 established canonical fluid vocabulary. G6.1 established and accepted the first deterministic river compiler.

Accepted rule:

```text
G5 FeatureId = semantic river owner
G6.1 provider = deterministic derived geography compiler
cell/LOD/renderer = representation only
```

Exact Windows G6.1 evidence:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
G5 World Feature Graph       PASS — 249 assertions
G5 feature/cell identity     PASS — 94 assertions
G6.0 fluid contracts         PASS — 169 assertions
G6.1 CasualRiverProviderV1   PASS — 74 assertions
git diff --check             PASS
```

## Current checkpoint — G6.2

G6.2 introduces no new production hydrology runtime. It proves continuity of one canonical river across changing G2 representation addresses.

Fixture:

```text
planet radius: 6,000,000 m
source:         longitude 34°
mouth:          longitude 58°
cube seam:      PX / PZ
LOD:            2 / 4 / 8 / 12
```

Representation cell sets must change while these stay stable:

```text
FeatureId
FluidRegionId
RiverSpline.spline_id
RiverChannelProfile.profile_id
provider manifest hash
canonical spline/surface checksums
```

Focused validation:

```powershell
$env:GODOT_BIN = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G6_2_CROSS_CELL_CONTINUITY_TESTS.ps1
```

If green, G6.2 becomes `ACCEPTED` and the blocking GEO track advances to `G6.3 — runtime WaterSurfaceQuery resolver`.

## Detail / asset research doctrine

The 2026-08-08 asset research remains **reference-only during the base generation program**.

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
