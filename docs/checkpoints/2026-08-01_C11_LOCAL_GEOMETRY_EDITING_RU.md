# Checkpoint C11 — Local Geometry Editing

**Дата:** 2026-08-01
**Статус:** IMPLEMENTED CANDIDATE
**База:** принятый C10, C9 commit `8d8bf77`
**Рекомендуемая ветка:** `feature/c11-local-geometry-editing`

## Цель

Добавить управляемое локальное редактирование параметрических строительных элементов без перехода к произвольному mesh-authority. C11 изменяет C10 parameters и semantic control-point path, после чего тем же C10 compiler пересчитывает геометрию, массу, объём и material usage.

## Архитектурная граница

```text
GeometryEditRequest
├── member/item/construct preconditions
├── ordered operations
├── constraints
└── checksum
        ↓ deterministic edit compiler
LocalGeometryState + updated C10 member instance
        ↓ one authoritative transaction
ItemProjection + PartRecord + ConstructSnapshot
        ↓
C5 capability / C8 recipe / renderer / collision rebuild
```

Mesh, collision, tessellation и editor gizmo остаются производными. Авторитетными являются строгие DTO запроса, локального geometry state, C10 instance, Item Graph projection и `ConstructSnapshot`.

## Операции

Поддержаны:

- `SET_PARAMETER` — изменение допустимого C10 параметра;
- `MOVE_CONTROL_POINT` — перенос существующей точки;
- `INSERT_CONTROL_POINT` — вставка точки в ordered path;
- `REMOVE_CONTROL_POINT` — удаление точки при сохранении валидного пути.

Операции упорядочены по sequence и pin-ят собственный checksum. Неизвестные поля, повторные sequence/ID и payload неправильного типа отклоняются до компиляции.

## Constraints

Поддержаны:

- `GRID_SNAP`;
- `LOCK_PARAMETER`;
- `LOCK_CONTROL_POINT`;
- `LOCK_AXES`;
- `MIN_SEGMENT_LENGTH`;
- `MAX_TOTAL_LENGTH`;
- `ORTHOGONAL_PATH`.

Constraints являются частью запроса и итогового geometry state. Поэтому replay, persistence и последующее редактирование используют те же ограничения, а не editor-only настройки.

## Semantic control-point path

`ConstructionLocalGeometryState` хранит:

```text
member checksum
edit revision
ordered control points
path length
actual local bounding box
constraints
provenance
checksum
```

Для прямого элемента начальный path выводится из `length_m`. После ломаного редактирования effective length равен длине path, а локальный bounding box — фактическому охвату control points.

## Пересчёт C10

C11 не пишет mass или material usage вручную. Edit compiler:

1. применяет операции к параметрам и control points;
2. проверяет locks, snap и геометрические ограничения;
3. выводит effective `length_m` из path;
4. вызывает принятый C10 compiler;
5. добавляет `local_geometry_edit_state` в provenance;
6. проверяет новый C10 instance целиком.

Таким образом изменение ширины, высоты или длины автоматически изменяет volume, mass, material usage и stock requirements.

## Authoritative transaction

`ConstructionGeometryEditTransactionPlanner` создаёт обычный `ConstructionItemTransactionPlan` типа `EDIT_PARAMETRIC_MEMBER`.

Одна транзакция синхронно:

- обновляет `components.parametric_member` конкретного item;
- увеличивает item revision;
- обновляет массу и metadata конкретного semantic part;
- увеличивает construct revision;
- добавляет audit record в `compiled_facets.geometry_edits`;
- записывает terminal operation result в shared ledger.

Relation, quantity, item ID, member ID и definition identity изменять запрещено.

## Replay и recovery

Exact replay определяется operation ID и request checksum:

```text
тот же operation ID + тот же request checksum
→ возвращается тот же edit record и member instance
→ adapter/history generation не меняются

тот же operation ID + другой request checksum
→ OPERATION_ID_CONFLICT
```

Если authoritative commit состоялся, но процесс упал до записи history, replay восстанавливает record из `ConstructSnapshot.compiled_facets.geometry_edits`, не выполняя mutation второй раз.

## Downstream recompilation

Проверено, что после edit:

- C5 parametric capability содержит актуальные mass, geometry и local geometry checksum;
- C8 fabrication recipe pin-ит новый member checksum и новый stock requirement;
- persistence сохраняет item, construct и edit history без расхождения;
- renderer/collision могут быть полностью перестроены из нового state.

## Контрольные сценарии

1. Прямая S355-балка получает новую длину и высоту; item, part и construct обновляются атомарно.
2. Ломаный path из трёх точек имеет длину 5 м и bounds `2 × 3 × 0`; масса пересчитывается по effective path length.
3. Второй edit изменяет профиль и path, сохраняя constraints и увеличивая edit revision.
4. Locked axis, слишком короткий segment и превышение maximum path length отклоняются без изменения state.
5. Injected commit failure не меняет Item Graph, construct или history.
6. Crash после commit восстанавливается exact replay без второго расхода generation.

## Focused проверки

```text
C11 contracts:    PASS — 109 assertions
C11 integration:  PASS — 90 assertions
C11 total:        PASS — 199 assertions
Editor parse:     PASS
```

Локальная совместимость должна быть подтверждена профилями C1–C10. Полный C2B, Network N0–M4, world regression и main-scene CLI повторяются на полном checkout.

## Gate принятия

```text
C1–C10 compatibility PASS
C11 focused PASS — 199 assertions
C2B PASS — 258 assertions
Network N0–M4 PASS
World regression PASS — 123/123 tests, 126 steps
Main-scene CLI PASS — 6/6
git diff --check PASS
C11 manifest unique and complete
```

## За границей C11

- произвольная destructive mesh editing;
- boolean CSG holes и material-volume subtraction;
- SDF/voxel patch storage;
- runtime graphical gizmos;
- multiplayer edit contention и permissions — C12;
- structural stress validation после edit;
- automatic stock cut/remnant optimisation.
