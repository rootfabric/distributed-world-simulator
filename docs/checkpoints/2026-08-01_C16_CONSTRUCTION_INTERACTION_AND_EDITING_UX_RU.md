# C16 — Construction Interaction and Editing UX

**Статус:** ACCEPTED
**База:** принятый C15
**Коммит:** `a4376cd`
**Рекомендуемая ветка:** `feature/c16-construction-interaction-editing-ux`

## Цель

C16 добавляет первый единый graphical interaction layer поверх принятого строительного ядра. UI не получает права напрямую изменять Item Graph, `ConstructSnapshot`, C3, C9 или C11 stores.

```text
mouse / keyboard / gamepad intent
        ↓
placement, gizmo and overlay models
        ↓
checksum-pinned C12 command
        ↓
C12 permission/session/precondition validation
        ↓
authoritative C3/C9/C11 process
        ↓
replicated result and visible rejection reason
```

## Semantic snapping

`ConstructionSnapTarget` описывает не произвольную точку mesh, а semantic target:

- `SURFACE`;
- `PORT`;
- `GRID`;
- `FREE`.

Target закрепляет construct, part, port, position, normal, up axis, совместимые placement kinds, priority и checksum. Resolver фильтрует targets по типу и semantic compatibility, затем детерминированно выбирает кандидат по priority, distance и target ID.

Grid snapping применяется после выбора semantic target. Результат содержит target checksum, world position, normalized quaternion, score и diagnostics. Если совместимого target нет, возвращается валидный negative solution, а не неявный fallback commit.

## Placement ghost

`ConstructionPlacementGhost` является чистым `Node3D` presentation-объектом:

- использует прозрачный `BoxMesh` для vertical slice;
- отображает допустимое и недопустимое состояние;
- принимает только проверенный placement solution;
- никогда не пишет transform обратно в BuildPlan или authoritative snapshot;
- может быть удалён без потери строительного состояния.

Фактическая стадия строительства отправляется через C12 после того, как пользователь подтвердил корректный plan/ghost workflow.

## C11 geometry gizmo

`ConstructionGeometryGizmo` строит `Marker3D` handles из authoritative `LocalGeometryState`. Drag не меняет состояние напрямую, а формирует обычный C11 `MOVE_CONTROL_POINT` operation.

Поддержаны UI-side ограничения:

- axis mask;
- grid step;
- выбор существующей semantic control point;
- deterministic operation ID и sequence.

Сервер повторно проверяет полный C11 request и constraints. UI-side snapping является удобством, а не authority.

## Material and repair overlays

`ConstructionMaterialOverlayModel` компилирует единый view для:

- C3 build stage material allocations;
- C9 repair ghost part states.

Overlay содержит точные item IDs, required quantity, stage, availability, ready flag и summary missing count. Подмена summary отклоняется validator.

## Multiplayer command boundary

`ConstructionInteractionCommandAdapter` зависит только от объекта с методом `submit()`. Он формирует строгие C12 commands для:

- `BUILD_STAGE`;
- `EDIT_GEOMETRY`;
- `APPLY_REPAIR`.

Adapter не принимает ссылки на C3/C9/C11 process и не может вызвать domain mutation в обход gateway. UI получает как accepted result, так и точный authoritative error code для отображения пользователю.

## Headless UI vertical slice

Проверены реальные Godot nodes:

- `ConstructionInteractionController`;
- `ConstructionPlacementGhost`;
- `MeshInstance3D` и `BoxMesh` ghost;
- `ConstructionGeometryGizmo`;
- `Marker3D` handles;
- `ConstructionInteractionOverlay`;
- `Label` и `ProgressBar` состояния.

Проверены mode transitions `IDLE/PLACE/EDIT/REPAIR/INSPECT`, скрытие неактивных инструментов и отказ placement update вне PLACE mode.

## Focused acceptance

```text
C16 contracts:    PASS — 39 assertions
C16 integration:  PASS — 32 assertions
C16 total:        PASS — 71 assertions
Editor parse:     PASS
```

Полная внешняя приёмка подтверждена: C2B 258, C9 204, Network N0–M4 PASS, world 133/133 tests и 136 steps, main-scene CLI 6/6.

Ожидаемый world profile:

```text
133/133 tests
136 steps
```

## Ограничения C16 vertical slice

- реальный mouse raycast и camera input остаются интеграцией игрового клиента;
- multi-user cursors и advisory locks не являются authority и переносятся в расширение C16/C17;
- placement transform пока используется как preview и не создаёт новый mutation path;
- сложная ghost geometry будет переиспользовать C13 runtime descriptors;
- fabrication queue panel пока представлен material/status contract, а не финальным художественным UI.
