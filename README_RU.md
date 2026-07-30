# PlanetSimulator

Текущая принятая архитектурная база: `v16.9.4-architecture-a2-networked-gameplay` (`FROZEN_WITH_GATES`).

Принятый стратегический checkpoint: `v16.9.5-roadmap-single-server-multiplayer-first`.

Принятый runtime/domain checkpoint: `v16.10.3-domain-m4-canonical-shared-gameplay` (`ACCEPTED`, delivery `fix1`).

Текущий подготовительный candidate:

```text
v16.10.3-pre-m5-graphical-acceptance-preparation
build_id: pre-m5-ui-replica-command-boundary
base: main @ 2879fdb
branch: feature/m5-graphical-multiplayer-acceptance
next: M5 graphical multiplayer acceptance
```

Подготовительная граница M5 связывает существующий inventory UI с canonical M4 Item Graph только через read-only replica projection и versioned `ITEM_COMMAND`. Cursor/drag/pending state остаётся локальным transient overlay и не мутирует authoritative graph. Graphical process profiles получают изолированные `user://` roots и уникальные либо отключённые MCP runtime ports.

```text
FULL SINGLE-SERVER MULTIPLAYER FIRST
A2 → M1 → M2 → M3 → M4 → M5 → M6 → A3 → B1 → B2 → N3 → N4 → N5 → N6
```

До принятия A3 production N3–N6 заблокирован. ENet остаётся realtime transport graphical clients; NATS после A3 используется только для server/service communication через B0 ports.

Основные документы:

- `docs/architecture/M5_GRAPHICAL_ACCEPTANCE_PREPARATION_RU.md`;
- `docs/checkpoints/2026-07-31_PRE_M5_GRAPHICAL_ACCEPTANCE_PREPARATION_RU.md`;
- `docs/architecture/M4_PRE_M5_HANDOFF_RU.md`;
- `docs/architecture/M4_CANONICAL_SHARED_GAMEPLAY_RU.md`;
- `docs/checkpoints/2026-07-30_V16_10_3_DOMAIN_M4_CANONICAL_SHARED_GAMEPLAY_RU.md`;
- `docs/architecture/M3_DEDICATED_GRAPHICAL_MULTIPLAYER_RU.md`;
- `docs/architecture/M2_DEDICATED_GRAPHICAL_CLIENT_RU.md`;
- `docs/architecture/M1_UNIFIED_NETWORKED_GAMEPLAY_CORE_RU.md`;
- `config/network/m5-graphical-acceptance-preparation.v1.json`;
- `config/network/canonical-shared-gameplay.v1.json`;
- `config/network/network-roadmap.v1.json`;
- `docs/plans/SINGLE_SERVER_MULTIPLAYER_ROADMAP_RU.md`;
- `NETWORK_ROADMAP_RU.md`.
