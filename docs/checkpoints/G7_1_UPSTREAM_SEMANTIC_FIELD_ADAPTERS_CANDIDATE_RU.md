# G7.1 G3/G5/G6 Upstream Semantic Field Adapters — FIX1 IMPLEMENTED CANDIDATE

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

## Первый реальный Windows gate

Первый full-checkout запуск корректно остановился внутри focused G7.1 suite:

```text
assertions reached     54
failures               6
world regression       NOT RUN
full gate              FAIL FAST
```

Это не изменение G6/G5 runtime и не P0 regression. Initial G7.1 candidate неверно повторил две формы accepted upstream API.

## Fix1 — G3 provider envelope

Accepted `GeoProvider.success(values)` имеет форму:

```text
{
  success: true,
  details: {
    values: {
      geo/surface-height-m: ...
    }
  }
}
```

Initial adapter ошибочно читал:

```text
provider_result.details[geo/surface-height-m]
```

Fix1 читает canonical path:

```text
provider_result.details.values[geo/surface-height-m]
```

Это объясняет пять ранних G3 failures: adapter возвращал failure; subsequent assertions получали пустые handled fields/sample/provenance, после чего старый test обращался к `source_refs[0]` и прекращал оставшуюся часть G3 subtest.

Test теперь отдельно проверяет наличие canonical `details.values` и guard-ит source ref lookup, чтобы один root cause больше не создавал cascade/noisy runtime error.

## G5 adapter

`semantic-adapter/g5-feature-v1` реализует:

```text
geo/valley-influence
```

Политика:

```text
FEATURE_BOUNDS_FALLOFF_V1
```

Это deterministic feature-derived proxy внутри accepted G5 `FeatureBounds`, а не geomorphology. G8 по-прежнему владеет valley incision, banks, floodplain и terrain shaping.

При совпадении provenance сохраняет исходный G5 `FeatureId` и checksum. Вне valley bounds значение равно `0`, и adapter не изобретает фиктивный FeatureId.

## Fix1 — G6 channel width

Accepted `WaterSurfaceSample` использует canonical key:

```text
channel_width_m
```

Initial G7.1 ошибочно использовал:

```text
width_m
```

Поэтому видимая шестая ошибка была:

```text
FAIL: river-width projects G6 channel width
```

Fix1 проецирует:

```text
geo/river-distance-m          <- distance_to_centerline_m
geo/river-width-m             <- channel_width_m
geo/fluid-surface-distance-m  <- distance_to_surface_m
```

Test теперь отдельно доказывает `channel_width_m` и отсутствие stale `width_m` alias.

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

## Current Fix1 blobs

```text
G3 adapter  c728cfed5a2b3dd55d23b81b250177af19746623
G5 adapter  39ef95704cdf516b10146d2fa79b0d80bf173492
G6 adapter  437d82b7f056648045fff08f1daa57968331104c
G7.1 test   1af618356b700e5c87a55b42daa05d35b267014e
```

The pre-Fix1 assistant stub smoke is superseded and must not be used as acceptance evidence: its fake upstream results were too permissive and did not reproduce `details.values` / `channel_width_m` exactly.

## Registry

Adapter-backed:

```text
geo/valley-influence
geo/river-distance-m
geo/river-width-m
geo/fluid-surface-distance-m
```

Vocabulary-only remains:

```text
geo/slope
geo/curvature
geo/drainage-potential
geo/continentalness
geo/temperature-baseline
geo/moisture-baseline
```

`geo/surface-height-m` already had accepted upstream identity and has an explicit G3 adapter.

## G7.0 forward compatibility

G7.0 keeps all 13 identity/type contracts. Its regression assertion now permits the planned availability transition only for G7.1 adapter fields:

```text
VOCABULARY_ONLY_G7_0 -> ADAPTER_AVAILABLE_G7_1
```

No field identity changed.

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

Especially:

```text
Semantic sample provenance references FeatureId / FluidRegionId
Semantic sample does not replace FeatureId / FluidRegionId
```

## Acceptance

Strengthened focused suite should now complete all paths and end with:

```text
G7.1 Upstream Semantic Field Adapters: 59 assertions, 0 failures
```

Focused command:

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_G7_1_UPSTREAM_SEMANTIC_FIELD_ADAPTERS_TESTS.ps1 -GodotPath $Godot
```

Full acceptance after focused PASS:

```powershell
.\RUN_G7_1_FULL_ACCEPTANCE.ps1 -GodotPath $Godot
```

Full runner additionally checks strict G7.1 changed-file allowlist, current G6 ancestry, G7.0 accepted ancestry, GLOBAL-P0 alignment, full world/core regression and final hygiene.

## Следующий checkpoint после acceptance

```text
G7.2 — Composition / Provenance
```

G7.2 объединит partial samples into deterministic semantic bundle без scheduler/cache ownership.
