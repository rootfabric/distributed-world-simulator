# Ближайшие итерации после S0 Spatial Simulation Substrate

## Текущая точка

```text
runtime checkpoint candidate: v16.8.2-simulation-s0-spatial-substrate
accepted aggregate base: v16.8.1-architecture-a1-generic-aggregate
architecture base: v16.7.1-architecture-a0-distributed-runtime
branch: feature/s0-spatial-simulation-substrate
```

S0 реализует stable hierarchical cells, spatial descriptors, explicit shard bindings, neighbour topology и boundary summaries. Authority address хранится отдельно и не выводится из cell identity.

## Следующий этап после принятия S0

```text
T1 Multi-peer Transport v2
→ B0 Message-bus Contracts
→ M0 Aggregate Transactions + Outbox
→ S1 Distributed Compute Contracts
```

T1 должен разделить listener lifecycle и peer lifecycle, добавить строгие peer sessions/events и per-peer queues, сохранив текущий N1 path через compatibility shim.

## Правило фокуса

До принятия S0:

- не начинать T1 в отдельной незавершённой ветке;
- не выводить authority owner из cell ID;
- не фиксировать единый физический размер cell глобально;
- не добавлять Population Field gameplay, NATS, Directory или workers;
- не выполнять dynamic shard split/merge до отдельных stages;
- не обходить `SpatialAggregateIndex` прямыми mutable mappings.

Подробности: [`DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md`](DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md).
