# PlanetSimulator

Текущий candidate: `v16.9.0-simulation-s1-distributed-compute`.

Принятая база включает N0–N2, R3.1, A0, H0, A1, S0, T1, B0 и M0. S1 добавляет immutable simulation jobs, read/write declarations, execution budgets, deterministic worker results и authority-side commit через M0 без прямого доступа worker к canonical state.

Следующий этап после принятия S1: `B1 — NATS Core adapter`. Подробности: `docs/architecture/S1_DISTRIBUTED_COMPUTE_CONTRACTS_RU.md` и `docs/plans/DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md`.

Текущий checkpoint: `v16.9.0-simulation-s1-distributed-compute`.
