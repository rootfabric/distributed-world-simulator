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

- `docs/architecture/DYNAMIC_MATTER_FABRIC_RU.md` — целевая парадигма изменяемого вещества, астероидов, пещер и добычи;
- `docs/architecture/MW0_MATTER_CONTRACTS_RU.md` — принятая граница canonical matter contracts;
- `docs/architecture/MW1_FIXED_SEED_ASTEROID_RU.md` — принятое детерминированное объёмное тело астероида, stable features и mass integration;
- `docs/architecture/MW2_SPARSE_BRICKS_AND_QUERY_RU.md` — принятые иерархические matter cells, sparse bricks, ghost samples и canonical query service;
- `docs/architecture/MW3_LOCAL_MESHING_RU.md` — local Freudenthal meshing, ghost-gradient normals, collision и camera-local laboratory;
- `docs/checkpoints/2026-07-31_V17_0_0_SIMULATION_MW0_MATTER_CONTRACTS_RU.md`;
- `docs/checkpoints/2026-07-31_V17_0_0_SIMULATION_MW0_MATTER_CONTRACTS_FIX1_RU.md` — принятый typed normalization fix1;
- `docs/checkpoints/2026-07-31_V17_1_0_SIMULATION_MW1_FIXED_SEED_ASTEROID_RU.md` — принятый MW1;
- `docs/checkpoints/2026-07-31_V17_2_0_SIMULATION_MW2_SPARSE_BRICKS_RU.md` — исходный MW2 candidate;
- `docs/checkpoints/2026-07-31_V17_2_0_SIMULATION_MW2_SPARSE_BRICKS_FIX1_RU.md` — принятый MW2 fix1;
- `docs/checkpoints/2026-07-31_V17_3_0_SIMULATION_MW3_LOCAL_MESHING_RU.md` — исходный MW3 candidate;
- `docs/checkpoints/2026-07-31_V17_3_0_SIMULATION_MW3_LOCAL_MESHING_FIX1_RU.md` — MW3 fix1: lifecycle-safe streamer и non-empty seam validation;
- `docs/checkpoints/2026-07-31_V17_3_0_SIMULATION_MW3_LOCAL_MESHING_FIX2_RU.md` — текущий MW3 fix2 candidate: корректный `SimulationCellAddress.cell_id` в streamer;
- `config/matter/mw1-fixed-seed-asteroid.v1.json`;
- `config/matter/mw2-sparse-bricks-and-query.v1.json`;
- `config/matter/mw3-local-meshing.v1.json`;
- `scenes/labs/matter_asteroid_meshing_lab.tscn` — изолированная сцена прямого запуска, не production world;
- `docs/plans/MUTABLE_WORLDS_ROADMAP_RU.md` — отдельный asteroid lab track и последующая интеграция в Луну;
- `docs/architecture/adr/ADR-017-dynamic-matter-fabric.md` — решение procedural volume + sparse persistent mutations;
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
