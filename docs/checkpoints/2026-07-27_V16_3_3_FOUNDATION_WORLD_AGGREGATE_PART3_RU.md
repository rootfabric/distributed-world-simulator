# Checkpoint v16.3.3 — Foundation World Aggregate Part 3

**Версия:** `v16.3.3-foundation-world-aggregate-part3`
**Основа:** `v16.3.2-foundation-lifecycle-part2-fix2` + metadata patch
**Build ID:** `foundation-world-aggregate-lifecycle-boundary-part3`

## Цель

Закрыть третий блок Foundation Gate:

```text
SimulationKernel / PresentationHost boundary
→ WorldEntityAggregate
→ одна spatial truth для WORLD-item
→ legacy migration
→ Entity/Chunk Lifecycle
→ server-safe persistence port
```

## Реализовано

### SimulationKernel boundary

Добавлен pure `RefCounted`-контейнер canonical services:

```text
SimulationClock
Command Gateway
Runtime Test Registry
LifecycleCoordinator
WorldEntityStore
domain services
```

Kernel рекурсивно отклоняет `Control`, `CanvasLayer`, `Camera3D`, `Viewport`,
`AudioStreamPlayer` и `InputEvent`, даже если presentation object спрятан во
вложенном Dictionary/Array.

`PresentationHost` создаётся только при presentation-enabled роли и владеет
глобальными UI nodes. В `simulation-server` host отсутствует, а lifecycle event
явно публикует `presentation_free=true` и `active_node_count=0`.

### WorldEntityAggregate

Добавлены:

```text
scripts/simulation/entities/world_entity_aggregate.gd
scripts/simulation/entities/world_entity_store.gd
```

Aggregate владеет SpatialRef, optional PartitionAddress, physics state,
domain components, lifecycle, authority и monotonic revision.

### Item Graph v2

Новая схема:

```text
planet_simulator.item_graph.v2
```

В snapshot добавлен `world_entities`. Старый v1 читается и транзакционно
мигрируется. WORLD relation после миграции содержит только `kind` и `entity_id`.

Physics capture больше не изменяет item relation/revision. Pickup удаляет
aggregate, drop создаёт его, save/restart восстанавливает.

### Lifecycle

Добавлены формальные state machines:

```text
Entity: DORMANT / WARM / ACTIVE / UNLOADING / DESTROYED
Chunk:  DORMANT / WARM / ACTIVE / UNLOADING
```

`LunarChunkRuntime` и `LunarZoneRuntime` сохраняют обратную совместимость со
старым `Activity`, но публикуют lifecycle state и revision. Zone transitions
выполняют child preflight и fail closed, если хотя бы один chunk не может
перейти.

### Persistence boundary

Добавлен `CanonicalStatePort` — server-safe `RefCounted` contract без Node.
JSON store валидирует payload до записи и отклоняет runtime objects,
NaN/Infinity и integers за безопасным JSON-диапазоном.

WorldEntityStore выполняет строгую exact-field validation и staged commit.

## Тесты

Новые обязательные тесты:

```text
tests/entities/test_world_entity_aggregate.gd
tests/entities/test_world_entity_store_failures.gd
tests/items/test_world_item_aggregate_migration.gd
tests/runtime/test_simulation_kernel_boundary.gd
```

Интеграционные item tests усилены проверками canonical relation, aggregate
creation/removal, placement restore и binding validation.

Профильный runner:

```powershell
.\RUN_FOUNDATION_WORLD_AGGREGATE_TESTS.ps1
```

Общий regression manifest содержит 44 test scripts.

## Инварианты checkpoint

- WORLD-item не содержит embedded spatial state;
- один WORLD-item соответствует одному aggregate;
- physics body не является canonical state;
- save/load v2 точен после JSON boundary;
- v1 миграция не теряет pose, velocity или UUID;
- malformed aggregate/store не изменяет live domain;
- server kernel не принимает presentation objects;
- authority epoch и revision не уменьшаются;
- zone/chunk lifecycle не допускает частичный переход после failed preflight.

## Ограничения

- WorldEntityStore пока специализирован для item aggregates и ещё не заменяет
  общий EntityRegistry;
- большинство runtime scenes всё ещё конструируют simulation и local
  presentation внутри одного world runtime, хотя kernel boundary уже явная;
- PartitionAddress для scenario WORLD-items может быть пустым;
- transport, leases и handoff не входят в этот checkpoint.

## Следующий шаг

Довести `v16.4.0-foundation-n0`:

1. завершить N0 contracts: delta, lease/route и handoff state machine;
2. добавить canonical fixtures и contract report;
3. расширить SimulationKernel ports для общего EntityRegistry/repository;
4. подготовить N1 transport adapter без изменения доменных команд.
