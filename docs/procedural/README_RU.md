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
G7.1 Upstream Semantic Field Adapters  IMPLEMENTED CANDIDATE
```

G7.0 accepted typed field identity/descriptors/query/sample/provenance while preserving `GeoKernel`, `GeoFieldBundle` and `GeoSample`.

G7.1 now connects accepted upstream semantics through partial adapters:

```text
G3 CasualMacroTerrainProviderV1
        │
        └─ geo/surface-height-m
                 ↓
        G3SurfaceSemanticFieldAdapterV1

G5 WorldFeatureGraph
        │
        └─ valley FeatureBounds + FeatureId
                 ↓
        G5FeatureSemanticFieldAdapterV1
                 ↓
        geo/valley-influence

G6 CasualRiverProviderV1 / WaterSurfaceResolverV1
        │
        ├─ FeatureId
        ├─ FluidRegionId
        ├─ RiverSpline
        └─ RiverChannelProfile
                 ↓
        G6FluidSemanticFieldAdapterV1
                 ↓
        geo/river-distance-m
        geo/river-width-m
        geo/fluid-surface-distance-m
```

The adapters do not create a second source of truth. Values are projections of accepted upstream semantics and provenance carries original ownership identities.

```text
G3 provider id   -> preserved
G5 FeatureId     -> preserved
G6 FluidRegionId -> preserved
```

`geo/valley-influence` in G7.1 uses explicit `FEATURE_BOUNDS_FALLOFF_V1`. This is only a feature-derived proxy; it does not carve terrain. G8 still owns valley/channel incision, banks, floodplain and erosion/deposition baseline.

Registry availability now distinguishes implemented adapters from future vocabulary:

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
```

Validation:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G7_1_UPSTREAM_SEMANTIC_FIELD_ADAPTERS_TESTS.ps1 -GodotPath $Godot
.\RUN_G7_1_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

G7.0 accepted record:

```text
docs/checkpoints/G7_0_SEMANTIC_FIELD_CONTRACTS_ACCEPTED_RU.md
```

G7.1 candidate record:

```text
docs/checkpoints/G7_1_UPSTREAM_SEMANTIC_FIELD_ADAPTERS_CANDIDATE_RU.md
validation/g7-1-upstream-semantic-field-adapters-validation.json
config/procedural/g7-1-upstream-semantic-field-adapters.v1.json
```

Next after G7.1 acceptance:

```text
G7.2 — Composition / Provenance
```

Global revision: `GLOBAL-P0-2026-08-08-R1`.
