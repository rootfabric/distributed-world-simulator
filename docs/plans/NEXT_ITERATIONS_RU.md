# Ближайшие итерации после B0 Message Bus Contracts

## Текущая точка

```text
runtime checkpoint candidate: v16.8.5-domain-m0-aggregate-transactions
accepted transport base: v16.8.3-network-t1-multi-peer
architecture base: v16.7.1-architecture-a0-distributed-runtime
branch: feature/b0-message-bus-contracts
```

B0 реализует пять независимых semantic ports, строгие versioned results и in-memory adapters без concrete broker SDK.

## Следующий этап после принятия B0

```text
M0 Aggregate Transactions + Outbox
→ S1 Distributed Compute Contracts
```

M0 должен добавить atomic multi-aggregate staging/commit и durable OutboxRecord как часть authoritative repository transaction.

## Правило фокуса

До принятия B0:

- не начинать NATS/JetStream adapters;
- не считать broker ACK authoritative commit;
- не объединять пять semantic ports в один universal bus;
- не помещать subjects/channels/broker IDs в domain DTO;
- не начинать Directory, Population Field или workers;
- не вводить durable publication до M0/B2.

Подробности: [`DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md`](DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md).
