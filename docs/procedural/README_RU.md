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
G7.2 Composition / Provenance           ACCEPTED
G7.3 Cross-Cell / Cross-LOD Invariance  NEXT
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

The accepted composition policy is strict:

```text
semantic-composition-policy/require-complete-v1

missing requested fields       REJECT
duplicate field ownership      REJECT
duplicate adapters             REJECT
unrequested contributed fields REJECT
input order                     NORMALIZED BY ADAPTER_ID
```

The composer does not recalculate upstream semantic values. `SemanticFieldCompositionReceipt` pins query, bundle, sample and provenance checksums and remains an audit artifact rather than canonical world identity.

## G7.3 target

G7.3 proves the representation-independence already required by P0:

```text
one world point + one canonical semantic query
    -> same values/checksums/provenance
       regardless of SurfaceCellKey / LOD path
```

Acceptance must demonstrate:

```text
same world point is semantic-cell invariant
LOD changes only representation density/addressing
PX/PZ and other cube-sphere seams do not change semantic value
one river/valley feature spans many cells without identity reroll
query field order does not change bundle/provenance
```

Surface-cell and LOD information remain external representation context and do not enter `SemanticFieldId`, `SemanticFieldQuery`, `SemanticFieldSample`, `SemanticFieldBundle` or upstream Feature/Fluid identity.

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

Records:

```text
docs/checkpoints/G7_1_UPSTREAM_SEMANTIC_FIELD_ADAPTERS_ACCEPTED_RU.md
docs/checkpoints/G7_2_COMPOSITION_PROVENANCE_ACCEPTED_RU.md
validation/g7-2-composition-provenance-validation.json
config/procedural/g7-2-composition-provenance.v1.json
```

Next implementation checkpoint:

```text
G7.3 — Cross-Cell / Cross-LOD Invariance
```

Global revision: `GLOBAL-P0-2026-08-08-R1`.
