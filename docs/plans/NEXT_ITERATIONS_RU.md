# Ближайшие итерации после T1 Multi-peer Transport v2

## Текущая точка

```text
runtime checkpoint candidate: v16.8.3-network-t1-multi-peer
accepted spatial base: v16.8.2-simulation-s0-spatial-substrate
architecture base: v16.7.1-architecture-a0-distributed-runtime
branch: feature/t1-multi-peer-transport-v2
```

T1 реализует listener lifecycle отдельно от peer lifecycle, строгие transport events, ProtocolFrame v2, targeted delivery, per-peer backpressure, route generation и реальный ENet listener с двумя клиентами.

## Следующий этап после принятия T1

```text
B0 Message-bus Contracts
→ M0 Aggregate Transactions + Outbox
→ S1 Distributed Compute Contracts
```

B0 должен определить semantic ports для request/reply, events, jobs, replication и bulk transfer без зависимости domain-кода от NATS subjects, ENet channels или конкретного broker SDK.

## Правило фокуса

До принятия T1:

- не начинать NATS adapter;
- не смешивать authority epoch с route generation;
- не удалять N1 transport v1;
- не переносить domain schemas в transport allowlist;
- не начинать Directory, Population Field или workers;
- не вводить durable delivery до M0/B2.

Подробности: [`DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md`](DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md).
