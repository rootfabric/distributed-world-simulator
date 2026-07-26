# Контракт `planet_simulator.entity.v2`

## Назначение

Entity v2 отделяет coordinate-space состояние, partition domain и server
authority. Это позволяет одной сущности менять сервер-владельца без смены её
физической идентичности или искусственного переписывания координат планеты.

## Основные поля

```text
entity_id
entity_type
spatial_ref: planet_simulator.spatial_ref.v1
partition_address: planet_simulator.partition_address.v2
authority_owner_id
authority_epoch
state_revision
last_simulation_tick
components
```

`world_position`, `zone_id`, `chunk_id` и `revision` временно сохраняются как
совместимые проекции для существующего лунного кода.

`spatial_ref.universe_id/instance_id` должны совпадать с partition runtime.
`spatial_ref.space_id` совпадать не обязан: например координатный домен `sol`
может размещаться в partition domain `moon`.

## Authority fencing

Изменяющая команда принимается только при совпадении:

```text
command.authority_owner_id == entity.authority_owner_id
command.authority_epoch == entity.authority_epoch
```

После handoff новый owner использует больший `authority_epoch`. Поздняя команда
старого owner отвергается независимо от численного `state_revision`.

## Атомарная пространственная команда

Одна логическая команда одновременно может изменить:

- position;
- orientation;
- linear/angular velocity;
- reference frame;
- zone/chunk address.

Вся операция увеличивает `state_revision` ровно один раз. Partition resolver
отвергает координаты из другого universe instance или из неверного
`partition_frame_id`.

## Различие lifecycle

```text
delete_authoritative_entity
    сущность перестала существовать

evict_local_record
    локальная запись выгружена, сущность продолжает существовать в store

evict_replica
    удалена только локальная replica

future release_authority
    владение передано другому authority
```

Удаление и выгрузка replica не должны использовать один неразличимый контракт.

## Миграция `lunar.entity.v1`

Legacy позиция считается `main/persistent/sol + body/moon/fixed`, старый
`revision` становится `state_revision`, а legacy chunk ID преобразуется в
`PartitionAddress v2`.
