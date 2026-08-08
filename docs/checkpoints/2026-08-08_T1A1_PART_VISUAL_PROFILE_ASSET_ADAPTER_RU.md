# T1A.1 — Part Visual Profile / Asset Adapter

**Дата:** 2026-08-08
**Ветка:** `feature/t1-complex-construct-demo-lab`
**Статус:** `IMPLEMENTED CANDIDATE`
**Global revision:** `GLOBAL-P0-2026-08-08-R1`
**Base head:** `b92cc1be4f7d0dfd268ed294928f57706b489268`

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
- material family;
- bounds/pivot/grid footprint;
- collision presentation policy;
- batching policy;
- independent NEAR/MID/FAR source descriptors;
- deterministic checksum.

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

`T1ComplexConstructDemo` теперь умеет строить presentation plan и публикует diagnostic metadata для catalog hash, presentation checksum и detail mode, не меняя T1A.0 fixture API.

## Почему это важно для станций

T2 может позже маршрутизировать один и тот же canonical part в разные backend:

```text
near interactive object
mid merged/static batch
far C22/C24 compiled proxy
none/dormant
```

Asset pack можно менять независимо от domain identity. Это позволяет подключать Quaternius/Sci-Fi assets и более сложные mesh compiler/instance backends без переписывания Construction semantics.

## Exact-engine isolated validation

Доступный Linux double build:

```text
Godot Engine v4.7.1.stable.double.custom_build.a13da4feb
editor import / parse                       PASS
T1A.1 part visual adapter                  PASS — 67 assertions
T1 demo scene adapter probe                PASS
```

Во время первого probe обнаружена JSON numeric normalization issue для integer-like fields/ranges. Исправлено до publication: JSON numeric values принимаются только если они конечные и целочисленные, затем canonical checksum использует integer normalization.

Это isolated contract harness, а не полный checkout regression.

## Windows acceptance gate

```powershell
$Godot = "C:\Godot\godot\bin\godot.windows.editor.double.x86_64.console.exe"
.\RUN_T1A1_PART_VISUAL_ADAPTER_TESTS.ps1 -GodotPath $Godot
```

Runner выполняет:

```text
editor import
T1A.0 dependency regression
T1A.1 visual adapter acceptance
```

После focused PASS требуется обычный full project regression перед `ACCEPTED`.

## Решение

```text
checkpoint: T1A1_PART_VISUAL_PROFILE_ASSET_ADAPTER
decision:   IMPLEMENTED_CANDIDATE
next:       T1A.2 D0 Authoritative Outpost Builder
```
