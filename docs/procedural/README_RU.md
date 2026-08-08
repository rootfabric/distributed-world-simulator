# Universal World Generation Fabric — entrypoint

Current implementation:

```text
feature/g4-provider-composition-replacement
```

Current state:

```text
G3 ACCEPTED
G4 IMPLEMENTED CANDIDATE
```

Start here:

1. `docs/procedural/STATUS_RU.md`
2. `docs/checkpoints/G4_PROVIDER_COMPOSITION_REPLACEMENT_CANDIDATE_RU.md`
3. `docs/checkpoints/G3_CASUAL_MACRO_SURFACE_ACCEPTED_RU.md`
4. `docs/procedural/NEXT_AFTER_G3_UNIVERSAL_WORLD_GENERATION_RU.md`
5. `docs/plans/UNIVERSAL_WORLD_GENERATION_EXECUTION_PLAN_RU.md`
6. `docs/plans/UNIVERSAL_WORLD_GENERATION_ROADMAP_RU.md`
7. `docs/procedural/SESSION_2026-08-08_GENERATION_ASSET_RESEARCH_RU.md`
8. `docs/plans/POST_BASELINE_WORLD_DETAIL_PLAN_RU.md`

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
```

G4 proves this replacement:

```text
CasualMacroTerrainLayerProviderV1
            ↓ recipe swap
AlternativeMacroTerrainProviderV1
```

without changing:

```text
GeoKernel
SurfaceCellKey
CubeSphereAddressing
SurfaceLodSelector
renderer query caller
final field: geo/surface-height-m
```

Composition proof:

```text
BaseSurface
    ↓
Macro provider
    ↓
Valley modifier
    ↓
final surface field
```

Focused tests:

```powershell
.\RUN_G4_PROVIDER_COMPOSITION_TESTS.ps1
```

Full acceptance:

```powershell
.\RUN_G4_FULL_ACCEPTANCE.ps1
```

Visual lab:

```text
res://scenes/labs/procedural/g4_provider_replacement_lab.tscn
```

Press `M` to replace the macro recipe while the same renderer and G2 LOD continue to operate.

After G4 acceptance the blocking GEO track moves to `G5 — World Feature Graph`; parallel `GR0` representation and `GE0` environment tracks become available under the post-G3 roadmap.

## Detail / asset research doctrine

The 2026-08-08 asset research is intentionally **reference-only during the base generation program**.

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
