# G7.1 G3/G5/G6 Upstream Semantic Field Adapters — IMPLEMENTED CANDIDATE

**Дата:** 2026-08-10
**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Branch:** `feature/g7-semantic-field-fabric`
**G7.0 accepted baseline:** `06466ac034a25492ef8c3ff3cfc053f536eb97b9`

## Цель

G7.1 подключает уже принятые G3/G5/G6 semantics к typed G7 contracts без переноса ownership.

```text
G3 macro surface provider
    -> G3SurfaceSemanticFieldAdapterV1

G5 WorldFeatureGraph
    -> G5FeatureSemanticFieldAdapterV1

G6 river/fluid geography
    -> G6FluidSemanticFieldAdapterV1
```

Adapters возвращают partial semantic samples. Их объединение в единый deterministic bundle остаётся G7.2.

## G3 adapter

`semantic-adapter/g3-surface-v1` проецирует accepted provider output:

```text
geo/surface-height-m
```

Значение не пересчитывается по собственной формуле G7: adapter вызывает upstream provider и оборачивает его результат в `SemanticFieldSample`.

Provenance сохраняет:

```text
provider_id
provider descriptor checksum
contract version
generator version
```

## G5 adapter

`semantic-adapter/g5-feature-v1` реализует:

```text
geo/valley-influence
```

Политика:

```text
FEATURE_BOUNDS_FALLOFF_V1
```

Это нормализованный deterministic influence внутри accepted G5 `FeatureBounds`. Он предназначен как feature-derived semantic proxy и **не является geomorphology**. G8 по-прежнему владеет valley incision, banks, floodplain и terrain shaping.

При совпадении provenance сохраняет исходный G5 `FeatureId` и checksum. Вне valley bounds значение равно `0`, и adapter не изобретает фиктивный FeatureId.

## G6 adapter

`semantic-adapter/g6-fluid-v1` использует accepted `WaterSurfaceResolverV1` и проецирует:

```text
geo/river-distance-m          <- distance_to_centerline_m
geo/river-width-m             <- channel width_m
geo/fluid-surface-distance-m  <- distance_to_surface_m
```

Provenance сохраняет canonical upstream refs:

```text
G5 source FeatureId
G6 FluidRegionId
RiverSplineId
RiverChannelProfileId
FluidSurfaceDescriptor checksum
resolver id/version
```

Adapter не создаёт собственную River identity или FluidRegion identity.

## Registry

Следующие fields переведены из vocabulary-only в:

```text
ADAPTER_AVAILABLE_G7_1
```

Поля:

```text
geo/valley-influence
geo/river-distance-m
geo/river-width-m
geo/fluid-surface-distance-m
```

Остаются vocabulary-only:

```text
geo/slope
geo/curvature
geo/drainage-potential
geo/continentalness
geo/temperature-baseline
geo/moisture-baseline
```

`geo/surface-height-m` уже имел accepted upstream identity и теперь получил explicit G3 adapter.

## P0 boundaries

```text
adapter != WorldQuery foundation
adapter != SurfaceCell / LOD identity
adapter != Authority / Interest owner
adapter != Persistence / Network owner
adapter != Material Ontology
adapter != Scheduler / Cache owner
adapter != Geomorphology
```

Особенно:

```text
Semantic sample provenance references FeatureId / FluidRegionId
Semantic sample does not replace FeatureId / FluidRegionId
```

## Tests

Focused acceptance проверяет:

- registry activation;
- G3 semantic value == direct accepted provider value;
- G5 valley center influence и zero-influence outside bounds;
- G5 provenance сохраняет FeatureId;
- G6 values == direct WaterSurfaceResolver values;
- G6 provenance сохраняет FeatureId и FluidRegionId;
- repeated adapter calls deterministic;
- adapter не выдаёт fields, которыми не владеет;
- G7.0 contracts продолжают проходить.

Focused command:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G7_1_UPSTREAM_SEMANTIC_FIELD_ADAPTERS_TESTS.ps1 -GodotPath $Godot
```

Full acceptance:

```powershell
.\RUN_G7_1_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

Full runner additionally проверяет strict G7.1 changed-file allowlist, current G6 ancestry, G7.0 accepted ancestry, GLOBAL-P0 alignment, full world/core regression и final hygiene.

## Следующий checkpoint после acceptance

```text
G7.2 — Composition / Provenance
```

G7.2 должен объединять partial samples из этих adapters в deterministic semantic bundle без создания scheduler/cache ownership.
