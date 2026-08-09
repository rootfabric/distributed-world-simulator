# G6 P0 Alignment Cleanup — ACCEPTED

**Дата:** 2026-08-09  
**Ветка:** `feature/g6-hydrology-fluid-surface-v0`  
**Global revision:** `GLOBAL-P0-2026-08-08-R1`

## Причина

После `G6 SOURCE_ACCEPTED` выполнен отдельный архитектурный аудит против GLOBAL-P0.

Runtime/ownership нарушения не найдены. Найдены два ledger-долга:

```text
docs/procedural/G6_P0_ALIGNMENT_RU.md
  -> оставался на старом BLOCKED_BY_SHARED_MW10 состоянии

config/procedural/g6-full-acceptance.v1.json
  -> оставался IMPLEMENTED_CANDIDATE_BLOCKED_BY_SHARED_BASELINE
```

Также до старта G7 потребовалось явно закрепить границы P0 Material Ontology и WorldQuery/Spatial ownership.

## Решение

```text
G6 runtime architecture          PASS
G6 SOURCE_ACCEPTED               PRESERVED
P0 local ledger freshness        FIXED
G6 acceptance manifest           ALIGNED_TO_SOURCE_ACCEPTED
G7-G13 roadmap                   P0-ALIGNED
```

## Зафиксированные invariants

```text
FeatureId != SurfaceCellKey
FluidRegionId != SurfaceCellKey
FluidRegionId != AuthorityRegionId
FluidRegionId != InterestRegionId
LOD != fluid identity
FluidTypeId != MaterialDefinitionId
SemanticFieldId != SurfaceCellKey
SemanticFieldId != LOD
SemanticFieldQuery != universal WorldQuery Fabric
```

G7 не получает ownership над:

```text
WorldAddress
Universal WorldQuery
Authority routing
Interest management
Persistence/durability
Network replication
Material ontology
Scheduler/cache execution ownership
```

G12 остаётся владельцем только generation scheduler/cache/provenance layer и не становится authority/persistence owner.

## Скорректированный Geo roadmap

```text
G6 Hydrology / Fluid Surface        SOURCE_ACCEPTED
        ↓
G7 Semantic Field Fabric            NEXT
        ↓
G8 Geomorphology
        ↓
G9 Layered Geology                  P0 Material Ontology gate
        ↓
G10 GeoVolume / SDF                 Geo != Matter
        ↓
G11 Heterogeneous Body Lab
        ↓
G12 Scheduler / Cache / Provenance  no authority/persistence ownership
        ↓
G13 Detail Contract Freeze
```

Полный план:

```text
docs/procedural/G7_G13_P0_ALIGNED_ROADMAP_RU.md
config/procedural/g7-g13-p0-aligned-roadmap.v1.json
```

## Следующий implementation checkpoint

```text
G7.0 Semantic Field Contracts + Registry Vocabulary
```

Он должен быть небольшим contract-first checkpoint без scheduler/cache/network/persistence и доказать stable field identity, value typing и provenance поверх принятых G3/G5/G6 semantics.
