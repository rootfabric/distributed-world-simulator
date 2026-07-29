# PlanetSimulator

Текущий candidate: `v16.8.5-domain-m0-aggregate-transactions`.

Принятая база включает N0–N2, R3.1, A0, H0, A1, S0, T1 и B0. M0 добавляет атомарные create/update/delete-транзакции нескольких aggregates, обязательные staged-инварианты, стабильный replay result и durable outbox без зависимости от брокера.

Следующий этап после принятия M0: `S1 — Distributed Compute Contracts`. Подробности: `docs/architecture/M0_MULTI_AGGREGATE_TRANSACTIONS_OUTBOX_RU.md` и `docs/plans/DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md`.

Текущий checkpoint: `v16.8.5-domain-m0-aggregate-transactions` — атомарные multi-aggregate transactions и outbox.
