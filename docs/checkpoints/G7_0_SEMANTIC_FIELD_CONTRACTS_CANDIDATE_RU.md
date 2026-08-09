# G7.0 Semantic Field Contracts + Registry Vocabulary — IMPLEMENTED CANDIDATE

**Дата:** 2026-08-09
**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Base:** `feature/g6-hydrology-fluid-surface-v0 @ 303d6830593cd3b4fbb20641daa90d6bef5d7ada`
**Branch:** `feature/g7-semantic-field-fabric`

## Цель

G7.0 вводит typed semantic-field boundary поверх уже существующего G0 Geo field payload, не заменяя `GeoKernel`, `GeoFieldBundle` или `GeoSample`.

```text
G0 GeoFieldBundle / GeoSample
    = existing provider execution payload

G7 Semantic Field contracts
    = typed semantic identity / descriptor / provenance boundary
```

То есть G7.0 не создаёт второй procedural kernel.

## Новые contracts

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

`SemanticFieldId` сохраняет уже используемый namespace `geo/<semantic-name>`, поэтому принятые поля не получают новую identity:

```text
geo/base-surface-height-m
geo/macro-surface-height-m
geo/surface-height-m
```

Начальный typed vocabulary поддерживает scalar float/int, bool, canonical id и vector3. Начальный semantic domain намеренно ограничен body-surface-point/body-volume-point и не является WorldAddress foundation.

## Registry Vocabulary v1

Upstream accepted field identity:

```text
geo/base-surface-height-m
geo/macro-surface-height-m
geo/surface-height-m
```

Vocabulary-only G7.0 entries:

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

`VOCABULARY_ONLY_G7_0` означает только зарезервированный typed descriptor. G7.0 не утверждает, что provider для такого поля уже существует.

## Provenance

`SemanticFieldProvenance` хранит producer/version, source field ids, generic canonical source refs, configuration hash и metadata. Конкретные G3/G5/G6 adapters остаются G7.1.

## P0 boundaries

```text
SemanticFieldId != SurfaceCellKey
SemanticFieldId != LOD
SemanticFieldId != AuthorityRegionId
SemanticFieldId != InterestRegionId
SemanticFieldQuery != universal WorldQuery Fabric
G7 != Material Ontology
G7 != scheduler/cache owner
G7 != persistence owner
G7 != network replication owner
```

В exact query schema нет `surface_cell_key`, `lod`, authority/interest routing, camera/renderer/network state. `MaterialDefinitionId` намеренно не введён ни в registry, ни в core contracts; P0-3 bridge остаётся отдельным будущим gate.

## Compatibility с G0/G3/G4

G7.0 сохраняет byte-level string identity existing Geo fields. Старый `GeoFieldBundle` продолжает принимать эти keys без адаптации.

```text
G7 registry describes existing field identity
G7 registry does not rename existing field identity
G7 registry does not replace provider execution DTO
```

## Assistant-side exact-engine evidence

Проверен exact опубликованный runtime/test content:

```text
Godot 4.7.1.stable.double.custom_build.a13da4feb
headless editor import / parse       PASS
G7.0 Semantic Field Contracts        PASS — 180 assertions
script parse/load errors             0
registry blob                        9e92aa345f02856cf906e81e2fa6e1746955199b
test blob                            8dea46beea10efda51439d17737c9be8ac7811e2
published tested runtime head         1f23befb793b74d951460ecb52a4747f5e73a710
```

Это isolated exact-engine verification новых contracts. Оно не заменяет полный Windows checkout gate.

## Full acceptance gate

Полный runner теперь сам проверяет current G6 ancestry, GLOBAL-P0 byte-alignment, allowlist changed-files, focused contracts, full world/core regression и финальную repository hygiene:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G7_0_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

Перед `ACCEPTED` нужны финальные markers:

```text
G7.0 FULL ACCEPTANCE: PASS
G6 SOURCE_ACCEPTED ancestor: PASS
G7.0 contract-first scope: PASS
G7.0 focused contracts: PASS
World/core regression: PASS
Working tree: CLEAN
```

## Следующий checkpoint после acceptance

```text
G7.1 — G3/G5/G6 Upstream Semantic Field Adapters
```

Он должен адаптировать принятые источники без создания новой river/feature/fluid identity.
