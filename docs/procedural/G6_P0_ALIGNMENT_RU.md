# G6 Hydrology / Fluid Surface v0 — P0 alignment

**Global revision:** `GLOBAL-P0-2026-08-08-R1`  
**Branch:** `feature/g6-hydrology-fluid-surface-v0`  
**Current stage:** `G6 Full Acceptance — SOURCE_ACCEPTED`  
**Next:** `G7 Semantic Field Fabric`

## Решение P0-аудита

G6 не нарушает GLOBAL-P0 runtime/ownership boundaries. Исправление после аудита относится только к актуальности branch-local ledger и плану следующих стадий.

```text
P0 architecture/runtime alignment        PASS
P0-1 global revision/config              PASS
P0-2 spatial identity separation         PASS
P0-3 material ontology compatibility     PASS_WITH_EXPLICIT_BRIDGE_REQUIRED
P0-4 cross-domain transaction boundary   PASS
P0-5 NX7/NX8/NX9 ownership               PASS
Geo/Matter boundary                      PASS
Representation boundary                  PASS
Status dimensions                        PASS
```

## Canonical boundary G6

```text
G5 WorldFeature / FeatureId
        ↓
G6.1 canonical fluid geography
        ↓
G6.3 read-only WaterSurfaceQuery resolver
        ↓
G6.4 derived adaptive presentation
```

Обязательные инварианты:

```text
FeatureId != SurfaceCellKey
FluidRegionId != SurfaceCellKey
FluidRegionId != AuthorityRegionId
FluidRegionId != InterestRegionId
LOD != fluid identity
terrain mesh != canonical G3 height field
renderer != authority
renderer != persistence
G5 River FeatureId remains semantic owner
```

`FluidRegionId` выводится из canonical fluid inputs и не зависит от cell/LOD/camera/renderer/network/authority routing. `WaterSurfaceResolverV1` является read-only domain resolver и не владеет transport, authority, persistence или universal spatial addressing.

## P0-3 Material Ontology bridge

Текущие G6 идентификаторы `fluid-type/*` остаются допустимым domain vocabulary, но не объявляются будущей общей материальной истиной.

Обязательная граница для дальнейшей разработки:

```text
FluidRegionId       = geographic/fluid-region identity
FluidTypeId         = fluid-domain semantic class
MaterialDefinitionId = future shared P0 material identity

FluidTypeId != MaterialDefinitionId
```

Когда P0 Unified Material Ontology будет материализован, Fluid domain должен подключиться через projection/reference, а не переименовывать существующую river/fluid geography identity.

Целевая эволюция без слома G6 identity:

```text
FluidSurfaceDescriptor
    ├── fluid_type_id
    └── material_definition_id / composition_ref   # future P0 projection
```

## G7 forbidden ownership overrides

G7 Semantic Field Fabric строится поверх G3/G5/G6 semantics, но не имеет права становиться новой глобальной foundation для соседних программ.

Запрещено:

```text
G7 owns WorldAddress             NO
G7 owns universal WorldQuery     NO
G7 owns authority routing        NO
G7 owns interest management      NO
G7 owns persistence/durability   NO
G7 owns network replication      NO
G7 owns material ontology        NO
G7 field identity depends on LOD NO
G7 field identity depends on cell NO
```

Допустимая композиция:

```text
future WorldAddress / WorldQuery Fabric
                ↓ adapter
         SemanticFieldQuery
                ↓
      G3 / G5 / G6 providers
```

`SemanticFieldQuery` в G7 — domain query contract, не замена будущему общему World Query Fabric.

## Geo/Matter и representation boundary

G8–G13 продолжают ту же архитектуру:

```text
procedural Geo baseline
        +
authoritative sparse Matter mutations
        ↓
current world truth
```

Поэтому:

- G8 владеет procedural geomorphology baseline, но не persistent excavation;
- G9 использует shared MaterialDefinitionId после P0 material bridge и не создаёт второй material namespace;
- G10 GeoVolume/SDF не становится второй Matter implementation;
- GM означает Geo/Matter Integration;
- G12 scheduler/cache/provenance не владеет authority или persistence;
- любые G visualization/LOD/cache artifacts остаются derived representation.

## Acceptance evidence G6

```text
G6.0-G6.4 focused chain                PASS
G6.4 contracts                         PASS — 158 assertions
Adaptive Macro Surface                 PASS
MW10 lock release retry                PASS — 12 assertions
RUN_WORLD_REGRESSION_TESTS.ps1         PASS
main_scene_cli_all                      PASS — 6 / 0 fail
PowerShell Fix3 parser                  PASS
git status --porcelain                 EMPTY
git diff --check G5...G6               PASS
working tree                            CLEAN
```

Final architecture status:

```text
SOURCE_ACCEPTED        YES
MAIN_INTEGRATED        NO
COMPOSITION_VERIFIED   NO
PRODUCTION_READY       NO
```

Подробный следующий roadmap: `docs/procedural/G7_G13_P0_ALIGNED_ROADMAP_RU.md`.
