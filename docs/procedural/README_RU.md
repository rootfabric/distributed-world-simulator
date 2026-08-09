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
G7.1 Upstream Semantic Field Adapters  ACCEPTED
G7.2 Composition / Provenance           IMPLEMENTED CANDIDATE
```

## Accepted semantic path

G7.0 introduced typed semantic-field identity/query/sample/provenance contracts without replacing `GeoKernel`, `GeoFieldBundle` or `GeoSample`.

G7.1 accepted projections:

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

Full G7.1 Windows acceptance passed on:

```text
61de8526448a5a2ab95745fa380cdc8b3c4ea24f
Godot 4.7.1.stable.double.custom_build.a13da4feb
```

Accepted G7.1 checkpoint:

```text
af0898ba2f0fc03dbd0298440f302b497a5d0cad
```

## G7.2 Composition / Provenance

G7.2 composes already-produced partial semantic samples:

```text
G3/G5/G6 partial adapter results
              │
              ▼
    SemanticFieldComposerV1
              │
              ├─ SemanticFieldBundle
              └─ SemanticFieldCompositionReceipt
```

Strict policy:

```text
semantic-composition-policy/require-complete-v1
```

It rejects:

```text
missing requested fields
duplicate field ownership
duplicate adapters
unrequested contributed fields
```

Adapter input ordering is normalized by canonical `adapter_id`, so equivalent inputs must produce identical bundle and receipt checksums.

The composer does not recalculate samples and does not replace upstream provenance. The receipt pins:

```text
query checksum
bundle checksum
per-field sample checksum
per-field provenance checksum
ordered adapter contributions
```

Focused tests compose real accepted adapter paths:

```text
G3 + G5
G3 + G6
```

and verify that G5 `FeatureId` and G6 `FluidRegionId` remain inside original sample provenance.

## Ownership / P0 guards

```text
SemanticFieldId != SurfaceCellKey
SemanticFieldId != LOD
SemanticFieldQuery != universal WorldQuery Fabric
FluidTypeId != MaterialDefinitionId

G7 != Material Ontology
G7 != Authority / Interest
G7 != Persistence / Network
G7 != Scheduler / Cache execution owner
G7 != Geomorphology

SemanticFieldCompositionReceipt != world identity
```

G8 still owns terrain incision, banks, floodplain and erosion/deposition. G12 remains the future scheduler/cache/provenance execution layer; G7.2 only performs synchronous deterministic composition of already available results.

## Validation

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_G7_2_COMPOSITION_PROVENANCE_TESTS.ps1 -GodotPath $Godot
.\RUN_G7_2_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

Records:

```text
docs/checkpoints/G7_1_UPSTREAM_SEMANTIC_FIELD_ADAPTERS_ACCEPTED_RU.md
docs/checkpoints/G7_2_COMPOSITION_PROVENANCE_CANDIDATE_RU.md
validation/g7-2-composition-provenance-validation.json
config/procedural/g7-2-composition-provenance.v1.json
```

Next after G7.2 acceptance:

```text
G7.3 — Cross-Cell / Cross-LOD Invariance
```

Global revision: `GLOBAL-P0-2026-08-08-R1`.
