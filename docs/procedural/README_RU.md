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
G7.1 Upstream Semantic Field Adapters  NEXT
```

G7.0 is accepted. It adds typed field identity/descriptors/query/sample/provenance and a registry vocabulary without replacing `GeoKernel`, `GeoFieldBundle` or `GeoSample`.

Core relationship:

```text
G0 GeoFieldBundle / GeoSample
        = provider execution payload, preserved

G7 SemanticField contracts
        = typed semantic metadata/query/result boundary
```

Accepted registry preserves upstream IDs:

```text
geo/base-surface-height-m
geo/macro-surface-height-m
geo/surface-height-m
```

and contains vocabulary for:

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

G7.0 full Windows acceptance:

```text
Godot                                  4.7.1.stable.double.custom_build.a13da4feb
G7.0 focused contracts                 PASS
M4 graphical shared gameplay Fix1      PASS — 22 / 0
world/core regression                   PASS
main_scene_cli_all                      PASS — 6 / 6
G7.0 FULL ACCEPTANCE                    PASS
Working tree                            CLEAN
```

Accepted record:

```text
docs/checkpoints/G7_0_SEMANTIC_FIELD_CONTRACTS_ACCEPTED_RU.md
validation/g7-0-semantic-field-contracts-validation.json
```

G7.1 now connects accepted upstream sources through adapters:

```text
G3 macro surface provider
    -> semantic field adapter

G5 WorldFeatureGraph
    -> feature-derived field adapter

G6 Fluid / river geography
    -> fluid-derived field adapter
```

Ownership rule:

```text
adapter output != new upstream identity

G3 provider id -> provenance
G5 FeatureId   -> provenance
G6 FluidRegionId -> provenance
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

Detailed G7–G13 plan:

```text
docs/procedural/G7_G13_P0_ALIGNED_ROADMAP_RU.md
config/procedural/g7-g13-p0-aligned-roadmap.v1.json
```

Global revision: `GLOBAL-P0-2026-08-08-R1`.
