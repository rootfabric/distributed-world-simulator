# Universal World Generation Fabric — entrypoint

Current implementation branch:

```text
feature/g7-semantic-field-fabric
```

Current state:

```text
G6 Hydrology / Fluid Surface           SOURCE_ACCEPTED
G6 P0 Alignment Cleanup                ACCEPTED
G7.0 Semantic Field Contracts          ACCEPTED
G7.1 Upstream Semantic Field Adapters  FIX1 IMPLEMENTED CANDIDATE
```

G7.0 introduced the typed semantic-field boundary without replacing `GeoKernel`, `GeoFieldBundle` or `GeoSample`.

G7.1 adapts accepted upstream semantics:

```text
G3 provider
  -> geo/surface-height-m

G5 WorldFeatureGraph
  -> geo/valley-influence

G6 WaterSurfaceResolverV1
  -> geo/river-distance-m
  -> geo/river-width-m
  -> geo/fluid-surface-distance-m
```

The first real Windows full-checkout G7.1 run failed fast inside the focused adapter gate and exposed two contract-shape errors in the initial candidate:

```text
G3 GeoProvider.success(values)
  canonical path = details.values

G6 WaterSurfaceSample
  canonical width key = channel_width_m
```

Initial G7.1 used `details` directly for G3 and stale `width_m` for G6. Fix1 corrects both and strengthens the test so these exact accepted shapes are pinned.

Current Fix1 blobs:

```text
G3 adapter  c728cfed5a2b3dd55d23b81b250177af19746623
G5 adapter  39ef95704cdf516b10146d2fa79b0d80bf173492
G6 adapter  437d82b7f056648045fff08f1daa57968331104c
G7.1 test   1af618356b700e5c87a55b42daa05d35b267014e
```

Expected focused marker after Fix1:

```text
G7.1 Upstream Semantic Field Adapters: 59 assertions, 0 failures
```

The previous assistant stub smoke is superseded and is not acceptance evidence because its fake upstream shapes were too permissive.

Ownership remains upstream:

```text
G3 provider id   -> preserved
G5 FeatureId     -> preserved
G6 FluidRegionId -> preserved
```

No new RiverId, FeatureId or FluidRegionId is created by G7.

`geo/valley-influence` remains only `FEATURE_BOUNDS_FALLOFF_V1` semantic proxy. G8 still owns terrain incision, banks, floodplain and erosion/deposition.

Registry availability:

```text
ADAPTER_AVAILABLE_G7_1
  geo/valley-influence
  geo/river-distance-m
  geo/river-width-m
  geo/fluid-surface-distance-m

VOCABULARY_ONLY_G7_0
  geo/slope
  geo/curvature
  geo/drainage-potential
  geo/continentalness
  geo/temperature-baseline
  geo/moisture-baseline
```

P0 guards remain mandatory:

```text
SemanticFieldId != SurfaceCellKey
SemanticFieldId != LOD
SemanticFieldQuery != universal WorldQuery Fabric
FluidTypeId != MaterialDefinitionId
G7 != Material Ontology
G7 != Authority / Interest / Persistence / Network
G7 != Scheduler / Cache execution owner
G7.1 != Geomorphology
```

Validation:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G7_1_UPSTREAM_SEMANTIC_FIELD_ADAPTERS_TESTS.ps1 -GodotPath $Godot
.\RUN_G7_1_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

Records:

```text
docs/checkpoints/G7_0_SEMANTIC_FIELD_CONTRACTS_ACCEPTED_RU.md
docs/checkpoints/G7_1_UPSTREAM_SEMANTIC_FIELD_ADAPTERS_CANDIDATE_RU.md
validation/g7-1-upstream-semantic-field-adapters-validation.json
config/procedural/g7-1-upstream-semantic-field-adapters.v1.json
```

Next after G7.1 acceptance:

```text
G7.2 — Composition / Provenance
```

Global revision: `GLOBAL-P0-2026-08-08-R1`.
