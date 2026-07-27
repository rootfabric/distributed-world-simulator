# Item Graph v2 — WORLD aggregate binding

## Изменение относительно v1

Item Graph v2 добавляет секцию:

```text
world_entities: planet_simulator.world_entity_store.v1
```

WORLD relation больше не владеет координатами. Она хранит ссылку на
`WorldEntityAggregate`.

## Snapshot

```text
schema: planet_simulator.item_graph.v2
schema_version: 2
items
containers
attachments
operations
world_entities
metadata
```

Все разделы загружаются в staged domain. Live domain заменяется только после
успешной проверки всего графа и aggregate bindings.

## Совместимость

Читается legacy:

```text
planet_simulator.item_graph.v1
schema_version: 1
```

Во время загрузки встроенные WORLD spatial relations мигрируют в aggregates.
Следующее сохранение выполняется только в v2.

## Fail-closed ошибки

```text
WORLD_ENTITY_NOT_FOUND
WORLD_ENTITY_ITEM_MISMATCH
ORPHAN_WORLD_ENTITY
LEGACY_WORLD_RELATION_NOT_MIGRATED
NON_WORLD_ITEM_HAS_WORLD_ENTITY
DUPLICATE_ENTITY_ID
DUPLICATE_ITEM_BINDING
INVALID_WORLD_ENTITY_SNAPSHOT
```

При ошибке исходный snapshot не перезаписывается автоматически, а live domain
не получает частично загруженные данные.
