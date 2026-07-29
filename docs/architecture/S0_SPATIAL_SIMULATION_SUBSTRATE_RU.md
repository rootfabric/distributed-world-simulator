# S0 — Spatial Simulation Substrate

**Checkpoint:** `v16.8.2-simulation-s0-spatial-substrate`
**Статус:** accepted
**Build ID:** `s0-spatial-simulation-substrate`
**База:** `v16.8.1-architecture-a1-generic-aggregate`
**Ветка:** `feature/s0-spatial-simulation-substrate`

## 1. Назначение

S0 создаёт устойчивый пространственный каркас для будущих полей, environment cells, процессов, сложных конструкций и распределённых simulation jobs.

Главный инвариант:

```text
SimulationCell = стабильный пространственный индекс и единица расчёта
SimulationCell ≠ автоматическая граница authority
```

Пространственное положение aggregate и адрес authoritative writer выражаются разными контрактами. Один spatial cell может содержать несколько aggregate kinds с разными владельцами. Один aggregate shard может покрывать несколько cells.

## 2. Что добавлено

```text
SimulationCellAddress
SpatialCellDescriptor
AggregateAuthorityAddress
AggregateShardDescriptor
CellNeighbourDescriptor
BoundarySummary
SpatialAggregateIndex
```

S0 не заменяет существующие `SpatialRef`, `PartitionAddress` и `AggregateSpatialScope`.

- `SpatialRef` остаётся точным положением индивидуальной сущности в reference frame.
- `PartitionAddress` остаётся адресом существующей terrain/zone/chunk системы.
- `AggregateSpatialScope` остаётся сетевым описанием охвата aggregate.
- `SimulationCellAddress` добавляет стабильную иерархическую адресацию единиц пространственной симуляции.

## 3. Иерархический адрес cell

`SimulationCellAddress` состоит из:

```text
universe_id
instance_id
space_id
grid_id
grid_revision
root_id
level
path
cell_id
```

Пример:

```text
universe/main
/instance/earth-01
/space/surface
/grid/quad-tree
/revision/1
/root/face-0
/level/2
/path/3.2
```

`path` хранит последовательность child indexes от root. Такая модель:

- не фиксирует глобальный физический размер cell;
- поддерживает quadtree, octree и специализированные planetary grids;
- позволяет вычислить parent и child identity;
- не зависит от render origin;
- меняет identity при изменении `grid_revision`;
- не содержит authority owner.

Физический смысл child index определяется grid implementation, а не generic address contract.

## 4. Почему физический размер не зафиксирован

Планеты и пространства требуют разных разрешений:

```text
поверхность Земли
поверхность Луны
орбитальное пространство
помещение
подземная система
локальная лабораторная симуляция
```

Поэтому S0 фиксирует hierarchy и bounds, но не вводит один глобальный размер вроде 64 или 256 метров.

`SpatialCellDescriptor` содержит conservative local AABB в reference frame:

```text
frame_id
minimum_m
maximum_m
parent_cell_id
child_capacity
descriptor_revision
```

Нулевая площадь по одной оси допустима для surface layer, но полностью нулевой bounds запрещён.

## 5. Cell descriptor не содержит authority

В `SpatialCellDescriptor` отсутствуют:

```text
authority_owner_id
authority_epoch
route_id
lease_id
```

Это намеренный fence. Нельзя вывести owner из cell ID или topology.

Отдельный `AggregateAuthorityAddress` содержит:

```text
authority_owner_id
authority_epoch
route_id
```

Переезд authority не меняет spatial cell identity. Render-origin shift также не меняет spatial identity.

## 6. Shards

Большой логический объект хранится как набор shards:

```text
Logical Meadow
├── aggregate-shard/meadow/a
├── aggregate-shard/meadow/b
└── aggregate-shard/meadow/c
```

`AggregateShardDescriptor` содержит:

```text
shard_id
logical_aggregate_id
aggregate_kind
state_schema
descriptor_revision
cell_ids
authority_address
neighbour_shard_ids
```

Инварианты:

- `cell_ids` sorted и unique;
- shard покрывает минимум одну cell;
- logical identity, kind и state schema не меняются при descriptor update;
- descriptor revision монотонна;
- authority epoch не откатывается;
- смена owner требует повышенного epoch;
- neighbour shard должен быть известен index;
- spatial binding не выводит authority автоматически.

## 7. Neighbour topology

Соседство является явным контрактом, а не догадкой по координатам.

Поддержаны отношения:

```text
FACE
EDGE
CORNER
PORTAL
PARENT_CHILD
```

