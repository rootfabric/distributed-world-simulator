# A1 — Generic Aggregate Foundation

**Checkpoint:** `v16.8.1-architecture-a1-generic-aggregate`
**Build ID:** `a1-generic-aggregate-foundation`
**Branch:** `feature/a1-generic-aggregate-foundation`
**Base:** `v16.8.0-runtime-h0-listen-host`

## 1. Назначение

A1 вводит общий контракт для authoritative aggregates, не превращая текущий item-backed `WorldEntityAggregate` в универсальный класс всего мира.

Новый foundation нужен для будущих:

- индивидуальных организмов;
- population fields;
- environment cells;
- сложных конструкций;
- процессов вроде пожара, реакции или эпидемии;
- spatial shards и distributed workers.

## 2. Главный инвариант

Каждый aggregate имеет строго разделённые блоки:

```text
AggregateDescriptor
├── AggregateIdentity
├── AggregateAuthorityState
├── AggregateSpatialScope
└── PartitionAddress (optional)

AggregateSnapshotEnvelope
├── descriptor
├── kind-specific state
└── checksum
```

Общий слой отвечает за identity, authority, revision, tick, spatial scope, canonical serialization и replay fencing. Kind-specific adapter отвечает за точную state schema.

## 3. Реализованные контракты

### DynamicTypeReference

Фиксирует immutable ссылку на тип:

```text
package_id
package_version
package_hash
state_schema
```

Одинаковое имя версии с разным hash является конфликтом на будущих этапах registry.

### AggregateIdentity

```text
aggregate_id
aggregate_kind
state_schema
dynamic_type_reference
```

`aggregate_kind` является строгим uppercase identifier, а `state_schema` обязан совпадать с type reference.

### AggregateAuthorityState

```text
authority_owner_id
authority_epoch
state_revision
server_tick
```

Сохраняются принятые N0/R3.1 invariants: один writer, monotonic epoch/revision/tick.

### AggregateSpatialScope

Поддержаны формы:

```text
NONE
POINT
BOUNDS
CELL
REGION
CELL_SET
```

Spatial scope не равен authority address. `POINT` использует существующий `SpatialRef`; `CELL` и `REGION` не требуют physics state или позиции сущности.

### AggregateSnapshotEnvelope

Строгий DTO:

```text
schema
protocol_version
snapshot_id
descriptor
state
checksum
```

State остаётся kind-specific, но обязан быть canonical JSON и пройти validator соответствующего adapter при экспорте, приёме snapshot и после применения delta. Неизвестный `aggregate_kind` без зарегистрированного adapter отклоняется.

### AggregateDeltaEnvelope

Delta привязан к:

```text
aggregate_id
aggregate_kind
state_schema
authority owner/epoch
base/result revision
server tick
```

Patch использует stable dictionary paths. Overlapping paths, stale revision, stale tick и checksum mismatch отклоняются.

## 4. Adapter boundary

`AggregateAdapterPort` требует:

```text
get_aggregate_kind
supports_aggregate
validate_snapshot
validate_delta
export_snapshot
export_delta
```

`AggregateAdapterRegistry`:

- регистрирует один adapter на kind;
- отклоняет конфликт kind;
- проверяет результат через строгие snapshot/delta DTO;
- не хранит domain-specific условия в generic core.

## 5. World item compatibility

`WorldItemAggregateAdapter` представляет существующий `WorldEntityAggregate` как:

```text
aggregate_kind = WORLD_ITEM
spatial_scope = POINT
partition_address = existing partition
state = {
    entity_type,
    item_instance_id,
    physics_state,
    domain_components,
    lifecycle_state,
    timestamps
}
```

Не изменены:

- `WorldEntityAggregate` validation;
- item binding;
- entity snapshot v1;
- item persistence;
- inventory relations;
- authority/revision semantics.

## 6. Generic replica store

`GenericAggregateStore` принимает только aggregate snapshots/deltas после canonical JSON round-trip.

Проверяются:

- aggregate identity conflict;
- authority owner/epoch conflict;
- stale snapshot revision;
- stale server tick;
- exact snapshot replay;
- authority-only owner transfer при повышенном epoch и неизменном state;
- запрет скрытой state mutation при той же revision;
- delta ID conflict;
- exact delta replay;
- повторная kind-specific валидация результирующего snapshot после delta;
- отсутствие mutable alias между caller и store.

Store хранит только DTO-копии и не получает ссылки на authority/domain objects.

## 7. Non-item proof

Тестовый `EnvironmentCell` aggregate использует:

```text
aggregate_kind = ENVIRONMENT_CELL
spatial_scope = CELL
state = temperature / moisture / nutrients
partition_address = optional/empty
```

Он не имеет и не требует:

```text
item_instance_id
physics_state
spatial_ref
inventory relation
WorldEntityAggregate
```

Это доказывает, что A1 является generic foundation, а не переименованным item snapshot.

## 8. Test fixtures и standalone discovery

Вспомогательные aggregate implementations для тестов размещаются под каталогом `fixtures` и могут сохранять наглядный префикс `test_*.gd`. Они не являются самостоятельными `SceneTree` entry points.

Общее правило world regression:

```text
tests/**/fixtures/test_*.gd
→ helper fixture
→ загружается основным тестом через preload
→ исключается из standalone discovery
```

Исключение основано на сегменте каталога `fixtures`, а не на двух конкретных A1-файлах. Поэтому следующие foundation-этапы могут добавлять fixtures без ручного расширения списка исключений. Самостоятельные suites по-прежнему обязаны находиться вне `fixtures` и присутствовать в явном runner manifest.

## 9. Ограничения A1

A1 не реализует:

- production `EnvironmentCellAggregate`;
- population fields;
- aggregate persistence repository;
- multi-aggregate transactions;
- PartGraph;
- spatial cell topology;
- NATS/message bus;
- compute workers;
- World Directory;
- generic handoff.

Эти элементы используют A1 как prerequisite и вводятся отдельными checkpoint.

## 10. Продолжение

A1 принят как prerequisite S0. Spatial substrate реализован в:

- [`S0_SPATIAL_SIMULATION_SUBSTRATE_RU.md`](S0_SPATIAL_SIMULATION_SUBSTRATE_RU.md);
- checkpoint `v16.8.2-simulation-s0-spatial-substrate`.

Следующий этап — `T1 Multi-peer Transport v2`.
