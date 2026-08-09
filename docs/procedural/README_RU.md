# Universal World Generation Fabric — entrypoint

Current implementation branch:

```text
feature/g7-semantic-field-fabric
```

Current state:

```text
G6 Hydrology / Fluid Surface           SOURCE_ACCEPTED
G6 P0 Alignment Cleanup                ACCEPTED
G7.0 Semantic Field Contracts          IMPLEMENTED CANDIDATE
```

G7.0 is intentionally contract-first. It adds typed field identity/descriptors/query/sample/provenance and a registry vocabulary without changing GeoKernel, G6 Hydrology, Matter, network, authority or persistence.

Core relationship:

```text
G0 GeoFieldBundle / GeoSample
        = provider execution payload, preserved

G7 SemanticField contracts
        = typed semantic metadata/query/result boundary
```

Initial registry preserves accepted upstream IDs:

```text
geo/base-surface-height-m
geo/macro-surface-height-m
geo/surface-height-m
```

and reserves vocabulary for:

```text
geo/slope
geo/curvature
geo/valley-influence
geo/river-distance-m
geo/river-width-m
geo/fluid-surface-distance-m
geo/drainage-potential
geo/continentalness
geo/temperature-baseline
geo/moisture-baseline
```

Vocabulary-only does not mean implemented provider. Actual G3/G5/G6 adapters are the next checkpoint, G7.1.

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

Assistant exact-engine isolated gate:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
headless editor import                PASS
G7.0 contracts                        PASS — 208 assertions
```

Full-checkout acceptance remains pending. Run:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G7_0_SEMANTIC_FIELD_CONTRACTS_TESTS.ps1 -GodotPath $Godot
```

Candidate details:

```text
docs/checkpoints/G7_0_SEMANTIC_FIELD_CONTRACTS_CANDIDATE_RU.md
validation/g7-0-semantic-field-contracts-validation.json
config/procedural/g7-0-semantic-field-contracts.v1.json
```

Detailed G7–G13 plan:

```text
docs/procedural/G7_G13_P0_ALIGNED_ROADMAP_RU.md
config/procedural/g7-g13-p0-aligned-roadmap.v1.json
```

Next after G7.0 acceptance:

```text
G7.1 — G3/G5/G6 Upstream Semantic Field Adapters
```

Global revision: `GLOBAL-P0-2026-08-08-R1`.