Это важно для:

- cube-sphere seams;
- переходов между разными grids;
- порталов и child spaces;
- поверхности и подземных пространств;
- нестандартных локальных сеток.

`PARENT_CHILD` дополнительно проверяется через hierarchy address. Bidirectional duplicate link с обратным направлением отклоняется.

## 8. Boundary summaries

Shards не должны обмениваться всеми внутренними объектами. Для границ вводится `BoundarySummary`:

```text
source_shard_id
target_shard_id
boundary_id
summary_schema
source_revision
from_tick
to_tick
values_by_key
checksum
```

Примеры будущих значений:

```text
seed_pressure
water_flow
fire_pressure
chemical_concentration
population_migration
```

Summary:

- JSON-safe;
- immutable по `summary_id`;
- checksum-protected;
- имеет монотонные source revision и tick window;
- публикуется только между spatially neighbouring shards;
- не является authoritative snapshot целевого shard.

## 9. SpatialAggregateIndex

Index хранит canonical DTO-копии:

```text
cells by ID
shards by ID
cell → shard IDs
logical aggregate → shard IDs
cell neighbour links
boundary summary streams
```

Он поддерживает:

- root-first hierarchy registration;
- parent bounds containment;
- child-capacity fence;
- exact replay;
- conflict rejection;
- multi-kind occupancy одной cell;
- multi-cell shard;
- logical object из нескольких shards;
- разные authority addresses внутри одной cell;
- monotonic shard descriptor update;
- immutable copies на чтении.

Index не хранит Godot `Node`, `Resource`, `RID`, `Callable` или presentation state.

## 10. Доказанный вертикальный сценарий

```text
root cell
├── cell A
├── cell B
└── cell C

cell A:
├── ENVIRONMENT_CELL shard, authority A
└── POPULATION_FIELD shard, authority B

population-field/meadow/main:
├── shard A covers cells A+B
└── shard B covers cell C
```

Между cells A и C зарегистрирована neighbour boundary. Между meadow shards публикуются последовательные boundary summaries.

Проверено:

- authority B не выводится из cell A;
- environment и population могут иметь разных owners в одной cell;
- один shard покрывает несколько cells;
- logical aggregate состоит из нескольких shards;
- rejected update не меняет live mappings;
- boundary summary replay безопасен;
- mutable aliases не выходят из index.

## 11. Fail-closed правила

Отклоняются:

```text
child cell до parent
child index за child_capacity
child bounds вне parent bounds
cell descriptor с authority field
wrong parent_cell_id
unknown cell in shard
unknown neighbour shard
same-revision shard mutation
authority epoch rollback
owner change без нового epoch
invalid parent-child topology
reverse duplicate bidirectional link
summary между несоседними shards
summary source revision rollback
overlapping/rollback tick window
modified checksum
runtime object in DTO
```

## 12. Что S0 не делает

S0 намеренно не реализует:

- автоматический выбор размера cells;
- terrain repartition;
- dynamic shard split/merge;
- live authority leases;
- World Directory;
- Population Field gameplay;
- Simulation Jobs;
- Mutation Proposal;
- NATS;
- ghost replication;
- multi-aggregate transaction.

## 13. Связь со следующими этапами

### T1

Multi-peer transport будет использовать stable cell/shard identities для diagnostics и routing context, но transport не станет владельцем topology.

### B0

Message-bus ports будут передавать boundary summaries, jobs и service requests без NATS subjects в domain DTO.

### M0

Materialization и shard split потребуют atomic multi-aggregate transaction.

### S1

Simulation jobs будут адресоваться к aggregate shard и immutable input snapshots.

### P0

Population Field будет использовать:

```text
PopulationFieldAggregate
→ AggregateShardDescriptor
→ cell bindings
→ neighbour boundary summaries
```

### N3/N4

Directory и handoff будут маршрутизировать authority address отдельно от spatial address.

## 14. Следующий checkpoint

```text
T1 — Multi-peer Transport v2
branch: feature/t1-multi-peer-transport-v2
checkpoint: v16.8.3-network-t1-multi-peer
```

T1 должен сохранить весь существующий single-peer N1 path через compatibility shim, но отделить listener lifecycle от peer sessions и добавить per-peer queues/events.


## 14. Следующий слой

T1 Multi-peer Transport v2 принят как `v16.8.3-network-t1-multi-peer`; B0 Message Bus Contracts реализован как candidate `v16.8.4-data-plane-b0-message-bus-contracts`. S0 cell/shard identity остаётся независимой от peer sessions, route generation и bus adapter routes.
