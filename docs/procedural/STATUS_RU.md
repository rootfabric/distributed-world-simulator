# Universal World Generation Fabric — status ledger

**Current branch:** `feature/g7-semantic-field-fabric`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`

```text
G6.0 Fluid Contracts                   ACCEPTED
G6.1 CasualRiverProviderV1             ACCEPTED
G6.2 Cross-Cell / Cross-LOD Continuity ACCEPTED
G6.3 Runtime WaterSurfaceQuery         ACCEPTED
G6.4 Casual Visual River Lab           ACCEPTED
G5 + MW10 shared baseline              ACCEPTED / INTEGRATED
G6 Full Acceptance                     SOURCE_ACCEPTED
G6 P0 Alignment Cleanup                ACCEPTED
G7.0 Semantic Field Contracts          IMPLEMENTED CANDIDATE
```

G7.0 introduces a typed semantic-field boundary while preserving the existing G0 provider execution payload:

```text
GeoFieldBundle / GeoSample             PRESERVED
GeoKernel                               UNCHANGED
existing geo/* field identities         PRESERVED
SemanticField registry                  ADDED
SemanticField typed query/sample        ADDED
```

Registry v1 contains 13 fields: three accepted upstream field identities and ten vocabulary-only fields reserved for G7.1+ providers/adapters.

P0 ownership remains explicit:

```text
SemanticFieldId != SurfaceCellKey
SemanticFieldId != LOD
SemanticFieldQuery != universal WorldQuery Fabric
G7 != Material Ontology
G7 != Authority / Interest
G7 != Persistence / Network
G7 != Scheduler / Cache owner
```

Assistant-side exact-engine isolated evidence:

```text
Godot 4.7.1 double                    PASS
headless editor import                PASS
G7.0 contracts                        PASS — 208 assertions
parse/load errors                     0
```

G7.0 is not yet `ACCEPTED`: full Windows checkout validation and project regression remain required.

Focused Windows command:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G7_0_SEMANTIC_FIELD_CONTRACTS_TESTS.ps1 -GodotPath $Godot
```

Candidate record:

```text
docs/checkpoints/G7_0_SEMANTIC_FIELD_CONTRACTS_CANDIDATE_RU.md
validation/g7-0-semantic-field-contracts-validation.json
config/procedural/g7-0-semantic-field-contracts.v1.json
```

After G7.0 acceptance:

```text
G7.1 G3/G5/G6 Upstream Semantic Field Adapters
```

Longer roadmap remains:

```text
G7 Semantic Field Fabric
    -> G8 Geomorphology
    -> G9 Layered Geology / P0 Material gate
    -> G10 GeoVolume / SDF
    -> G11 Heterogeneous Body Lab
    -> G12 Scheduler / Cache / Provenance
    -> G13 Detail Contract Freeze
```
