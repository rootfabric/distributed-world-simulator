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
G7.0 Semantic Field Contracts          ACCEPTED
G7.1 Upstream Semantic Field Adapters  NEXT
```

G7.0 introduced a typed semantic-field boundary while preserving the existing G0 provider execution payload:

```text
GeoFieldBundle / GeoSample             PRESERVED
GeoKernel                               UNCHANGED
existing geo/* field identities        PRESERVED
SemanticField registry                 ACCEPTED
SemanticField typed query/sample       ACCEPTED
```

Windows full acceptance on tested head `03d1dd1e61ba671456259ab660286d3376520f8e`:

```text
Godot                                  4.7.1.stable.double.custom_build.a13da4feb
G7.0 focused contracts                 PASS
M4 graphical shared gameplay Fix1      PASS — 22 assertions / 0 failures
RL3 representation streaming processes PASS — 37 assertions
main_scene_cli_all                      PASS — 6 / 6
world/core regression                   PASS
G7.0 FULL ACCEPTANCE                    PASS
working tree                            CLEAN
```

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

Accepted record:

```text
docs/checkpoints/G7_0_SEMANTIC_FIELD_CONTRACTS_ACCEPTED_RU.md
validation/g7-0-semantic-field-contracts-validation.json
```

Current implementation target:

```text
G7.1 G3/G5/G6 Upstream Semantic Field Adapters
```

G7.1 must preserve upstream ownership:

```text
G3 provider identity  -> provenance, not replaced
G5 FeatureId          -> provenance, not replaced
G6 FluidRegionId      -> provenance, not replaced
river/fluid fields    -> derived projections, not new canonical river identity
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
