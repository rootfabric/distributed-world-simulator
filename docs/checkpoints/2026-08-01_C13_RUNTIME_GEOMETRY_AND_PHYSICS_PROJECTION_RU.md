# C13 — Runtime Geometry and Physics Projection

**Статус:** IMPLEMENTED CANDIDATE
**Рекомендуемая ветка:** `feature/c13-runtime-geometry-physics-projection`
**База:** принятый C12 поверх C11 `6d26f69`

## Цель

Создать удаляемую и полностью восстанавливаемую Godot-проекцию строительного домена, не превращая mesh, collision или physics state в источник истины.

```text
ConstructSnapshot + ItemProjection + C6/C7 profiles
        ↓
RuntimeProjectionRequest
        ↓
RuntimeConstructDescriptor
        ↓
MeshInstance3D / CollisionShape3D
StaticBody3D / RigidBody3D
```

## Реализовано

- строгие runtime request/part/opening/construct DTO с checksum;
- geometry source precedence: C11 local path → C10 geometry → semantic fallback;
- BoxMesh/BoxShape для beam, panel, wall и generic parts;
- CylinderMesh/CylinderShape для pipe, cable и wheels;
- segment mesh/collision для C11 control-point paths;
- прямое подключение CollisionShape3D к PhysicsBody3D;
- StaticBody3D для стационарных constructs;
- RigidBody3D и mass/freeze для C6 mobile constructs;
- C7 door state projection в transform closure part;
- NavigationLink3D и interaction anchor для runtime openings;
- incremental rebuild по part source checksum;
- authoritative world synchronization для C9 split/removal;
- descriptor store, persistence, stale и same-revision rejection;
- полная очистка SceneTree projection и deterministic rebuild.

## Инварианты

1. Node, Resource, RID, Transform3D и Shape3D не входят в domain DTO.
2. Presentation не изменяет ItemProjection, PartRecord или ConstructSnapshot.
3. Descriptor pin-ит construct checksum и revision.
4. Unchanged part сохраняет runtime node identity.
5. Destroyed part не видим и не участвует в collision.
6. Один item identity не может одновременно принадлежать двум runtime constructs.
7. Потеря runtime cache не означает потерю мира.

## Focused-профиль

```text
C13 contracts:    PASS — 58 assertions
C13 integration:  PASS — 66 assertions
C13 total:        PASS — 124 assertions
Godot editor:     PASS
```

Проверены реальные Godot-классы и resources в headless SceneTree, partial rebuild, C11 path, C7 door, navigation link/interaction anchor, C6 rigid body, C9 split и cache recovery.

## Compatibility

Локально повторно пройдены C1–C8 и C10–C12. C9 focused, C2B, Network N0–M4, полный world regression и main-scene CLI требуют полного production M0/item-domain дерева и остаются внешним gate.

Ожидаемая внешняя приёмка:

```text
C1–C12:            PASS
C13:               PASS — 124 assertions
C2B:               PASS — 258 assertions
Network N0–M4:     PASS
World regression:  PASS — 127/127 тестов, 130 шагов
Main-scene CLI:    PASS — 6/6
git diff --check:  PASS
```
