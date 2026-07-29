# Checkpoint v16.8.2 — S0 Spatial Simulation Substrate

**Статус:** candidate
**Ветка:** `feature/s0-spatial-simulation-substrate`
**База:** `v16.8.1-architecture-a1-generic-aggregate`
**Build ID:** `s0-spatial-simulation-substrate`

## Результат

Добавлен исполняемый пространственный substrate для generic aggregates:

- стабильный hierarchical `SimulationCellAddress`;
- `SpatialCellDescriptor` с frame/bounds/hierarchy;
- отдельный `AggregateAuthorityAddress`;
- `AggregateShardDescriptor`;
- explicit cell neighbour topology;
- checksum-protected monotonic `BoundarySummary`;
- `SpatialAggregateIndex` с canonical copy boundary.

## Главный инвариант

```text
cell identity не определяет authority owner
```

Одна cell может содержать несколько aggregate kinds и несколько authority owners. Один shard может покрывать несколько cells. Logical aggregate может состоять из нескольких shards.

## Acceptance profile

```text
S0 contracts
S0 integration
full network profile
full world regression
main scene offline/listen-host
simulation-server lifecycle
```

Подробное описание: [`../architecture/S0_SPATIAL_SIMULATION_SUBSTRATE_RU.md`](../architecture/S0_SPATIAL_SIMULATION_SUBSTRATE_RU.md).

## Следующий этап

```text
T1 — Multi-peer Transport v2
feature/t1-multi-peer-transport-v2
```
