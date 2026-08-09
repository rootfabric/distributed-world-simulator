# G7.2 Composition / Provenance — IMPLEMENTED CANDIDATE

**Дата:** 2026-08-10
**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Branch:** `feature/g7-semantic-field-fabric`
**G7.1 accepted baseline:** `af0898ba2f0fc03dbd0298440f302b497a5d0cad`

## Цель

G7.2 объединяет partial semantic samples из принятых G7.1 adapters в один deterministic `SemanticFieldBundle` и создаёт отдельный auditable `SemanticFieldCompositionReceipt`.

```text
G3 adapter ─┐
G5 adapter ─┼─> SemanticFieldComposerV1
G6 adapter ─┘          │
                       ├─ SemanticFieldBundle
                       └─ SemanticFieldCompositionReceipt
```

Composer не вычисляет новые значения и не переписывает upstream provenance.

## Strict composition policy

```text
semantic-composition-policy/require-complete-v1
```

Правила:

```text
missing requested field      -> REJECT
duplicate field ownership    -> REJECT
duplicate adapter            -> REJECT
unrequested contributed field-> REJECT
partial-result input order    -> NORMALIZED BY ADAPTER_ID
```

Любой requested field должен иметь ровно одного producer в конкретной композиции.

Это важнее, чем автоматически выбирать winner: silent winner policy создала бы скрытый новый ownership layer.

## Bundle

G7.2 использует уже принятый `SemanticFieldBundle` из G7.0.

Samples помещаются в bundle без пересоздания:

```text
sample checksum before compose == sample checksum inside bundle
provenance checksum before compose == provenance checksum inside bundle
```

Таким образом:

```text
FeatureId
FluidRegionId
provider identity
adapter provenance
```

остаются upstream truth.

## Composition receipt

Новый `SemanticFieldCompositionReceipt` фиксирует:

```text
composer id/version
composition policy
query checksum
bundle checksum
ordered adapter contributions
per-field sample checksum
per-field upstream provenance checksum
```

Receipt является audit/provenance artifact и не становится новым World identity.

## Determinism

Composer сортирует adapter contributions по canonical `adapter_id`.

Поэтому:

```text
compose([G3, G6])
compose([G6, G3])
```

должны давать одинаковые:

```text
bundle checksum
receipt checksum
```

при одинаковых partial samples.

## Реальные integration paths в focused test

### G3 + G5

```text
G3 CasualMacroTerrainProviderV1
  -> geo/surface-height-m

G5 WorldFeatureGraph
  -> geo/valley-influence

-> one SemanticFieldBundle
```

Проверяется сохранение G5 `FeatureId` provenance.

### G3 + G6

```text
G3
  -> geo/surface-height-m

G6 WaterSurfaceResolverV1
  -> geo/river-distance-m
  -> geo/river-width-m
  -> geo/fluid-surface-distance-m

-> one SemanticFieldBundle
```

Проверяется сохранение upstream G5 FeatureId и G6 FluidRegionId.

## P0 boundaries

```text
composer != scheduler
composer != cache
composer != WorldQuery foundation
composer != authority owner
composer != persistence owner
composer != network owner
composer != material ontology
composer != geomorphology
receipt != world identity
```

G7.2 выполняет синхронную deterministic composition только для уже полученных partial results. Execution scheduling и caching остаются будущим G12 / общим work-budget fabric.

## Validation

Focused:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G7_2_COMPOSITION_PROVENANCE_TESTS.ps1 -GodotPath $Godot
```

Full:

```powershell
.\RUN_G7_2_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

Full gate проверяет:

- G7.1 accepted ancestry;
- current G6 ancestry;
- GLOBAL-P0 alignment;
- strict G7.2 changed-file allowlist;
- G7.0 regression;
- G7.1 regression;
- G7.2 focused composition/provenance;
- full world/core regression;
- transient Windows cleanup;
- final clean tree и `git diff --check`.

## Следующий этап после acceptance

```text
G7.3 — Cross-Cell / Cross-LOD Invariance
```

G7.3 должен доказать, что semantic values/identity/provenance не меняются из-за SurfaceCell partitioning или representation LOD.
