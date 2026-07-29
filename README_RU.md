# PlanetSimulator

Текущий принятый checkpoint: `v16.9.0-simulation-s1-distributed-compute-fix1`.

Текущий кодовый кандидат: `v16.9.1-runtime-h1-playable-listen-host` (`H1 — Playable listen-host`).

Принятая foundation-линия включает N0–N2, R3.1, A0, H0, A1, S0, T1, B0, M0 и S1. Она задаёт authoritative client/server boundary, process recovery, generic aggregates, spatial shards, multi-peer transport, semantic bus ports, atomic transactions/outbox и безопасные distributed compute proposals.

После независимой приёмки H1 следующий основной этап: `H2 — Dedicated server + 1 graphical client`.

Утверждённая последовательность:

```text
H1 → H2 → H3 → A2 → B1 → B2 → P0 → D1 → N3 → N4 → N5 → N6
```

После H3 выполняется `A2 — Networked gameplay architecture checkpoint`, затем начинается NATS/JetStream infrastructure track.

Подробности:

- `docs/plans/PLAYABLE_NETWORK_MILESTONES_RU.md`;
- `docs/checkpoints/2026-07-29_V16_9_1_RUNTIME_H1_PLAYABLE_LISTEN_HOST_RU.md`;
- `docs/architecture/H1_PLAYABLE_LISTEN_HOST_RU.md`;
- `docs/checkpoints/2026-07-29_POST_S1_PLAYABLE_NETWORK_ROADMAP_RU.md`;
- `docs/plans/DISTRIBUTED_RUNTIME_FOUNDATION_ROADMAP_RU.md`.
