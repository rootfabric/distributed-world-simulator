# PlanetSimulator

Текущая принятая архитектурная база: `v16.9.4-architecture-a2-networked-gameplay` (`FROZEN_WITH_GATES`).

Принятый стратегический checkpoint: `v16.9.5-roadmap-single-server-multiplayer-first`.

Принятый runtime checkpoint: `v16.10.5-persistence-m6-dedicated-recovery` (`ACCEPTED`, delivery `fix1`).

Текущий architecture candidate:

```text
v16.10.6-architecture-a3-single-server-multiplayer
build_id: a3-single-server-multiplayer-architecture-freeze
runtime base: v16.10.5-persistence-m6-dedicated-recovery
branch: feature/a3-single-server-multiplayer-architecture
status: candidate
next after acceptance: B1 NATS Core adapter
```

A3 фиксирует единственный production gameplay path: один `NetworkedGameplayService`, общие versioned wire contracts, LOOPBACK/ENet adapters, replica-only graphical clients, canonical M4 Item Graph и M6 durable recovery/replay. B1 после A3 может добавлять только server-to-server transport и не вправе создавать второй gameplay authority.

```text
FULL SINGLE-SERVER MULTIPLAYER FIRST
A2 → M1 → M2 → M3 → M4 → M5 → M6 → A3 → B1 → B2 → N3 → N4 → N5 → N6
```

До принятия A3 B1/B2 production integration отложена; N3–N6 заблокированы до A3 и B2. ENet остаётся realtime transport graphical clients.

Основные документы:

- `docs/architecture/A3_SINGLE_SERVER_MULTIPLAYER_ARCHITECTURE_RU.md`;
- `config/network/single-server-multiplayer-architecture.v1.json`;
- `docs/checkpoints/2026-07-31_V16_10_6_ARCHITECTURE_A3_SINGLE_SERVER_MULTIPLAYER_RU.md`;
- `docs/architecture/M6_DEDICATED_PERSISTENCE_RECOVERY_RU.md`;
- `docs/checkpoints/2026-07-31_V16_10_5_PERSISTENCE_M6_DEDICATED_RECOVERY_RU.md`;
- `config/network/dedicated-persistence-recovery.v1.json`;
- `docs/architecture/M5_GRAPHICAL_MULTIPLAYER_ACCEPTANCE_RU.md`;
- `docs/architecture/M5_GRAPHICAL_ACCEPTANCE_PREPARATION_RU.md`;
- `docs/checkpoints/2026-07-31_V16_10_4_TESTING_M5_GRAPHICAL_MULTIPLAYER_ACCEPTANCE_RU.md`;
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

## Текущий realtime-netcode roadmap

Новый рабочий приоритет — комфортное сетевое взаимодействие поверх принятого single-server authority path:

```text
NX0 → NX1 → NX2 → NX3 → NX4 → NX5 → NX6 → NX7 → NX8 → NX9
```

Принятые основы и текущий implementation candidate:

```text
accepted: v16.10.8-network-nx0-observability-baseline
accepted: v16.11.0-network-nx1-deterministic-condition-simulator / fix2
candidate: v16.12.0-network-nx2-realtime-traffic-separation
base commit: f1abeca
branch: feature/nx2-realtime-traffic-separation
```

NX2 разделяет CONTROL/INPUT/SNAPSHOT/ITEM/RESYNC/TELEMETRY, переводит realtime-потоки на raw ENet unreliable с application-level latest-wins sequencing, объединяет input в transition-based redundancy batches и подавляет успешные movement results, per-input delta и full snapshot. Строгая физическая привязка channel/mode использует peer-local quarantine: ошибочный клиент отключается без остановки listener и здоровых peers. Authoritative snapshots публикуются compact-пакетами не чаще 20 Hz; item traffic остаётся отдельным reliable FIFO. NX3 fixed tick и NX4 prediction пока не реализованы.

Основные документы:

- `docs/network/NETWORK_EXPERIENCE_ROADMAP_NX0_NX9_RU.md`;
- `docs/network/NX2_REALTIME_TRAFFIC_SEPARATION_RU.md`;
- `docs/network/NX1_DETERMINISTIC_NETWORK_CONDITION_SIMULATOR_RU.md`;
- `docs/network/NX0_OBSERVABILITY_BASELINE_RU.md`;
- `config/network/network-experience-roadmap.v1.json`;
- `config/network/nx2-realtime-traffic-separation.v1.json`;
- `config/network/nx1-deterministic-network-condition-simulator.v1.json`;
- `config/network/network-condition-presets.v1.json`;
- `RUN_NX2_REALTIME_TRAFFIC_SEPARATION_TESTS.ps1/.sh`;
- `RUN_NX1_DETERMINISTIC_NETWORK_CONDITION_TESTS.ps1/.sh`.
