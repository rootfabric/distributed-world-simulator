# T1A.1 — Part Visual Profile / Asset Adapter

**Дата:** 2026-08-08  
**Acceptance update:** 2026-08-09  
**Ветка:** `feature/t1-complex-construct-demo-lab`  
**Validation overlay:** `fix/t1-m5-convergence-finish-barrier`  
**Статус:** `SOURCE_ACCEPTED / COMPOSITION_VERIFIED`  
**Global revision:** `GLOBAL-P0-2026-08-08-R1`  
**Validated head:** `280c6e24ef5b847f27be7099140832ddd7e23a25`

## Статус в терминах P0

```text
SOURCE_ACCEPTED       = true
MAIN_INTEGRATED       = false
COMPOSITION_VERIFIED  = true
PRODUCTION_READY      = false
```

`SOURCE_ACCEPTED` означает, что T1A.1 принят в своей исходной T1-линии после exact-engine focused validation и полного Windows world regression. Это не означает, что stage уже находится в `main`, что весь T1 принят или что production budgets закрыты.

## Цель

Ввести presentation-only границу между canonical Construction identity и конкретным способом отображения детали.

```text
part / construct identity
    ↓
semantic representation class
    ↓
PartVisualProfile
    ↓
near / mid / far source
    ↓
renderer/backend
```

Замена visual asset не имеет права менять fixture/construct/item identity.

## Реализовано

Добавлены четыре базовых representation class:

```text
STRUCTURAL_CELL
STATIC_COMPLEX_MESH
INSTANCED_MESH
INTERACTIVE_FIXTURE
```

Каждый `PartVisualProfile` содержит:

- stable `visual_profile_id`;
- representation class;
- presentation `material_family`;
- bounds/pivot/grid footprint;
- collision presentation policy;
- batching policy;
- independent NEAR/MID/FAR source descriptors;
- deterministic presentation checksum.

Source kinds:

```text
NONE
BUILTIN_PRIMITIVE
RESOURCE_PATH
COMPILED_PROXY
```

Catalog не загружает mesh/resource во время contract resolution. `res://...` является presentation reference; headless authority может полностью игнорировать catalog.

## Adapter proof

`T1PartVisualAdapter` строит отдельный presentation plan для существующего T1A.0 fixture.

Ключевой инвариант:

```text
fixture checksum before visual adaptation
==
fixture checksum after visual adaptation
```

При этом NEAR/MID/FAR presentation plan checksum различается, что доказывает разделение canonical state и representation.

D0 routing:

```text
40 STRUCTURAL_CELL
 8 STATIC_COMPLEX_MESH
 8 INSTANCED_MESH
 8 INTERACTIVE_FIXTURE
= 64 parts
```

D1 использует тот же routing contract на 384 parts.

`T1ComplexConstructDemo` умеет строить presentation plan и публикует diagnostic metadata для catalog hash, presentation checksum и detail mode, не меняя T1A.0 fixture API.

## P0 alignment

T1A.1 не создаёт и не владеет ни одной новой global foundation:

```text
visual_profile_id     != canonical part identity
material_family       != MaterialDefinitionId
near/mid/far mode     != authority region
HLOD/proxy artifact   != canonical construct state
renderer backend      != persistence owner
```

Следовательно, stage не блокирует будущие P0 foundations:

- Spatial Domain Fabric будет маппить Construction scopes наружу, а не заменяться section/HLOD keys;
- Unified Material Ontology позже станет источником физических/material semantics; текущий `material_family` остаётся presentation-only;
- cross-domain consume/build/salvage операции должны идти через общий `WorldOperation / WorldTransactionPlan`, а не через локальный T1 RPC bridge;
- NX7/NX8/NX9 остаются общими authority/interest/persistence policy layers и не реализуются внутри T1A.1.

## Exact-engine focused validation

```text
Godot Engine v4.7.1.stable.double.custom_build.a13da4feb
editor import / parse                       PASS
T1A.1 part visual adapter                  PASS — 67 assertions
T1 demo scene adapter probe                PASS
```

Во время первого probe была обнаружена JSON numeric normalization issue для integer-like fields/ranges. Она была исправлена до publication: JSON numeric values принимаются только если конечные и целочисленные, затем canonical checksum использует integer normalization.

## Full Windows composition validation

На validation overlay после устранения M5/boot/MW7 regression blockers получено:

```text
World boot matrix                             PASS / exit 0
MW7 matter interest replication              PASS / 114 assertions / exit 0
RUN_WORLD_REGRESSION_TESTS.ps1                PASS
All world/core regression tests through NX4  PASS
```

Эти M5/persistence/MW7 исправления являются regression-enabling fixes соседних foundations. Они не делают T1 владельцем network, persistence или Matter semantics.

## Решение

```text
checkpoint:            T1A1_PART_VISUAL_PROFILE_ASSET_ADAPTER
SOURCE_ACCEPTED:       true
MAIN_INTEGRATED:       false
COMPOSITION_VERIFIED:  true
PRODUCTION_READY:      false
next:                  T1A.2 D0 Authoritative Outpost Builder
```

Следующий архитектурный gate в T1A.2/T1A.3: authoritative Construction state и Item integration не должны вводить private Spatial/Material/Transaction foundation.
