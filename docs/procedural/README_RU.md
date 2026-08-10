# Universal World Generation Fabric — entrypoint

Current implementation branch:

```text
feature/g7-semantic-field-fabric
```

Current state:

```text
G6 Hydrology / Fluid Surface            SOURCE_ACCEPTED
G6 P0 Alignment Cleanup                 ACCEPTED
G7.0 Semantic Field Contracts           ACCEPTED
G7.1 Upstream Semantic Field Adapters   ACCEPTED
G7.2 Composition / Provenance            ACCEPTED
G7.3 Cross-Cell / Cross-LOD Invariance  IMPLEMENTED CANDIDATE
```

**Active GLOBAL revision:** `GLOBAL-P0-2026-08-10-R2`

R2 frontier policy:

```text
active G7 global ledger == main
historical accepted G6 may remain on its historical R1 revision
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

G7.2 accepted deterministic composition:

```text
G3/G5/G6 partial adapter results
              │
              ▼
    SemanticFieldComposerV1
              │
              ├─ SemanticFieldBundle
              └─ SemanticFieldCompositionReceipt
```

Full G7.2 Windows acceptance passed on:

```text
70d9a78d8f176ce532412a64afbbcb2592623720
Godot 4.7.1.stable.double.custom_build.a13da4feb
```

Accepted G7.2 checkpoint:

```text
68c4f90dbdac0e2d9968b4461207713f5661521b
```

## G7.3 — Cross-Cell / Cross-LOD Invariance

G7.3 is intentionally proof-only. It does not add cell-aware production semantics; it validates that cell/LOD remain representation concerns.

Main formula:

```text
canonical world point + SemanticFieldQuery
    -> canonical semantic result

SurfaceCellKey / LOD
    -> representation addressing only
```

The focused proof uses LOD `2, 4, 8, 12` and the accepted G6 river fixture that crosses the PX/PZ cube-sphere seam.

For one shared world point the test requires equality of:

```text
query checksum
bundle checksum
composition receipt checksum
per-field sample checksum
per-field provenance checksum
```

while `SurfaceCellKey` and representation resolution actually change.

The test also verifies:

```text
SemanticFieldQuery has no surface_cell / surface_cell_key / lod fields
query field-order normalization is deterministic
an alternate valid external SurfaceCellKey cannot perturb the canonical bundle
one river feature spans multiple cells
FeatureId stays stable across cells
FluidRegionId stays stable across cells
river-distance-m remains centerline-consistent on both PX/PZ seam sides
```

No `SemanticCellId`, LOD-specific FeatureId or LOD-specific FluidRegionId is introduced.

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

G8 still owns terrain incision, banks, floodplain and erosion/deposition. G12 remains the future scheduler/cache/provenance execution layer.

Validation:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"

.\RUN_G7_3_CROSS_CELL_CROSS_LOD_INVARIANCE_TESTS.ps1 -GodotPath $Godot
.\RUN_G7_3_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

Records:

```text
docs/checkpoints/G7_2_COMPOSITION_PROVENANCE_ACCEPTED_RU.md
docs/checkpoints/G7_3_CROSS_CELL_CROSS_LOD_INVARIANCE_CANDIDATE_RU.md
validation/g7-3-cross-cell-cross-lod-invariance-validation.json
config/procedural/g7-3-cross-cell-cross-lod-invariance.v1.json
```

Next after G7.3 acceptance:

```text
G7.4 — Semantic Field Lab
```
