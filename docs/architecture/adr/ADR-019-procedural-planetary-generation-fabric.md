# ADR-019 — Procedural Planetary Generation Fabric

**Статус:** Proposed / experimental branch decision.
**Дата:** 2026-08-08.
**Ветка:** `feature/g0-procedural-planetary-generation-lab`.

## Контекст

Проекту требуется процедурно создавать разные типы планет и малых тел с существенно отличающимися условиями: землеподобные поверхности, безводные тела, ледяные миры, астероиды, реки, каньоны, скалы, пещеры и в будущем изменяемую Matter-геометрию.

Монолитный terrain generator создаёт несколько критических проблем:

- concrete algorithm начинает владеть streaming, mesh и collision;
- geography зависит от chunk lifecycle;
- смена генератора ломает downstream systems;
- LOD начинает создавать разные версии мира;
- caves/overhangs плохо совместимы с heightfield-only truth;
- high-resolution detail невозможно независимо развивать и тестировать;
- persistent Matter deltas становятся опасно привязаны к implementation details старого generator.

## Решение

Принять `Procedural Planetary Generation Fabric` как layered provider architecture.

Основные решения:

1. `GeoKernel` является чистым композитором versioned providers.
2. Конкретная планета задаётся `PlanetRecipe`, а не planet-specific branches в core.
3. Body-fixed double-precision coordinate space является canonical query space.
4. Geodetic coordinates и local tangent frame предоставляются adapter/service layer.
5. Streaming cells адресуют representation scope, но не являются источником terrain truth.
6. Крупные geography objects существуют как stable `WorldFeature` выше chunks.
7. Связь между providers выполняется через semantic fields и versioned contracts.
8. Surface и Volume queries существуют как отдельные contracts с раннего этапа.
9. LOD меняет representation error/budget, но не semantic world identity.
10. Procedural baseline отделён от persistent Matter/Construction modifications.
11. Mesh, collision proxy, impostor и detail patch являются derived artifacts.
12. High-resolution detail generator является отдельным replaceable backend.
13. High-resolution visual detail не может молча становиться canonical topology.
14. Simulation-relevant high-resolution topology обязана быть частью GeoVolume baseline либо явно promoted в canonical feature/Matter channel.
15. Generator versions входят в provenance/cache/persistence compatibility boundaries.

## Последствия

Положительные:

- разные типы планет собираются из независимых algorithms;
- river/geology/cave/detail tracks можно вести параллельно;
- ранний prototype может быть визуально простым;
- realistic algorithms заменяют casual algorithms без переписывания ядра;
- high-resolution generator можно тестировать на recorded patch fixtures;
- architecture совместима с existing Matter и Representation LOD Fabric;
- fly-in от десятков километров до локальной пещеры использует одну world identity.

Цена:

- больше contracts и explicit versioning;
- требуется debug observability fields/features;
- необходимо строго контролировать deterministic randomness;
- provider dependency graph требует validation;
- нельзя быстро смешивать presentation hacks с canonical world state.

## Отвергнутые варианты

### Один terrain generator на планету

Отвергнут: слишком сильная связанность, дорогая смена algorithms.

### Chunk-local procedural generation

Отвергнут: риск seams, load-order dependency и отсутствия stable feature identity.

### Вся планета dense voxels

Отвергнут как обязательная architecture: слишком дорого и не нужно для большинства поверхности.

### Только heightfield

Отвергнут как canonical model: не представляет caves/overhangs/excavation topology.

### High-resolution generator как последняя фаза того же monolith

Отвергнут: блокирует parallel research и смешивает разные scale/computational concerns.

## Compatibility rule

Изменение semantic contract требует новой contract version.

Изменение algorithm output при том же semantic contract требует новой `generator_version`, если результат влияет на canonical procedural baseline.

Existing persistent deltas нельзя применять к изменившемуся baseline без explicit compatibility/migration fence.

## Проверка решения

Решение подтверждается roadmap gates G0–G16.

Ключевые доказательства:

```text
provider replacement
cross-cell river continuity
LOD semantic stability
multi-recipe planet loading
volume cave without teleport
standalone high-resolution patch fixture
Matter-compatible procedural baseline boundary
```
