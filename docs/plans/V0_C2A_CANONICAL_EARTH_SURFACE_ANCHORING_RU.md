# V0-C2A — Canonical Earth Surface Anchoring

**Status:** IMPLEMENTATION CHECKPOINT / REQUIRED BEFORE V0-C3  
**Date:** 2026-08-14  
**Parent roadmap:** `V0_INTEGRATION_CHECKPOINT_ROADMAP_RU.md`

## 1. Причина checkpoint

V0-C1 и V0-C2 доказали, что canonical Construction build flow, C22/C24 proxy mesh и collision могут собирать MVP outpost. Ручной runtime test выявил пространственный integration defect:

- при удалении игрока фундамент визуально погружался в поверхность;
- при прыжке конструкция двигалась вместе с высотой наблюдателя;
- при detached spectator terrain удалялся, а construct оставался около observer;
- topology, build stages и proxy geometry при этом оставались корректными.

Причина: Earth Construction presentation использовала observer planar position и observer tangent basis как источник transform самого construct.

Это нарушает базовые разделения проекта:

```text
canonical state != presentation
world location != camera/observer state
Construction topology != world placement
```

## 2. Архитектурное решение

Construction не получает новую систему мировых координат.

Целевая модель:

```text
root Item
  -> WORLD(entity_id)
  -> WorldEntity spatial state
  -> SpatialRef(frame_id = earth.fixed, position, rotation)

ConstructAggregate
  -> local parts / bonds / sections

C22/C24
  -> derived mesh/collision only

Presentation
  -> project(canonical SpatialRef, current render origin)
  -> local Node3D Transform3D
```

Observer movement никогда не мутирует canonical anchor.

## 3. Bounded V0 implementation

Полная Item Graph -> WORLD entity -> SpatialRef интеграция относится к дальнейшему world-item convergence. V0-C2A не создаёт второй authority и не переносит spatial truth внутрь Construction.

Для текущего fixed MVP outpost используется bounded bootstrap:

1. canonical M3 outpost planar location остаётся фиксированной: `(0, -12)`;
2. она один раз детерминированно отображается на procedural Earth surface;
3. root construct anchor кэшируется как Earth-fixed `Transform3D`;
4. foundation center поднимается на `0.25 m`, то есть на половину толщины canonical foundation bbox `0.5 m`;
5. каждый render update вычисляет только derived transform относительно `EarthWorld.render_origin_world` и текущего Earth-fixed -> observer basis;
6. C22/C24 получает только этот derived transform;
7. никакое движение, прыжок или spectator translation не переписывает anchor.

Этот bootstrap должен позднее быть заменён получением того же anchor из canonical `SpatialRef`, без изменения projector/presentation API.

## 4. Новый presentation boundary

Добавляется pure helper:

```text
EarthSurfaceRenderProjector

create_surface_anchor(surface_point, clearance)
    -> stable Earth-fixed Transform3D

project_anchor(canonical_anchor, render_origin, frame_basis)
    -> derived local Transform3D
```

Helper:

- не хранит состояние;
- не знает Item Graph;
- не знает Construction authority;
- не знает network authority;
- не получает camera authority;
- только выполняет преобразование координат presentation layer.

## 5. Запрещённые обходные решения

Не допускаются:

```text
house_y -= player_jump
house_position = observer_position + fixed_offset
special spectator correction
ConstructionSnapshot.x/y/z как новая world truth
eye_height как world placement construct
client-private persistent anchor
```

Если world placement становится изменяемым/персистентным, owner должен быть canonical spatial/world layer через `SpatialRef`.

## 6. Acceptance

V0-C2A PASS требует:

1. foundation стоит на terrain support surface;
2. player проходит минимум 50 m — construct остаётся в той же мировой точке;
3. player прыгает — terrain и construct сохраняют взаимное положение;
4. detached spectator отлетает на 100 m и 1 km — terrain и construct удаляются согласованно;
5. возврат из spectator возвращает тот же construct в ту же точку;
6. A и B видят один outpost в одной Earth-fixed позиции;
7. C22 detail/LOD rebuild не меняет anchor;
8. canonical Construction checksum/revision не зависит от observer movement;
9. derived presentation не содержит direct authority references.

## 7. Automated invariant

`tests/runtime/test_v0_c2a_earth_surface_render_projector.gd` проверяет:

- surface-normal orientation;
- foundation half-height support offset;
- observer-relative walking delta;
- jump delta;
- spectator delta;
- reference-frame basis conversion;
- неизменность canonical anchor origin/basis.

Первый execution evidence на Godot `4.7.1.stable.double.custom_build.a13da4feb`:

```text
V0-C2A Earth surface render projector: PASS (10 assertions)
```

## 8. Routing после PASS

```text
V0-C1  Canonical Outpost Build Flow
  -> V0-C2  C22/C24 presentation
  -> V0-C2A Earth-fixed surface anchoring
  -> V0-C3  Inventory <-> Construction resources
  -> V0-R1  reconnect same live world
```

V0-C3 не должен начинаться с закреплением observer-owned construct placement.
