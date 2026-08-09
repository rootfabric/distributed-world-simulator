# G7.0 Semantic Field Contracts + Registry Vocabulary — ACCEPTED

**Дата:** 2026-08-10
**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Branch:** `feature/g7-semantic-field-fabric`
**Windows tested head:** `03d1dd1e61ba671456259ab660286d3376520f8e`

## Решение

```text
G7.0 Semantic Field Contracts          ACCEPTED
```

Приняты contracts:

```text
SemanticFieldId
SemanticFieldValueType
SemanticFieldDomain
SemanticFieldDescriptor
SemanticFieldProvenance
SemanticFieldQuery
SemanticFieldSample
SemanticFieldBundle
SemanticFieldRegistryV1
```

G7.0 остаётся typed domain boundary поверх существующего `GeoFieldBundle / GeoSample` и не является вторым procedural kernel.

## Полный Windows gate

Godot:

```text
4.7.1.stable.double.custom_build.a13da4feb
```

Финальные markers:

```text
All world/core regression tests through NX4 client prediction and reconciliation passed.
G7.0 FULL ACCEPTANCE: PASS
Global revision: GLOBAL-P0-2026-08-08-R1
G6 SOURCE_ACCEPTED ancestor: PASS
G7.0 contract-first scope: PASS
G7.0 focused contracts: PASS
World/core regression: PASS
Working tree: CLEAN
```

Дополнительные результаты конца общего regression:

```text
RL3 representation streaming processes   PASS — 37 assertions
main_scene_cli_all                        PASS — 6 / 6
```

## M4 Fix1

Первый full-run обнаружил race чтения server report в старом M4 process test. Shared fix был выполнен в upstream G6 и синхронизирован в G7.

Повторная focused Windows проверка:

```text
M4 graphical shared gameplay             PASS — 22 assertions / 0 failures
server canonical graph                   PASS
shared container replication             PASS
server/client Item Graph convergence     PASS
```

Это был test-harness defect; production Item Graph/network/G7 runtime не менялись.

## P0 boundaries

Подтверждено:

```text
SemanticFieldId != SurfaceCellKey
SemanticFieldId != LOD
SemanticFieldId != AuthorityRegionId
SemanticFieldId != InterestRegionId
SemanticFieldQuery != universal WorldQuery Fabric
G7 != Material Ontology
G7 != Authority / Interest / Persistence / Network
G7 != Scheduler / Cache owner
```

`MaterialDefinitionId` не изобретён в G7.0.

## Следующий checkpoint

```text
G7.1 — G3/G5/G6 Upstream Semantic Field Adapters
```

G7.1 должен только адаптировать accepted upstream semantics и сохранять исходные `FeatureId`, `FluidRegionId` и provider identity в provenance.
