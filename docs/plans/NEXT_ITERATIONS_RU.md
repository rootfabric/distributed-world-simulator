# Ближайшие итерации после S1 Distributed Compute Contracts

## Текущая точка

```text
runtime checkpoint candidate: v16.9.0-simulation-s1-distributed-compute
accepted domain base: v16.8.5-domain-m0-aggregate-transactions
accepted transport base: v16.8.3-network-t1-multi-peer
architecture base: v16.7.1-architecture-a0-distributed-runtime
branch: feature/s1-distributed-compute-contracts
```

S1 завершает обязательную foundation-последовательность `A0 → H0 → A1 → S0 → T1 → B0 → M0 → S1`. Реализованы immutable jobs, projected read-state, declared read/write sets, budgets, deterministic worker results и authority-side commit через M0.

## Следующий этап после принятия S1

```text
B1 — NATS Core service adapter
→ B2 — JetStream durable jobs/events и outbox publisher
→ контролируемые simulation/network tracks
```

B1 подключает реальную межпроцессную service bus реализацию только к уже принятым B0-портам. Domain/application-код не получает NATS subjects или broker SDK.

## Правило фокуса

До принятия S1:

- не начинать NATS/JetStream adapters;
- не давать worker прямой write-доступ к repository или aggregate registry;
- не считать worker result authoritative state;
- не обходить M0 при commit proposal;
- не начинать World Directory, Population Field или dynamic rule runtime;
- не заявлять durable compute-result inbox до B2.

Подробности: [`DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md`](DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md).
