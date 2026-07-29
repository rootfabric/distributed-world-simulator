# PlanetSimulator

Текущий принятый checkpoint: `v16.9.0-simulation-s1-distributed-compute-fix1`.

Принятая foundation-линия включает N0–N2, R3.1, A0, H0, A1, S0, T1, B0, M0 и S1. Она задаёт authoritative client/server boundary, process recovery, generic aggregates, spatial shards, multi-peer transport, semantic bus ports, atomic transactions/outbox и безопасные distributed compute proposals.

Ближайший основной этап: `H1 — Playable listen-host`.

Утверждённая последовательность:

```text
H1 → H2 → H3 → A2 → B1 → B2 → P0 → D1 → N3 → N4 → N5 → N6
```

После H3 выполняется `A2 — Networked gameplay architecture checkpoint`, затем начинается NATS/JetStream infrastructure track.

Подробности:

- `docs/plans/PLAYABLE_NETWORK_MILESTONES_RU.md`;
- `docs/checkpoints/2026-07-29_POST_S1_PLAYABLE_NETWORK_ROADMAP_RU.md`;
- `docs/plans/DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md`.
