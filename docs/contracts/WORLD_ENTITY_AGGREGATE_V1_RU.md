# Контракт WorldEntityAggregate v1

## Назначение

`WorldEntityAggregate` — единственный канонический владелец пространственного и
физического состояния предмета, находящегося в relation `WORLD`.

Предметный граф хранит идентичность, количество, definition и отношения. Godot
`RigidBody3D` является временным physics/presentation adapter и не является
источником истины.

## Схема

```text
planet_simulator.world_entity_aggregate.v1
```

Обязательные поля:

```text
entity_id
entity_type = world_item
item_instance_id
spatial_ref
partition_address
physics_state
domain_components
authority_owner_id
authority_epoch
state_revision
last_simulation_tick
lifecycle_state
created_at_utc
updated_at_utc
```

Snapshot использует точный набор полей. Неизвестные и отсутствующие поля,
неверные JSON-типы, unsafe integers, NaN/Infinity и неединичный quaternion
отклоняются до изменения live store.

## Инварианты

1. Для каждого WORLD-item существует ровно один aggregate.
2. `item_instance_id` и `entity_id` уникальны.
3. Relation WORLD содержит только:

```json
{
  "kind": "WORLD",
  "entity_id": "entity/item/..."
}
```

4. Relation не содержит `spatial_ref`, transform или velocity.
5. `authority_epoch` положителен и только увеличивается.
6. `state_revision` не уменьшается.
7. Spatial write разрешён только в lifecycle `ACTIVE`.
8. Physics capture изменяет aggregate revision, но не item revision.
9. CONTAINER/ATTACHMENT/DESTROYED item не может сохранять WORLD aggregate.
10. Quaternion хранится в единичной детерминированной форме; `q` и `-q`
    канонизируются одинаково.

## Lifecycle

```text
DORMANT → WARM → ACTIVE → UNLOADING → DORMANT
```

`DESTROYED` является терминальным состоянием entity aggregate.

Запрещённые переходы возвращают `ILLEGAL_LIFECYCLE_TRANSITION` и не меняют
revision.

## Authority и revisions

Команда spatial/domain update может передавать:

```text
expected_revision
expected_authority_epoch
```

Ошибки:

```text
REVISION_CONFLICT
STALE_AUTHORITY_EPOCH
ENTITY_NOT_ACTIVE
```

Authority transfer требует `next_epoch > authority_epoch` и увеличивает
`state_revision` ровно один раз.

## Persistence

Store schema:

```text
planet_simulator.world_entity_store.v1
```

Item graph schema:

```text
planet_simulator.item_graph.v2
```

Загрузка выполняется через staged store. Commit разрешён только после проверки:

- точной схемы всех aggregates;
- отсутствия duplicate entity/item binding;
- совпадения `entity_count`;
- отсутствия orphan aggregates;
- совпадения WORLD relation и aggregate item binding;
- полной валидности Item/Container/Attachment graph.

При любой ошибке live domain остаётся неизменным.

## Legacy migration

`planet_simulator.item_graph.v1` и старые WORLD relations со встроенным
`SpatialRef` читаются, но после загрузки преобразуются:

```text
legacy WORLD relation
→ WorldEntityAggregate
→ relation {kind, entity_id}
→ сохранение уже как item_graph.v2
```

## Presentation adapter

При создании physics body:

```text
WorldEntityAggregate → RigidBody3D
```

При сохранении или явном capture:

```text
RigidBody3D → WorldEntityAggregate
```

Повторная синхронизация не имеет права переигрывать старую позу поверх уже
живого physics body, пока aggregate revision не изменился.

## Ограничения v1

- `partition_address` пока может быть пустым в локальных scenario worlds;
- aggregate WORLD-item пока не объединён с общим `EntityRegistry` в один store;
- physics capture выполняется адаптером текущего процесса;
- сетевой transport и authority handoff появятся после завершения N0/N1.
