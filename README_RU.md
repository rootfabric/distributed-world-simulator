# PlanetSimulator

Текущая принятая архитектурная база: `v16.9.4-architecture-a2-networked-gameplay` (`FROZEN_WITH_GATES`).

Принятый стратегический checkpoint: `v16.9.5-roadmap-single-server-multiplayer-first`.

Принятый runtime checkpoint: `v16.10.0-runtime-m1-unified-networked-gameplay-core`.

Текущий runtime candidate:

```text
v16.10.1-runtime-m2-dedicated-graphical-client
branch: feature/m2-dedicated-graphical-client
next after acceptance: M3 dedicated + two graphical clients
```

M2 запускает один headless dedicated server и один настоящий graphical Godot client без embedded authority. Клиент получает stable player identity, двигается только через authoritative M1 gameplay service, использует replica inventory/hotbar и reconnect-ится к той же entity с новым ownership epoch.

```text
FULL SINGLE-SERVER MULTIPLAYER FIRST
A2 → M1 → M2 → M3 → M4 → M5 → M6 → A3 → B1 → B2 → N3 → N4 → N5 → N6
```

До принятия A3 production N3–N6 заблокирован. ENet остаётся realtime transport graphical clients; NATS после A3 используется только для server/service communication через B0 ports.

Основные документы:

- `docs/checkpoints/2026-07-30_V16_10_1_RUNTIME_M2_DEDICATED_GRAPHICAL_CLIENT_RU.md`;
- `docs/checkpoints/2026-07-30_V16_10_0_RUNTIME_M1_UNIFIED_NETWORKED_GAMEPLAY_CORE_RU.md`;
- `docs/architecture/M2_DEDICATED_GRAPHICAL_CLIENT_RU.md`;
- `docs/architecture/M1_UNIFIED_NETWORKED_GAMEPLAY_CORE_RU.md`;
- `docs/architecture/adr/ADR-014-dedicated-graphical-client.md`;
- `docs/architecture/adr/ADR-013-unified-networked-gameplay-core.md`;
- `config/network/dedicated-graphical-client.v1.json`;
- `config/network/networked-gameplay-core.v1.json`;
- `docs/plans/SINGLE_SERVER_MULTIPLAYER_ROADMAP_RU.md`;
- `NETWORK_ROADMAP_RU.md`.
