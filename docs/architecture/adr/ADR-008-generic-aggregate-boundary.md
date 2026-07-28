# ADR-008: Generic aggregate boundary без превращения WorldEntityAggregate в god object

- Статус: принято в A0
- Дата: 2026-07-29

## Контекст

Текущий `WorldEntityAggregate` тесно связан с Item Registry, WORLD relation и item identity. Population fields, environment cells и processes имеют другую spatial/state semantics.

## Решение

Сохранить текущий aggregate как item-backed implementation. Ввести общий descriptor и adapter contract:

```text
AggregateDescriptor
AggregateAdapterPort
AggregateSnapshotEnvelope
AggregateDeltaEnvelope
```

Поддерживать отдельные kinds:

```text
WORLD_ITEM
INDIVIDUAL_ORGANISM
POPULATION_FIELD
ENVIRONMENT_CELL
COMPOUND_STRUCTURE
PROCESS
```

`EntitySnapshotEnvelope v1` не изменять. Для неточечных aggregates использовать отдельный aggregate envelope со `spatial_scope`.

## Последствия

- существующий item vertical slice остаётся стабильным;
- новые aggregate kinds имеют собственные schemas;
- handoff/directory/persistence позднее работают через adapters;
- требуется registry validators по kind/schema.

## Запрещённый обход

Нельзя выдавать полю фиктивный `item_instance_id` или физическое положение только ради совместимости с item envelope.
