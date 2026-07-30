# PlanetSimulator

Текущая принятая архитектурная база: `v16.9.4-architecture-a2-networked-gameplay` (`FROZEN_WITH_GATES`).

Текущий roadmap candidate: `v16.9.5-roadmap-single-server-multiplayer-first`.

Стратегическое решение:

```text
FULL SINGLE-SERVER MULTIPLAYER FIRST
A2 → M1 → M2 → M3 → M4 → M5 → M6 → A3 → B1 → B2 → N3 → N4 → N5 → N6
```

Ближайшая реализация — `M1 Unified Networked Gameplay Core`: свести H1/H2/H3 к одному `NetworkedGameplayService` и общим versioned wire validators.

До принятия A3 B1/B2 не являются основным потоком, а production N3–N6 заблокирован. ENet остаётся realtime transport graphical clients; NATS после A3 используется только для server/service communication через B0 ports.

Основные документы:

- `docs/checkpoints/2026-07-30_POST_A2_SINGLE_SERVER_MULTIPLAYER_ROADMAP_RU.md`;
- `docs/plans/SINGLE_SERVER_MULTIPLAYER_ROADMAP_RU.md`;
- `docs/architecture/adr/ADR-012-single-server-multiplayer-first.md`;
- `config/network/single-server-multiplayer-roadmap.v1.json`;
- `config/network/networked-gameplay-architecture.v1.json`;
- `NETWORK_ROADMAP_RU.md`.
