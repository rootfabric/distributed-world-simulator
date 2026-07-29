# PlanetSimulator

Текущий candidate: `v16.8.4-data-plane-b0-message-bus-contracts`.

Принятая база включает N0–N2, R3.1, A0, H0, A1, S0 и T1. B0 добавляет пять независимых semantic ports для request/reply, events, jobs, replication и bulk transfer, строгие versioned results и in-memory adapters без зависимости от NATS/ENet SDK в application/domain-коде.

Следующий этап: `M0 — Multi-aggregate Transactions and Outbox Foundation`. Подробности: `docs/architecture/B0_TRANSPORT_INDEPENDENT_MESSAGE_BUS_RU.md` и `docs/plans/DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md`.
