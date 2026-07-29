# PlanetSimulator

Текущий candidate: `v16.8.3-network-t1-multi-peer`.

Принятая база включает N0–N2, R3.1, A0, H0, A1 и S0. T1 добавляет multi-peer transport v2: отдельный listener lifecycle, независимые peer sessions, targeted delivery, route generation, per-peer backpressure и реальный ENet-сценарий с двумя клиентами.

Следующий этап: `B0 — Transport-independent Message Bus Contracts`. Подробности: `docs/architecture/T1_MULTI_PEER_TRANSPORT_V2_RU.md` и `docs/plans/DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md`.
