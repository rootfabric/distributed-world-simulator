# Ближайшие итерации после A1 Generic Aggregate Foundation

## Текущая точка

```text
runtime checkpoint candidate: v16.8.1-architecture-a1-generic-aggregate
accepted runtime: v16.8.0-runtime-h0-listen-host
architecture base: v16.7.1-architecture-a0-distributed-runtime
branch: feature/a1-generic-aggregate-foundation
```

A1 реализует общий aggregate contract, adapter registry и generic replica store. Существующий item-backed `WorldEntityAggregate` не ослаблен и подключён через `WorldItemAggregateAdapter`. Отдельный EnvironmentCell fixture доказывает non-item path.

## Следующий этап после принятия A1

```text
S0 Spatial Simulation Substrate
→ T1 Multi-peer Transport v2
→ B0 Message-bus Contracts
→ M0 Aggregate Transactions + Outbox
→ S1 Distributed Compute Contracts
```

S0 должен определить stable cell addressing, spatial scopes, shard descriptors и boundary summaries. Он не должен реализовывать Population Field gameplay, NATS или Directory.

## Правило фокуса

До принятия A1:

- не начинать S0 в отдельной незавершённой ветке;
- не добавлять новые aggregate kinds через условные ветки в `WorldEntityAggregate`;
- не использовать generic `state` без kind adapter и exact schema;
- не начинать Population Field, NATS, Directory или workers;
- не вводить multi-aggregate commit до M0.

Подробности: [`DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md`](DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md).
